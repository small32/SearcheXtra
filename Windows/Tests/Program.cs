using SearcheXtra.Windows;
using System.Text.Json;
using System.Text;
using System.Security.Cryptography;
using System.IO.Compression;

Environment.SetEnvironmentVariable("SEARCHEXTRA_DATA_DIR", Path.Combine(Path.GetTempPath(), "SearcheXtra-tests-" + Guid.NewGuid().ToString("N")));
var count = 0;
void Check(bool condition, string message) { if (!condition) throw new Exception(message); count++; }
var unchangedTab = new BrowserTab();
var notifications = 0;
unchangedTab.PropertyChanged += (_, _) => notifications++;
unchangedTab.Title = "Example"; unchangedTab.Favicon = "https://example.com/favicon.ico";
var initialNotifications = notifications;
unchangedTab.Title = "Example"; unchangedTab.Favicon = "https://example.com/favicon.ico";
Check(notifications == initialNotifications, "Unchanged tab properties do not rebuild UI");
const string search = "https://www.bing.com/search?q={0}";
Check(AddressParser.Resolve("example.com/path", search).AbsoluteUri == "https://example.com/path", "Bare hostname");
Check(AddressParser.Resolve("localhost:8080/test", search).AbsoluteUri == "http://localhost:8080/test", "Localhost");
Check(AddressParser.Resolve("中文 test & x", search).Query.Contains("%26"), "Search escaping");
Check(!AddressParser.IsWeb("javascript:alert(1)"), "Reject script bookmark");
Check(AddressParser.Resolve("", search).AbsoluteUri == "about:blank", "Blank page");
var imported = BookmarkImport.ParseHtml("<DL><p><DT><H3>Work &amp; tools</H3><DL><p><DT><A HREF=\"https://example.com/?a=1&amp;b=2\">Example</A><DT><H3>Nested</H3><DL><DT><A HREF=\"https://example.org\">Second</A></DL></DL><DT><A HREF=\"javascript:evil()\">Bad</A></DL>");
Check(imported.Count == 1 && imported[0].Title == "Work & tools", "Import folder");
Check(imported[0].Children?.Count == 2, "Import children");
Check(BookmarkImport.Flatten(imported).Count(b => b.Url != null) == 2, "Nested import and unsafe URL filtering");
Check(imported[0].Children![0].Url!.Contains("&b=2"), "HTML URL decoding");
var sortFixture = new List<Bookmark> { new() { Title = "Z", Children = [new() { Title = "Child" }] }, new() { Title = "a", Url = "https://a.example" }, new() { Title = "A", Url = "https://b.example" } };
var folderBeforeSort = sortFixture[0];
BookmarkImport.SortByName(sortFixture);
Check(sortFixture.Select(node => node.Title).SequenceEqual(new[] { "a", "A", "Z" }), "Bookmark name sorting is stable and ignores case");
Check(ReferenceEquals(sortFixture[2], folderBeforeSort) && folderBeforeSort.Children![0].Title == "Child", "Bookmark sorting preserves folder identity and children");
var movedA = new Bookmark { Title = "A", Url = "https://a.example" };
var movedB = new Bookmark { Title = "B", Url = "https://b.example" };
var movedC = new Bookmark { Title = "C", Url = "https://c.example" };
var dragNestedFolder = new Bookmark { Title = "Nested", Children = [] };
var destination = new Bookmark { Title = "Destination", Children = [dragNestedFolder] };
var dragTree = new List<Bookmark> { movedA, movedB, movedC, destination };
Check(BookmarkImport.Move(dragTree, [movedA.Id, movedB.Id], null, 3) && dragTree.Take(3).SequenceEqual(new[] { movedC, movedA, movedB }), "Batch bookmark reorder adjusts insertion index and preserves relative order");
Check(BookmarkImport.Move(dragTree, [movedB.Id, movedA.Id], destination.Id) && destination.Children!.Skip(1).SequenceEqual(new[] { movedA, movedB }), "Drag into folder preserves original tree order rather than selection order");
Check(!BookmarkImport.Move(dragTree, [destination.Id], dragNestedFolder.Id) && dragTree.Contains(destination), "Reject moving folder inside its descendant without deleting contents");
Check(BookmarkImport.Move(dragTree, [destination.Id, movedA.Id], null, 0) && dragTree[0] == destination && destination.Children!.Contains(movedA), "Dragging selected folder and child moves the folder once");
Check(!BookmarkImport.Move(dragTree, [movedC.Id], Guid.NewGuid()) && dragTree.Contains(movedC), "Reject unknown destination without losing bookmarks");
Check(SiteSearch.Match(new(), "yout")?.Name == "YouTube" && SiteSearch.Match(new(), "so")?.Name == "Stack Overflow", "Built-in site search prefixes and aliases");
Check(SiteSearch.Match(new(), "youtube cats") == null && SiteSearch.Match(new(), "y") == null, "Site search needs a name prefix");
var chromeTree = BrowserImport.ChromeBookmarks("""{"roots":{"bookmark_bar":{"name":"Bar","children":[{"name":"Example","url":"https://example.com"},{"name":"Bad","url":"javascript:bad"}]}}}""");
Check(chromeTree.Count == 1 && chromeTree[0].Children?.Count == 1, "Chrome profile bookmarks preserve folders and filter scripts");
var chromeProfile = Path.Combine(DataStore.Root, "ChromeFixture"); Directory.CreateDirectory(chromeProfile);
await using (var database = new Microsoft.Data.Sqlite.SqliteConnection("Data Source=" + Path.Combine(chromeProfile, "History")))
{
    await database.OpenAsync(); using var command = database.CreateCommand(); command.CommandText = "CREATE TABLE urls(url TEXT,title TEXT,last_visit_time INTEGER); INSERT INTO urls VALUES('https://example.com','Imported',13380163200000000);"; await command.ExecuteNonQueryAsync();
}
var browserData = await BrowserImport.ProfileAsync(chromeProfile);
Check(browserData.History.Count == 1 && browserData.History[0].Visited.Year == 2025, "Chrome SQLite history timestamps convert from Windows epoch");
var firefoxProfile = Path.Combine(DataStore.Root, "FirefoxFixture"); Directory.CreateDirectory(firefoxProfile);
await using (var database = new Microsoft.Data.Sqlite.SqliteConnection("Data Source=" + Path.Combine(firefoxProfile, "places.sqlite")))
{
    await database.OpenAsync(); using var command = database.CreateCommand(); command.CommandText = """
        CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_date INTEGER);
        CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, parent INTEGER, type INTEGER, title TEXT, fk INTEGER, position INTEGER, guid TEXT);
        INSERT INTO moz_places VALUES
          (1,'https://a.example','A',1735689600000000),(2,'https://tools.example','Tools',NULL),
          (3,'https://b.example','B',NULL),(4,'https://menu.example','Menu',NULL),
          (5,'https://other.example','Other',NULL),(6,'https://mobile.example','Mobile',NULL),
          (7,'https://custom.example','Custom',NULL),(8,'javascript:bad','Bad',NULL);
        INSERT INTO moz_bookmarks VALUES
          (1,0,2,'',NULL,0,'root________'),(2,1,2,'Bookmarks Menu',NULL,0,'menu________'),
          (3,1,2,'Bookmarks Toolbar',NULL,1,'toolbar_____'),(4,1,2,'Tags',NULL,2,'tags________'),
          (5,1,2,'',NULL,3,'unfiled_____'),(6,1,2,'',NULL,4,'mobile______'),
          (7,1,2,'Custom',NULL,5,'custom______'),
          (10,3,1,'A',1,0,'bookmarkA___'),(11,3,2,'Tags',NULL,1,'realFolder__'),
          (12,3,1,'B',3,2,'bookmarkB___'),(13,11,1,'Tool',2,0,'bookmarkTool'),
          (14,2,1,'Menu site',4,0,'bookmarkMenu'),(15,5,1,'Other site',5,0,'bookmarkOthr'),
          (16,6,1,'Mobile site',6,0,'bookmarkMobl'),(17,7,1,'Custom site',7,0,'bookmarkCust'),
          (18,3,1,'Unsafe',8,3,'bookmarkBad_'),(19,3,3,'',NULL,4,'separator___'),
          (20,4,2,'Internal tag',NULL,0,'internalTag_'),(21,20,1,'A duplicate',1,0,'tagDupA_____'),
          (22,20,2,'Nested tag',NULL,1,'nestedTag___'),(23,22,1,'B duplicate',3,0,'tagDupB_____');
        """; await command.ExecuteNonQueryAsync();
}
var firefoxData = await BrowserImport.ProfileAsync(firefoxProfile);
Check(firefoxData.Bookmarks.Select(item => item.Title).SequenceEqual(new[] { "A", "Tags", "B", "Menu site", "Other", "Mobile", "Custom" }), "Firefox flattens its internal containers and preserves toolbar order and real folders");
Check(BookmarkImport.Flatten(firefoxData.Bookmarks).Count(item => item.Url != null) == 7 && !BookmarkImport.Flatten(firefoxData.Bookmarks).Any(item => item.Title is "Internal tag" or "Nested tag" or "A duplicate" or "B duplicate"), "Firefox excludes the entire internal tags tree without losing user bookmarks named Tags");
Check(firefoxData.Bookmarks[1].Children?.Single().Url == "https://tools.example" && firefoxData.Bookmarks[^1].Children?.Single().Url == "https://custom.example", "Firefox keeps nested user folders and additional roots");
Check(firefoxData.History.Single().Visited == new DateTimeOffset(2025, 1, 1, 0, 0, 0, TimeSpan.Zero), "Firefox SQLite timestamps use the Unix epoch");
var firstVisit = new HistoryEntry("https://a.example", "First", new(2025, 1, 1, 0, 0, 0, TimeSpan.Zero));
var secondVisit = firstVisit with { Title = "Second", Visited = firstVisit.Visited.AddDays(1) };
var latestVisit = firstVisit with { Title = "Latest imported", Visited = firstVisit.Visited.AddDays(3) };
var existingVisits = new List<HistoryEntry> { secondVisit, firstVisit, firstVisit };
var mergedVisits = BrowserImport.MergeHistory(existingVisits, new[] { latestVisit, latestVisit, firstVisit with { Title = "Duplicate imported" } });
Check(mergedVisits.Count == 4 && mergedVisits[0] == latestVisit && mergedVisits.Count(visit => visit.Visited == firstVisit.Visited) == 2, "History import preserves every existing visit and adds newer imported visits without duplicate imports");
Check(BrowserImport.MergeHistory(mergedVisits, new[] { latestVisit }).SequenceEqual(mergedVisits), "Repeating a history import does not add the same visit twice");
Check(BrowserImport.MergeHistory(existingVisits, Array.Empty<HistoryEntry>()).SequenceEqual(existingVisits), "Bookmark-only imports leave existing history unchanged");
var store = await DataStore.LoadAsync();
store.Settings.CompactBookmarksBar = true;
store.Settings.BookmarkOpening = BookmarkOpening.Background;
store.Bookmarks.AddRange(imported);
store.Session = new() { Tabs = [new("https://example.com", "Restored", true, "Default")], ActiveIndex = 0 };
await store.SaveAsync();
var restored = await DataStore.LoadAsync();
Check(restored.Settings.CompactBookmarksBar && restored.Settings.BookmarkOpening == BookmarkOpening.Background, "Persist bookmark preferences");
Check(restored.Session.Tabs.Count == 1 && restored.Session.Tabs[0].Pinned, "Persist lazy session metadata");
await File.WriteAllTextAsync(Path.Combine(DataStore.Root, "bookmarks.json"), "broken json");
var corrupt = await DataStore.LoadAsync();
Check(corrupt.Bookmarks.Count == 0 && Directory.GetFiles(DataStore.Root, "bookmarks.json.corrupt-*").Length == 1, "Quarantine corrupt data");
Check(!Directory.GetFiles(DataStore.Root, "*.tmp").Any(), "Atomic writes cleaned up");
var csv = CsvPasswords.Parse("name,url,username,password\r\nExample,https://example.com/login,\"a,b\",\"p\"\"w\"\r\nBad,javascript:bad,x,y");
Check(csv.Count == 1 && csv[0].Origin == "https://example.com" && csv[0].Username == "a,b" && csv[0].Password == "p\"w", "CSV quotes and origin filtering");
var multilinePassword = "line1\r\nline2\nline3\rend\r";
var multilineCsv = CsvPasswords.Parse("url,username,password\r\nhttps://example.com,user,\"" + multilinePassword + "\"\r\n");
Check(multilineCsv.Single().Password == multilinePassword, "Password CSV preserves every quoted CR and LF, including the final carriage return");
Check(CsvPasswords.Parse("url,username,password\nhttps://example.com,user,\"password\r\"").Single().Password == "password\r", "Password CSV preserves a quoted trailing CR in the final record without a line separator");
foreach (var separator in new[] { "\r\n", "\n", "\r" })
{
    var separated = CsvPasswords.Parse("url,username,password" + separator + "https://example.com,a,p1" + separator + "https://other.example,b,p2" + separator);
    Check(separated.Count == 2 && separated[0].Password == "p1" && separated[1].Origin == "https://other.example", "Password CSV supports " + separator.Replace("\r", "CR").Replace("\n", "LF") + " record separators");
}
Check(CrxInstaller.StoreId("https://chromewebstore.google.com/detail/test/aapbdbdomjkkjkaonfhkkikfgjllcleb") == "aapbdbdomjkkjkaonfhkkikfgjllcleb", "Store listing ID");
Check(CrxInstaller.StoreId("https://evil.example/detail/aapbdbdomjkkjkaonfhkkikfgjllcleb") == null, "Store host validation");
static byte[] Varint(uint value) { var bytes = new List<byte>(); do { var b = (byte)(value & 127); value >>= 7; bytes.Add((byte)(b | (value > 0 ? 128 : 0))); } while (value > 0); return bytes.ToArray(); }
static byte[] Field(uint number, byte[] data) => Varint((number << 3) | 2).Concat(Varint((uint)data.Length)).Concat(data).ToArray();
using var rsa = RSA.Create(2048); var key = rsa.ExportSubjectPublicKeyInfo(); var identity = SHA256.HashData(key)[..16]; var id = CrxInstaller.Letters(identity);
using var archiveBytes = new MemoryStream();
using (var archive = new ZipArchive(archiveBytes, ZipArchiveMode.Create, true)) { using var writer = new StreamWriter(archive.CreateEntry("manifest.json").Open()); writer.Write("{\"manifest_version\":3,\"name\":\"Signed fixture\",\"version\":\"1.0\"}"); }
var zip = archiveBytes.ToArray(); var signed = Field(1, identity); var message = Encoding.ASCII.GetBytes("CRX3 SignedData\0").Concat(BitConverter.GetBytes(signed.Length)).Concat(signed).Concat(zip).ToArray();
var signature = rsa.SignData(message, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1); var proof = Field(1, key).Concat(Field(2, signature)).ToArray(); var header = Field(2, proof).Concat(Field(10000, signed)).ToArray();
var crx = Encoding.ASCII.GetBytes("Cr24").Concat(BitConverter.GetBytes(3)).Concat(BitConverter.GetBytes(header.Length)).Concat(header).Concat(zip).ToArray();
Check(CrxInstaller.VerifiedZip(crx, id).SequenceEqual(zip), "CRX3 owner signature verifies");
bool Reject(Action action) { try { action(); return false; } catch (InvalidDataException) { return true; } }
var damaged = crx.ToArray(); damaged[^1] ^= 1;
Check(Reject(() => CrxInstaller.VerifiedZip(damaged, id)), "Tampered CRX3 rejected");
Check(Reject(() => CrxInstaller.VerifiedZip(crx, new string('a', 32))), "Wrong extension ID rejected");
var unpack = Path.Combine(DataStore.Root, "unpack"); CrxInstaller.Unpack(zip, unpack); CrxInstaller.PreserveId(unpack, id, crx);
Check(CrxInstaller.ValidateFolder(unpack) == Path.GetFullPath(unpack), "Ordinary extension packages pass the directory boundary check");
if (OperatingSystem.IsWindows())
{
    var outside = Path.Combine(DataStore.Root, "outside-extension"); Directory.CreateDirectory(outside);
    using var junction = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe")
    {
        Arguments = $"/c mklink /J \"{Path.Combine(unpack, "outside-link")}\" \"{outside}\"",
        UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
    })!;
    junction.WaitForExit();
    Check(junction.ExitCode == 0 && Reject(() => CrxInstaller.ValidateFolder(unpack)), "A directory junction outside the extension package is rejected");
    Directory.Delete(Path.Combine(unpack, "outside-link"));
}
Check(JsonDocument.Parse(File.ReadAllText(Path.Combine(unpack, "manifest.json"))).RootElement.GetProperty("key").GetString() == Convert.ToBase64String(key), "Unpacked extension preserves Chrome ID");
var crx2Signature = rsa.SignData(zip, HashAlgorithmName.SHA1, RSASignaturePadding.Pkcs1);
var crx2 = Encoding.ASCII.GetBytes("Cr24").Concat(BitConverter.GetBytes(2)).Concat(BitConverter.GetBytes(key.Length)).Concat(BitConverter.GetBytes(crx2Signature.Length)).Concat(key).Concat(crx2Signature).Concat(zip).ToArray();
Check(CrxInstaller.PackageId(crx2) == id && CrxInstaller.PackageId(crx) == id, "CRX2 and CRX3 identity extraction");
Check(CrxInstaller.VerifiedZip(crx2, id).SequenceEqual(zip), "Legacy CRX2 RSA signature verifies");
var badCrx2 = crx2.ToArray(); badCrx2[^1] ^= 1;
Check(Reject(() => CrxInstaller.VerifiedZip(badCrx2, id)), "Tampered CRX2 rejected");
Check(Reject(() => CrxInstaller.VerifiedZip(crx2, new string('a', 32))), "CRX2 wrong identity rejected");
Check(Reject(() => CrxInstaller.VerifiedZip(crx2[..14], id)), "Truncated CRX2 rejected");
var legacyPath = Path.Combine(DataStore.Root, "legacy.crx"); await File.WriteAllBytesAsync(legacyPath, crx2);
var legacyFolder = await CrxInstaller.ImportAsync(legacyPath, Path.Combine(DataStore.Root, "imports"));
Check(JsonDocument.Parse(File.ReadAllText(Path.Combine(legacyFolder, "manifest.json"))).RootElement.GetProperty("key").GetString() == Convert.ToBase64String(key), "Imported CRX2 retains extension identity");
using var nestedZip = new MemoryStream(); using (var archive = new ZipArchive(nestedZip, ZipArchiveMode.Create, true)) { using var writer = new StreamWriter(archive.CreateEntry("old-extension/manifest.json").Open()); writer.Write("{\"manifest_version\":2,\"name\":\"Legacy\",\"version\":\"1.0\"}"); }
var nestedPath = Path.Combine(DataStore.Root, "nested.zip"); await File.WriteAllBytesAsync(nestedPath, nestedZip.ToArray()); var nestedFolder = await CrxInstaller.ImportAsync(nestedPath, Path.Combine(DataStore.Root, "imports"));
Check(JsonDocument.Parse(File.ReadAllText(Path.Combine(nestedFolder, "manifest.json"))).RootElement.GetProperty("manifest_version").GetInt32() == 2, "ZIP import discovers nested original MV2 manifest");
using var unsafeBytes = new MemoryStream(); using (var archive = new ZipArchive(unsafeBytes, ZipArchiveMode.Create, true)) { using var writer = new StreamWriter(archive.CreateEntry("../escape.txt").Open()); writer.Write("bad"); }
Check(Reject(() => CrxInstaller.Unpack(unsafeBytes.ToArray(), Path.Combine(DataStore.Root, "bad"))) && !File.Exists(Path.Combine(DataStore.Root, "escape.txt")), "Archive traversal rejected before writing");
using var permissionManifest = JsonDocument.Parse("""
    {"permissions":["downloads","webRequest","webRequestBlocking","nativeMessaging","futurePermission"],"host_permissions":["https://*/*","http://localhost/*"],"optional_permissions":["history"]}
    """);
var permissionLabels = ExtensionPermissions.Describe(permissionManifest.RootElement, true);
Check(permissionLabels.Contains("管理下载的文件") && permissionLabels.Contains("与电脑上的其他应用通信"), "Extension consent describes capabilities in plain language");
Check(permissionLabels.Count(p => p == "查看或修改网站的网络请求") == 1 && !permissionLabels.Any(p => p.Contains("localhost") || p.Contains("futurePermission") || p.Contains("历史")), "Consent groups duplicates and excludes raw identifiers and optional permissions");
using var siteManifest = JsonDocument.Parse("""{"content_scripts":[{"matches":["https://*.example.com/*"]}]}""");
Check(ExtensionPermissions.Describe(siteManifest.RootElement, false).Single() == "Read and change data on example.com and its subdomains", "Content-script site access is described in English");
using var emptyManifest = JsonDocument.Parse("{}");
Check(ExtensionPermissions.Describe(emptyManifest.RootElement, true).Count == 0, "Extensions without additional permissions have an empty consent list");
Check(CrxInstaller.IsNewerVersion("1.10", "1.9") && CrxInstaller.IsNewerVersion("2", "1.99.99.99"), "Extension updates compare numeric version components");
Check(!CrxInstaller.IsNewerVersion("1.2.0.0", "1.2") && !CrxInstaller.IsNewerVersion("1.9", "1.10"), "Equal padded versions and older store versions do not reinstall");
Check(Reject(() => CrxInstaller.IsNewerVersion("not-a-version", "1")) && Reject(() => CrxInstaller.IsNewerVersion("65536", "1")), "Invalid extension versions cannot be treated as updates");
var updateXml = $"<?xml version='1.0'?><gupdate xmlns='http://www.google.com/update2/response'><app appid='{id}' status='ok'><updatecheck status='ok' version='2.0.17'/></app></gupdate>";
Check(CrxInstaller.StoreVersion(updateXml, id) == "2.0.17", "Store version comes from the matching extension update element");
Check(CrxInstaller.StoreVersion($"<gupdate><app appid='{id}' status='ok'><updatecheck status='noupdate'/></app></gupdate>", id) == null, "Store no-update response is recognized");
Check(Reject(() => CrxInstaller.StoreVersion($"<gupdate><app appid='{id}' status='error'/></gupdate>", id)), "Malformed or failed store checks are not reported as latest");
if (args.Length == 2 && args[0] == "--store-probe") { var folder = await CrxInstaller.FetchAsync(args[1], Path.Combine(DataStore.Root, "store")); Console.WriteLine("Verified Chrome store package: " + folder); }
Console.WriteLine($"PASS: {count} checks. Isolated test data: {DataStore.Root}");
