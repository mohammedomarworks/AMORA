using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ISuggestionService
{
    ProactiveSuggestion? ActiveSuggestion { get; }
    bool IsEnabled => true;

    event EventHandler<ProactiveSuggestion?>? ActiveSuggestionChanged;

    void PresentSuggestion(ProactiveSuggestion suggestion);
    Task ExecuteActiveActionAsync();
    void SnoozeActive(TimeSpan duration);
    void DismissActive();
    void ClearActive() => DismissActive();
}
