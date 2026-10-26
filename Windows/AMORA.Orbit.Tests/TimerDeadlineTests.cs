using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class TimerDeadlineTests
{
    [Fact]
    public void DelayedCallback_UsesElapsedTimeInsteadOfCountingOneTick()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        timer.Start(TimeSpan.FromMinutes(5));
        clock.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(TimeSpan.FromMinutes(3), timer.CurrentTimer.Remaining);
    }

    [Fact]
    public void SuspendBeyondDeadline_CompletesOnceOnNextCallback()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        var completed = 0;
        var finished = 0;
        timer.TimerCompleted += (_, _) => completed++;
        timer.TimerFinished += (_, _) => finished++;
        timer.Start(TimeSpan.FromMinutes(5));
        var callback = clock.Timers.Last();
        clock.MoveWallClock(TimeSpan.FromHours(1));
        callback.FireEvenIfDisposed();
        callback.FireEvenIfDisposed();
        Assert.Equal(TimerStatus.Completed, timer.CurrentTimer.Status);
        Assert.Equal(TimeSpan.Zero, timer.CurrentTimer.Remaining);
        Assert.Equal(1, completed);
        Assert.Equal(1, finished);
    }

    [Fact]
    public void PausedTime_DoesNotCountAgainstResumedDeadline()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        timer.Start(TimeSpan.FromMinutes(5));
        clock.Advance(TimeSpan.FromSeconds(90));
        timer.Pause();
        clock.Advance(TimeSpan.FromHours(1));
        Assert.Equal(TimeSpan.FromSeconds(210), timer.CurrentTimer.Remaining);
        timer.Resume();
        clock.Advance(TimeSpan.FromSeconds(30));
        Assert.Equal(TimeSpan.FromMinutes(3), timer.CurrentTimer.Remaining);
    }

    [Fact]
    public void AddTime_UsesRequestedSecondsThroughInterfaceAndExtendsDeadline()
    {
        var clock = new ManualTimeProvider();
        using var service = new StandardTimerService(clock);
        ITimerService timer = service;
        timer.Start(TimeSpan.FromMinutes(5));
        clock.Advance(TimeSpan.FromMinutes(2));
        timer.AddTime(90);
        Assert.Equal(TimeSpan.FromSeconds(390), timer.CurrentTimer.TotalDuration);
        Assert.Equal(TimeSpan.FromSeconds(270), timer.CurrentTimer.Remaining);
        clock.Advance(TimeSpan.FromSeconds(270));
        Assert.Equal(TimerStatus.Completed, timer.CurrentTimer.Status);
    }

    [Fact]
    public void LateCallbackFromReplacedTimer_CannotChangeNewCountdown()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        timer.Start(TimeSpan.FromSeconds(1));
        var stale = clock.Timers.Last();
        timer.Start(TimeSpan.FromMinutes(25));
        clock.MoveWallClock(TimeSpan.FromSeconds(2));
        stale.FireEvenIfDisposed();
        Assert.Equal(TimeSpan.FromMinutes(25), timer.CurrentTimer.Remaining);
        Assert.Equal(TimerStatus.Running, timer.CurrentTimer.Status);
    }

    [Fact]
    public void InvalidStart_DoesNotCancelExistingTimer()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        timer.Start(TimeSpan.FromMinutes(5));
        Assert.Throws<ArgumentOutOfRangeException>(() => timer.Start(TimeSpan.Zero));
        Assert.Throws<ArgumentOutOfRangeException>(() => timer.Start(TimeSpan.FromSeconds(-1)));
        Assert.Equal(TimerStatus.Running, timer.CurrentTimer.Status);
        Assert.Equal(TimeSpan.FromMinutes(5), timer.CurrentTimer.TotalDuration);
    }

    [Fact]
    public void ClockCorrectionBackwards_DoesNotExtendCountdown()
    {
        var clock = new ManualTimeProvider();
        using var timer = new StandardTimerService(clock);
        timer.Start(TimeSpan.FromMinutes(5));
        clock.MoveWallClock(TimeSpan.FromHours(-1));
        clock.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(TimeSpan.FromMinutes(3), timer.CurrentTimer.Remaining);
    }

    [Fact]
    public void Dispose_PreventsQueuedCompletionNotification()
    {
        var clock = new ManualTimeProvider();
        var timer = new StandardTimerService(clock);
        var events = 0;
        timer.TimerFinished += (_, _) => events++;
        timer.Start(TimeSpan.FromSeconds(1));
        var callback = clock.Timers.Last();
        timer.Dispose();
        clock.MoveWallClock(TimeSpan.FromMinutes(5));
        callback.FireEvenIfDisposed();
        Assert.Equal(0, events);
    }

    [Fact]
    public void Display_RoundsUpFractionalRemainingSecond()
    {
        var snapshot = new TimerSnapshot(TimerStatus.Running,
            TimeSpan.FromMilliseconds(59999), TimeSpan.FromMinutes(1));
        Assert.Equal("01:00", snapshot.FormattedRemaining);
        Assert.Equal(60, snapshot.RemainingSeconds);
    }

    private sealed class ManualTimeProvider : TimeProvider
    {
        private DateTimeOffset _utc = DateTimeOffset.UnixEpoch;
        private long _timestamp;
        public List<ManualTimer> Timers { get; } = new();
        public override DateTimeOffset GetUtcNow() => _utc;
        public override long GetTimestamp() => _timestamp;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = new ManualTimer(this, callback, state, dueTime, period);
            Timers.Add(timer);
            return timer;
        }
        public void MoveWallClock(TimeSpan delta) => _utc += delta;
        public void Advance(TimeSpan elapsed)
        {
            _utc += elapsed;
            _timestamp += elapsed.Ticks;
            // Deliberately coalesce overdue callbacks, as can happen after sleep.
            foreach (var timer in Timers.ToArray()) timer.FireIfDue();
        }
        public sealed class ManualTimer : ITimer
        {
            private readonly ManualTimeProvider _clock;
            private readonly TimerCallback _callback;
            private readonly object? _state;
            private long _dueAt;
            private TimeSpan _period;
            private bool _disposed;
            public ManualTimer(ManualTimeProvider clock, TimerCallback callback, object? state, TimeSpan due, TimeSpan period)
            {
                _clock = clock;
                _callback = callback;
                _state = state;
                Change(due, period);
            }
            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                if (_disposed) return false;
                _dueAt = _clock._timestamp + dueTime.Ticks;
                _period = period;
                return true;
            }
            public void FireIfDue()
            {
                if (_disposed || _clock._timestamp < _dueAt) return;
                _dueAt = _clock._timestamp + _period.Ticks;
                _callback(_state);
            }
            public void FireEvenIfDisposed() => _callback(_state);
            public void Dispose() => _disposed = true;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
}
