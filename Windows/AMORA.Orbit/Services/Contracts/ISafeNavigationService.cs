using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ISafeNavigationService
{
    Task<AssistantExecutionResult?> TryExecuteAsync(string input, CancellationToken cancellationToken = default);
    Task<AssistantExecutionResult> ConfirmAsync(CancellationToken cancellationToken = default);
    void CancelPending();
}

public interface ISafeNavigationPlatform
{
    Task<bool> OpenApplicationAsync(SafeApplication application, CancellationToken cancellationToken = default);
    Task<bool> OpenKnownFolderAsync(SafeKnownFolder folder, CancellationToken cancellationToken = default);
}
