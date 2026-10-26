using System.Diagnostics;
using System.Runtime.InteropServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using Windows.Storage;
using Windows.System;

namespace AMORA.Orbit.Services.Implementations;

public sealed class WindowsSafeNavigationPlatform : ISafeNavigationPlatform
{
    private readonly Func<Uri, CancellationToken, Task<bool>> _queryProtocol;
    private readonly Func<Uri, CancellationToken, Task<bool>> _launchProtocol;
    private readonly Func<string, CancellationToken, Task<bool>> _launchSystemApplication;

    public WindowsSafeNavigationPlatform(
        Func<Uri, CancellationToken, Task<bool>>? queryProtocol = null,
        Func<Uri, CancellationToken, Task<bool>>? launchProtocol = null,
        Func<string, CancellationToken, Task<bool>>? launchSystemApplication = null)
    {
        _queryProtocol = queryProtocol ?? QueryProtocolAsync;
        _launchProtocol = launchProtocol ?? LaunchProtocolAsync;
        _launchSystemApplication = launchSystemApplication ?? LaunchSystemApplicationAsync;
    }

    public async Task<bool> OpenApplicationAsync(SafeApplication application, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        string? scheme = application switch
        {
            SafeApplication.Calculator => "calculator:", SafeApplication.WindowsSettings => "ms-settings:", _ => null
        };
        if (scheme != null)
        {
            var uri = new Uri(scheme);
            // calc.exe may be only a successful, short-lived stub when Calculator
            // is not installed. Query the actual fixed protocol before launch.
            if (!await _queryProtocol(uri, cancellationToken)) return false;
            cancellationToken.ThrowIfCancellationRequested();
            return await _launchProtocol(uri, cancellationToken);
        }
        string? fileName = application switch
        {
            SafeApplication.Notepad => "notepad.exe", SafeApplication.Paint => "mspaint.exe", _ => null
        };
        if (fileName == null) return false;
        // Only fixed OS applications, never PATH lookup, user-supplied paths, arguments or a shell.
        string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), fileName);
        return await _launchSystemApplication(path, cancellationToken);
    }

    private static async Task<bool> QueryProtocolAsync(Uri uri, CancellationToken token) =>
        await Launcher.QueryUriSupportAsync(uri, LaunchQuerySupportType.Uri).AsTask(token) == LaunchQuerySupportStatus.Available;

    private static async Task<bool> LaunchProtocolAsync(Uri uri, CancellationToken token) =>
        await Launcher.LaunchUriAsync(uri).AsTask(token);

    private static async Task<bool> LaunchSystemApplicationAsync(string path, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!File.Exists(path)) return false;
        using var process = Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = false });
        if (process == null) return false;
        // Notepad/Paint may also be forwarding stubs. An immediate clean exit is
        // not evidence of an opened app; conservatively decline that outcome.
        await Task.Delay(350, cancellationToken);
        process.Refresh();
        return !process.HasExited;
    }

    public async Task<bool> OpenKnownFolderAsync(SafeKnownFolder folder, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        string? path = ResolveKnownFolder(folder);
        if (path == null || !Directory.Exists(path)) return false;
        var storageFolder = await StorageFolder.GetFolderFromPathAsync(path).AsTask(cancellationToken);
        return await Launcher.LaunchFolderAsync(storageFolder).AsTask(cancellationToken);
    }

    internal static string? ResolveKnownFolder(SafeKnownFolder folder)
    {
        Guid id = folder switch
        {
            SafeKnownFolder.Downloads => new("374DE290-123F-4565-9164-39C4925E467B"),
            SafeKnownFolder.Documents => new("FDD39AD0-238F-46AF-ADB4-6C85480369C7"),
            SafeKnownFolder.Desktop => new("B4BFCC3A-DB2C-424C-B029-7FE99A87C641"),
            SafeKnownFolder.Home => new("5E6C858F-0E22-4760-9AFE-EA3317B67173"),
            _ => Guid.Empty
        };
        if (id == Guid.Empty) return null;
        nint pointer = 0;
        try
        {
            int result = SHGetKnownFolderPath(ref id, 0, 0, out pointer);
            return result < 0 || pointer == 0 ? null : Marshal.PtrToStringUni(pointer);
        }
        finally { if (pointer != 0) Marshal.FreeCoTaskMem(pointer); }
    }

    [DllImport("shell32.dll", ExactSpelling = true)]
    private static extern int SHGetKnownFolderPath(ref Guid folderId, uint flags, nint token, out nint path);
}
