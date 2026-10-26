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
    private readonly Func<AISettings> _settingsProvider;
    private readonly IExplicitMemoryService? _memory;
    private readonly ISafeNavigationService? _navigation;
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
        IConversationSession? conversationSession = null,
        Func<AISettings>? settingsProvider = null,
        IExplicitMemoryService? memory = null,
        ISafeNavigationService? navigation = null)
    {
        _router = router ?? throw new ArgumentNullException(nameof(router));
        _timerService = timerService ?? throw new ArgumentNullException(nameof(timerService));
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _batteryService = batteryService ?? throw new ArgumentNullException(nameof(batteryService));
        _telemetryService = telemetryService ?? throw new ArgumentNullException(nameof(telemetryService));
        _aiProvider = aiProvider;
        _conversationSession = conversationSession ?? new ConversationSession();
        _settingsProvider = settingsProvider ?? (() => AISettings.Default);
        _memory = memory;
        _navigation = navigation;
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
            _navigation?.CancelPending();

            // Only explicit user input enters memory; provider actions never do.
            // Memory commands/results stay out of cloud conversation history.
            if (_memory != null)
            {
                var memoryResult = await _memory.TryExecuteAsync(input, cancellationToken);
                if (memoryResult != null)
                {
                    if (memoryResult.RequiresConfirmation)
                    {
                        _pendingPrompt = memoryResult.Message;
                        _pendingAction = () => _memory.ConfirmClearAsync();
                    }
                    return memoryResult;
                }
            }

            var context = BuildCommandContext();
            if (_navigation != null)
            {
                var navigationResult = await _navigation.TryExecuteAsync(input, cancellationToken);
                if (navigationResult != null)
                {
                    if (navigationResult.RequiresConfirmation)
                    {
                        _pendingPrompt = navigationResult.Message;
                        _pendingAction = () => _navigation.ConfirmAsync();
                    }
                    return navigationResult;
                }
            }
            var command = _router.Route(input, context);

            return await DispatchCommandAsync(command, input, context, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception)
        {
            return AssistantExecutionResult.Failed("The local action could not be completed. Check the relevant module and try again.");
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
        catch (Exception)
        {
            return AssistantExecutionResult.Failed("The confirmed action could not be completed. Check the target and try again.");
        }
        finally
        {
            _executionLock.Release();
        }
    }

    public void CancelPendingAction()
    {
        _memory?.CancelPendingClear();
        _navigation?.CancelPending();
        _pendingAction = null;
        _pendingPrompt = null;
    }

    public void ResetConversation()
    {
        CancelPendingAction();
        _conversationSession.Clear();
    }

    private CommandContext BuildCommandContext()
    {
        var timerSnapshot = _timerService.CurrentTimer;
        var track = _mediaService.CurrentTrack;
        var battery = _batteryService.GetSnapshot();
        var telemetry = _telemetryService.GetSnapshot();

        var snapshot = new AmoraContextSnapshot(
            Timer: timerSnapshot,
            Media: track,
            Battery: battery,
            Telemetry: telemetry,
            CapturedAt: DateTimeOffset.UtcNow
        );

        return new CommandContext(
            IsTimerActive: timerSnapshot.Status != TimerStatus.None,
            IsTimerRunning: timerSnapshot.Status == TimerStatus.Running,
            IsMediaPlaying: track.IsPlaying,
            HasTrack: track != MediaTrack.None && !string.IsNullOrWhiteSpace(track.Title),
            Snapshot: snapshot
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
            AssistantCommand.GetTimerStatus => HandleGetTimerStatus(),
            AssistantCommand.GetMediaStatus => HandleGetMediaStatus(),

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

        if (add.Duration <= TimeSpan.Zero || add.Duration.TotalSeconds > int.MaxValue)
            return AssistantExecutionResult.Failed("The requested timer adjustment is outside the supported range.");
        _timerService.AddTime((int)add.Duration.TotalSeconds);

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

    private AssistantExecutionResult HandleGetTimerStatus()
    {
        var timer = _timerService.CurrentTimer;
        if (timer.Status is TimerStatus.None or TimerStatus.Idle)
        {
            return AssistantExecutionResult.Information("No active timer running.", MascotMood.Idle);
        }

        string stateStr = timer.Status == TimerStatus.Paused ? " (paused)" : "";
        string labelStr = !string.IsNullOrWhiteSpace(timer.Label) ? $" ({timer.Label})" : "";
        return AssistantExecutionResult.Information(
            $"{timer.FormattedRemaining} remaining{labelStr}{stateStr}.",
            timer.Status == TimerStatus.Running ? MascotMood.Focused : MascotMood.Idle
        );
    }

    private AssistantExecutionResult HandleGetMediaStatus()
    {
        var track = _mediaService.CurrentTrack;
        if (!_mediaService.IsConnected || track == MediaTrack.None || !track.IsAvailable || string.IsNullOrWhiteSpace(track.Title) || track.Title == "No Media Playing")
        {
            return AssistantExecutionResult.Information("No active media playing.", MascotMood.Idle);
        }

        string stateStr = track.IsPlaying ? "Playing" : "Paused";
        string artistStr = !string.IsNullOrWhiteSpace(track.Artist) && track.Artist != "None" ? $" by {track.Artist}" : "";
        return AssistantExecutionResult.Information(
            $"{stateStr}: {track.Title}{artistStr}.",
            track.IsPlaying ? MascotMood.Happy : MascotMood.Idle
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
        if (_aiProvider != null && (_aiProvider.IsConfigured || _aiProvider.ProviderId == AISettings.ProviderLocalBrain))
        {
            try
            {
                var history = _conversationSession.GetHistory();
                var settings = _settingsProvider();
                string promptToSend = rawInput;

                // Privacy safeguard: only send status context if user explicitly opt-in enabled it!
                if (settings.SendStatusContextToAI && context.Snapshot != null)
                {
                    string summary = context.Snapshot.ToCompactSummary();
                    if (!string.IsNullOrWhiteSpace(summary))
                    {
                        promptToSend = $"[System Context: {summary}]\n{rawInput}";
                    }
                }

                string aiResponse = await _aiProvider.GenerateResponseAsync(promptToSend, history, cancellationToken);

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
            catch (LocalBrainException ex) { return AssistantExecutionResult.Failed(ex.Message, MascotMood.Curious); }
            catch (Exception ex)
            {
                // Classify transport failures without echoing provider bodies or secrets.
                string reason = ex is TimeoutException || ex.Message.Contains("timed out", StringComparison.OrdinalIgnoreCase) || ex.Message.Contains("timeout", StringComparison.OrdinalIgnoreCase)
                    ? "connection timed out. Please check your connection."
                    : ex.Message.Contains("429") || ex.Message.Contains("quota", StringComparison.OrdinalIgnoreCase)
                    ? "rate limit reached. Please wait before trying again."
                    : ex.Message.Contains("503") ? "provider unavailable (503). Try again later."
                    : ex.Message.Contains("401") || ex.Message.Contains("403") || ex.Message.Contains("API key", StringComparison.OrdinalIgnoreCase)
                    ? "credentials were rejected. Check your selected provider in Settings."
                    : "the selected provider could not complete the request. Check its setup, model and connection.";
                return AssistantExecutionResult.Failed($"AI request failed: {reason}");
            }
        }

        return AssistantExecutionResult.Unsupported(
            "Your selected AI provider is not ready. Open Settings to install Local Brain for offline chat or configure your chosen cloud provider. Timers, media, memory and system controls remain available locally.",
            MascotMood.Curious
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
