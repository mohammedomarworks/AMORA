using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Win32;

namespace AMORA.Orbit.Services.BrowserBridge;

public interface IBrowserHostRegistration
{
    bool IsRegistered { get; }
    Task RegisterAsync(CancellationToken token = default);
    Task UnregisterAsync(CancellationToken token = default);
}

/// <summary>Explicit per-user installation; never runs during app startup or enabling media.</summary>
public sealed class BrowserHostRegistration : IBrowserHostRegistration
{
    private static readonly string[] RegistryPaths =
    [ @"Software\Google\Chrome\NativeMessagingHosts\com.amora.browser", @"Software\Microsoft\Edge\NativeMessagingHosts\com.amora.browser" ];
    private readonly string _sourceDirectory;
    private readonly string _installRoot;
    private string ManifestPath => Path.Combine(_installRoot, "com.amora.browser.json");

    public BrowserHostRegistration(string? applicationDirectory = null)
    {
        _sourceDirectory = Path.Combine(applicationDirectory ?? AppContext.BaseDirectory, "browser-host");
        _installRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AMORA", "BrowserHost");
    }

    public bool IsRegistered
    {
        get
        {
            try
            {
                if (!File.Exists(ManifestPath)) return false;
                using var doc = JsonDocument.Parse(File.ReadAllText(ManifestPath));
                var root = doc.RootElement;
                if (root.GetProperty("name").GetString() != BrowserWireProtocol.HostName ||
                    root.GetProperty("allowed_origins").GetArrayLength() != 1 ||
                    root.GetProperty("allowed_origins")[0].GetString() != BrowserWireProtocol.ExtensionOrigin ||
                    root.GetProperty("path").GetString() is not { } path || !File.Exists(path)) return false;
                return RegistryPaths.All(key =>
                {
                    using var entry = Registry.CurrentUser.OpenSubKey(key);
                    return string.Equals(entry?.GetValue(null) as string, ManifestPath, StringComparison.OrdinalIgnoreCase);
                });
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException or InvalidOperationException or KeyNotFoundException or System.Security.SecurityException) { return false; }
        }
    }

    public Task RegisterAsync(CancellationToken token = default) => Task.Run(() =>
    {
        var host = Path.Combine(_sourceDirectory, "AMORA.BrowserHost.exe");
        var assembly = Path.Combine(_sourceDirectory, "AMORA.BrowserHost.dll");
        if (!File.Exists(host) || !File.Exists(assembly) || !File.Exists(Path.Combine(_sourceDirectory, "coreclr.dll")))
            throw new InvalidOperationException("This build is missing the self-contained browser host. Use the complete AMORA release folder.");
        var digest = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assembly)))[..20];
        var destination = Path.GetFullPath(Path.Combine(_installRoot, "host-" + digest));
        var allowedRoot = Path.GetFullPath(_installRoot) + Path.DirectorySeparatorChar;
        if (!destination.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Invalid host installation path.");
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(_sourceDirectory, "*", new EnumerationOptions
                 { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = false }))
        {
            token.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(_sourceDirectory, file);
            var target = Path.GetFullPath(Path.Combine(destination, relative));
            if (!target.StartsWith(destination + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
                (File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("Invalid browser host bundle.");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            // A content-specific folder remains stable across launches and does not
            // overwrite an executable currently owned by a different host build.
            if (!File.Exists(target) || !SHA256.HashData(File.ReadAllBytes(file)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(target))))
                File.Copy(file, target, overwrite: true);
        }
        var manifest = JsonSerializer.Serialize(new
        {
            name = BrowserWireProtocol.HostName, description = "AMORA browser media bridge", type = "stdio",
            path = Path.Combine(destination, "AMORA.BrowserHost.exe"), allowed_origins = new[] { BrowserWireProtocol.ExtensionOrigin }
        }, new JsonSerializerOptions { WriteIndented = true });
        token.ThrowIfCancellationRequested();
        var temporary = ManifestPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temporary, manifest);
        File.Move(temporary, ManifestPath, overwrite: true);
        foreach (var path in RegistryPaths)
        {
            using var entry = Registry.CurrentUser.CreateSubKey(path) ?? throw new IOException("Unable to register the current-user browser host.");
            entry.SetValue(null, ManifestPath, RegistryValueKind.String);
        }
    }, token);

    public Task UnregisterAsync(CancellationToken token = default) => Task.Run(() =>
    {
        foreach (var path in RegistryPaths)
        {
            token.ThrowIfCancellationRequested();
            bool owns;
            using (var entry = Registry.CurrentUser.OpenSubKey(path))
                owns = string.Equals(entry?.GetValue(null) as string, ManifestPath, StringComparison.OrdinalIgnoreCase);
            if (owns) Registry.CurrentUser.DeleteSubKey(path, throwOnMissingSubKey: false);
        }
        // Retain binaries while a browser may still hold them open. Unregistering
        // prevents future native host launches; disabling media closes current IPC.
    }, token);
}
