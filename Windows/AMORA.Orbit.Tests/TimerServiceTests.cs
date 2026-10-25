using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class TimerServiceTests
{
    [Fact]
    public void InitialState_IsNone()
    {
        using var timer = new StandardTimerService();
        Assert.Equal(TimerStatus.None, timer.CurrentTimer.Status);
        Assert.Equal(TimeSpan.Zero, timer.CurrentTimer.Remaining);
    }

    [Fact]
    public void Start_InitializesRunningSnapshot()
    {
        using var timer = new StandardTimerService();
        timer.Start(TimeSpan.FromMinutes(25), "Pomodoro Focus");

        var snapshot = timer.CurrentTimer;
        Assert.Equal(TimerStatus.Running, snapshot.Status);
        Assert.Equal("Pomodoro Focus", snapshot.Label);
        Assert.Equal(TimeSpan.FromMinutes(25), snapshot.TotalDuration);
        Assert.Equal("25:00", snapshot.FormattedRemaining);
    }

    [Fact]
    public void PauseAndResume_TogglesStatus()
    {
        using var timer = new StandardTimerService();
        timer.Start(TimeSpan.FromMinutes(5), "Break");

        timer.Pause();
        Assert.Equal(TimerStatus.Paused, timer.CurrentTimer.Status);

        timer.Resume();
        Assert.Equal(TimerStatus.Running, timer.CurrentTimer.Status);
    }

    [Fact]
    public void AddMinute_IncreasesRemainingAndTotal()
    {
        using var timer = new StandardTimerService();
        timer.Start(TimeSpan.FromMinutes(5), "Break");

        timer.AddMinute();
        Assert.True(timer.CurrentTimer.Remaining >= TimeSpan.FromMinutes(5.9));
        Assert.Equal(TimeSpan.FromMinutes(6), timer.CurrentTimer.TotalDuration);
    }

    [Fact]
    public void Cancel_ResetsSnapshotToNone()
    {
        using var timer = new StandardTimerService();
        timer.Start(TimeSpan.FromMinutes(15), "Sprint");

        timer.Cancel();
        Assert.Equal(TimerStatus.None, timer.CurrentTimer.Status);
        Assert.Equal(TimeSpan.Zero, timer.CurrentTimer.Remaining);
    }

    [Fact]
    public void ProgressPercent_CalculatesAccurately()
    {
        var snapshot = new TimerSnapshot(
            Status: TimerStatus.Running,
            Remaining: TimeSpan.FromMinutes(10),
            TotalDuration: TimeSpan.FromMinutes(20),
            Label: "Test");

        // 10 elapsed out of 20 = 50%
        Assert.Equal(0.5, snapshot.ProgressPercent, precision: 2);
    }
}
