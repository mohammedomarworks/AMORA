using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class SuggestionServiceTests
{
    [Fact]
    public void PresentSuggestion_SetsActiveSuggestion()
    {
        using var service = new ProactiveSuggestionService();
        var suggestion = new ProactiveSuggestion(
            Id: "sug-1",
            Title: "Take a break",
            Message: "You've been focused for 2 hours.",
            ActionLabel: "Break",
            Category: "Wellness",
            Priority: SuggestionPriority.Medium);

        service.PresentSuggestion(suggestion);

        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal("sug-1", service.ActiveSuggestion.Id);
        Assert.Equal("Take a break", service.ActiveSuggestion.Title);
    }

    [Fact]
    public async Task ExecuteActiveAction_InvokesActionAndDismisses()
    {
        using var service = new ProactiveSuggestionService();
        bool actionExecuted = false;

        var suggestion = new ProactiveSuggestion(
            Id: "sug-exec",
            Title: "Test Action",
            Message: "Click to run action",
            ActionLabel: "Run",
            Category: "Test",
            Priority: SuggestionPriority.High,
            OnAction: () =>
            {
                actionExecuted = true;
                return Task.CompletedTask;
            });

        service.PresentSuggestion(suggestion);
        await service.ExecuteActiveActionAsync();

        Assert.True(actionExecuted);
        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void DismissActive_ClearsActiveSuggestion_AndSuppressesFuturePresent()
    {
        using var service = new ProactiveSuggestionService();
        var suggestion = new ProactiveSuggestion(
            Id: "sug-dismiss",
            Title: "Dismiss Me",
            Message: "Testing dismissal",
            ActionLabel: "Dismiss",
            Category: "Test",
            Priority: SuggestionPriority.Low);

        service.PresentSuggestion(suggestion);
        Assert.NotNull(service.ActiveSuggestion);

        service.DismissActive();
        Assert.Null(service.ActiveSuggestion);

        // Attempting to present the same dismissed ID should be ignored
        service.PresentSuggestion(suggestion);
        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void SnoozeActive_TemporarilyClearsActiveSuggestion()
    {
        using var service = new ProactiveSuggestionService();
        var suggestion = new ProactiveSuggestion(
            Id: "sug-snooze",
            Title: "Snooze Me",
            Message: "Testing snooze",
            ActionLabel: "Snooze",
            Category: "Test",
            Priority: SuggestionPriority.Medium);

        service.PresentSuggestion(suggestion);
        service.SnoozeActive(TimeSpan.FromMinutes(10));

        Assert.Null(service.ActiveSuggestion);

        // Immediate re-presentation while snoozed is suppressed
        service.PresentSuggestion(suggestion);
        Assert.Null(service.ActiveSuggestion);
    }
}
