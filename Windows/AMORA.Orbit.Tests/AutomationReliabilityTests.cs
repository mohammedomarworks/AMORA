using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class AutomationReliabilityTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "amora-automation-durable-" + Guid.NewGuid().ToString("N"));
    private string DataPath => Path.Combine(_directory, "automations.json");
    public AutomationReliabilityTests() => Directory.CreateDirectory(_directory);
    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task FailedCreateDoesNotActivateOrPublishUnsavedAutomation()
    {
        var blockedParent = Path.Combine(_directory, "file-is-not-a-directory");
        File.WriteAllText(blockedParent, "sentinel");
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions,
            Path.Combine(blockedParent, "automations.json"), startScheduler: false);
        int changed = 0;
        service.AutomationsChanged += (_, _) => changed++;
        await Assert.ThrowsAsync<AutomationPersistenceException>(() => service.CreateAutomationAsync("Focus",
            AutomationTrigger.Daily(9, 0), AutomationAction.Timer(TimeSpan.FromMinutes(25))));
        Assert.Empty(service.Automations);
        Assert.Equal(0, changed);
        Assert.Equal("sentinel", File.ReadAllText(blockedParent));
    }

    [Fact]
    public async Task FailedToggleAndDeleteLeaveDurableAndInMemoryStateUnchanged()
    {
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions, DataPath, startScheduler: false);
        var item = await service.CreateAutomationAsync("Reminder", AutomationTrigger.Daily(9, 0), AutomationAction.Reminder("Hello"));
        var original = await File.ReadAllTextAsync(DataPath);
        using (var held = new FileStream(DataPath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            await Assert.ThrowsAsync<AutomationPersistenceException>(() => service.ToggleEnabledAsync(item.Id));
            await Assert.ThrowsAsync<AutomationPersistenceException>(() => service.DeleteAutomationAsync(item.Id));
            Assert.Equal(item, Assert.Single(service.Automations));
        }
        Assert.Equal(original, await File.ReadAllTextAsync(DataPath));
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp-*"));
    }

    [Fact]
    public async Task FailedDurableReservationPreventsScheduledSideEffect()
    {
        var now = DateTimeOffset.UtcNow;
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions, DataPath, () => now, startScheduler: false);
        var item = await service.CreateAutomationAsync("Focus", AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(1)), AutomationAction.Timer(TimeSpan.FromMinutes(25)));
        now = now.AddMinutes(2);
        AutomationExecutionResult? result = null;
        service.AutomationFired += (_, value) => result = value;
        using (var held = new FileStream(DataPath, FileMode.Open, FileAccess.Read, FileShare.None))
            await service.EvaluateDueAutomationsAsync();
        Assert.NotNull(result);
        Assert.False(result.IsSuccess);
        Assert.Contains("Nothing was executed", result.Message);
        Assert.Equal(TimerStatus.None, timer.CurrentTimer.Status);
        Assert.Equal(item, Assert.Single(service.Automations));
    }

    [Fact]
    public async Task ConcurrentCreatesRetainEveryPersistedItem()
    {
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions, DataPath, startScheduler: false);
        await Task.WhenAll(Enumerable.Range(0, 20).Select(i => service.CreateAutomationAsync("Reminder " + i,
            AutomationTrigger.Daily(9, 0), AutomationAction.Reminder("Hello"))));
        Assert.Equal(20, service.Automations.Count);
        Assert.Equal(20, JsonSerializer.Deserialize<List<AmoraAutomation>>(await File.ReadAllTextAsync(DataPath))!.Count);
    }

    [Fact]
    public async Task ConcurrentSchedulerEvaluationsExecuteOccurrenceOnce()
    {
        var now = DateTimeOffset.UtcNow;
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        var media = new BlockingMedia();
        using var service = new LocalAutomationService(timer, media, suggestions, DataPath, () => now, startScheduler: false);
        await service.CreateAutomationAsync("Pause", AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(1)), AutomationAction.PauseMedia());
        now = now.AddMinutes(2);
        var first = service.EvaluateDueAutomationsAsync();
        await media.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var second = service.EvaluateDueAutomationsAsync();
        media.Release.TrySetResult();
        await Task.WhenAll(first, second);
        Assert.Equal(1, media.PauseCalls);
        Assert.True(service.Automations[0].NextRunAt > now);
    }

    [Fact]
    public async Task DeleteDuringInFlightActionCannotResurrectOrEditWrongItem()
    {
        var now = DateTimeOffset.UtcNow;
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        var media = new BlockingMedia();
        using var service = new LocalAutomationService(timer, media, suggestions, DataPath, () => now, startScheduler: false);
        var target = await service.CreateAutomationAsync("Pause", AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(1)), AutomationAction.PauseMedia());
        now = now.AddMinutes(2);
        var evaluation = service.EvaluateDueAutomationsAsync();
        await media.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var deletion = service.DeleteAutomationAsync(target.Id);
        Assert.False(deletion.IsCompleted);
        media.Release.TrySetResult();
        await evaluation;
        Assert.True(await deletion);
        Assert.Empty(service.Automations);
        Assert.Empty(JsonSerializer.Deserialize<List<AmoraAutomation>>(await File.ReadAllTextAsync(DataPath))!);
    }

    [Fact]
    public async Task CorruptStorageIsPreservedBeforeExplicitReplacement()
    {
        await File.WriteAllTextAsync(DataPath, "{broken");
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService();
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions, DataPath, startScheduler: false);
        await Assert.ThrowsAsync<AutomationPersistenceException>(() => service.LoadAutomationsAsync());
        Assert.Empty(service.Automations);
        var backup = Assert.Single(Directory.GetFiles(_directory, "*.corrupt-*"));
        Assert.Equal("{broken", await File.ReadAllTextAsync(backup));
        Assert.Equal("{broken", await File.ReadAllTextAsync(DataPath));
        await service.CreateAutomationAsync("New", AutomationTrigger.Daily(9, 0), AutomationAction.Reminder("Hello"));
        Assert.Single(service.Automations);
        Assert.Equal("{broken", await File.ReadAllTextAsync(backup));
    }

    [Fact]
    public async Task ExplicitRemindersWorkWhileProactiveSuggestionsStayDisabled()
    {
        using var timer = new StandardTimerService();
        using var suggestions = new ProactiveSuggestionService(settingsProvider: () => new AISettings(EnableProactiveSuggestions: false));
        using var service = new LocalAutomationService(timer, new PreviewMediaService(), suggestions, DataPath, startScheduler: false);
        var item = await service.CreateAutomationAsync("Hydrate", AutomationTrigger.Daily(9, 0), AutomationAction.Reminder("Drink water"));
        var result = await service.RunManuallyAsync(item.Id);
        Assert.True(result.IsSuccess);
        Assert.False(suggestions.IsEnabled);
        Assert.Equal("Drink water", suggestions.ActiveSuggestion!.Message);
        suggestions.IsEnabled = false;
        Assert.NotNull(suggestions.ActiveSuggestion);
        suggestions.DismissActive();
        suggestions.PresentSuggestion(new("unsolicited", "Insight", "Hello", "OK", "Test"));
        Assert.Null(suggestions.ActiveSuggestion);
        Assert.True((await service.RunManuallyAsync(item.Id)).IsSuccess);
        Assert.Equal("Drink water", suggestions.ActiveSuggestion!.Message); // later occurrence is not permanently dismissed
    }

    [Fact]
    public void ExplicitRemindersQueueWithoutLosingTheirOrder()
    {
        using var suggestions = new ProactiveSuggestionService { IsEnabled = false };
        Assert.True(suggestions.PresentReminder(new("one", "First", "One", "OK", "Automation")));
        Assert.True(suggestions.PresentReminder(new("two", "Second", "Two", "OK", "Automation")));
        Assert.Equal("one", suggestions.ActiveSuggestion!.Id);
        suggestions.DismissActive();
        Assert.Equal("two", suggestions.ActiveSuggestion!.Id);
        suggestions.DismissActive();
        Assert.Null(suggestions.ActiveSuggestion);
    }

    [Fact]
    public async Task CompletingOldSuggestionDoesNotDismissReminderArrivingDuringAction()
    {
        using var suggestions = new ProactiveSuggestionService();
        var finish = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        suggestions.PresentSuggestion(new("insight", "Insight", "Run", "Run", "Test", OnAction: () => finish.Task));
        var action = suggestions.ExecuteActiveActionAsync();
        suggestions.PresentReminder(new("reminder", "Reminder", "Important", "OK", "Automation"));
        finish.SetResult();
        await action;
        Assert.Equal("reminder", suggestions.ActiveSuggestion!.Id);
    }

    private sealed class BlockingMedia : IMediaService
    {
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int PauseCalls { get; private set; }
        public MediaTrack CurrentTrack => MediaTrack.None;
        public bool IsConnected => true;
        public string ProviderName => "Test";
        public event EventHandler<MediaTrack>? TrackChanged { add { } remove { } }
        public Task RefreshAsync() => Task.CompletedTask;
        public Task TogglePlayPauseAsync() => Task.CompletedTask;
        public Task PlayAsync() => Task.CompletedTask;
        public async Task PauseAsync() { PauseCalls++; Started.TrySetResult(); await Release.Task; }
        public Task NextTrackAsync() => Task.CompletedTask;
        public Task PreviousTrackAsync() => Task.CompletedTask;
        public Task SeekAsync(double seconds) => Task.CompletedTask;
    }
}
