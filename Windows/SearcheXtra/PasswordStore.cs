using System.Security.Cryptography;
using System.Text.Json;

namespace SearcheXtra.Windows;

public static class PasswordStore
{
    private static string FilePath => Path.Combine(DataStore.Root, "passwords.bin");
    public static async Task<List<Login>> ReadAsync()
    {
        if (!File.Exists(FilePath)) return [];
        var encrypted = await File.ReadAllBytesAsync(FilePath);
        var plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
        try { return JsonSerializer.Deserialize<List<Login>>(plain) ?? []; }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public static async Task UpdateAsync(Action<List<Login>> update)
    {
        await Gate.WaitAsync();
        try { var logins = await ReadAsync(); update(logins); await WriteCoreAsync(logins); }
        finally { Gate.Release(); }
    }

    public static Task SaveAsync(Login login) => UpdateAsync(logins =>
    {
        logins.RemoveAll(old => old.Origin == login.Origin && old.Username == login.Username);
        logins.Add(login);
    });

    public static async Task WriteAsync(List<Login> logins)
    {
        await Gate.WaitAsync();
        try { await WriteCoreAsync(logins); }
        finally { Gate.Release(); }
    }

    private static async Task WriteCoreAsync(List<Login> logins)
    {
        var plain = JsonSerializer.SerializeToUtf8Bytes(logins);
        try
        {
            var encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
            await File.WriteAllBytesAsync(FilePath + ".tmp", encrypted);
            File.Move(FilePath + ".tmp", FilePath, true);
        }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }
}
