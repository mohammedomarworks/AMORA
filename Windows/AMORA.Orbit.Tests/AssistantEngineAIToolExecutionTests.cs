using System;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantEngineAIToolExecutionTests : IDisposable
{
    private class MockAIProvider : IAIProvider
    {
        private readonly Func<string, Task<string>> _generator;

        public MockAIProvider(Func<string, Task<string>> generator, bool isConfigured = true)
        {
            _generator = generator;
            IsConfigured = isConfigured;
        }

        public string ProviderId => "mock_ai";
        public string DisplayName => "Mock AI Provider";
        public bool IsConfigured { get; set; }

        public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
            _generator(prompt);
    }

    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;
    private readonly DeterministicCommandRouter _router;

    public AssistantEngineAIToolExecutionTests()
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
    public async Task ExecuteAsync_AIConversationalResponse_ReturnsInformationOutcome()
    {
        var mockAi = new MockAIProvider(prompt =>
            Task.FromResult("Mount Everest is the highest mountain above sea level at 8,848.86 meters.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("How tall is Mount Everest?");

        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.Contains("Mount Everest", result.Message);
        Assert.Equal(MascotMood.Happy, result.Mood);
    }

    [Fact]
    public async Task ExecuteAsync_AIProposesValidTimerAction_ExecutesRealTimerDirectly()
    {
        var mockAi = new MockAIProvider(prompt =>
            Task.FromResult("Sure thing, I'll set a timer for your tea.\n[COMMAND: start 12m timer]")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Put on a tea timer for 12 minutes please");

        Assert.Equal(AssistantResultStatus.Success, result.Status);
        Assert.Equal(TimerStatus.Running, _timerService.CurrentTimer.Status);
        Assert.Equal(TimeSpan.FromMinutes(12), _timerService.CurrentTimer.TotalDuration);
        Assert.Contains("Sure thing", result.Message);
        Assert.Contains("Timer started: 12m", result.Message);
    }

    [Fact]
    public async Task ExecuteAsync_AIProposesValidMediaAction_ExecutesRealMediaDirectly()
    {
        // Media starts playing
        Assert.True(_mediaService.CurrentTrack.IsPlaying);

        var mockAi = new MockAIProvider(prompt =>
            Task.FromResult("[COMMAND: pause music]\nPaused your music.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Silence the music for a moment");

        Assert.Equal(AssistantResultStatus.Success, result.Status);
        Assert.False(_mediaService.CurrentTrack.IsPlaying);
        Assert.Contains("Playback paused", result.Message);
    }

    [Fact]
    public async Task ExecuteAsync_AIProposesConsequentialAction_RequiresExplicitConfirmation()
    {
        var mockAi = new MockAIProvider(prompt =>
            Task.FromResult("[COMMAND: reset settings]\nI can reset your settings, but please confirm first.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Can you restore defaults?");

        // Security check: Even if proposed by AI, consequential actions MUST trigger confirmation!
        Assert.Equal(AssistantResultStatus.NeedsConfirmation, result.Status);
        Assert.True(result.RequiresConfirmation);
        Assert.True(engine.HasPendingAction);

        var confirmResult = await engine.ConfirmPendingActionAsync();
        Assert.Equal(AssistantResultStatus.Success, confirmResult.Status);
        Assert.False(engine.HasPendingAction);
    }

    [Fact]
    public async Task ExecuteAsync_AIProposesUnsafeUnknownCommand_FailsSafelyWithoutExecution()
    {
        var mockAi = new MockAIProvider(prompt =>
            Task.FromResult("[COMMAND: delete system32 /f]\nAttempting dangerous command.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Run an unknown action");

        // Action was rejected by allowlist router; treated as conversational response safely
        Assert.Equal(AssistantResultStatus.Information, result.Status);
        Assert.False(engine.HasPendingAction);
    }

    [Fact]
    public async Task ExecuteAsync_AIProviderThrowsException_ReturnsTruthfulFailureOutcome()
    {
        var mockAi = new MockAIProvider(prompt =>
            throw new HttpRequestException("Authentication failed (401): Invalid API key.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Test query");

        Assert.Equal(AssistantResultStatus.Failed, result.Status);
        Assert.Contains("AI request failed", result.Message);
        Assert.Contains("credentials were rejected", result.Message);
        Assert.DoesNotContain("invalid Gemini API key", result.Message);
        Assert.Equal(MascotMood.Alert, result.Mood);
    }

    [Fact]
    public async Task ExecuteAsync_RateLimit429_ReturnsFriendlyRateLimitOutcome()
    {
        var mockAi = new MockAIProvider(prompt =>
            throw new HttpRequestException("Google Gemini API returned 429 ResourceExhausted: Quota exceeded.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Test query");

        Assert.Equal(AssistantResultStatus.Failed, result.Status);
        Assert.Contains("AI request failed: rate limit reached", result.Message);
        Assert.Equal(MascotMood.Alert, result.Mood);
    }

    [Fact]
    public async Task ExecuteAsync_ConnectionTimeout_ReturnsFriendlyTimeoutOutcome()
    {
        var mockAi = new MockAIProvider(prompt =>
            throw new TimeoutException("The connection timed out after 15 seconds.")
        );

        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            mockAi
        );

        var result = await engine.ExecuteAsync("Test query");

        Assert.Equal(AssistantResultStatus.Failed, result.Status);
        Assert.Contains("AI request failed: connection timed out", result.Message);
        Assert.Equal(MascotMood.Alert, result.Mood);
    }
}
