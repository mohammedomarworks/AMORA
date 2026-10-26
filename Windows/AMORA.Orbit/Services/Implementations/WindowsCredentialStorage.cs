using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Secure credential storage using Windows Data Protection API (DPAPI).
/// Encrypts secrets using the current Windows user's master key (DataProtectionScope.CurrentUser).
/// Secrets are never stored in plaintext, environment variables, or config files.
/// </summary>
public class WindowsCredentialStorage : ISecureCredentialStorage
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("AMORA.Orbit.CredentialStorage.Entropy.v1");
    private readonly string _storageDirectory;

    public WindowsCredentialStorage(string? customDirectory = null)
    {
        if (!string.IsNullOrWhiteSpace(customDirectory))
        {
            _storageDirectory = customDirectory;
        }
        else
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                localAppData = AppContext.BaseDirectory;
            }
            _storageDirectory = Path.Combine(localAppData, "AMORA", "Credentials");
        }
    }

    public Task SetCredentialAsync(string target, string secret)
    {
        if (string.IsNullOrWhiteSpace(target))
        {
            throw new ArgumentException("Target name cannot be empty.", nameof(target));
        }

        if (string.IsNullOrWhiteSpace(secret))
        {
            return DeleteCredentialAsync(target);
        }

        Directory.CreateDirectory(_storageDirectory);
        string filePath = GetFilePath(target);

        byte[] plainBytes = Encoding.UTF8.GetBytes(secret.Trim());

        try
        {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Secure credentials require Windows DPAPI.");
            byte[] cipherBytes = ProtectedData.Protect(plainBytes, Entropy, DataProtectionScope.CurrentUser);
            string temporaryPath = filePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllBytes(temporaryPath, cipherBytes);
                File.Move(temporaryPath, filePath, overwrite: true);
            }
            finally { if (File.Exists(temporaryPath)) File.Delete(temporaryPath); }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plainBytes);
        }

        return Task.CompletedTask;
    }

    public Task<string?> GetCredentialAsync(string target)
    {
        if (string.IsNullOrWhiteSpace(target))
        {
            return Task.FromResult<string?>(null);
        }

        string filePath = GetFilePath(target);
        if (!File.Exists(filePath))
        {
            return Task.FromResult<string?>(null);
        }

        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                byte[] cipherBytes = File.ReadAllBytes(filePath);
                byte[] plainBytes = ProtectedData.Unprotect(cipherBytes, Entropy, DataProtectionScope.CurrentUser);
                try { return Task.FromResult<string?>(Encoding.UTF8.GetString(plainBytes)); }
                finally { CryptographicOperations.ZeroMemory(plainBytes); }
            }
            else
            {
                return Task.FromResult<string?>(null);
            }
        }
        catch
        {
            // Decryption failure (e.g. file modified or different user account)
            return Task.FromResult<string?>(null);
        }
    }

    public Task DeleteCredentialAsync(string target)
    {
        if (string.IsNullOrWhiteSpace(target))
        {
            return Task.CompletedTask;
        }

        string filePath = GetFilePath(target);
        if (File.Exists(filePath))
        {
            File.Delete(filePath);
        }

        return Task.CompletedTask;
    }

    public Task<bool> HasCredentialAsync(string target)
    {
        if (string.IsNullOrWhiteSpace(target))
        {
            return Task.FromResult(false);
        }

        string filePath = GetFilePath(target);
        return Task.FromResult(File.Exists(filePath));
    }

    private string GetFilePath(string target)
    {
        string safeName = Path.GetFileName(target.Replace('.', '_').Replace(':', '_').Replace('/', '_'));
        return Path.Combine(_storageDirectory, $"{safeName}.dat");
    }

    /// <summary>
    /// Masks a secret for safe display in UI (e.g. "AIzaSy...4f8b").
    /// </summary>
    public static string MaskSecret(string? secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
        {
            return string.Empty;
        }

        string s = secret.Trim();
        if (s.Length <= 8)
        {
            return "••••••••";
        }

        string prefix = s[..Math.Min(6, s.Length / 3)];
        string suffix = s[^Math.Min(4, s.Length / 4)..];
        return $"{prefix}...{suffix}";
    }

    /// <summary>
    /// Redacts a known secret from arbitrary log messages, diagnostics, or exceptions.
    /// </summary>
    public static string RedactSecret(string text, string? secret)
    {
        if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(secret) || secret.Length < 4)
        {
            return text;
        }

        return text.Replace(secret, "[REDACTED_API_KEY]");
    }
}
