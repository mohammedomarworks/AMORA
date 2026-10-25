namespace AMORA.Orbit.Models;

/// <summary>
/// Discriminated union of strongly-typed assistant intents parsed from natural language.
/// </summary>
public abstract record AssistantCommand
{
    // Timer commands
    public sealed record StartTimer(TimeSpan Duration, string Label = "Timer") : AssistantCommand;
    public sealed record PauseTimer : AssistantCommand;
    public sealed record ResumeTimer : AssistantCommand;
    public sealed record CancelTimer : AssistantCommand;
    public sealed record AddTimerTime(TimeSpan Duration) : AssistantCommand
    {
        public TimeSpan AdditionalTime => Duration;
    }

    // Media commands
    public sealed record PlayMedia : AssistantCommand;
    public sealed record PauseMedia : AssistantCommand;
    public sealed record TogglePlayPauseMedia : AssistantCommand;
    public sealed record NextTrack : AssistantCommand;
    public sealed record PreviousTrack : AssistantCommand;

    // Status queries
    public sealed record GetBatteryStatus : AssistantCommand;
    public sealed record GetSystemStatus : AssistantCommand;
    public sealed record GetTimerStatus : AssistantCommand;
    public sealed record GetMediaStatus : AssistantCommand;

    // Conversation management
    public sealed record ResetConversation : AssistantCommand;

    // Consequential action requiring confirmation
    public sealed record ConsequentialAction(
        string ActionId,
        string Description,
        Func<Task<AssistantExecutionResult>> Execute
    ) : AssistantCommand
    {
        public bool RequiresConfirmation => true;
        public string ActionDescription => Description;
    }

    // Unrecognized or unsupported command
    public sealed record Unknown(string RawInput, string Reason = "") : AssistantCommand
    {
        public string OriginalQuery => RawInput;
    }
}
