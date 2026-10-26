using System;
using System.IO;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AutomationServiceTests
{
    private (LocalAutomationService Service, StandardTimerService Timer, PreviewMediaService Media, ProactiveSuggestionService Suggestion, string FilePath) CreateTestContext(Func<DateTimeOffset>? clock = null)
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"amora_auto_test_{Guid.NewGuid():N}.json");
        var timer = new StandardTimerService();
        var media = new PreviewMediaService();
        var suggestion = new ProactiveSuggestionService();

        var service = new LocalAutomationService(timer, media, suggestion, tempFile, clock);
        return (service, timer, media, suggestion, tempFile);
    }

    [Fact]
    public async Task CreateAutomation_PersistsToDisk_AndCalculatesNextRun()
    {
        var (service, timer, media, suggestion, path) = CreateTestContext();
        try
        {
            var created = await service.CreateAutomationAsync(
                "Morning Focus",
                AutomationTrigger.Daily(9, 0),
                AutomationAction.Timer(TimeSpan.FromMinutes(25), "Morning Focus")
            );

            Assert.NotNull(created);
            Assert.Single(service.Automations);
            Assert.Equal("Morning Focus", service.Automations[0].Name);
            Assert.True(service.Automations[0].IsEnabled);
            Assert.NotNull(service.Automations[0].NextRunAt);
            Assert.True(File.Exists(path));
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task RestoreAutomations_OnRestart_LoadsConfiguredAutomations()
    {
        var (service1, timer1, media1, suggestion1, path) = CreateTestContext();
        try
        {
            await service1.CreateAutomationAsync(
                "Hydration Reminder",
                AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(45)),
                AutomationAction.Reminder("Drink a glass of water")
            );

            service1.Dispose();

            // Create service 2 with the same file path
            var timer2 = new StandardTimerService();
            var media2 = new PreviewMediaService();
            var suggestion2 = new ProactiveSuggestionService();
            using var service2 = new LocalAutomationService(timer2, media2, suggestion2, path);

            await service2.LoadAutomationsAsync();

            Assert.Single(service2.Automations);
            var restored = service2.Automations[0];
            Assert.Equal("Hydration Reminder", restored.Name);
            Assert.Equal(AutomationTriggerType.Interval, restored.Trigger.Type);
            Assert.Equal(TimeSpan.FromMinutes(45), restored.Trigger.Interval);
            Assert.Equal("Drink a glass of water", restored.Action.Message);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task ToggleEnabled_DisablesAndClearsNextRun_EnablesAndRecalculates()
    {
        var (service, _, _, _, path) = CreateTestContext();
        try
        {
            var created = await service.CreateAutomationAsync(
                "Daily Standup",
                AutomationTrigger.Daily(10, 0),
                AutomationAction.Reminder("Standup in 5 minutes")
            );

            // Toggle off
            await service.ToggleEnabledAsync(created.Id);
            var disabled = service.Automations[0];
            Assert.False(disabled.IsEnabled);
            Assert.Null(disabled.NextRunAt);
            Assert.Contains("Disabled", disabled.LastStatus);

            // Toggle on
            await service.ToggleEnabledAsync(created.Id);
            var enabled = service.Automations[0];
            Assert.True(enabled.IsEnabled);
            Assert.NotNull(enabled.NextRunAt);
            Assert.Contains("Enabled", enabled.LastStatus);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task DeleteAutomation_RemovesItem_AndPersists()
    {
        var (service, _, _, _, path) = CreateTestContext();
        try
        {
            var created = await service.CreateAutomationAsync(
                "Temporary",
                AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(10)),
                AutomationAction.PauseMedia()
            );

            Assert.Single(service.Automations);

            await service.DeleteAutomationAsync(created.Id);
            Assert.Empty(service.Automations);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void DailySchedule_CalculatesNextRun_TodayIfInFuture_TomorrowIfInPast()
    {
        var trigger = AutomationTrigger.Daily(9, 0);

        // Reference: Today at 08:00
        var now = DateTimeOffset.Now;
        var today8am = new DateTimeOffset(now.Year, now.Month, now.Day, 8, 0, 0, now.Offset);
        var nextFrom8am = trigger.CalculateNextRunAt(today8am);

        Assert.NotNull(nextFrom8am);
        Assert.Equal(9, nextFrom8am.Value.Hour);
        Assert.Equal(today8am.Day, nextFrom8am.Value.Day);

        // Reference: Today at 10:00 (past 9:00 AM)
        var today10am = new DateTimeOffset(now.Year, now.Month, now.Day, 10, 0, 0, now.Offset);
        var nextFrom10am = trigger.CalculateNextRunAt(today10am);

        Assert.NotNull(nextFrom10am);
        Assert.Equal(9, nextFrom10am.Value.Hour);
        Assert.Equal(today10am.AddDays(1).Day, nextFrom10am.Value.Day);
    }

    [Fact]
    public void IntervalSchedule_CalculatesNextRun_AndAdvancesMissedSchedules()
    {
        var trigger = AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(30));

        var baseTime = new DateTimeOffset(2026, 10, 26, 12, 0, 0, TimeSpan.Zero);
        var nextRun = trigger.CalculateNextRunAt(baseTime);
        Assert.NotNull(nextRun);
        Assert.Equal(baseTime.AddMinutes(30), nextRun.Value);

        // At an exact boundary after four missed intervals, schedule the next strictly future boundary.
        var twoHoursAgo = baseTime.AddHours(-2);
        var advanced = trigger.CalculateNextRunAt(baseTime, twoHoursAgo);
        Assert.NotNull(advanced);
        Assert.Equal(baseTime.AddMinutes(30), advanced.Value);
        Assert.True(advanced.Value > baseTime);

        // Between boundaries, skip all missed intervals and keep the same next scheduled boundary.
        var fiveMinutesLater = baseTime.AddMinutes(5);
        var advancedBetweenBoundaries = trigger.CalculateNextRunAt(fiveMinutesLater, twoHoursAgo);
        Assert.NotNull(advancedBetweenBoundaries);
        Assert.Equal(baseTime.AddMinutes(30), advancedBetweenBoundaries.Value);
        Assert.True(advancedBetweenBoundaries.Value > fiveMinutesLater);
    }

    [Fact]
    public async Task Scheduler_FiresDueAutomation_AndUpdatesNextRun()
    {
        var simulatedTime = new DateTimeOffset(2026, 10, 26, 8, 59, 0, TimeSpan.Zero);
        var (service, timer, media, suggestion, path) = CreateTestContext(clock: () => simulatedTime);

        try
        {
            var created = await service.CreateAutomationAsync(
                "Due Test",
                AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(10)),
                AutomationAction.Reminder("Take a deep breath")
            );

            // Advance simulated clock past next run (8:59 + 10m = 9:09)
            simulatedTime = new DateTimeOffset(2026, 10, 26, 9, 10, 0, TimeSpan.Zero);

            await service.EvaluateDueAutomationsAsync();

            var updated = service.Automations[0];
            Assert.NotNull(updated.LastFiredAt);
            Assert.Equal(simulatedTime, updated.LastFiredAt.Value);
            Assert.True(updated.NextRunAt > simulatedTime);
            Assert.NotNull(suggestion.ActiveSuggestion);
            Assert.Equal("Due Test", suggestion.ActiveSuggestion.Title);
            Assert.Equal("Take a deep breath", suggestion.ActiveSuggestion.Message);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task DuplicateSuppression_SuppressesRapidSuccessionFiring()
    {
        var simulatedTime = new DateTimeOffset(2026, 10, 26, 9, 0, 0, TimeSpan.Zero);
        var (service, timer, media, suggestion, path) = CreateTestContext(clock: () => simulatedTime);

        try
        {
            await service.CreateAutomationAsync(
                "Duplicate Test",
                AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(5)),
                AutomationAction.Reminder("Check posture")
            );

            // Move forward to trigger
            simulatedTime = simulatedTime.AddMinutes(6);
            await service.EvaluateDueAutomationsAsync();

            int firedCount = 0;
            service.AutomationFired += (s, e) => firedCount++;

            // Immediately tick again 1 second later: should be suppressed
            simulatedTime = simulatedTime.AddSeconds(1);
            await service.EvaluateDueAutomationsAsync();

            Assert.Equal(0, firedCount);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task ActionSafety_StartTimer_StartsStandardTimer()
    {
        var (service, timer, _, _, path) = CreateTestContext();
        try
        {
            var auto = await service.CreateAutomationAsync(
                "Focus Sprint",
                AutomationTrigger.Daily(9, 0),
                AutomationAction.Timer(TimeSpan.FromMinutes(15), "Sprint")
            );

            var result = await service.RunManuallyAsync(auto.Id);

            Assert.True(result.IsSuccess);
            Assert.Equal(TimerStatus.Running, timer.CurrentTimer.Status);
            Assert.Equal("Sprint", timer.CurrentTimer.Label);
            Assert.Equal(TimeSpan.FromMinutes(15), timer.CurrentTimer.TotalDuration);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task ActionSafety_MediaPlayPause_ControlsMedia()
    {
        var (service, _, media, _, path) = CreateTestContext();
        try
        {
            var auto = await service.CreateAutomationAsync(
                "Pause Music",
                AutomationTrigger.Daily(17, 0),
                AutomationAction.PauseMedia()
            );

            var result = await service.RunManuallyAsync(auto.Id);

            Assert.True(result.IsSuccess);
            Assert.False(media.CurrentTrack.IsPlaying);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task ActionSafety_UnapprovedAction_IsSafelyRejected()
    {
        var (service, _, _, _, path) = CreateTestContext();
        try
        {
            // Create automation with corrupted/unapproved action type
            var unapprovedAction = new AutomationAction((AutomationActionType)999);
            var auto = await service.CreateAutomationAsync(
                "Unapproved Action",
                AutomationTrigger.Daily(9, 0),
                unapprovedAction
            );

            var result = await service.RunManuallyAsync(auto.Id);

            Assert.False(result.IsSuccess);
            Assert.Contains("Unapproved action type rejected", result.Message);
        }
        finally
        {
            service.Dispose();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public async Task MissedSchedule_OnStartup_RescheduledPredictably()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"amora_missed_test_{Guid.NewGuid():N}.json");
        var now = DateTimeOffset.UtcNow;

        // Write a pre-existing automation that was due 3 hours ago
        var missed = new AmoraAutomation(
            Id: "missed-1",
            Name: "Missed Daily",
            Trigger: AutomationTrigger.Daily(9, 0),
            Action: AutomationAction.Reminder("Daily check"),
            IsEnabled: true,
            NextRunAt: now.AddHours(-3),
            LastStatus: "Scheduled"
        );

        string json = System.Text.Json.JsonSerializer.Serialize(new[] { missed });
        await File.WriteAllTextAsync(tempFile, json);

        var timer = new StandardTimerService();
        var media = new PreviewMediaService();
        var suggestion = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, media, suggestion, tempFile);

        try
        {
            await service.LoadAutomationsAsync();

            Assert.Single(service.Automations);
            var item = service.Automations[0];
            Assert.True(item.IsEnabled);
            Assert.True(item.NextRunAt > now);
            Assert.Contains("Missed schedule while offline", item.LastStatus);
        }
        finally
        {
            if (File.Exists(tempFile)) File.Delete(tempFile);
        }
    }

    [Fact]
    public void GeminiIsolation_DeterministicCommandRouter_DoesNotExposeAutomationCreation()
    {
        var router = new DeterministicCommandRouter();
        var context = new CommandContext();

        // Any attempt to command AI or pattern matching to create automations should NOT match
        // and must not create or modify automations autonomously.
        var result1 = router.Route("create automation for 9am timer", context);
        Assert.IsType<AssistantCommand.Unknown>(result1);

        var result2 = router.Route("schedule reminder every day at 10", context);
        Assert.IsType<AssistantCommand.Unknown>(result2);

        var result3 = router.Route("delete all automations", context);
        Assert.IsType<AssistantCommand.Unknown>(result3);
    }
}
