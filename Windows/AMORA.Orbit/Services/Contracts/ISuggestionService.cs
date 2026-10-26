using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ISuggestionService
{
    ProactiveSuggestion? ActiveSuggestion { get; }
    bool IsEnabled => true;

    event EventHandler<ProactiveSuggestion?>? ActiveSuggestionChanged;

    void PresentSuggestion(ProactiveSuggestion suggestion);
    // Explicit user-created reminders are separate from optional proactive suggestions.
    // Returns whether the implementation accepted the reminder for display or queuing.
    bool PresentReminder(ProactiveSuggestion reminder)
    {
        PresentSuggestion(reminder);
        return ActiveSuggestion?.Id == reminder.Id;
    }
    Task ExecuteActiveActionAsync();
    void SnoozeActive(TimeSpan duration);
    void DismissActive();
    void ClearActive() => DismissActive();
}
