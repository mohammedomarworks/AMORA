using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>A single elapsed-time countdown shared by commands, UI and automations.</summary>
public class StandardTimerService : ITimerService, IDisposable
{
    private readonly TimeProvider _clock;
    private readonly object _lock = new();
    private TimerSnapshot _current = TimerSnapshot.None;
    private ITimer? _ticker;
    private TimeSpan _remainingAtStart;
    private DateTimeOffset _deadline;
    private long _startedTimestamp;
    private long _generation;
    private bool _disposed;

    public StandardTimerService(TimeProvider? timeProvider = null) => _clock = timeProvider ?? TimeProvider.System;
    public TimerSnapshot CurrentTimer { get { lock (_lock) return _current; } }
    public event EventHandler<TimerSnapshot>? TimerUpdated;
    public event EventHandler<TimerSnapshot>? TimerFinished;
    public event EventHandler? TimerCompleted;

    public void Start(TimeSpan duration, string label = "Focus")
    {
        ValidateDuration(duration);
        lock (_lock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            // Validate before replacing a running timer. Invalid commands must not
            // silently cancel a user's existing focus session.
            var deadline = _clock.GetUtcNow().Add(duration);
            StopInternal();
            _current = new TimerSnapshot(TimerStatus.Running, duration, duration, label);
            BeginRunning(duration, deadline);
            Publish(false);
        }
    }

    public void Pause()
    {
        lock (_lock)
        {
            if (_disposed || _current.Status != TimerStatus.Running) return;
            bool completed = RefreshElapsed();
            if (!completed)
            {
                StopInternal();
                _current = _current with { Status = TimerStatus.Paused };
            }
            Publish(completed);
        }
    }

    public void Resume()
    {
        lock (_lock)
        {
            if (_disposed || _current.Status != TimerStatus.Paused) return;
            var deadline = _clock.GetUtcNow().Add(_current.Remaining);
            _current = _current with { Status = TimerStatus.Running };
            BeginRunning(_current.Remaining, deadline);
            Publish(false);
        }
    }

    public void Cancel()
    {
        lock (_lock)
        {
            if (_disposed) return;
            StopInternal();
            _current = TimerSnapshot.None;
            Publish(false);
        }
    }

    public void AddMinute() => AddTime(60);

    public void AddTime(int seconds)
    {
        if (seconds <= 0) throw new ArgumentOutOfRangeException(nameof(seconds));
        lock (_lock)
        {
            if (_disposed || !_current.IsActive) return;
            bool completed = _current.Status == TimerStatus.Running && RefreshElapsed();
            if (!completed)
            {
                var added = TimeSpan.FromSeconds(seconds);
                var total = _current.TotalDuration.Add(added);
                ValidateDuration(total);
                var remaining = _current.Remaining.Add(added);
                var deadline = _clock.GetUtcNow().Add(remaining);
                _current = _current with { Remaining = remaining, TotalDuration = total };
                if (_current.Status == TimerStatus.Running)
                {
                    StopInternal();
                    BeginRunning(remaining, deadline);
                }
            }
            Publish(completed);
        }
    }

    private void BeginRunning(TimeSpan remaining, DateTimeOffset deadline)
    {
        _remainingAtStart = remaining;
        _deadline = deadline;
        _startedTimestamp = _clock.GetTimestamp();
        var generation = ++_generation;
        _ticker = _clock.CreateTimer(OnTick, generation, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
    }

    private void OnTick(object? state)
    {
        lock (_lock)
        {
            if (_disposed || state is not long generation || generation != _generation ||
                _current.Status != TimerStatus.Running) return;
            var previous = _current;
            bool completed = RefreshElapsed();
            if (previous != _current) Publish(completed);
        }
    }

    private bool RefreshElapsed()
    {
        // The wall deadline includes suspension; monotonic elapsed prevents a
        // clock correction backwards from extending an active focus session.
        var wallRemaining = _deadline - _clock.GetUtcNow();
        var monotonicRemaining = _remainingAtStart - _clock.GetElapsedTime(_startedTimestamp);
        var remaining = wallRemaining < monotonicRemaining ? wallRemaining : monotonicRemaining;
        if (remaining <= TimeSpan.Zero)
        {
            StopInternal();
            _current = _current with { Remaining = TimeSpan.Zero, Status = TimerStatus.Completed };
            return true;
        }
        _current = _current with { Remaining = remaining };
        return false;
    }

    private void Publish(bool completed)
    {
        // Mutations and their notifications stay serialized. A queued callback
        // from a replaced/disposed timer cannot overwrite the new UI state.
        var snapshot = _current;
        TimerUpdated?.Invoke(this, snapshot);
        if (completed)
        {
            TimerFinished?.Invoke(this, snapshot);
            TimerCompleted?.Invoke(this, EventArgs.Empty);
        }
    }

    private static void ValidateDuration(TimeSpan duration)
    {
        if (duration <= TimeSpan.Zero || duration.TotalSeconds > int.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(duration), "Timer duration must be positive and fit within the supported range.");
    }

    private void StopInternal()
    {
        _generation++;
        _ticker?.Dispose();
        _ticker = null;
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (_disposed) return;
            _disposed = true;
            StopInternal();
        }
        GC.SuppressFinalize(this);
    }
}
