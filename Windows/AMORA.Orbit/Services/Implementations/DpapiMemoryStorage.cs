using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// User-bound encrypted memory with atomic replacement and preserved corrupt
/// originals. No plaintext fallback on other platforms, and no content logging.
/// </summary>
public sealed class DpapiMemoryStorage : IMemoryStorage
{
    private const int MaximumFileBytes = 1_048_576;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("AMORA.Orbit.ExplicitMemory.v1");
    private readonly string _filePath;
    private string? _expectedFingerprint;
    private string? _quarantinedFingerprint;
    private bool _loaded;
    private sealed record Document(int SchemaVersion, ExplicitMemory[] Items);

    public DpapiMemoryStorage(string? filePath = null)
    {
        _filePath = Path.GetFullPath(filePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AMORA", "memories.enc"));
    }

    public Task<MemoryLoadResult> LoadAsync(CancellationToken cancellationToken = default)
    {
        RequireWindows();
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            using var fileLock = AcquireFileLock();
            _expectedFingerprint = Fingerprint();
            if (_expectedFingerprint == null)
            {
                _loaded = true;
                return Task.FromResult(new MemoryLoadResult(Array.Empty<ExplicitMemory>()));
            }
            byte[]? plaintext = null;
            try
            {
                if (new FileInfo(_filePath).Length > MaximumFileBytes) throw new InvalidDataException();
                byte[] ciphertext = File.ReadAllBytes(_filePath);
                plaintext = ProtectedData.Unprotect(ciphertext, Entropy, DataProtectionScope.CurrentUser);
                var document = JsonSerializer.Deserialize<Document>(plaintext);
                if (document?.SchemaVersion != 1 || document.Items == null) throw new InvalidDataException();
                ValidateItems(document.Items);
                _loaded = true;
                return Task.FromResult(new MemoryLoadResult(document.Items.ToArray()));
            }
            catch (Exception ex) when (ex is CryptographicException or JsonException or InvalidDataException)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (_quarantinedFingerprint != _expectedFingerprint)
                {
                    // Never overwrite an unreadable original unless a durable backup exists.
                    string backup = _filePath + ".corrupt-" + Guid.NewGuid().ToString("N");
                    File.Copy(_filePath, backup, overwrite: false);
                    _quarantinedFingerprint = _expectedFingerprint;
                }
                _loaded = true;
                return Task.FromResult(new MemoryLoadResult(Array.Empty<ExplicitMemory>(),
                    "A damaged memory file was preserved locally. No memories could be loaded from it."));
            }
            finally { if (plaintext != null) CryptographicOperations.ZeroMemory(plaintext); }
        }
        catch (OperationCanceledException) { throw; }
        catch { throw new MemoryStorageException("Memory could not be read safely. Existing data was preserved."); }
    }

    public Task SaveAsync(IReadOnlyList<ExplicitMemory> items, CancellationToken cancellationToken = default)
    {
        RequireWindows();
        cancellationToken.ThrowIfCancellationRequested();
        string? temporaryPath = null;
        byte[]? plaintext = null;
        try
        {
            if (!_loaded) throw new InvalidOperationException("Load memory before saving.");
            ValidateItems(items);
            using var fileLock = AcquireFileLock();
            if (Fingerprint() != _expectedFingerprint)
                throw new MemoryStorageException("Memory changed in another process. Restart AMORA before editing it.");
            plaintext = JsonSerializer.SerializeToUtf8Bytes(new Document(1, items.ToArray()));
            if (plaintext.Length > MaximumFileBytes - 4096) throw new InvalidDataException();
            byte[] ciphertext = ProtectedData.Protect(plaintext, Entropy, DataProtectionScope.CurrentUser);
            temporaryPath = _filePath + ".tmp-" + Guid.NewGuid().ToString("N");
            using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(ciphertext);
                stream.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            // Same-directory replacement. Once committed, do not turn cancellation
            // into a failure that would leave the in-memory cache behind the disk.
            File.Move(temporaryPath, _filePath, overwrite: true);
            temporaryPath = null;
            _expectedFingerprint = Convert.ToHexString(SHA256.HashData(ciphertext));
            _quarantinedFingerprint = null;
            return Task.CompletedTask;
        }
        catch (OperationCanceledException) { throw; }
        catch (MemoryStorageException) { throw; }
        catch { throw new MemoryStorageException("Memory could not be saved. The previous memories were preserved."); }
        finally
        {
            if (plaintext != null) CryptographicOperations.ZeroMemory(plaintext);
            if (temporaryPath != null)
            {
                try { File.Delete(temporaryPath); } catch { /* Encrypted orphan only; never report commit success. */ }
            }
        }
    }

    private FileStream AcquireFileLock()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        return new FileStream(_filePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private string? Fingerprint()
    {
        if (!File.Exists(_filePath)) return null;
        using var stream = File.OpenRead(_filePath);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static void RequireWindows()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Encrypted memory requires Windows DPAPI.");
    }

    private static void ValidateItems(IReadOnlyList<ExplicitMemory> items)
    {
        if (items.Count > MemoryPrivacyValidator.MaximumItems || items.Any(i => i == null) ||
            items.Select(i => i.Id).Distinct().Count() != items.Count) throw new InvalidDataException();
        foreach (var item in items)
            if (item.Id == Guid.Empty || MemoryPrivacyValidator.Validate(item.Key, item.Value) != null ||
                item.CreatedAt == default || item.UpdatedAt < item.CreatedAt) throw new InvalidDataException();
    }
}

/// <summary>Only safe, content-free messages may cross this storage boundary.</summary>
public sealed class MemoryStorageException(string message) : Exception(message);
