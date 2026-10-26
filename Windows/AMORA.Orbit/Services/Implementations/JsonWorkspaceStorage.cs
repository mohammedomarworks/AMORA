using System.Security.Cryptography;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Local notes and path references. Never reads the contents of shelf files.</summary>
public sealed class JsonWorkspaceStorage : IWorkspaceStorage
{
    private const int MaximumBytes = 8_388_608;
    private readonly string _path;
    private bool _loaded;
    private string? _fingerprint;
    private sealed record Document(int SchemaVersion, WorkspaceNote[] Notes, ShelfReference[] Shelf);

    public JsonWorkspaceStorage(string? path = null) => _path = Path.GetFullPath(path ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AMORA", "workspace.json"));

    public Task<WorkspaceSnapshot> LoadAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            using var fileLock = AcquireLock();
            _fingerprint = Fingerprint();
            if (_fingerprint == null)
            {
                _loaded = true;
                return Task.FromResult(WorkspaceSnapshot.Empty);
            }
            if (new FileInfo(_path).Length > MaximumBytes) throw new InvalidDataException();
            var doc = JsonSerializer.Deserialize<Document>(File.ReadAllBytes(_path));
            if (doc?.SchemaVersion != 1 || doc.Notes == null || doc.Shelf == null) throw new InvalidDataException();
            var result = new WorkspaceSnapshot(doc.Notes, doc.Shelf);
            Validate(result);
            _loaded = true;
            return Task.FromResult(result);
        }
        catch (OperationCanceledException) { throw; }
        catch { _loaded = false; throw new WorkspaceStorageException("Workspace data could not be read. Existing data was preserved."); }
    }

    public Task SaveAsync(WorkspaceSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        string? temporary = null;
        try
        {
            if (!_loaded) throw new InvalidOperationException();
            Validate(snapshot);
            using var fileLock = AcquireLock();
            if (Fingerprint() != _fingerprint)
                throw new WorkspaceStorageException("Workspace changed in another process. Refresh before editing again.");
            byte[] data = JsonSerializer.SerializeToUtf8Bytes(new Document(1, snapshot.Notes.ToArray(), snapshot.Shelf.ToArray()));
            if (data.Length > MaximumBytes) throw new InvalidDataException();
            temporary = _path + ".tmp-" + Guid.NewGuid().ToString("N");
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporary, _path, overwrite: true);
            temporary = null;
            _fingerprint = Convert.ToHexString(SHA256.HashData(data));
            return Task.CompletedTask;
        }
        catch (OperationCanceledException) { throw; }
        catch (WorkspaceStorageException) { throw; }
        catch { throw new WorkspaceStorageException("Workspace changes could not be saved. Your previous data is unchanged."); }
        finally { if (temporary != null) { try { File.Delete(temporary); } catch { } } }
    }

    private FileStream AcquireLock()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        return new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private string? Fingerprint()
    {
        if (!File.Exists(_path)) return null;
        if (new FileInfo(_path).Length > MaximumBytes) throw new InvalidDataException();
        using var stream = File.OpenRead(_path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    internal static void Validate(WorkspaceSnapshot data)
    {
        if (data.Notes.Count > WorkspaceToolsService.MaximumNotes || data.Shelf.Count > WorkspaceToolsService.MaximumShelfItems ||
            data.Notes.Any(n => n == null || n.Id == Guid.Empty || string.IsNullOrWhiteSpace(n.Title) ||
                n.Title.Length > 120 || string.IsNullOrWhiteSpace(n.Body) || n.Body.Length > 32000 ||
                n.CreatedAt == default || n.UpdatedAt < n.CreatedAt) ||
            data.Notes.Select(n => n.Id).Distinct().Count() != data.Notes.Count ||
            data.Shelf.Any(f => f == null || f.Id == Guid.Empty || !WorkspacePathPolicy.TryNormalize(f.Path, out _) ||
                string.IsNullOrWhiteSpace(f.Name) || f.AddedAt == default) ||
            data.Shelf.Select(f => f.Id).Distinct().Count() != data.Shelf.Count ||
            data.Shelf.Select(f => f.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count() != data.Shelf.Count)
            throw new InvalidDataException();
    }
}

public sealed class WorkspaceStorageException : Exception
{
    public WorkspaceStorageException(string message) : base(message) { }
}
