using System.Collections.Concurrent;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class ProactiveSuggestionService : ISuggestionService, IDisposable
{
    private ProactiveSuggestion? _activeSuggestion;
    private readonly object _lock = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _snoozedUntil = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _cooldownUntil = new();
    private readonly ConcurrentBag<string> _dismissedIds = new();
    private CancellationTokenSource? _snoozeCts;
    private readonly Queue<ProactiveSuggestion> _reminderQueue = new();
    private readonly Dictionary<string, CancellationTokenSource> _reminderSnoozes = new();
    private bool _activeIsReminder;
    private bool _disposed;

    private readonly ITimerService? _timerService;
    private readonly IBatteryService? _batteryService;
    private readonly IAISettingsService? _settingsService;
    private readonly Func<AISettings>? _settingsProvider;
    private bool _localEnabled = true;

    public ProactiveSuggestionService()
        : this(null, null, null, null)
    {
    }

    public ProactiveSuggestionService(
        ITimerService? timerService = null,
        IBatteryService? batteryService = null,
        IAISettingsService? settingsService = null,
        Func<AISettings>? settingsProvider = null)
    {
        _timerService = timerService;
        _batteryService = batteryService;
        _settingsService = settingsService;
        _settingsProvider = settingsProvider ?? (_settingsService != null ? () => _settingsService.CurrentSettings : null);

        if (_timerService != null)
        {
            _timerService.TimerFinished += OnTimerFinished;
            _timerService.TimerUpdated += OnTimerUpdated;
        }

        if (_batteryService != null)
        {
            _batteryService.BatteryUpdated += OnBatteryUpdated;
        }

        if (_settingsService != null)
        {
            _settingsService.SettingsChanged += OnSettingsChanged;
        }
    }

    public bool IsEnabled
    {
        get => _settingsProvider != null ? _settingsProvider().EnableProactiveSuggestions : _localEnabled;
        set
        {
            _localEnabled = value;
            if (!value)
            {
                ClearProactive();
            }
        }
    }

    public ProactiveSuggestion? ActiveSuggestion
    {
        get
        {
            lock (_lock)
            {
                return _activeSuggestion;
            }
        }
        private set
        {
            lock (_lock)
            {
                if (_activeSuggestion == value) return;
                _activeSuggestion = value;
            }
            ActiveSuggestionChanged?.Invoke(this, value);
        }
    }

    public event EventHandler<ProactiveSuggestion?>? ActiveSuggestionChanged;

    public bool PresentReminder(ProactiveSuggestion reminder)
    {
        ArgumentNullException.ThrowIfNull(reminder);
        ProactiveSuggestion? active;
        lock (_lock)
        {
            if (_disposed) return false;
            if (_activeSuggestion?.Id == reminder.Id || _reminderQueue.Any(r => r.Id == reminder.Id)) return true;
            if (_reminderQueue.Count >= 32) return false;
            if (_activeSuggestion != null && _activeIsReminder)
                _reminderQueue.Enqueue(reminder);
            else
            {
                // An explicitly scheduled reminder takes precedence over an unsolicited insight.
                _activeSuggestion = reminder;
                _activeIsReminder = true;
            }
            active = _activeSuggestion;
        }
        ActiveSuggestionChanged?.Invoke(this, active);
        return true;
    }

    public void PresentSuggestion(ProactiveSuggestion suggestion)
    {
        ArgumentNullException.ThrowIfNull(suggestion);

        if (!IsEnabled)
        {
            return;
        }

        lock (_lock)
        {
            if (_disposed) return;
            // At most one suggestion at a time; do not interrupt active suggestion
            if (_activeSuggestion != null)
            {
                return;
            }

            // Duplicate suppression: dismissed in current session
            if (_dismissedIds.Contains(suggestion.Id))
            {
                return;
            }

            // Cooldown suppression
            if (_cooldownUntil.TryGetValue(suggestion.Id, out var cooldownEnd))
            {
                if (DateTimeOffset.UtcNow < cooldownEnd)
                {
                    return;
                }
                _cooldownUntil.TryRemove(suggestion.Id, out _);
            }

            // Snooze suppression
            if (_snoozedUntil.TryGetValue(suggestion.Id, out var resumeTime))
            {
                if (DateTimeOffset.UtcNow < resumeTime)
                {
                    return;
                }
                _snoozedUntil.TryRemove(suggestion.Id, out _);
            }

            // Record cooldown if duration specified
            if (suggestion.CooldownDuration.HasValue)
            {
                _cooldownUntil[suggestion.Id] = DateTimeOffset.UtcNow.Add(suggestion.CooldownDuration.Value);
            }

            _activeSuggestion = suggestion;
            _activeIsReminder = false;
        }

        ActiveSuggestionChanged?.Invoke(this, suggestion);
    }

    public async Task ExecuteActiveActionAsync()
    {
        ProactiveSuggestion? current;
        lock (_lock)
        {
            current = _activeSuggestion;
        }

        if (current == null) return;
        if (current.OnAction != null)
        {
            try
            {
                await current.OnAction();
            }
            catch
            {
                lock (_lock)
                {
                    if (_activeSuggestion?.Id != current.Id) return;
                    _activeSuggestion = current with { Message = "That action could not be completed. Check the service and try again.", ActionLabel = "Try again" };
                }
                ActiveSuggestionChanged?.Invoke(this, ActiveSuggestion);
                return;
            }
        }

        DismissActive(current?.Id);
    }

    public void SnoozeActive(TimeSpan duration)
    {
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromDays(1)) throw new ArgumentOutOfRangeException(nameof(duration));
        ProactiveSuggestion? current;
        bool isReminder;
        CancellationTokenSource wake;
        CancellationToken token;
        ProactiveSuggestion? next;
        lock (_lock)
        {
            current = _activeSuggestion;
            if (current == null || _disposed) return;
            isReminder = _activeIsReminder;
            _snoozedUntil[current.Id] = DateTimeOffset.UtcNow.Add(duration);
            next = PromoteReminder();
            wake = new CancellationTokenSource();
            token = wake.Token;
            if (isReminder)
            {
                if (_reminderSnoozes.Remove(current.Id, out var previous)) { previous.Cancel(); previous.Dispose(); }
                _reminderSnoozes[current.Id] = wake;
            }
            else
            {
                _snoozeCts?.Cancel();
                _snoozeCts?.Dispose();
                _snoozeCts = wake;
            }
        }

        ActiveSuggestionChanged?.Invoke(this, next);

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(duration, token);
                if (!token.IsCancellationRequested && !_dismissedIds.Contains(current.Id))
                {
                    if (isReminder) PresentReminder(current);
                    else if (IsEnabled) PresentSuggestion(current);
                }
            }
            catch (TaskCanceledException)
            {
                // Snooze was cancelled or renewed
            }
            finally
            {
                if (isReminder)
                {
                    lock (_lock)
                    {
                        if (_reminderSnoozes.TryGetValue(current.Id, out var pending) && ReferenceEquals(pending, wake))
                            _reminderSnoozes.Remove(current.Id);
                    }
                    wake.Dispose();
                }
            }
        });
    }

    public void DismissActive() => DismissActive(null);

    private void DismissActive(string? expectedId)
    {
        ProactiveSuggestion? current;
        ProactiveSuggestion? next;
        lock (_lock)
        {
            current = _activeSuggestion;
            if (current == null) return;
            if (expectedId != null && current.Id != expectedId) return;
            _dismissedIds.Add(current.Id);
            if (current.CooldownDuration.HasValue)
            {
                _cooldownUntil[current.Id] = DateTimeOffset.UtcNow.Add(current.CooldownDuration.Value);
            }
            next = PromoteReminder();
        }

        ActiveSuggestionChanged?.Invoke(this, next);
    }

    public void ClearActive()
    {
        ProactiveSuggestion? current;
        ProactiveSuggestion? next;
        lock (_lock)
        {
            current = _activeSuggestion;
            if (current == null) return;
            next = PromoteReminder();
        }

        ActiveSuggestionChanged?.Invoke(this, next);
    }

    // Called while holding _lock. Does not turn on proactive suggestions.
    private ProactiveSuggestion? PromoteReminder()
    {
        _activeSuggestion = _reminderQueue.Count > 0 ? _reminderQueue.Dequeue() : null;
        _activeIsReminder = _activeSuggestion != null;
        return _activeSuggestion;
    }

    private void ClearProactive()
    {
        ProactiveSuggestion? next;
        lock (_lock)
        {
            if (_activeIsReminder) return;
            if (_activeSuggestion == null) return;
            next = PromoteReminder();
        }
        ActiveSuggestionChanged?.Invoke(this, next);
    }

    private void OnSettingsChanged(object? sender, AISettings settings)
    {
        if (!settings.EnableProactiveSuggestions)
        {
            ClearProactive();
        }
    }

    private void OnTimerFinished(object? sender, TimerSnapshot snapshot)
    {
        if (!IsEnabled) return;
        if (snapshot == null) return;

        bool isBreak = !string.IsNullOrWhiteSpace(snapshot.Label) &&
                       snapshot.Label.Equals("Break", StringComparison.OrdinalIgnoreCase);
        string id = isBreak ? "timer-break-finished" : "timer-focus-finished";

        var suggestion = isBreak
            ? new ProactiveSuggestion(
                Id: id,
                Title: "Break Completed",
                Message: "Break is over. Ready to start another focus session?",
                ActionLabel: "Start 25m Focus",
                Category: "Timer",
                Priority: SuggestionPriority.Normal,
                OnAction: () =>
                {
                    _timerService?.Start(TimeSpan.FromMinutes(25), "Focus");
                    return Task.CompletedTask;
                },
                CooldownDuration: TimeSpan.FromMinutes(2))
            : new ProactiveSuggestion(
                Id: id,
                Title: string.IsNullOrWhiteSpace(snapshot.Label) ? "Timer Completed" : $"{snapshot.Label} Completed",
                Message: "Focus session complete. Take a 5-minute break to recharge.",
                ActionLabel: "Start 5m Break",
                Category: "Timer",
                Priority: SuggestionPriority.Normal,
                OnAction: () =>
                {
                    _timerService?.Start(TimeSpan.FromMinutes(5), "Break");
                    return Task.CompletedTask;
                },
                CooldownDuration: TimeSpan.FromMinutes(2));

        PresentSuggestion(suggestion);
    }

    private void OnTimerUpdated(object? sender, TimerSnapshot snapshot)
    {
        if (snapshot.Status == TimerStatus.Running)
        {
            lock (_lock)
            {
                if (_activeSuggestion?.Id is "timer-focus-finished" or "timer-break-finished")
                {
                    ClearActive();
                }
            }
        }
    }

    private void OnBatteryUpdated(object? sender, BatterySnapshot snapshot)
    {
        if (!IsEnabled) return;
        if (snapshot == null) return;

        // Desktop PC on direct AC power has no physical battery
        if (!snapshot.HasBattery || snapshot.IsDesktopAC)
        {
            if (ActiveSuggestion?.Id == "battery-low")
            {
                ClearActive();
            }
            return;
        }

        // If charging or plugged in, battery is not discharging
        if (snapshot.IsPluggedIn || snapshot.IsCharging)
        {
            if (ActiveSuggestion?.Id == "battery-low")
            {
                ClearActive();
            }
            return;
        }

        // Truthful data validation: only trigger on valid low battery (1% to 20%)
        if (snapshot.Percentage <= 0 || snapshot.Percentage > 20)
        {
            return;
        }

        string timeRemainingText = string.Empty;
        if (snapshot.EstimatedRemaining.HasValue && snapshot.EstimatedRemaining.Value.TotalMinutes > 0)
        {
            int h = (int)snapshot.EstimatedRemaining.Value.TotalHours;
            int m = snapshot.EstimatedRemaining.Value.Minutes;
            timeRemainingText = h > 0 ? $" (~{h}h {m}m remaining)" : $" (~{m}m remaining)";
        }

        var suggestion = new ProactiveSuggestion(
            Id: "battery-low",
            Title: "Low Battery",
            Message: $"Battery is at {snapshot.Percentage}%{timeRemainingText}. Plug in your PC to keep working smoothly.",
            ActionLabel: "Acknowledge",
            Category: "Power",
            Priority: snapshot.Percentage <= 10 ? SuggestionPriority.Urgent : SuggestionPriority.High,
            OnAction: () => Task.CompletedTask,
            CooldownDuration: TimeSpan.FromMinutes(15));

        PresentSuggestion(suggestion);
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (_disposed) return;
            _disposed = true;
            _reminderQueue.Clear();
            foreach (var pending in _reminderSnoozes.Values) { pending.Cancel(); pending.Dispose(); }
            _reminderSnoozes.Clear();
        }
        _snoozeCts?.Cancel();
        _snoozeCts?.Dispose();

        if (_timerService != null)
        {
            _timerService.TimerFinished -= OnTimerFinished;
            _timerService.TimerUpdated -= OnTimerUpdated;
        }

        if (_batteryService != null)
        {
            _batteryService.BatteryUpdated -= OnBatteryUpdated;
        }

        if (_settingsService != null)
        {
            _settingsService.SettingsChanged -= OnSettingsChanged;
        }

        ClearActive();
    }
}
