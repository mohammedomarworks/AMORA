using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.ViewModels;

/// <summary>Bounded reactions to AMORA-owned activity; no random moods or background capture.</summary>
public class RobotMascotViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly TimeProvider _clock;
    private MascotExpression _expression = MascotExpression.Idle();
    private MascotExpression? _eventExpression;
    private MascotExpression? _clickExpression;
    private MascotMood _ambientMood = MascotMood.Idle;
    private DateTimeOffset _eventExpiresAt, _clickExpiresAt, _lastClick = DateTimeOffset.MinValue;
    private DateTimeOffset _lastInteraction, _lastEvent = DateTimeOffset.MinValue;
    private string? _lastEventIdentity;
    private int _rapidClicks, _reactionCycle;
    private string _statusSubtext = "Ready to help";
    private string? _eventMessage;
    private bool _isAntennaGlowActive = true, _sleepModeEnabled = true, _disposed;
    private TimeSpan _idleTimeout = TimeSpan.FromMinutes(5);
    private double _animationIntensity = 1;

    public RobotMascotViewModel(TimeProvider? timeProvider = null)
    {
        _clock = timeProvider ?? TimeProvider.System;
        _lastInteraction = _clock.GetUtcNow();
    }

    public MascotExpression Expression
    {
        get => _expression;
        private set
        {
            if (_expression == value) return;
            _expression = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(Mood));
            OnPropertyChanged(nameof(StatusDescription));
            OnPropertyChanged(nameof(IsAsleep));
        }
    }
    public MascotMood Mood => Expression.Mood;
    public string StatusDescription => Expression.Description;
    public bool IsAsleep => Mood == MascotMood.Sleepy;
    public bool HasClickReaction => _clickExpression != null;
    public bool IsAntennaGlowActive { get => _isAntennaGlowActive; set { _isAntennaGlowActive = value; OnPropertyChanged(); } }
    public string StatusSubtext { get => _statusSubtext; set { if (_statusSubtext == value || _disposed) return; _statusSubtext = value; OnPropertyChanged(); } }
    public bool SleepModeEnabled { get => _sleepModeEnabled; set { _sleepModeEnabled = value; RefreshIdleState(); } }
    public TimeSpan IdleTimeout { get => _idleTimeout; set { _idleTimeout = value < TimeSpan.FromSeconds(10) ? TimeSpan.FromSeconds(10) : value; RefreshIdleState(); } }
    public double AnimationIntensity
    {
        get => _animationIntensity;
        set { _animationIntensity = double.IsFinite(value) ? Math.Clamp(value, 0, 1) : 0; OnPropertyChanged(); }
    }
    public event PropertyChangedEventHandler? PropertyChanged;

    public void NoteInteraction()
    {
        if (_disposed) return;
        _lastInteraction = _clock.GetUtcNow();
        RefreshIdleState();
    }

    public void UpdateAmbientState(bool timerRunning, bool mediaPlaying, bool assistantBusy)
    {
        if (_disposed) return;
        _ambientMood = assistantBusy ? MascotMood.Thinking : timerRunning ? MascotMood.Focused : mediaPlaying ? MascotMood.Music : MascotMood.Idle;
        if (!assistantBusy && _eventExpression?.Mood == MascotMood.Thinking) _eventExpression = null;
        RefreshIdleState();
    }

    public void SetMood(MascotMood mood, string? customDescription = null)
    {
        if (_disposed) return;
        var now = _clock.GetUtcNow();
        var identity = $"{mood}:{customDescription}";
        if (identity == _lastEventIdentity && now - _lastEvent < TimeSpan.FromMilliseconds(350)) return;
        _lastEventIdentity = identity;
        _lastEvent = now;
        var candidate = MascotExpression.Create(mood);
        // Routine background state must not mask a currently displayed critical alert.
        if (_eventExpression?.Mood == MascotMood.Alert && now < _eventExpiresAt &&
            candidate.Priority < 90 && mood is not (MascotMood.Idle or MascotMood.Happy)) return;
        if (mood is MascotMood.Idle or MascotMood.Focused or MascotMood.Music)
        {
            _ambientMood = mood;
            _eventExpression = null;
        }
        else
        {
            _eventExpression = candidate;
            _eventExpiresAt = now + (mood switch
            {
                MascotMood.Thinking => TimeSpan.FromDays(1), // Live busy state or the next result ends it.
                MascotMood.Alert => TimeSpan.FromSeconds(6),
                MascotMood.Celebrating => TimeSpan.FromSeconds(5),
                MascotMood.Listening => TimeSpan.FromSeconds(4),
                _ => TimeSpan.FromSeconds(3)
            });
        }
        _eventMessage = customDescription;
        if (candidate.Priority >= 75 || mood == MascotMood.Celebrating) _clickExpression = null;
        _lastInteraction = now;
        RefreshIdleState();
        if (_clickExpression == null && !string.IsNullOrWhiteSpace(customDescription)) StatusSubtext = customDescription;
    }

    // Retain the existing async UI contract; expiration is serviced by the shell's
    // existing cadence, so no detached tasks/timers can mutate a disposed view.
    public Task TriggerClickReactionAsync()
    {
        if (_disposed) return Task.CompletedTask;
        var now = _clock.GetUtcNow();
        var elapsed = now - _lastClick;
        if (elapsed < TimeSpan.FromMilliseconds(220)) return Task.CompletedTask;
        if ((_eventExpression?.Priority ?? 0) >= 75 || _ambientMood == MascotMood.Thinking) return Task.CompletedTask;
        _rapidClicks = elapsed > TimeSpan.FromSeconds(1.5) ? 1 : _rapidClicks + 1;
        _lastClick = now;
        _lastInteraction = now;
        MascotMood reaction;
        if (_rapidClicks >= 3) { reaction = MascotMood.Grumpy; _rapidClicks = 0; }
        else
        {
            MascotMood[] cycle = [MascotMood.Affection, MascotMood.Excited, MascotMood.Curious, MascotMood.Grumpy];
            reaction = cycle[_reactionCycle++ % cycle.Length];
        }
        _clickExpression = MascotExpression.Create(reaction);
        _clickExpiresAt = now + TimeSpan.FromSeconds(3);
        RefreshIdleState();
        return Task.CompletedTask;
    }

    public void RefreshIdleState()
    {
        if (_disposed) return;
        var now = _clock.GetUtcNow();
        if (_clickExpression != null && now >= _clickExpiresAt) _clickExpression = null;
        if (_eventExpression != null && now >= _eventExpiresAt) _eventExpression = null;
        if (_clickExpression != null)
        {
            Expression = _clickExpression;
            StatusSubtext = _clickExpression.Mood switch
            {
                MascotMood.Affection => "Sending positive vibes!",
                MascotMood.Excited => "Energized and ready!",
                MascotMood.Curious => "Observing closely!",
                _ => "Careful with the visor!"
            };
            return;
        }
        if (_eventExpression != null)
        {
            Expression = _eventExpression;
            StatusSubtext = string.IsNullOrWhiteSpace(_eventMessage) ? _eventExpression.Description : _eventMessage;
            return;
        }
        var ambient = _ambientMood;
        var idle = now - _lastInteraction;
        if (ambient == MascotMood.Idle)
        {
            if (_sleepModeEnabled && idle >= _idleTimeout) ambient = MascotMood.Sleepy;
            else if (idle >= TimeSpan.FromSeconds(Math.Min(75, _idleTimeout.TotalSeconds / 2))) ambient = MascotMood.Bored;
        }
        Expression = MascotExpression.Create(ambient);
        // Avoid a stale "Listening" or click message surviving its expression.
        StatusSubtext = ambient switch
        {
            MascotMood.Sleepy => "Resting here. I'll wake when you need me.",
            MascotMood.Bored => "Still here, whenever you're ready.",
            MascotMood.Focused => "One thing at a time. You've got this.",
            MascotMood.Music => "Keeping you company while you listen.",
            MascotMood.Thinking => "Thinking…",
            _ => "Ready to help"
        };
    }

    public void Dispose() { _disposed = true; _clickExpression = null; _eventExpression = null; }
    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    { if (!_disposed) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName)); }
}
