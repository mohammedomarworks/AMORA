using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class WorkspaceToolsService : IWorkspaceToolsService
{
    public const int MaximumNotes = 200;
    public const int MaximumShelfItems = 100;
    private readonly IWorkspaceStorage _storage;
    private readonly IWorkspaceLauncher _launcher;
    private readonly Func<DateTimeOffset> _clock;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private WorkspaceSnapshot _snapshot = WorkspaceSnapshot.Empty;
    private bool _loaded;

    public WorkspaceToolsService(IWorkspaceStorage? storage = null, IWorkspaceLauncher? launcher = null, Func<DateTimeOffset>? clock = null)
    {
        _storage = storage ?? new JsonWorkspaceStorage();
        _launcher = launcher ?? new WindowsWorkspaceLauncher();
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    public WorkspaceSnapshot Snapshot => new(_snapshot.Notes.ToArray(), _snapshot.Shelf.ToArray());

    public Task<WorkspaceResult> RefreshAsync(CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        var data = await _storage.LoadAsync(cancellationToken);
        JsonWorkspaceStorage.Validate(data);
        _snapshot = WithCurrentFileStates(data);
        _loaded = true;
        return new(true, "Workspace refreshed. Notes stay local; shelf items store references only.");
    }, cancellationToken, ensureLoaded: false);

    public IReadOnlyList<WorkspaceNote> SearchNotes(string query)
    {
        string trimmed = (query ?? "").Trim();
        return _snapshot.Notes.Where(n => trimmed.Length == 0 || n.Title.Contains(trimmed, StringComparison.OrdinalIgnoreCase) ||
                n.Body.Contains(trimmed, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAt).ToArray();
    }

    public Task<WorkspaceResult> SaveNoteAsync(Guid? id, string title, string body, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        string text = (body ?? "").Trim();
        string heading = (title ?? "").Trim();
        if (text.Length == 0 || text.Length > 32000 || heading.Length > 120)
            return new(false, "Enter a note of 1–32,000 characters and a title of up to 120 characters.");
        if (heading.Length == 0) heading = text.Split('\n')[0].Trim();
        if (heading.Length > 120) heading = heading[..120];
        var items = _snapshot.Notes.ToList();
        var existing = id.HasValue ? items.FirstOrDefault(n => n.Id == id) : null;
        if (id.HasValue && existing == null) return new(false, "That note no longer exists. Refresh the list.");
        if (existing == null && items.Count >= MaximumNotes) return new(false, "The 200-note limit has been reached. Remove a note before adding another.");
        var now = _clock();
        var note = existing == null ? new WorkspaceNote(Guid.NewGuid(), heading, text, false, now, now) :
            existing with { Title = heading, Body = text, UpdatedAt = now < existing.CreatedAt ? existing.CreatedAt : now };
        if (existing != null) items.Remove(existing);
        items.Insert(0, note);
        await CommitAsync(new(items, _snapshot.Shelf), cancellationToken);
        return new(true, existing == null ? "Note saved locally." : "Note updated locally.");
    }, cancellationToken);

    public Task<WorkspaceResult> DeleteNoteAsync(Guid id, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        if (!_snapshot.Notes.Any(n => n.Id == id)) return new(false, "That note no longer exists.");
        await CommitAsync(new(_snapshot.Notes.Where(n => n.Id != id).ToArray(), _snapshot.Shelf), cancellationToken);
        return new(true, "Note deleted.");
    }, cancellationToken);

    public Task<WorkspaceResult> ToggleNotePinAsync(Guid id, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        var note = _snapshot.Notes.FirstOrDefault(n => n.Id == id);
        if (note == null) return new(false, "That note no longer exists.");
        await CommitAsync(new(_snapshot.Notes.Select(n => n.Id == id ? n with { IsPinned = !n.IsPinned } : n).ToArray(), _snapshot.Shelf), cancellationToken);
        return new(true, note.IsPinned ? "Note unpinned." : "Note pinned.");
    }, cancellationToken);

    public Task<WorkspaceResult> AddPathsAsync(IEnumerable<string> paths, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        var input = paths.Take(MaximumShelfItems + 1).ToArray();
        if (input.Length == 0 || input.Length > MaximumShelfItems) return new(false, "Choose between 1 and 100 local files or folders.");
        var items = _snapshot.Shelf.ToList();
        foreach (string value in input)
        {
            if (!WorkspacePathPolicy.TryNormalize(value, out string path))
                return new(false, "Only local drive paths are supported. URLs, network shares, device paths and commands are not accepted.");
            bool folder = Directory.Exists(path), exists = folder || File.Exists(path);
            if (!exists) return new(false, "A selected file or folder is unavailable. No references were added.");
            var existing = items.FirstOrDefault(f => string.Equals(f.Path, path, StringComparison.OrdinalIgnoreCase));
            if (existing != null) items.Remove(existing);
            string name = Path.GetFileName(Path.TrimEndingDirectorySeparator(path));
            if (name.Length == 0) name = path;
            items.Insert(0, new(existing?.Id ?? Guid.NewGuid(), path, name, folder, existing?.IsPinned ?? false, false, _clock()));
        }
        if (items.Count > MaximumShelfItems) return new(false, "The shelf holds up to 100 references. Remove an item before adding more.");
        await CommitAsync(new(_snapshot.Notes, items), cancellationToken);
        return new(true, "File references saved. Original files were not copied or changed.");
    }, cancellationToken);

    public Task<WorkspaceResult> RemoveShelfAsync(Guid id, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        if (!_snapshot.Shelf.Any(f => f.Id == id)) return new(false, "That shelf reference no longer exists.");
        await CommitAsync(new(_snapshot.Notes, _snapshot.Shelf.Where(f => f.Id != id).ToArray()), cancellationToken);
        return new(true, "Reference removed. The original file is unchanged.");
    }, cancellationToken);

    public Task<WorkspaceResult> ToggleShelfPinAsync(Guid id, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        var item = _snapshot.Shelf.FirstOrDefault(f => f.Id == id);
        if (item == null) return new(false, "That shelf reference no longer exists.");
        await CommitAsync(new(_snapshot.Notes, _snapshot.Shelf.Select(f => f.Id == id ? f with { IsPinned = !f.IsPinned } : f).ToArray()), cancellationToken);
        return new(true, item.IsPinned ? "Reference unpinned." : "Reference pinned.");
    }, cancellationToken);

    public Task<WorkspaceResult> OpenShelfAsync(Guid id, bool reveal = false, CancellationToken cancellationToken = default) => RunAsync(async () =>
    {
        _snapshot = WithCurrentFileStates(_snapshot);
        var item = _snapshot.Shelf.FirstOrDefault(f => f.Id == id);
        if (item == null) return new(false, "That shelf reference no longer exists.");
        if (item.IsMissing) return new(false, "The original file or folder is unavailable. The reference has been marked missing.");
        if (!WorkspacePathPolicy.TryNormalize(item.Path, out string path) || WorkspacePathPolicy.HasReparsePoint(path))
            return new(false, "AMORA cannot open linked or redirected paths. Open the original location in File Explorer.");
        if (!item.IsFolder && !reveal && !WorkspacePathPolicy.CanOpenFile(path))
            return new(false, "AMORA opens common documents, images and media only. Use Show in folder for executables, scripts or other file types.");
        bool opened = await _launcher.OpenAsync(path, item.IsFolder, reveal, cancellationToken);
        return new(opened, opened ? (reveal ? "Shown in File Explorer." : "Opened with Windows.") : "Windows could not open this item. Check its default application or permissions.");
    }, cancellationToken);

    private async Task<WorkspaceResult> RunAsync(Func<Task<WorkspaceResult>> operation, CancellationToken token, bool ensureLoaded = true)
    {
        await _gate.WaitAsync(token);
        try
        {
            if (ensureLoaded && !_loaded)
            {
                var data = await _storage.LoadAsync(token);
                JsonWorkspaceStorage.Validate(data);
                _snapshot = WithCurrentFileStates(data);
                _loaded = true;
            }
            return await operation();
        }
        catch (OperationCanceledException) { throw; }
        catch (WorkspaceStorageException ex) { return new(false, ex.Message); }
        catch { return new(false, "The workspace action could not be completed. Saved data was preserved."); }
        finally { _gate.Release(); }
    }

    private async Task CommitAsync(WorkspaceSnapshot next, CancellationToken token)
    {
        await _storage.SaveAsync(next, token);
        _snapshot = new(next.Notes.ToArray(), next.Shelf.ToArray());
    }

    private static WorkspaceSnapshot WithCurrentFileStates(WorkspaceSnapshot state) => new(state.Notes.ToArray(),
        state.Shelf.Select(f => f with { IsMissing = f.IsFolder ? !Directory.Exists(f.Path) : !File.Exists(f.Path) }).ToArray());
}
