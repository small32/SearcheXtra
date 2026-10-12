using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using Microsoft.Windows.AppLifecycle;
using System.Text.RegularExpressions;

namespace SearcheXtra.Windows;

public partial class App : Application
{
    internal static readonly List<MainWindow> Windows = [];
    internal static DataStore Store { get; private set; } = null!;
    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            Directory.CreateDirectory(DataStore.Root);
            File.WriteAllText(Path.Combine(DataStore.Root, "last-error.txt"), args.Exception.ToString());
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        if (RuntimeInformation.OSArchitecture != Architecture.X64 ||
            !OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763))
            throw new PlatformNotSupportedException("Requires Windows 10 1809 or later on x86_64.");
        var key = "SearcheXtra-" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(DataStore.Root)))[..20];
        var instance = AppInstance.FindOrRegisterForKey(key);
        if (!instance.IsCurrent) { await instance.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs()); Exit(); return; }
        instance.Activated += (_, activation) => { if (activation.Data is global::Windows.ApplicationModel.Activation.ILaunchActivatedEventArgs launch) { var match = Regex.Match(launch.Arguments, "--url\\s+\"?(https?://[^\"\\s]+)"); if (match.Success && Windows.Count > 0) Windows[0].DispatcherQueue.TryEnqueue(() => { if (Store.Settings.LittleLinks) NewWindow(initialUrl: match.Groups[1].Value, small: true); else { Windows[0].OpenExternal(match.Groups[1].Value); Windows[0].Activate(); } }); } };
        Store = await DataStore.LoadAsync();
        var sessions = Store.WindowSessions.ToArray();
        if (Store.Settings.RestoreSession && sessions.Length > 0)
            foreach (var session in sessions) NewWindow(restore: true, session);
        else NewWindow(restore: true);
        var command = Environment.GetCommandLineArgs(); var index = Array.IndexOf(command, "--url");
        if (index >= 0 && index + 1 < command.Length && AddressParser.IsWeb(command[index + 1])) { if (Store.Settings.LittleLinks) NewWindow(initialUrl: command[index + 1], small: true); else Windows[0].OpenExternal(command[index + 1]); }
    }

    internal static MainWindow NewWindow(bool restore = false, SessionState? session = null, string? initialUrl = null, bool small = false)
    {
        var window = new MainWindow(Store, restore, session);
        Windows.Add(window);
        window.Closed += (_, _) => { Windows.Remove(window); };
        if (initialUrl != null) window.OpenExternal(initialUrl);
        if (small) window.AppWindow.Resize(new global::Windows.Graphics.SizeInt32(720, 540));
        window.Activate();
        return window;
    }
}
