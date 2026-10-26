namespace AMORA.Orbit.Models;

/// <summary>A user-requested fact; distinct from ephemeral conversation history.</summary>
public sealed record ExplicitMemory(Guid Id, string Key, string Value, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

public sealed record MemoryLoadResult(IReadOnlyList<ExplicitMemory> Items, string? RecoveryNotice = null);

public enum MemoryCommandKind { Save, Recall, List, Update, Forget, RequestClear, ConfirmClear, Invalid }

public sealed record MemoryCommand(MemoryCommandKind Kind, string Subject = "", string Value = "");
