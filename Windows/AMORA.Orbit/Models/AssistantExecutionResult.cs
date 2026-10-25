namespace AMORA.Orbit.Models;

public enum AssistantResultStatus
{
    Success,
    Failed,
    Unsupported,
    NeedsConfirmation,
    Information
}

/// <summary>
/// Truthful result of assistant command processing and execution.
/// </summary>
public record AssistantExecutionResult(
    AssistantResultStatus Status,
    string Message,
    MascotMood Mood = MascotMood.Idle,
    bool RequiresConfirmation = false,
    string? PendingActionId = null
)
{
    public string FeedbackMessage => Message;

    public static AssistantExecutionResult Success(string message, MascotMood mood = MascotMood.Happy) =>
        new(AssistantResultStatus.Success, message, mood);

    public static AssistantExecutionResult Failed(string message, MascotMood mood = MascotMood.Alert) =>
        new(AssistantResultStatus.Failed, message, mood);

    public static AssistantExecutionResult Unsupported(string message, MascotMood mood = MascotMood.Idle) =>
        new(AssistantResultStatus.Unsupported, message, mood);

    public static AssistantExecutionResult NeedsConfirmation(string prompt, string actionId, MascotMood mood = MascotMood.Alert) =>
        new(AssistantResultStatus.NeedsConfirmation, prompt, mood, RequiresConfirmation: true, PendingActionId: actionId);

    public static AssistantExecutionResult Information(string message, MascotMood mood = MascotMood.Listening) =>
        new(AssistantResultStatus.Information, message, mood);
}
