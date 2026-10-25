using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class SuggestionViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly ISuggestionService _suggestionService;
    private ProactiveSuggestion? _suggestion;

    public SuggestionViewModel(ISuggestionService suggestionService)
    {
        _suggestionService = suggestionService ?? throw new ArgumentNullException(nameof(suggestionService));
        _suggestion = _suggestionService.ActiveSuggestion;

        _suggestionService.ActiveSuggestionChanged += OnSuggestionChanged;
    }

    public ProactiveSuggestion? CurrentSuggestion => _suggestion;
    public bool HasSuggestion => _suggestion != null;

    public string Title => _suggestion?.Title ?? "No active alerts";
    public string Message => _suggestion?.Message ?? "AMORA Orbit is monitoring your workspace.";
    public string ActionLabel => _suggestion?.ActionLabel ?? "Review";
    public string Category => _suggestion?.Category ?? "General";

    public string PriorityBadgeColor => _suggestion?.Priority switch
    {
        SuggestionPriority.Urgent => "#FF453A", // Coral Red
        SuggestionPriority.High => "#FF9F0A",   // Amber
        SuggestionPriority.Medium => "#52CCFF", // Electric Cyan
        _ => "#707E94"                          // Muted Blue-Grey
    };

    public string PriorityGlyph => _suggestion?.Priority switch
    {
        SuggestionPriority.Urgent => "\uE7BA", // Warning / Alert
        SuggestionPriority.High => "\uE814",   // Lightbulb / Info
        _ => "\uE946"                          // Info
    };

    public event PropertyChangedEventHandler? PropertyChanged;

    public async Task ExecuteActionAsync()
    {
        await _suggestionService.ExecuteActiveActionAsync();
    }

    public void Snooze(int minutes = 15)
    {
        _suggestionService.SnoozeActive(TimeSpan.FromMinutes(minutes));
    }

    public void Dismiss()
    {
        _suggestionService.DismissActive();
    }

    private void OnSuggestionChanged(object? sender, ProactiveSuggestion? suggestion)
    {
        _suggestion = suggestion;
        OnPropertyChanged(nameof(CurrentSuggestion));
        OnPropertyChanged(nameof(HasSuggestion));
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(Message));
        OnPropertyChanged(nameof(ActionLabel));
        OnPropertyChanged(nameof(Category));
        OnPropertyChanged(nameof(PriorityBadgeColor));
        OnPropertyChanged(nameof(PriorityGlyph));
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        _suggestionService.ActiveSuggestionChanged -= OnSuggestionChanged;
    }
}
