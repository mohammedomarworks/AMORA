using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IExplicitMemoryService
{
    bool HasPendingClear { get; }
    /// <summary>Only call with the user's input, never provider-generated actions.</summary>
    Task<AssistantExecutionResult?> TryExecuteAsync(string input, CancellationToken cancellationToken = default);
    Task<AssistantExecutionResult> ConfirmClearAsync(CancellationToken cancellationToken = default);
    void CancelPendingClear();
}

/// <summary>Save must commit atomically or leave previous persisted data intact.</summary>
public interface IMemoryStorage
{
    Task<MemoryLoadResult> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(IReadOnlyList<ExplicitMemory> items, CancellationToken cancellationToken = default);
}
