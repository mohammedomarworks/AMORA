using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class StandardTimerService : ITimerService, IDisposable
{
    private TimerSnapshot _current = TimerSnapshot.None;
    public TimerSnapshot CurrentTimer => _current;

    public event EventHandler<TimerSnapshot>? TimerUpdated;
    public event EventHandler<TimerSnapshot>? TimerFinished;
    public event EventHandler? TimerCompleted;

    private System.Threading.Timer? _ticker;
    private readonly object _lock = new();

    public void Start(TimeSpan duration, string label = "Focus")
    {
        lock (_lock)
        {
            StopInternal();
            if (duration <= TimeSpan.Zero) return;

            _current = new TimerSnapshot(TimerStatus.Running, duration, duration, label);
            _ticker = new System.Threading.Timer(OnTick, null, 1000, 1000);
        }

        TimerUpdated?.Invoke(this, _current);
    }

    public void Pause()
    {
        lock (_lock)
        {
            if (_current.Status != TimerStatus.Running) return;
            _ticker?.Change(Timeout.Infinite, Timeout.Infinite);
            _current = _current with { Status = TimerStatus.Paused };
        }

        TimerUpdated?.Invoke(this, _current);
    }

    public void Resume()
    {
        lock (_lock)
        {
            if (_current.Status != TimerStatus.Paused) return;
            _current = _current with { Status = TimerStatus.Running };
            _ticker?.Change(1000, 1000);
        }

        TimerUpdated?.Invoke(this, _current);
    }

    public void Cancel()
    {
        lock (_lock)
        {
            StopInternal();
            _current = TimerSnapshot.None;
        }

        TimerUpdated?.Invoke(this, _current);
    }

    public void AddMinute()
    {
        lock (_lock)
        {
            if (_current.Status is TimerStatus.Running or TimerStatus.Paused)
            {
                var newRemaining = _current.Remaining.Add(TimeSpan.FromMinutes(1));
                var newTotal = _current.TotalDuration.Add(TimeSpan.FromMinutes(1));
                _current = _current with { Remaining = newRemaining, TotalDuration = newTotal };
            }
        }

        TimerUpdated?.Invoke(this, _current);
    }

    private void OnTick(object? state)
    {
        TimerSnapshot snapshotToFire;
        bool isDone = false;

        lock (_lock)
        {
            if (_current.Status != TimerStatus.Running) return;

            var newRemaining = _current.Remaining.Subtract(TimeSpan.FromSeconds(1));
            if (newRemaining <= TimeSpan.Zero)
            {
                isDone = true;
                StopInternal();
                _current = _current with { Remaining = TimeSpan.Zero, Status = TimerStatus.Completed };
            }
            else
            {
                _current = _current with { Remaining = newRemaining };
            }

            snapshotToFire = _current;
        }

        TimerUpdated?.Invoke(this, snapshotToFire);

        if (isDone)
        {
            TimerFinished?.Invoke(this, snapshotToFire);
            TimerCompleted?.Invoke(this, EventArgs.Empty);
        }
    }

    private void StopInternal()
    {
        _ticker?.Dispose();
        _ticker = null;
    }

    public void Dispose()
    {
        lock (_lock)
        {
            StopInternal();
        }
        GC.SuppressFinalize(this);
    }
}
