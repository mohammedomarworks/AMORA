using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class AssistantEngine : IAssistantEngine
{
    private static readonly Regex CommandTagRegex = new(
        @"\[(?:COMMAND|ACTION):\s*([^\]]+)\]",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private readonly IAssistantCommandRouter _router;
    private readonly ITimerService _timerService;
    private readonly IMediaService _mediaService;
    private readonly IBatteryService _batteryService;
    private readonly ISystemTelemetryService _telemetryService;
    private readonly IAIProvider? _aiProvider;
    private readonly IConversationSession _conversationSession;
    private readonly SemaphoreSlim _executionLock = new(1, 1);

    private Func<Task<AssistantExecutionResult>>? _pendingAction;
    private string? _pendingPrompt;

    public bool HasPendingConfirmation => _pendingAction != null;
    public string? PendingConfirmationPrompt => _pendingPrompt;

    public bool HasPendingAction => HasPendingConfirmation;
    public string? PendingActionDescription => PendingConfirmationPrompt;

    public IReadOnlyList<ChatMessage> ConversationHistory => _conversationSession.GetHistory();

    public AssistantEngine(
        IAssistantCommandRouter router,
        ITimerService timerService,
        IMediaService mediaService,
        IBatteryService batteryService,
        ISystemTelemetryService telemetryService,
        IAIProvider? aiProvider = null,
        IConversationSession? conversationSession = null)
    {
        _router = router ?? throw new ArgumentNullException(nameof(router));
        _timerService = timerService ?? throw new ArgumentNullException(nameof(timerService));
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _batteryService = batteryService ?? throw new ArgumentNullException(nameof(batteryService));
        _telemetryService = telemetryService ?? throw new ArgumentNullException(nameof(telemetryService));
        _aiProvider = aiProvider;
        _conversationSession = conversationSession ?? new ConversationSession();
    }

    public async Task<AssistantExecutionResult> ExecuteAsync(string input, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return AssistantExecutionResult.Failed("Please enter a command or question.");
        }

        await _executionLock.WaitAsync(cancellationToken);
        try
        {
            // Cancel any previous pending action if user inputs a new command
            _pendingAction = null;
            _pendingPrompt = null;

            var context = BuildCommandContext();
            var command = _router.Route(input, context);

            return await DispatchCommandAsync(command, input, context, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return AssistantExecutionResult.Failed($"Action failed: {ex.Message}");
        }
        finally
        {
            _executionLock.Release();
        }
    }

    public async Task<AssistantExecutionResult> ConfirmPendingActionAsync()
    {
        await _executionLock.WaitAsync();
        try
        {
            if (_pendingAction == null)
            {
                return AssistantExecutionResult.Failed("No action is currently pending confirmation.");
            }

            var action = _pendingAction;
            _pendingAction = null;
            _pendingPrompt = null;

            return await action();
        }
        catch (Exception ex)
        {
            return AssistantExecutionResult.Failed($"Execution failed: {ex.Message}");
        }
        finally
        {
            _executionLock.Release();
        }
    }

    public void CancelPendingAction()
    {
        _pendingAction = null;
        _pendingPrompt = null;
    }

    public void ResetConversation()
    {
        _conversationSession.Clear();
    }

    private CommandContext BuildCommandContext()
    {
        var timerSnapshot = _timerService.CurrentTimer;
        var track = _mediaService.CurrentTrack;

        return new CommandContext(
            IsTimerActive: timerSnapshot.Status != TimerStatus.None,
            IsTimerRunning: timerSnapshot.Status == TimerStatus.Running,
            IsMediaPlaying: track.IsPlaying,
            HasTrack: track != MediaTrack.None && !string.IsNullOrWhiteSpace(track.Title)
        );
    }

    private async Task<AssistantExecutionResult> DispatchCommandAsync(
        AssistantCommand command,
        string rawInput,
        CommandContext context,
        CancellationToken cancellationToken)
    {
        return command switch
        {
            AssistantCommand.StartTimer start => HandleStartTimer(start),
            AssistantCommand.PauseTimer => HandlePauseTimer(),
            AssistantCommand.ResumeTimer => HandleResumeTimer(),
            AssistantCommand.CancelTimer => HandleCancelTimer(),
            AssistantCommand.AddTimerTime add => HandleAddTimerTime(add),

            AssistantCommand.PlayMedia => await HandlePlayMediaAsync(),
            AssistantCommand.PauseMedia => await HandlePauseMediaAsync(),
            AssistantCommand.TogglePlayPauseMedia => await HandleTogglePlayPauseMediaAsync(),
            AssistantCommand.NextTrack => await HandleNextTrackAsync(),
            AssistantCommand.PreviousTrack => await HandlePreviousTrackAsync(),

            AssistantCommand.GetBatteryStatus => HandleGetBatteryStatus(),
            AssistantCommand.GetSystemStatus => HandleGetSystemStatus(),

            AssistantCommand.ResetConversation => HandleResetConversation(),

            AssistantCommand.ConsequentialAction consequential => HandleConsequentialAction(consequential),

            AssistantCommand.Unknown => await HandleUnknownAsync(rawInput, context, cancellationToken),

            _ => AssistantExecutionResult.Unsupported($"Unsupported command: {rawInput}")
        };
    }

    private AssistantExecutionResult HandleStartTimer(AssistantCommand.StartTimer start)
    {
        if (start.Duration <= TimeSpan.Zero)
        {
            return AssistantExecutionResult.Failed("Timer duration must be greater than zero.");
        }

        _timerService.Start(start.Duration, start.Label);
        string formatted = FormatDuration(start.Duration);
        return AssistantExecutionResult.Success($"Timer started: {formatted} ({start.Label}).", MascotMood.Focused);
    }

    private AssistantExecutionResult HandlePauseTimer()
    {
        var status = _timerService.CurrentTimer.Status;
        if (status != TimerStatus.Running)
        {
            return AssistantExecutionResult.Failed("No running timer to pause.");
        }

        _timerService.Pause();
        return AssistantExecutionResult.Success("Focus timer paused.", MascotMood.Idle);
    }

    private AssistantExecutionResult HandleResumeTimer()
    {
        var status = _timerService.CurrentTimer.Status;
        if (status != TimerStatus.Paused)
        {
            return AssistantExecutionResult.Failed("No paused timer to resume.");
        }

        _timerService.Resume();
        return AssistantExecutionResult.Success("Focus timer resumed.", MascotMood.Focused);
    }

    private AssistantExecutionResult HandleCancelTimer()
    {
        var status = _timerService.CurrentTimer.Status;
        if (status == TimerStatus.None)
        {
            return AssistantExecutionResult.Failed("No active timer to cancel.");
        }

        _timerService.Cancel();
        return AssistantExecutionResult.Success("Focus timer cancelled.", MascotMood.Idle);
    }

    private AssistantExecutionResult HandleAddTimerTime(AssistantCommand.AddTimerTime add)
    {
        var status = _timerService.CurrentTimer.Status;
        if (status is not (TimerStatus.Running or TimerStatus.Paused))
        {
            return AssistantExecutionResult.Failed("No active timer to add time to.");
        }

        int minutes = Math.Max(1, (int)add.Duration.TotalMinutes);
        for (int i = 0; i < minutes; i++)
        {
            _timerService.AddMinute();
        }

        return AssistantExecutionResult.Success($"Added {FormatDuration(add.Duration)} to timer.", MascotMood.Focused);
    }

    private async Task<AssistantExecutionResult> HandlePlayMediaAsync()
    {
        if (!_mediaService.IsConnected || _mediaService.CurrentTrack == MediaTrack.None || !_mediaService.CurrentTrack.IsAvailable)
        {
            return AssistantExecutionResult.Failed("No active media session found.");
        }

        if (_mediaService.CurrentTrack.IsPlaying)
        {
            return AssistantExecutionResult.Failed("Media is already playing.");
        }

        await _mediaService.PlayAsync();
        return AssistantExecutionResult.Success($"Now playing: {_mediaService.CurrentTrack.Title}.", MascotMood.Happy);
    }

    private async Task<AssistantExecutionResult> HandlePauseMediaAsync()
    {
        if (!_mediaService.IsConnected || _mediaService.CurrentTrack == MediaTrack.None || !_mediaService.CurrentTrack.IsAvailable)
        {
            return AssistantExecutionResult.Failed("No active media session found.");
        }

        if (!_mediaService.CurrentTrack.IsPlaying)
        {
            return AssistantExecutionResult.Failed("Media is already paused.");
        }

        await _mediaService.PauseAsync();
        return AssistantExecutionResult.Success("Playback paused.", MascotMood.Idle);
    }

    private async Task<AssistantExecutionResult> HandleTogglePlayPauseMediaAsync()
    {
        if (!_mediaService.IsConnected || _mediaService.CurrentTrack == MediaTrack.None || !_mediaService.CurrentTrack.IsAvailable)
        {
            return AssistantExecutionResult.Failed("No active media session found.");
        }

        await _mediaService.TogglePlayPauseAsync();
        bool isPlaying = _mediaService.CurrentTrack.IsPlaying;
        return AssistantExecutionResult.Success(
            isPlaying ? $"Now playing: {_mediaService.CurrentTrack.Title}." : "Playback paused.",
            isPlaying ? MascotMood.Happy : MascotMood.Idle
        );
    }

    private async Task<AssistantExecutionResult> HandleNextTrackAsync()
    {
        if (!_mediaService.IsConnected || _mediaService.CurrentTrack == MediaTrack.None || !_mediaService.CurrentTrack.IsAvailable)
        {
            return AssistantExecutionResult.Failed("No active media session to skip.");
        }

        await _mediaService.NextTrackAsync();
        return AssistantExecutionResult.Success($"Now playing: {_mediaService.CurrentTrack.Title}.", MascotMood.Happy);
    }

    private async Task<AssistantExecutionResult> HandlePreviousTrackAsync()
    {
        if (!_mediaService.IsConnected || _mediaService.CurrentTrack == MediaTrack.None || !_mediaService.CurrentTrack.IsAvailable)
        {
            return AssistantExecutionResult.Failed("No active media session to navigate.");
        }

        await _mediaService.PreviousTrackAsync();
        return AssistantExecutionResult.Success($"Now playing: {_mediaService.CurrentTrack.Title}.", MascotMood.Happy);
    }

    private AssistantExecutionResult HandleGetBatteryStatus()
    {
        var battery = _batteryService.GetSnapshot();
        return AssistantExecutionResult.Information(battery.Description, MascotMood.Listening);
    }

    private AssistantExecutionResult HandleGetSystemStatus()
    {
        var telemetry = _telemetryService.GetSnapshot();
        return AssistantExecutionResult.Information(
            $"CPU: {telemetry.CpuDisplayText} | RAM: {telemetry.MemoryDetailedText}",
            MascotMood.Listening
        );
    }

    private AssistantExecutionResult HandleConsequentialAction(AssistantCommand.ConsequentialAction consequential)
    {
        _pendingAction = consequential.Execute;
        _pendingPrompt = $"Confirmation required: Are you sure you want to {consequential.Description}?";

        return AssistantExecutionResult.NeedsConfirmation(_pendingPrompt, consequential.ActionId);
    }

    private AssistantExecutionResult HandleResetConversation()
    {
        ResetConversation();
        return AssistantExecutionResult.Success("Conversation history cleared.", MascotMood.Idle);
    }

    private async Task<AssistantExecutionResult> HandleUnknownAsync(
        string rawInput,
        CommandContext context,
        CancellationToken cancellationToken)
    {
        if (_aiProvider != null && _aiProvider.IsConfigured)
        {
            try
            {
                var history = _conversationSession.GetHistory();
                string aiResponse = await _aiProvider.GenerateResponseAsync(rawInput, history, cancellationToken);

                // Check if the AI proposed an allowlisted command
                var match = CommandTagRegex.Match(aiResponse);
                if (match.Success)
                {
                    string proposedCommand = match.Groups[1].Value.Trim();
                    string cleanText = CommandTagRegex.Replace(aiResponse, "").Trim();

                    // Strictly validate and route the proposed action through the deterministic engine
                    var parsedCommand = _router.Route(proposedCommand, context);

                    if (parsedCommand is not AssistantCommand.Unknown)
                    {
                        var executionResult = await DispatchCommandAsync(parsedCommand, proposedCommand, context, cancellationToken);

                        string recordedModelText = !string.IsNullOrWhiteSpace(cleanText) ? cleanText : aiResponse.Trim();
                        _conversationSession.AddTurn(rawInput, recordedModelText);

                        if (!string.IsNullOrWhiteSpace(cleanText))
                        {
                            return executionResult with
                            {
                                Message = $"{cleanText}\n{executionResult.Message}"
                            };
                        }

                        return executionResult;
                    }
                }

                _conversationSession.AddTurn(rawInput, aiResponse.Trim());
                return AssistantExecutionResult.Information(aiResponse.Trim(), MascotMood.Happy);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                return AssistantExecutionResult.Failed($"AI request failed: {ex.Message}");
            }
        }

        return AssistantExecutionResult.Unsupported(
            "Local AI engine is currently offline. You can control timers, media, and system status directly.",
            MascotMood.Thinking
        );
    }

    private static string FormatDuration(TimeSpan duration)
    {
        if (duration.TotalHours >= 1)
        {
            int h = (int)duration.TotalHours;
            int m = duration.Minutes;
            return m > 0 ? $"{h}h {m}m" : $"{h}h";
        }
        if (duration.TotalMinutes >= 1)
        {
            int m = (int)duration.TotalMinutes;
            int s = duration.Seconds;
            return s > 0 ? $"{m}m {s}s" : $"{m}m";
        }
        return $"{duration.Seconds}s";
    }
}
