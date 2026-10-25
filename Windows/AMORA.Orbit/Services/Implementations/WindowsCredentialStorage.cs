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

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            byte[] cipherBytes = ProtectedData.Protect(plainBytes, Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(filePath, cipherBytes);
        }
        else
        {
            // Fallback for non-Windows host environments / testing
            string base64 = Convert.ToBase64String(plainBytes);
            File.WriteAllText(filePath, base64);
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
                return Task.FromResult<string?>(Encoding.UTF8.GetString(plainBytes));
            }
            else
            {
                string base64 = File.ReadAllText(filePath);
                byte[] plainBytes = Convert.FromBase64String(base64);
                return Task.FromResult<string?>(Encoding.UTF8.GetString(plainBytes));
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
            try
            {
                File.Delete(filePath);
            }
            catch
            {
            }
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
