using System;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantEngineTests : IDisposable
{
    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;
    private readonly LocalStubAIProvider _aiProvider;
    private readonly DeterministicCommandRouter _router;
    private readonly AssistantEngine _engine;

    public AssistantEngineTests()
    {
        _timerService = new StandardTimerService();
        _mediaService = new PreviewMediaService();
        _batteryService = new PreviewBatteryService();
        _telemetryService = new PreviewSystemTelemetryService();
        _aiProvider = new LocalStubAIProvider();
        _router = new DeterministicCommandRouter();

        _engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            _aiProvider);
    }

    public void Dispose()
    {
        _timerService.Dispose();
    }

    [Fact]
    public async Task TimerExecution_EndToEndWorkflow()
    {
        // 1. Start timer
        var startResult = await _engine.ExecuteAsync("start 10m timer");
        Assert.Equal(AssistantResultStatus.Success, startResult.Status);
        Assert.Equal(TimerStatus.Running, _timerService.CurrentTimer.Status);
        Assert.Equal(MascotMood.Focused, startResult.Mood);

        // 2. Add time
        var addResult = await _engine.ExecuteAsync("add a minute");
        Assert.Equal(AssistantResultStatus.Success, addResult.Status);

        // 3. Pause
        var pauseResult = await _engine.ExecuteAsync("pause timer");
        Assert.Equal(AssistantResultStatus.Success, pauseResult.Status);
        Assert.Equal(TimerStatus.Paused, _timerService.CurrentTimer.Status);

        // 4. Honest failure on duplicate pause
        var dupPauseResult = await _engine.ExecuteAsync("pause timer");
        Assert.Equal(AssistantResultStatus.Failed, dupPauseResult.Status);
        Assert.Contains("No running timer", dupPauseResult.FeedbackMessage);

        // 5. Resume
        var resumeResult = await _engine.ExecuteAsync("resume timer");
        Assert.Equal(AssistantResultStatus.Success, resumeResult.Status);
        Assert.Equal(TimerStatus.Running, _timerService.CurrentTimer.Status);

        // 6. Honest failure on duplicate resume
        var dupResumeResult = await _engine.ExecuteAsync("resume timer");
        Assert.Equal(AssistantResultStatus.Failed, dupResumeResult.Status);
        Assert.Contains("No paused timer", dupResumeResult.FeedbackMessage);

        // 7. Cancel
        var cancelResult = await _engine.ExecuteAsync("cancel timer");
        Assert.Equal(AssistantResultStatus.Success, cancelResult.Status);
        Assert.Equal(TimerStatus.None, _timerService.CurrentTimer.Status);

        // 8. Honest failure on cancel when none active
        var dupCancelResult = await _engine.ExecuteAsync("cancel timer");
        Assert.Equal(AssistantResultStatus.Failed, dupCancelResult.Status);
        Assert.Contains("No active timer", dupCancelResult.FeedbackMessage);
    }

    [Fact]
    public async Task MediaExecution_EndToEndWorkflow()
    {
        // PreviewMediaService starts in Playing state
        Assert.True(_mediaService.CurrentTrack.IsPlaying);

        // 1. Pause media
        var pauseResult = await _engine.ExecuteAsync("pause music");
        Assert.Equal(AssistantResultStatus.Success, pauseResult.Status);
        Assert.False(_mediaService.CurrentTrack.IsPlaying);

        // 2. Play media
        var playResult = await _engine.ExecuteAsync("play music");
        Assert.Equal(AssistantResultStatus.Success, playResult.Status);
        Assert.True(_mediaService.CurrentTrack.IsPlaying);

        // 3. Skip track
        var nextResult = await _engine.ExecuteAsync("next track");
        Assert.Equal(AssistantResultStatus.Success, nextResult.Status);
        Assert.Contains("Now playing", nextResult.FeedbackMessage);

        // 4. Previous track
        var prevResult = await _engine.ExecuteAsync("prev track");
        Assert.Equal(AssistantResultStatus.Success, prevResult.Status);

        // 5. Toggle playback
        var toggleResult = await _engine.ExecuteAsync("toggle playback");
        Assert.Equal(AssistantResultStatus.Success, toggleResult.Status);
    }

    [Fact]
    public async Task MediaExecution_TruthfulFailure_WhenNoSessionOrDuplicateState()
    {
        var unavailableMedia = new PreviewMediaService(MediaTrack.None);
        var customEngine = new AssistantEngine(
            _router,
            _timerService,
            unavailableMedia,
            _batteryService,
            _telemetryService,
            _aiProvider);

        var playResult = await customEngine.ExecuteAsync("play music");
        Assert.Equal(AssistantResultStatus.Failed, playResult.Status);
        Assert.Contains("No active media session", playResult.FeedbackMessage);

        var pauseResult = await customEngine.ExecuteAsync("pause music");
        Assert.Equal(AssistantResultStatus.Failed, pauseResult.Status);
        Assert.Contains("No active media session", pauseResult.FeedbackMessage);
    }

    [Fact]
    public async Task TelemetryAndBatteryExecution_ReturnsTruthfulInformation()
    {
        var batteryResult = await _engine.ExecuteAsync("battery status");
        Assert.Equal(AssistantResultStatus.Information, batteryResult.Status);
        Assert.Contains("%", batteryResult.FeedbackMessage);

        var systemResult = await _engine.ExecuteAsync("system status");
        Assert.Equal(AssistantResultStatus.Information, systemResult.Status);
        Assert.Contains("CPU", systemResult.FeedbackMessage);
        Assert.Contains("RAM", systemResult.FeedbackMessage);
    }

    [Fact]
    public async Task ConsequentialAction_RequiresConfirmationFlow()
    {
        Assert.False(_engine.HasPendingAction);

        var promptResult = await _engine.ExecuteAsync("reset settings");
        Assert.Equal(AssistantResultStatus.NeedsConfirmation, promptResult.Status);
        Assert.True(promptResult.RequiresConfirmation);
        Assert.Equal(MascotMood.Alert, promptResult.Mood);
        Assert.True(_engine.HasPendingAction);
        Assert.NotNull(_engine.PendingActionDescription);

        // Confirm the action
        var confirmResult = await _engine.ConfirmPendingActionAsync();
        Assert.Equal(AssistantResultStatus.Success, confirmResult.Status);
        Assert.Contains("Settings reset", confirmResult.FeedbackMessage);
        Assert.False(_engine.HasPendingAction);
    }

    [Fact]
    public async Task ConsequentialAction_CancelClearsPendingState()
    {
        await _engine.ExecuteAsync("clear all memories");
        Assert.True(_engine.HasPendingAction);

        _engine.CancelPendingAction();
        Assert.False(_engine.HasPendingAction);

        // Attempting to confirm after cancel fails honestly
        var confirmResult = await _engine.ConfirmPendingActionAsync();
        Assert.Equal(AssistantResultStatus.Failed, confirmResult.Status);
        Assert.Contains("No action", confirmResult.FeedbackMessage);
    }

    [Fact]
    public async Task UnknownQuery_WithOfflineAIProvider_ReturnsTruthfulUnsupported()
    {
        var result = await _engine.ExecuteAsync("explain quantum electrodynamics");

        Assert.Equal(AssistantResultStatus.Unsupported, result.Status);
        Assert.Contains("Local AI engine is currently offline", result.FeedbackMessage);
        Assert.Equal(MascotMood.Thinking, result.Mood);
    }

    [Fact]
    public async Task EmptyInput_ReturnsTruthfulFailed()
    {
        var result = await _engine.ExecuteAsync("   ");

        Assert.Equal(AssistantResultStatus.Failed, result.Status);
        Assert.Contains("Please enter a command", result.FeedbackMessage);
    }
}
