using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class ProactiveSuggestionEngineTests
{
    [Fact]
    public void OptInDefault_IsDisabled_InAISettingsDefault()
    {
        var settings = AISettings.Default;
        Assert.False(settings.EnableProactiveSuggestions);
    }

    [Fact]
    public void ProactiveEngine_DisabledByDefault_GeneratesNoSuggestionsOnTimerFinished()
    {
        var timerService = new StandardTimerService();
        var batteryService = new PreviewBatteryService();
        using var service = new ProactiveSuggestionService(
            timerService,
            batteryService,
            settingsProvider: () => AISettings.Default
        );

        Assert.False(service.IsEnabled);

        // Manually trigger a timer finished event
        timerService.Start(TimeSpan.FromSeconds(1), "Focus");
        timerService.Cancel(); // Reset

        // Directly invoke what happens on finish via service's trigger test
        service.PresentSuggestion(new ProactiveSuggestion(
            Id: "timer-focus-finished",
            Title: "Focus Completed",
            Message: "Break time",
            ActionLabel: "Break",
            Category: "Timer"
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void ProactiveEngine_DisabledByDefault_GeneratesNoSuggestionsOnLowBattery()
    {
        var batteryService = new PreviewBatteryService();
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => AISettings.Default
        );

        Assert.False(service.IsEnabled);

        // Send a low battery update while disabled
        batteryService.SetState(new BatterySnapshot(
            Percentage: 12,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromMinutes(45)
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void TimerFinished_WhenEnabled_PresentsFocusBreakSuggestion()
    {
        var timerService = new StandardTimerService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            timerService: timerService,
            settingsProvider: () => enabledSettings
        );

        Assert.True(service.IsEnabled);

        // Simulate a completed focus timer by starting and triggering completion
        timerService.Start(TimeSpan.FromSeconds(1), "Deep Work");
        // Wait briefly for tick to complete
        Thread.Sleep(1200);

        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal("timer-focus-finished", service.ActiveSuggestion.Id);
        Assert.Equal("Deep Work Completed", service.ActiveSuggestion.Title);
        Assert.Equal("Start 5m Break", service.ActiveSuggestion.ActionLabel);
        Assert.Equal("Timer", service.ActiveSuggestion.Category);
        Assert.Equal(SuggestionPriority.Normal, service.ActiveSuggestion.Priority);
    }

    [Fact]
    public void TimerFinished_BreakTimer_PresentsFocusSuggestion()
    {
        var timerService = new StandardTimerService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            timerService: timerService,
            settingsProvider: () => enabledSettings
        );

        timerService.Start(TimeSpan.FromSeconds(1), "Break");
        Thread.Sleep(1200);

        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal("timer-break-finished", service.ActiveSuggestion.Id);
        Assert.Equal("Break Completed", service.ActiveSuggestion.Title);
        Assert.Equal("Start 25m Focus", service.ActiveSuggestion.ActionLabel);
    }

    [Fact]
    public async Task TimerFinished_ActionExecution_StartsNewTimerAndDismisses()
    {
        var timerService = new StandardTimerService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            timerService: timerService,
            settingsProvider: () => enabledSettings
        );

        timerService.Start(TimeSpan.FromSeconds(1), "Focus");
        Thread.Sleep(1200);

        Assert.NotNull(service.ActiveSuggestion);

        // User clicks "Start 5m Break"
        await service.ExecuteActiveActionAsync();

        Assert.Null(service.ActiveSuggestion);
        Assert.Equal(TimerStatus.Running, timerService.CurrentTimer.Status);
        Assert.Equal("Break", timerService.CurrentTimer.Label);
        Assert.Equal(TimeSpan.FromMinutes(5), timerService.CurrentTimer.TotalDuration);
    }

    [Fact]
    public void StartingNewTimer_AutomaticallyClearsObsoleteTimerSuggestion()
    {
        var timerService = new StandardTimerService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            timerService: timerService,
            settingsProvider: () => enabledSettings
        );

        timerService.Start(TimeSpan.FromSeconds(1), "Focus");
        Thread.Sleep(1200);

        Assert.NotNull(service.ActiveSuggestion);

        // User starts a new timer independently
        timerService.Start(TimeSpan.FromMinutes(10), "Independent");

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void LowBattery_WhenEnabledAndUnplugged_PresentsWarning()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        batteryService.SetState(new BatterySnapshot(
            Percentage: 18,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromHours(1).Add(TimeSpan.FromMinutes(15))
        ));

        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal("battery-low", service.ActiveSuggestion.Id);
        Assert.Equal("Low Battery", service.ActiveSuggestion.Title);
        Assert.Contains("18%", service.ActiveSuggestion.Message);
        Assert.Contains("1h 15m", service.ActiveSuggestion.Message);
        Assert.Equal("Acknowledge", service.ActiveSuggestion.ActionLabel);
        Assert.Equal("Power", service.ActiveSuggestion.Category);
        Assert.Equal(SuggestionPriority.High, service.ActiveSuggestion.Priority);
    }

    [Fact]
    public void CriticalBattery_SetsUrgentPriority()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        batteryService.SetState(new BatterySnapshot(
            Percentage: 8,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromMinutes(20)
        ));

        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal(SuggestionPriority.Urgent, service.ActiveSuggestion.Priority);
    }

    [Fact]
    public void LowBattery_IgnoredOnDesktopAC()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        // Desktop PC (no battery)
        batteryService.SetState(new BatterySnapshot(
            Percentage: 10,
            IsCharging: false,
            IsPluggedIn: true,
            HasBattery: false,
            EstimatedRemaining: null
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void LowBattery_IgnoredWhenPluggedInOrCharging()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        // Battery is at 15%, but plugged in and charging
        batteryService.SetState(new BatterySnapshot(
            Percentage: 15,
            IsCharging: true,
            IsPluggedIn: true,
            HasBattery: true,
            EstimatedRemaining: null
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void LowBattery_IgnoredWhenPercentageZeroOrNegative()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        // Invalid or missing telemetry
        batteryService.SetState(new BatterySnapshot(
            Percentage: 0,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: null
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void LowBattery_AutoClears_WhenLaptopPluggedIn()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        batteryService.SetState(new BatterySnapshot(
            Percentage: 15,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromMinutes(30)
        ));

        Assert.NotNull(service.ActiveSuggestion);

        // User plugs in power cable
        batteryService.SetState(new BatterySnapshot(
            Percentage: 15,
            IsCharging: true,
            IsPluggedIn: true,
            HasBattery: true,
            EstimatedRemaining: null
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void ShowAtMostOneSuggestionAtATime_DoesNotInterruptActiveSuggestion()
    {
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            settingsProvider: () => enabledSettings
        );

        var first = new ProactiveSuggestion(
            Id: "sug-first",
            Title: "First Alert",
            Message: "Don't interrupt me",
            ActionLabel: "OK",
            Category: "General",
            Priority: SuggestionPriority.Normal
        );

        var second = new ProactiveSuggestion(
            Id: "sug-second",
            Title: "Second Alert",
            Message: "I should be blocked",
            ActionLabel: "Dismiss",
            Category: "General",
            Priority: SuggestionPriority.High
        );

        service.PresentSuggestion(first);
        Assert.Equal("sug-first", service.ActiveSuggestion?.Id);

        // Present second while first is active
        service.PresentSuggestion(second);
        Assert.Equal("sug-first", service.ActiveSuggestion?.Id);
    }

    [Fact]
    public void DuplicateSuppression_CooldownBlocksImmediateRePresentation()
    {
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            settingsProvider: () => enabledSettings
        );

        var suggestion = new ProactiveSuggestion(
            Id: "sug-cooldown",
            Title: "Cooldown Test",
            Message: "Testing cooldown",
            ActionLabel: "OK",
            Category: "Test",
            CooldownDuration: TimeSpan.FromMinutes(10)
        );

        service.PresentSuggestion(suggestion);
        Assert.NotNull(service.ActiveSuggestion);

        // Clear active suggestion
        service.ClearActive();
        Assert.Null(service.ActiveSuggestion);

        // Immediate re-presentation should be blocked by cooldown
        service.PresentSuggestion(suggestion);
        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public async Task TogglingSettingOff_ImmediatelyClearsActiveSuggestion()
    {
        var credStorage = new InMemoryCredentialStorage();
        var settingsService = new AISettingsService(credStorage, System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AMORA.Tests", System.Guid.NewGuid().ToString("N"), "settings.json"));
        await settingsService.SaveSettingsAsync(AISettings.Default with { EnableProactiveSuggestions = true });

        using var service = new ProactiveSuggestionService(
            settingsService: settingsService
        );

        Assert.True(service.IsEnabled);

        service.PresentSuggestion(new ProactiveSuggestion(
            Id: "sug-active",
            Title: "Active Alert",
            Message: "To be cleared",
            ActionLabel: "Action",
            Category: "Test"
        ));

        Assert.NotNull(service.ActiveSuggestion);

        // Toggle setting to disabled
        await settingsService.SaveSettingsAsync(AISettings.Default with { EnableProactiveSuggestions = false });

        Assert.False(service.IsEnabled);
        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public void Lifecycle_Dispose_UnsubscribesAndClears()
    {
        var batteryService = new PreviewBatteryService();
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        var service = new ProactiveSuggestionService(
            batteryService: batteryService,
            settingsProvider: () => enabledSettings
        );

        service.PresentSuggestion(new ProactiveSuggestion(
            Id: "sug-dispose",
            Title: "Before Dispose",
            Message: "Message",
            ActionLabel: "OK",
            Category: "Test"
        ));

        Assert.NotNull(service.ActiveSuggestion);

        service.Dispose();

        Assert.Null(service.ActiveSuggestion);

        // Subsequent update after disposal should not throw or resurrect suggestions
        batteryService.SetState(new BatterySnapshot(
            Percentage: 10,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: null
        ));

        Assert.Null(service.ActiveSuggestion);
    }

    [Fact]
    public async Task ActionSafety_NeverExecutesActionAutomatically()
    {
        bool actionWasInvoked = false;
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            settingsProvider: () => enabledSettings
        );

        var suggestion = new ProactiveSuggestion(
            Id: "sug-safety",
            Title: "Safe Action",
            Message: "Requires explicit click",
            ActionLabel: "Run",
            Category: "Safety",
            OnAction: () =>
            {
                actionWasInvoked = true;
                return Task.CompletedTask;
            }
        );

        service.PresentSuggestion(suggestion);

        // Triggering and presenting must NEVER execute OnAction automatically!
        Assert.False(actionWasInvoked);
        Assert.NotNull(service.ActiveSuggestion);

        // Only explicit user click invokes it
        await service.ExecuteActiveActionAsync();
        Assert.True(actionWasInvoked);
    }

    [Fact]
    public async Task ActionSafety_HandlesActionExceptionGracefully()
    {
        var enabledSettings = AISettings.Default with { EnableProactiveSuggestions = true };
        using var service = new ProactiveSuggestionService(
            settingsProvider: () => enabledSettings
        );

        var suggestion = new ProactiveSuggestion(
            Id: "sug-throwing",
            Title: "Throwing Action",
            Message: "Throws exception",
            ActionLabel: "Fail",
            Category: "Test",
            OnAction: () => throw new InvalidOperationException("Simulation failure")
        );

        service.PresentSuggestion(suggestion);
        Assert.NotNull(service.ActiveSuggestion);

        // Keep a truthful retry state instead of hiding a failed action as if it succeeded.
        var exception = await Record.ExceptionAsync(() => service.ExecuteActiveActionAsync());
        Assert.Null(exception);
        Assert.NotNull(service.ActiveSuggestion);
        Assert.Equal("sug-throwing", service.ActiveSuggestion.Id);
        Assert.Equal("Try again", service.ActiveSuggestion.ActionLabel);
        Assert.Contains("could not be completed", service.ActiveSuggestion.Message);
        Assert.DoesNotContain("Simulation failure", service.ActiveSuggestion.Message);
    }

    [Fact]
    public void SuggestionViewModel_ReflectsDisabledStateTruthfully()
    {
        using var disabledService = new ProactiveSuggestionService(
            settingsProvider: () => AISettings.Default // EnableProactiveSuggestions == false
        );

        using var vm = new SuggestionViewModel(disabledService);

        Assert.False(vm.HasSuggestion);
        Assert.Equal("Suggestions Disabled", vm.Title);
        Assert.Contains("Settings", vm.Message);
        Assert.Equal(string.Empty, vm.ActionLabel);

        using var enabledService = new ProactiveSuggestionService(
            settingsProvider: () => AISettings.Default with { EnableProactiveSuggestions = true }
        );

        using var vm2 = new SuggestionViewModel(enabledService);

        Assert.False(vm2.HasSuggestion);
        Assert.Equal("All caught up", vm2.Title);
        Assert.Contains("No suggestions", vm2.Message);
        Assert.Equal(string.Empty, vm2.ActionLabel);
    }
}
