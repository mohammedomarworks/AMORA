namespace AMORA.Orbit.Models;

public sealed record WorkspaceNote(Guid Id, string Title, string Body, bool IsPinned,
    DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)
{
    public string Preview => Body.Length <= 140 ? Body : Body[..140] + "…";
    public string PinText => IsPinned ? "Unpin" : "Pin";
}

public sealed record ShelfReference(Guid Id, string Path, string Name, bool IsFolder,
    bool IsPinned, bool IsMissing, DateTimeOffset AddedAt)
{
    public string StatusText => IsMissing ? "Missing — original location unavailable" : IsFolder ? "Folder" : "File reference";
    public string PinText => IsPinned ? "Unpin" : "Pin";
}

public sealed record WorkspaceSnapshot(IReadOnlyList<WorkspaceNote> Notes, IReadOnlyList<ShelfReference> Shelf)
{
    public static WorkspaceSnapshot Empty => new(Array.Empty<WorkspaceNote>(), Array.Empty<ShelfReference>());
}

public sealed record WorkspaceResult(bool Success, string Message);
