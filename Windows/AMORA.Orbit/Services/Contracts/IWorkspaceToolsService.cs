using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IWorkspaceToolsService
{
    WorkspaceSnapshot Snapshot { get; }
    Task<WorkspaceResult> RefreshAsync(CancellationToken cancellationToken = default);
    IReadOnlyList<WorkspaceNote> SearchNotes(string query);
    Task<WorkspaceResult> SaveNoteAsync(Guid? id, string title, string body, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> DeleteNoteAsync(Guid id, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> ToggleNotePinAsync(Guid id, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> AddPathsAsync(IEnumerable<string> paths, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> RemoveShelfAsync(Guid id, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> ToggleShelfPinAsync(Guid id, CancellationToken cancellationToken = default);
    Task<WorkspaceResult> OpenShelfAsync(Guid id, bool reveal = false, CancellationToken cancellationToken = default);
}

public interface IWorkspaceStorage
{
    Task<WorkspaceSnapshot> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(WorkspaceSnapshot snapshot, CancellationToken cancellationToken = default);
}

/// <summary>Called only by an explicit workspace button; never an AI action target.</summary>
public interface IWorkspaceLauncher
{
    Task<bool> OpenAsync(string localPath, bool isFolder, bool reveal, CancellationToken cancellationToken = default);
}
