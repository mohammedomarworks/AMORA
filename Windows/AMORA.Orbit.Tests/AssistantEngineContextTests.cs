using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantEngineContextTests : IDisposable
{
    private class RecordingMockAIProvider : IAIProvider
    {
        public string ProviderId => "recording_mock";
        public string DisplayName => "Recording Mock AI";
        public bool IsConfigured { get; set; } = true;

        public List<string> CapturedPrompts { get; } = new();

        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
            GenerateResponseAsync(prompt, null, cancellationToken);

        public Task<string> GenerateResponseAsync(
            string prompt,
            IReadOnlyList<ChatMessage>? history,
            CancellationToken cancellationToken = default)
        {
            CapturedPrompts.Add(prompt);
            return Task.FromResult($"AI Answer to: {prompt}");
        }
    }

    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;
    private readonly DeterministicCommandRouter _router;

    public AssistantEngineContextTests()
    {
        _timerService = new StandardTimerService();
        _mediaService = new PreviewMediaService();
        _batteryService = new PreviewBatteryService();
        _telemetryService = new PreviewSystemTelemetryService();
        _router = new DeterministicCommandRouter();
    }

    public void Dispose()
    {
        _timerService.Dispose();
    }

    [Fact]
    public async Task GetTimerStatus_WithRunningTimer_TruthfullyReportsRemainingTime()
    {
        _timerService.Start(TimeSpan.FromMinutes(15), "Focus Session");

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("how much time is left?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Equal(MascotMood.Focused, result.Mood);
        Assert.Contains("remaining", result.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Focus Session", result.Message);
    }

    [Fact]
    public async Task GetTimerStatus_WithNoTimer_TruthfullyReportsNoneActive()
    {
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("how much time is left?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Equal(MascotMood.Idle, result.Mood);
        Assert.Contains("No active timer running", result.Message);
    }

    [Fact]
    public async Task GetMediaStatus_WithPlayingTrack_TruthfullyReportsTitleAndArtist()
    {
        var track = new MediaTrack("Starboy", "The Weeknd", IsPlaying: true, IsAvailable: true);
        var mediaService = new PreviewMediaService(track);

        var engine = new AssistantEngine(
            _router,
            _timerService,
            mediaService,
            _batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("what song is this?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Equal(MascotMood.Happy, result.Mood);
        Assert.Contains("Playing: Starboy by The Weeknd", result.Message);
    }

    [Fact]
    public async Task GetMediaStatus_WithNoMedia_TruthfullyReportsNoSession()
    {
        var mediaService = new PreviewMediaService(MediaTrack.None);

        var engine = new AssistantEngine(
            _router,
            _timerService,
            mediaService,
            _batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("what's playing?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Equal(MascotMood.Idle, result.Mood);
        Assert.Contains("No active media playing", result.Message);
    }

    [Fact]
    public async Task GetBatteryStatus_DesktopAC_TruthfullyReportsDirectAC()
    {
        var batteryService = new PreviewBatteryService(BatterySnapshot.DesktopAC);

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("am i charging?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Contains("Desktop PC (Direct AC)", result.Message);
    }

    [Fact]
    public async Task GetBatteryStatus_LaptopCharging_ReportsChargingPercentage()
    {
        var chargingLaptop = BatterySnapshot.FromBatteryState(
            percentage: 75,
            isCharging: true,
            isPluggedIn: true,
            isDesktopAC: false,
            estimatedTimeRemaining: TimeSpan.FromMinutes(45)
        );
        var batteryService = new PreviewBatteryService(chargingLaptop);

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            batteryService,
            _telemetryService
        );

        var result = await engine.ExecuteAsync("am i charging?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Contains("75% (Charging)", result.Message);
    }

    [Fact]
    public async Task PrivacyDefault_DoesNotSendStatusContextToAI()
    {
        var mockAi = new RecordingMockAIProvider();
        var defaultSettings = AISettings.Default; // SendStatusContextToAI is false by default

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            aiProvider: mockAi,
            settingsProvider: () => defaultSettings
        );

        var result = await engine.ExecuteAsync("Tell me a fun fact about Mars");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Single(mockAi.CapturedPrompts);

        // Privacy assertion: default settings must NOT inject system context!
        Assert.Equal("Tell me a fun fact about Mars", mockAi.CapturedPrompts[0]);
        Assert.DoesNotContain("[System Context:", mockAi.CapturedPrompts[0]);
    }

    [Fact]
    public async Task PrivacyOptIn_IncludesCompactStatusContextInAIPrompt()
    {
        var mockAi = new RecordingMockAIProvider();
        _timerService.Start(TimeSpan.FromMinutes(20), "Coding");

        // Explicit opt-in enabled
        var optInSettings = AISettings.Default with { SendStatusContextToAI = true };

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            aiProvider: mockAi,
            settingsProvider: () => optInSettings
        );

        var result = await engine.ExecuteAsync("What am I currently doing?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Single(mockAi.CapturedPrompts);

        string promptSent = mockAi.CapturedPrompts[0];
        Assert.Contains("[System Context:", promptSent);
        Assert.Contains("Timer: 20:00 remaining of 20m (Coding) [running]", promptSent);
        Assert.Contains("What am I currently doing?", promptSent);
    }

    [Fact]
    public async Task ConversationHistory_NeverStoresInjectedSystemContext()
    {
        var mockAi = new RecordingMockAIProvider();
        var optInSettings = AISettings.Default with { SendStatusContextToAI = true };

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            aiProvider: mockAi,
            settingsProvider: () => optInSettings
        );

        await engine.ExecuteAsync("Summarize my current workflow");

        Assert.Equal(2, engine.ConversationHistory.Count);

        // Crucial privacy guarantee: ConversationHistory must store only the clean user query!
        Assert.Equal("Summarize my current workflow", engine.ConversationHistory[0].Content);
        Assert.DoesNotContain("[System Context:", engine.ConversationHistory[0].Content);
    }
}
