using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantCommandViewModelTests : IDisposable
{
    private sealed class ControlledAssistantEngine : IAssistantEngine
    {
        private readonly TaskCompletionSource<AssistantExecutionResult> _execution = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public bool HasPendingConfirmation => false;
        public string? PendingConfirmationPrompt => null;
        public string? SubmittedInput { get; private set; }

        public Task<AssistantExecutionResult> ExecuteAsync(string input, CancellationToken cancellationToken = default)
        {
            SubmittedInput = input;
            return _execution.Task;
        }

        public Task<AssistantExecutionResult> ConfirmPendingActionAsync() =>
            Task.FromResult(AssistantExecutionResult.Failed("No confirmation is pending."));

        public void CancelPendingAction() { }

        public void Complete(AssistantExecutionResult result) => _execution.TrySetResult(result);
    }

    private class CancellableAIProvider : IAIProvider
    {
        private readonly TaskCompletionSource<string> _tcs = new();

        public string ProviderId => "cancellable_ai";
        public string DisplayName => "Cancellable AI Provider";
        public bool IsConfigured => true;

        public async Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default)
        {
            using var reg = cancellationToken.Register(() => _tcs.TrySetCanceled(cancellationToken));
            return await _tcs.Task;
        }

        public void Complete(string result) => _tcs.TrySetResult(result);
    }

    private readonly StandardTimerService _timerService;
    private readonly PreviewMediaService _mediaService;
    private readonly PreviewBatteryService _batteryService;
    private readonly PreviewSystemTelemetryService _telemetryService;
    private readonly LocalStubAIProvider _aiProvider;
    private readonly DeterministicCommandRouter _router;
    private readonly AssistantEngine _engine;
    private readonly AssistantCommandViewModel _viewModel;

    public AssistantCommandViewModelTests()
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

        _viewModel = new AssistantCommandViewModel(_engine);
    }

    public void Dispose()
    {
        _viewModel.Dispose();
        _timerService.Dispose();
    }

    [Fact]
    public void InputText_TracksCanSubmitAndHasText()
    {
        var changedProps = new List<string>();
        _viewModel.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName != null)
                changedProps.Add(e.PropertyName);
        };

        Assert.False(_viewModel.HasText);
        Assert.False(_viewModel.CanSubmit);

        _viewModel.InputText = "start 10m timer";
        Assert.True(_viewModel.HasText);
        Assert.True(_viewModel.CanSubmit);
        Assert.Contains(nameof(_viewModel.InputText), changedProps);
        Assert.Contains(nameof(_viewModel.HasText), changedProps);
        Assert.Contains(nameof(_viewModel.CanSubmit), changedProps);

        _viewModel.InputText = "   ";
        Assert.True(_viewModel.HasText);
        Assert.False(_viewModel.CanSubmit);
    }

    [Fact]
    public async Task SubmitAsync_ExecutesCommand_ClearsInput_AndFiresEvent()
    {
        AssistantExecutionResult? capturedResult = null;
        _viewModel.ResultReceived += (s, res) => capturedResult = res;

        _viewModel.InputText = "start 5m timer";
        await _viewModel.SubmitAsync();

        Assert.Equal(string.Empty, _viewModel.InputText);
        Assert.True(_viewModel.HasStatus);
        Assert.NotNull(capturedResult);
        Assert.Equal(AssistantResultStatus.Success, capturedResult.Status);
        Assert.Equal(MascotMood.Focused, capturedResult.Mood);
        Assert.Contains("5m", _viewModel.StatusMessage);
    }

    [Fact]
    public async Task SubmitAsync_EmptyOrWhitespace_DoesNotExecute()
    {
        bool eventFired = false;
        _viewModel.ResultReceived += (s, _) => eventFired = true;

        _viewModel.InputText = "";
        await _viewModel.SubmitAsync();

        Assert.False(eventFired);
        Assert.False(_viewModel.HasStatus);
    }

    [Fact]
    public async Task ConsequentialAction_PresentsConfirmation_AndConfirms()
    {
        _viewModel.InputText = "reset settings";
        await _viewModel.SubmitAsync();

        Assert.True(_viewModel.HasPendingConfirmation);
        Assert.NotNull(_viewModel.PendingActionDescription);
        Assert.Equal("\uE7BA", _viewModel.StatusGlyph); // Warning glyph

        await _viewModel.ConfirmAsync();

        Assert.False(_viewModel.HasPendingConfirmation);
        Assert.Null(_viewModel.PendingActionDescription);
        Assert.Contains("Settings reset", _viewModel.StatusMessage);
    }

    [Fact]
    public async Task ConsequentialAction_CanBeCancelled()
    {
        _viewModel.InputText = "clear all memories";
        await _viewModel.SubmitAsync();

        Assert.True(_viewModel.HasPendingConfirmation);

        _viewModel.CancelConfirmation();

        Assert.False(_viewModel.HasPendingConfirmation);
        Assert.Contains("cancelled", _viewModel.StatusMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Clear_ResetsInputAndStatus()
    {
        _viewModel.InputText = "some text";
        _viewModel.Clear();

        Assert.Equal(string.Empty, _viewModel.InputText);
        Assert.False(_viewModel.HasStatus);
        Assert.Empty(_viewModel.StatusMessage);
        Assert.False(_viewModel.HasPendingConfirmation);
    }

    [Fact]
    public void ResetConversation_ClearsEngineAndUpdatesStatus()
    {
        _viewModel.InputText = "some text";
        _viewModel.ResetConversation();

        Assert.Equal(string.Empty, _viewModel.InputText);
        Assert.True(_viewModel.HasStatus);
        Assert.Equal("Conversation reset.", _viewModel.StatusMessage);
        Assert.Equal(AssistantResultStatus.Information, _viewModel.LastStatus);
    }

    [Fact]
    public async Task SubmitAsync_EmitsThinkingStateBeforeFinalResult()
    {
        var capturedResults = new List<AssistantExecutionResult>();
        _viewModel.ResultReceived += (s, res) => capturedResults.Add(res);

        _viewModel.InputText = "start 5m timer";
        await _viewModel.SubmitAsync();

        Assert.True(capturedResults.Count >= 2);
        Assert.Equal("AMORA is thinking...", capturedResults[0].FeedbackMessage);
        Assert.Equal(MascotMood.Thinking, capturedResults[0].Mood);
        Assert.Equal(AssistantResultStatus.Success, capturedResults[1].Status);
    }

    [Fact]
    public async Task SubmitAsync_ProcessingStateDrivesStatusColorAndGlyph()
    {
        var engine = new ControlledAssistantEngine();
        using var viewModel = new AssistantCommandViewModel(engine);
        var processingTransitions = new List<bool>();
        viewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(viewModel.IsProcessing))
            {
                processingTransitions.Add(viewModel.IsProcessing);
            }
        };

        viewModel.InputText = "hold this request";
        var submitTask = viewModel.SubmitAsync();

        Assert.Equal("hold this request", engine.SubmittedInput);
        Assert.True(viewModel.IsProcessing);
        Assert.Equal("#52CCFF", viewModel.StatusColor);
        Assert.Equal("\uF16A", viewModel.StatusGlyph);

        viewModel.InputText = "another request";
        Assert.False(viewModel.CanSubmit);

        engine.Complete(AssistantExecutionResult.Success("Completed."));
        await submitTask;

        Assert.False(viewModel.IsProcessing);
        Assert.True(viewModel.CanSubmit);
        Assert.Equal("#30D158", viewModel.StatusColor);
        Assert.Equal(new[] { true, false }, processingTransitions);

        viewModel.Clear();
        Assert.Equal("#9AA2B2", viewModel.StatusColor);
    }

    [Fact]
    public async Task CancelActiveRequest_CancelsInFlightRequest_AndReportsCancelled()
    {
        var cancellableAi = new CancellableAIProvider();
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            cancellableAi);

        using var vm = new AssistantCommandViewModel(engine);
        vm.InputText = "Tell me a long story";

        var submitTask = vm.SubmitAsync();

        Assert.True(vm.IsProcessing);

        vm.CancelActiveRequest();

        var result = await submitTask;

        Assert.False(vm.IsProcessing);
        Assert.Equal("Request cancelled.", result.FeedbackMessage);
        Assert.Equal(MascotMood.Idle, result.Mood);
    }

    [Fact]
    public async Task ResetConversation_CancelsActiveInFlightRequest()
    {
        var cancellableAi = new CancellableAIProvider();
        var engine = new AssistantEngine(
            _router,
            _timerService,
            _mediaService,
            _batteryService,
            _telemetryService,
            cancellableAi);

        using var vm = new AssistantCommandViewModel(engine);
        vm.InputText = "Tell me a story";

        var submitTask = vm.SubmitAsync();

        Assert.True(vm.IsProcessing);

        vm.ResetConversation();

        var result = await submitTask;

        Assert.False(vm.IsProcessing);
        Assert.Equal("Conversation reset.", vm.StatusMessage);
        Assert.Equal(AssistantResultStatus.Information, vm.LastStatus);
    }
}
