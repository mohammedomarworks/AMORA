namespace AMORA.Orbit.Models;

public enum SuggestionPriority
{
    Low,
    Normal,
    Medium = Normal,
    High,
    Urgent
}

public record ProactiveSuggestion(
    string Id,
    string Title,
    string Message,
    string ActionLabel,
    string Category,
    SuggestionPriority Priority = SuggestionPriority.Normal,
    Func<Task>? OnAction = null,
    TimeSpan? CooldownDuration = null
)
{
    public static ProactiveSuggestion DefaultSample => new(
        Id: "default-focus",
        Title: "Deep Focus Session",
        Message: "You have 45 minutes of quiet time. Would you like to start a focus timer?",
        ActionLabel: "Start 25m Focus",
        Category: "Productivity",
        Priority: SuggestionPriority.Normal,
        CooldownDuration: TimeSpan.FromMinutes(15)
    );
}
