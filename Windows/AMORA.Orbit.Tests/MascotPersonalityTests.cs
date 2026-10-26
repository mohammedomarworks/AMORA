using AMORA.Orbit.Models;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class MascotPersonalityTests
{
    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 10, 26, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(double seconds) => _now += TimeSpan.FromSeconds(seconds);
    }

    [Fact]
    public async Task ClickDebounceDoesNotAdvanceReactionCycle()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(MascotMood.Affection, mascot.Mood);
        clock.Advance(.1);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(MascotMood.Affection, mascot.Mood);
        clock.Advance(.2);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(MascotMood.Excited, mascot.Mood);
    }

    [Fact]
    public async Task ThirdRapidClickIsPlayfullyGrumpy()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        await mascot.TriggerClickReactionAsync();
        clock.Advance(.3);
        await mascot.TriggerClickReactionAsync();
        clock.Advance(.3);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(MascotMood.Grumpy, mascot.Mood);
        Assert.Equal(EyeShape.SlantedGrumpy, mascot.Expression.EyeShape);
    }

    [Fact]
    public async Task DeliberateClicksFollowMacPersonalityCycle()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        foreach (var expected in new[] { MascotMood.Affection, MascotMood.Excited, MascotMood.Curious, MascotMood.Grumpy, MascotMood.Affection })
        {
            await mascot.TriggerClickReactionAsync();
            Assert.Equal(expected, mascot.Mood);
            clock.Advance(2);
        }
    }

    [Fact]
    public async Task ClickExpirationReturnsToLatestRealAmbientState()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        await mascot.TriggerClickReactionAsync();
        mascot.UpdateAmbientState(timerRunning: true, mediaPlaying: true, assistantBusy: false);
        Assert.Equal(MascotMood.Affection, mascot.Mood);
        clock.Advance(3);
        mascot.RefreshIdleState();
        Assert.Equal(MascotMood.Focused, mascot.Mood);
        Assert.False(mascot.HasClickReaction);
        Assert.Contains("One thing", mascot.StatusSubtext);
    }

    [Theory]
    [InlineData(MascotMood.Alert)]
    [InlineData(MascotMood.Thinking)]
    [InlineData(MascotMood.Celebrating)]
    public async Task ImportantEventsInterruptClickReaction(MascotMood important)
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        await mascot.TriggerClickReactionAsync();
        mascot.SetMood(important, "Actual AMORA event");
        Assert.Equal(important, mascot.Mood);
        Assert.False(mascot.HasClickReaction);
        Assert.Equal("Actual AMORA event", mascot.StatusSubtext);
        clock.Advance(.3);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(important, mascot.Mood);
    }

    [Fact]
    public void CriticalAlertSuppressesRoutineStateButAllowsRecovery()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        mascot.SetMood(MascotMood.Alert, "Timer needs attention");
        clock.Advance(1);
        mascot.SetMood(MascotMood.Curious, "Routine update");
        Assert.Equal(MascotMood.Alert, mascot.Mood);
        Assert.Equal("Timer needs attention", mascot.StatusSubtext);
        mascot.SetMood(MascotMood.Happy, "Recovered");
        Assert.Equal(MascotMood.Happy, mascot.Mood);
    }

    [Fact]
    public void InformationResultDoesNotLeaveMascotListeningForever()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        mascot.SetMood(MascotMood.Listening, "Here is your answer");
        clock.Advance(4);
        mascot.RefreshIdleState();
        Assert.Equal(MascotMood.Idle, mascot.Mood);
        Assert.Equal("Ready to help", mascot.StatusSubtext);
        Assert.Equal(EyeShape.HappyArch, mascot.Expression.EyeShape);
    }

    [Fact]
    public void RepeatedEventIsDebouncedWithoutExtendingItsLifetime()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        mascot.SetMood(MascotMood.Happy, "Done");
        clock.Advance(.2);
        mascot.SetMood(MascotMood.Happy, "Done");
        clock.Advance(2.8);
        mascot.RefreshIdleState();
        Assert.Equal(MascotMood.Idle, mascot.Mood);
    }

    [Fact]
    public void InactivityMovesThroughBoredAndSleepyAndInteractionWakes()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock) { IdleTimeout = TimeSpan.FromSeconds(120) };
        clock.Advance(60);
        mascot.RefreshIdleState();
        Assert.Equal(MascotMood.Bored, mascot.Mood);
        clock.Advance(60);
        mascot.RefreshIdleState();
        Assert.True(mascot.IsAsleep);
        mascot.NoteInteraction();
        Assert.Equal(MascotMood.Idle, mascot.Mood);
        Assert.False(mascot.IsAsleep);
    }

    [Fact]
    public void SleepCanBeDisabled()
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock) { SleepModeEnabled = false };
        clock.Advance(600);
        mascot.RefreshIdleState();
        Assert.Equal(MascotMood.Bored, mascot.Mood);
        Assert.False(mascot.IsAsleep);
    }

    [Theory]
    [InlineData(true, false, false, MascotMood.Focused)]
    [InlineData(false, true, false, MascotMood.Music)]
    [InlineData(true, true, true, MascotMood.Thinking)]
    public void ActiveWorkDoesNotFallAsleep(bool timer, bool media, bool assistant, MascotMood expected)
    {
        var clock = new Clock();
        using var mascot = new RobotMascotViewModel(clock);
        mascot.UpdateAmbientState(timer, media, assistant);
        clock.Advance(600);
        mascot.RefreshIdleState();
        Assert.Equal(expected, mascot.Mood);
    }

    [Fact]
    public void BusyCompletionRevealsCurrentTimerOrMusicState()
    {
        using var mascot = new RobotMascotViewModel(new Clock());
        mascot.SetMood(MascotMood.Thinking);
        mascot.UpdateAmbientState(false, true, false);
        Assert.Equal(MascotMood.Music, mascot.Mood);
    }

    [Fact]
    public async Task DisposedMascotNeverReceivesDelayedUpdates()
    {
        var clock = new Clock();
        var mascot = new RobotMascotViewModel(clock);
        await mascot.TriggerClickReactionAsync();
        var expression = mascot.Expression;
        var changes = 0;
        mascot.PropertyChanged += (_, _) => changes++;
        mascot.Dispose();
        clock.Advance(600);
        mascot.RefreshIdleState();
        mascot.NoteInteraction();
        mascot.SetMood(MascotMood.Alert);
        mascot.UpdateAmbientState(true, false, false);
        await mascot.TriggerClickReactionAsync();
        Assert.Equal(expression, mascot.Expression);
        Assert.Equal(0, changes);
    }

    [Theory]
    [InlineData(-1, 0)]
    [InlineData(2, 1)]
    [InlineData(double.NaN, 0)]
    public void AnimationPreferenceIsBoundedWithoutDisablingExpressions(double input, double expected)
    {
        using var mascot = new RobotMascotViewModel(new Clock()) { AnimationIntensity = input };
        mascot.SetMood(MascotMood.Happy);
        Assert.Equal(expected, mascot.AnimationIntensity);
        Assert.Equal(MascotMood.Happy, mascot.Mood);
    }
}
