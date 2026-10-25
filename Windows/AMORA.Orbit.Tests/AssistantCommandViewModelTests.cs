using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AssistantCommandViewModelTests : IDisposable
{
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
}
