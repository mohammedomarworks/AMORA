using System;
using System.Collections.Generic;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IAssistantEngine
{
    bool HasPendingConfirmation { get; }
    string? PendingConfirmationPrompt { get; }

    bool HasPendingAction => HasPendingConfirmation;
    string? PendingActionDescription => PendingConfirmationPrompt;

    IReadOnlyList<ChatMessage> ConversationHistory => Array.Empty<ChatMessage>();

    Task<AssistantExecutionResult> ExecuteAsync(string input, CancellationToken cancellationToken = default);
    Task<AssistantExecutionResult> ConfirmPendingActionAsync();
    void CancelPendingAction();
    void ResetConversation() { }
}
