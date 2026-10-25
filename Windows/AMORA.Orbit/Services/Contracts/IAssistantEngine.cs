using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IAssistantEngine
{
    bool HasPendingConfirmation { get; }
    string? PendingConfirmationPrompt { get; }

    bool HasPendingAction => HasPendingConfirmation;
    string? PendingActionDescription => PendingConfirmationPrompt;

    Task<AssistantExecutionResult> ExecuteAsync(string input, CancellationToken cancellationToken = default);
    Task<AssistantExecutionResult> ConfirmPendingActionAsync();
    void CancelPendingAction();
}
