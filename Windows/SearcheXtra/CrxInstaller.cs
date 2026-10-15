using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace SearcheXtra.Windows;

public static class CrxInstaller
{
    public static string ValidateFolder(string folder)
    {
        var directory = new DirectoryInfo(Path.GetFullPath(folder));
        var root = (directory.ResolveLinkTarget(true) ?? directory).FullName.TrimEnd(Path.DirectorySeparatorChar);
        var pending = new Stack<string>(); pending.Push(root);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        while (pending.TryPop(out var path))
        {
            if (!seen.Add(path)) continue;
            foreach (var item in new DirectoryInfo(path).EnumerateFileSystemInfos())
            {
                var target = item.Attributes.HasFlag(FileAttributes.ReparsePoint) ? item.ResolveLinkTarget(true) : item;
                if (target == null || (!target.FullName.Equals(root, StringComparison.OrdinalIgnoreCase) && !target.FullName.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)))
                    throw new InvalidDataException("Extension folder contains a link outside its package.");
                if (target.Attributes.HasFlag(FileAttributes.Directory)) pending.Push(target.FullName);
            }
        }
        return root;
    }
    public static bool IsNewerVersion(string remote, string local)
    {
        static int[] Parts(string version)
        {
            var parts = version.Split('.');
            if (parts.Length is < 1 or > 4 || parts.Any(p => !ushort.TryParse(p, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out _)))
                throw new InvalidDataException("Invalid extension version.");
            return parts.Select(int.Parse).Concat(Enumerable.Repeat(0, 4 - parts.Length)).ToArray();
        }
        var newer = Parts(remote); var current = Parts(local);
        for (var i = 0; i < 4; i++) if (newer[i] != current[i]) return newer[i] > current[i];
        return false;
    }
    public static string? StoreVersion(string xml, string id)
    {
        var app = XDocument.Parse(xml).Descendants().FirstOrDefault(e => e.Name.LocalName == "app" && (string?)e.Attribute("appid") == id);
        var check = app?.Elements().FirstOrDefault(e => e.Name.LocalName == "updatecheck");
        var status = (string?)check?.Attribute("status");
        if (status == "noupdate") return null;
        if (status != "ok" || (string?)check?.Attribute("version") is not { Length: > 0 } version) throw new InvalidDataException("Could not check the store version.");
        return version;
    }
    public static async Task<string?> CheckUpdateAsync(string id, string currentVersion)
    {
        if (Id(id) != id) throw new InvalidDataException("Invalid Chrome extension ID.");
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        var url = "https://clients2.google.com/service/update2/crx?response=updatecheck&prodversion=140.0.0.0&acceptformat=crx3&x=" + Uri.EscapeDataString($"id={id}&v={currentVersion}&uc");
        var remote = StoreVersion(await client.GetStringAsync(url), id);
        return remote != null && IsNewerVersion(remote, currentVersion) ? remote : null;
    }
    public static string? Id(string text) => Regex.Match(text.ToLowerInvariant(), @"(?<![a-z])([a-p]{32})(?![a-z])") is { Success: true } m ? m.Groups[1].Value : null;
    public static string? StoreId(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var u) || u.Scheme != "https" || u.UserInfo.Length > 0) return null;
        var pattern = u.Host switch { "chromewebstore.google.com" => @"^/detail/(?:[^/]+/)?([a-p]{32})(?:/.*)?$", "chrome.google.com" => @"^/webstore/detail/(?:[^/]+/)?([a-p]{32})(?:/.*)?$", _ => "(?!)" };
        var match = Regex.Match(u.AbsolutePath, pattern); return match.Success ? match.Groups[1].Value : null;
    }
    public static async Task<string> FetchAsync(string id, string root, CancellationToken cancellation = default)
    {
        if (Id(id) != id) throw new InvalidDataException("Invalid Chrome extension ID.");
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        var url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0.0.0&acceptformat=crx3&x=" + Uri.EscapeDataString($"id={id}&installsource=ondemand&uc");
        var bytes = await client.GetByteArrayAsync(url, cancellation);
        var zip = await Task.Run(() => VerifiedZip(bytes, id), cancellation);
        var folder = Path.Combine(root, id, Guid.NewGuid().ToString("N"));
        await Task.Run(() => Unpack(zip, folder), cancellation);
        await Task.Run(() => PreserveId(folder, id, bytes), cancellation);
        return folder;
    }
    public static async Task<string> ImportAsync(string path, string root, CancellationToken cancellation = default)
    {
        var bytes = await File.ReadAllBytesAsync(path, cancellation); var folder = Path.Combine(root, "local", Guid.NewGuid().ToString("N"));
        return await Task.Run(() =>
        {
            if (Path.GetExtension(path).Equals(".crx", StringComparison.OrdinalIgnoreCase))
            {
                var id = PackageId(bytes); var zip = VerifiedZip(bytes, id); Unpack(zip, folder); PreserveId(folder, id, bytes); return folder;
            }
            if (!Path.GetExtension(path).Equals(".zip", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Choose a CRX or ZIP extension.");
            Unpack(bytes, folder, requireManifest: false);
            if (File.Exists(Path.Combine(folder, "manifest.json"))) return folder;
            var manifests = Directory.GetFiles(folder, "manifest.json", SearchOption.AllDirectories);
            if (manifests.Length != 1) throw new InvalidDataException("ZIP must contain one extension manifest.");
            return Path.GetDirectoryName(manifests[0])!;
        }, cancellation);
    }
    public static string PackageId(byte[] crx)
    {
        if (crx.Length < 16 || Encoding.ASCII.GetString(crx, 0, 4) != "Cr24") throw new InvalidDataException("Invalid CRX file.");
        var version = BinaryPrimitives.ReadUInt32LittleEndian(crx.AsSpan(4)); var size = BinaryPrimitives.ReadUInt32LittleEndian(crx.AsSpan(8));
        if (version == 2) { if (size == 0 || size > crx.Length - 16) throw new InvalidDataException("Invalid CRX2 key length."); return Letters(SHA256.HashData(crx.AsSpan(16, (int)size))[..16]); }
        if (version != 3 || size > crx.Length - 12) throw new InvalidDataException("Unsupported CRX format.");
        var signed = Fields(crx.AsSpan(12, (int)size).ToArray()).FirstOrDefault(f => f.Number == 10000).Data ?? throw new InvalidDataException("Unsigned CRX3.");
        var identity = Fields(signed).FirstOrDefault(f => f.Number == 1).Data;
        if (identity?.Length != 16) throw new InvalidDataException("Invalid CRX3 identity."); return Letters(identity);
    }
    private static byte[] VerifiedCrx2(byte[] bytes, string id)
    {
        if (bytes.Length < 16) throw new InvalidDataException("Truncated CRX2.");
        var keyLength = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(8)); var signatureLength = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(12));
        if (keyLength == 0 || signatureLength == 0 || (ulong)keyLength + signatureLength > (ulong)(bytes.Length - 16)) throw new InvalidDataException("Invalid CRX2 lengths.");
        var key = bytes.AsSpan(16, (int)keyLength); var signature = bytes.AsSpan(16 + (int)keyLength, (int)signatureLength); var zip = bytes[(16 + (int)keyLength + (int)signatureLength)..];
        if (Letters(SHA256.HashData(key)[..16]) != id) throw new InvalidDataException("Extension ID does not match.");
        try { using var rsa = RSA.Create(); rsa.ImportSubjectPublicKeyInfo(key, out _); if (rsa.VerifyData(zip, signature, HashAlgorithmName.SHA1, RSASignaturePadding.Pkcs1)) return zip; }
        catch (CryptographicException) { }
        throw new InvalidDataException("CRX2 signature verification failed.");
    }
    public static byte[] VerifiedZip(byte[] bytes, string id)
    {
        if (bytes.Length >= 8 && Encoding.ASCII.GetString(bytes, 0, 4) == "Cr24" && BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(4)) == 2) return VerifiedCrx2(bytes, id);
        if (bytes.Length < 12 || Encoding.ASCII.GetString(bytes, 0, 4) != "Cr24" || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(4)) != 3) throw new InvalidDataException("Not a CRX3 extension.");
        var size = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(8));
        if (size > bytes.Length - 12) throw new InvalidDataException("Invalid CRX3 header.");
        var header = Fields(bytes.AsSpan(12, (int)size).ToArray());
        var signed = header.FirstOrDefault(f => f.Number == 10000).Data ?? throw new InvalidDataException("Unsigned CRX3.");
        var crxId = Fields(signed).FirstOrDefault(f => f.Number == 1).Data;
        if (crxId == null || Letters(crxId) != id) throw new InvalidDataException("Extension ID does not match.");
        var zip = bytes[(12 + (int)size)..];
        using var message = new MemoryStream(); message.Write(Encoding.ASCII.GetBytes("CRX3 SignedData\0"));
        var length = new byte[4]; BinaryPrimitives.WriteUInt32LittleEndian(length, (uint)signed.Length);
        message.Write(length); message.Write(signed); message.Write(zip);
        foreach (var proof in header.Where(f => f.Number is 2 or 3))
        {
            var fields = Fields(proof.Data); var key = fields.FirstOrDefault(f => f.Number == 1).Data; var signature = fields.FirstOrDefault(f => f.Number == 2).Data;
            if (key == null || signature == null || Letters(SHA256.HashData(key)[..16]) != id) continue;
            try
            {
                bool valid;
                if (proof.Number == 2) { using var rsa = RSA.Create(); rsa.ImportSubjectPublicKeyInfo(key, out _); valid = rsa.VerifyData(message.ToArray(), signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1); }
                else { using var ec = ECDsa.Create(); ec.ImportSubjectPublicKeyInfo(key, out _); valid = ec.VerifyData(message.ToArray(), signature, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence); }
                if (valid) return zip;
            }
            catch (CryptographicException) { }
        }
        throw new InvalidDataException("CRX3 signature verification failed.");
    }
    public static string Letters(byte[] bytes) => new(bytes.SelectMany(b => new[] { (char)('a' + (b >> 4)), (char)('a' + (b & 15)) }).ToArray());
    private static List<(int Number, byte[] Data)> Fields(byte[] bytes)
    {
        var result = new List<(int, byte[])>(); var at = 0;
        ulong Varint() { ulong value = 0; for (var shift = 0; shift < 64 && at < bytes.Length; shift += 7) { var b = bytes[at++]; value |= (ulong)(b & 127) << shift; if ((b & 128) == 0) return value; } throw new InvalidDataException("Malformed CRX3 protobuf."); }
        while (at < bytes.Length)
        {
            var tag = Varint(); var number = checked((int)(tag >> 3));
            switch (tag & 7)
            {
                case 2: var size = Varint(); if (size > (ulong)(bytes.Length - at)) throw new InvalidDataException("Truncated CRX3 protobuf."); result.Add((number, bytes.AsSpan(at, (int)size).ToArray())); at += (int)size; break;
                case 0: Varint(); break;
                case 1: at += 8; break;
                case 5: at += 4; break;
                default: throw new InvalidDataException("Unsupported CRX3 protobuf wire type.");
            }
            if (at > bytes.Length) throw new InvalidDataException("Truncated CRX3 protobuf.");
        }
        return result;
    }
    public static void Unpack(byte[] zip, string folder, bool requireManifest = true)
    {
        var root = Path.GetFullPath(folder) + Path.DirectorySeparatorChar;
        using var archive = new ZipArchive(new MemoryStream(zip));
        foreach (var entry in archive.Entries)
        {
            var path = Path.GetFullPath(Path.Combine(root, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase) || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000) throw new InvalidDataException("Invalid extension archive path.");
        }
        Directory.CreateDirectory(root);
        archive.ExtractToDirectory(root);
        var manifestPath = Path.Combine(root, "manifest.json");
        if (requireManifest && !File.Exists(manifestPath)) throw new InvalidDataException("Extension manifest missing.");
        // A verified store package keeps its Chrome ID when loaded unpacked.
    }
    public static void PreserveId(string folder, string id, byte[] crx)
    {
        // Verify the package again before adopting its original extension identity.
        VerifiedZip(crx, id);
        var size = BinaryPrimitives.ReadUInt32LittleEndian(crx.AsSpan(8));
        if (BinaryPrimitives.ReadUInt32LittleEndian(crx.AsSpan(4)) == 2)
        {
            var path = Path.Combine(folder, "manifest.json"); var manifest = JsonNode.Parse(File.ReadAllText(path))!;
            manifest["key"] = Convert.ToBase64String(crx.AsSpan(16, (int)size)); File.WriteAllText(path, manifest.ToJsonString()); return;
        }
        foreach (var proof in Fields(crx.AsSpan(12, (int)size).ToArray()).Where(f => f.Number is 2 or 3))
        {
            var key = Fields(proof.Data).FirstOrDefault(f => f.Number == 1).Data;
            if (key == null || Letters(SHA256.HashData(key)[..16]) != id) continue;
            var path = Path.Combine(folder, "manifest.json"); var manifest = JsonNode.Parse(File.ReadAllText(path))!;
            manifest["key"] = Convert.ToBase64String(key); File.WriteAllText(path, manifest.ToJsonString()); return;
        }
    }
}
