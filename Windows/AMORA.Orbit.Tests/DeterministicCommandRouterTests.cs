using System;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class DeterministicCommandRouterTests
{
    private readonly DeterministicCommandRouter _router = new();

    private static CommandContext DefaultContext => new(
        IsTimerActive: false,
        IsTimerRunning: false,
        IsMediaPlaying: false,
        HasTrack: false);

    [Theory]
    [InlineData("start 10m timer", 10, "Timer")]
    [InlineData("timer 25m Focus Session", 25, "Focus Session")]
    [InlineData("pomodoro", 25, "Pomodoro")]
    [InlineData("POMODORO", 25, "Pomodoro")]
    [InlineData("start a 1 hour timer for Deep Work", 60, "Deep Work")]
    [InlineData("start a 1 hour timer for Deep   Work", 60, "Deep   Work")]
    [InlineData("set 45 min timer", 45, "Timer")]
    public void Route_StartTimer_Minutes(string input, double expectedMinutes, string expectedLabel)
    {
        var command = _router.Route(input, DefaultContext);

        var startTimer = Assert.IsType<AssistantCommand.StartTimer>(command);
        Assert.Equal(TimeSpan.FromMinutes(expectedMinutes), startTimer.Duration);
        Assert.Equal(expectedLabel, startTimer.Label);
    }

    [Fact]
    public void Route_StartTimer_Seconds()
    {
        var command = _router.Route("30s countdown", DefaultContext);

        var startTimer = Assert.IsType<AssistantCommand.StartTimer>(command);
        Assert.Equal(TimeSpan.FromSeconds(30), startTimer.Duration);
        Assert.Equal("Countdown", startTimer.Label);
    }

    [Theory]
    [InlineData("pause timer")]
    [InlineData("pause the timer")]
    [InlineData("hold timer")]
    public void Route_PauseTimer_Explicit(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.PauseTimer>(command);
    }

    [Theory]
    [InlineData("resume timer")]
    [InlineData("unpause timer")]
    [InlineData("continue timer")]
    public void Route_ResumeTimer_Explicit(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.ResumeTimer>(command);
    }

    [Theory]
    [InlineData("cancel timer")]
    [InlineData("stop timer")]
    [InlineData("clear timer")]
    [InlineData("reset timer")]
    public void Route_CancelTimer_Explicit(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.CancelTimer>(command);
    }

    [Theory]
    [InlineData("add a minute", 1)]
    [InlineData("add 5m to timer", 5)]
    [InlineData("+2m", 2)]
    public void Route_AddTimerTime(string input, double expectedMinutes)
    {
        var command = _router.Route(input, DefaultContext);

        var addTime = Assert.IsType<AssistantCommand.AddTimerTime>(command);
        Assert.Equal(TimeSpan.FromMinutes(expectedMinutes), addTime.Duration);
        Assert.Equal(TimeSpan.FromMinutes(expectedMinutes), addTime.AdditionalTime);
    }

    [Theory]
    [InlineData("play music")]
    [InlineData("resume music")]
    [InlineData("play song")]
    public void Route_PlayMedia_Explicit(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.PlayMedia>(command);
    }

    [Theory]
    [InlineData("pause music")]
    [InlineData("stop music")]
    [InlineData("pause song")]
    public void Route_PauseMedia_Explicit(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.PauseMedia>(command);
    }

    [Theory]
    [InlineData("next track")]
    [InlineData("skip song")]
    [InlineData("skip")]
    public void Route_NextTrack(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.NextTrack>(command);
    }

    [Theory]
    [InlineData("previous track")]
    [InlineData("previous song")]
    [InlineData("prev track")]
    public void Route_PreviousTrack(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.PreviousTrack>(command);
    }

    [Theory]
    [InlineData("toggle music")]
    [InlineData("play pause")]
    public void Route_ToggleMedia(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.TogglePlayPauseMedia>(command);
    }

    [Fact]
    public void Route_ContextualPause_WhenOnlyTimerRunning_RoutesToTimer()
    {
        var context = new CommandContext(
            IsTimerActive: true,
            IsTimerRunning: true,
            IsMediaPlaying: false,
            HasTrack: false);

        var command = _router.Route("pause", context);
        Assert.IsType<AssistantCommand.PauseTimer>(command);
    }

    [Fact]
    public void Route_ContextualPause_WhenOnlyMediaPlaying_RoutesToMedia()
    {
        var context = new CommandContext(
            IsTimerActive: false,
            IsTimerRunning: false,
            IsMediaPlaying: true,
            HasTrack: true);

        var command = _router.Route("pause", context);
        Assert.IsType<AssistantCommand.PauseMedia>(command);
    }

    [Fact]
    public void Route_ContextualPause_WhenBothActive_RequiresClarification()
    {
        var context = new CommandContext(
            IsTimerActive: true,
            IsTimerRunning: true,
            IsMediaPlaying: true,
            HasTrack: true);

        var command = _router.Route("pause", context);

        var unknown = Assert.IsType<AssistantCommand.Unknown>(command);
        Assert.Contains("timer or music", unknown.Reason, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Route_ContextualResume_WhenTimerPaused_RoutesToTimer()
    {
        var context = new CommandContext(
            IsTimerActive: true,
            IsTimerRunning: false, // Paused
            IsMediaPlaying: false,
            HasTrack: false);

        var command = _router.Route("resume", context);
        Assert.IsType<AssistantCommand.ResumeTimer>(command);
    }

    [Theory]
    [InlineData("battery")]
    [InlineData("battery level")]
    [InlineData("how much battery")]
    public void Route_BatteryStatus(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.GetBatteryStatus>(command);
    }

    [Theory]
    [InlineData("system status")]
    [InlineData("cpu usage")]
    [InlineData("ram usage")]
    [InlineData("memory usage")]
    public void Route_SystemStatus(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.GetSystemStatus>(command);
    }

    [Theory]
    [InlineData("reset settings", "reset_settings")]
    [InlineData("clear all memories", "clear_memories")]
    [InlineData("wipe cache", "wipe_cache")]
    public void Route_ConsequentialActions_RequireConfirmation(string input, string expectedActionId)
    {
        var command = _router.Route(input, DefaultContext);

        var consequential = Assert.IsType<AssistantCommand.ConsequentialAction>(command);
        Assert.Equal(expectedActionId, consequential.ActionId);
        Assert.True(consequential.RequiresConfirmation);
        Assert.False(string.IsNullOrWhiteSpace(consequential.ActionDescription));
    }

    [Theory]
    [InlineData("reset conversation")]
    [InlineData("clear conversation")]
    [InlineData("new conversation")]
    [InlineData("clear chat")]
    [InlineData("reset chat")]
    [InlineData("clear history")]
    [InlineData("reset history")]
    public void Route_ResetConversation_RecognizesVariants(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.ResetConversation>(command);
    }

    [Theory]
    [InlineData("how much time is left")]
    [InlineData("how much time is left on my timer")]
    [InlineData("time remaining")]
    [InlineData("remaining time")]
    [InlineData("how long is left")]
    [InlineData("check timer")]
    [InlineData("timer status")]
    [InlineData("time left")]
    public void Route_TimerStatusQueries(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.GetTimerStatus>(command);
    }

    [Theory]
    [InlineData("what's playing")]
    [InlineData("what is playing")]
    [InlineData("what song is this")]
    [InlineData("current track")]
    [InlineData("current song")]
    [InlineData("now playing")]
    [InlineData("media status")]
    public void Route_MediaQueryQueries(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.GetMediaStatus>(command);
    }

    [Theory]
    [InlineData("am i charging")]
    [InlineData("is it charging")]
    [InlineData("is it plugged in")]
    [InlineData("charging status")]
    [InlineData("am i on battery")]
    [InlineData("on battery")]
    [InlineData("plugged in")]
    public void Route_BatteryQueries_ChargingAndStatus(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.GetBatteryStatus>(command);
    }

    [Fact]
    public void Route_PauseIt_TimerRunningOnly_RoutesToPauseTimer()
    {
        var context = new CommandContext(
            IsTimerActive: true,
            IsTimerRunning: true,
            IsMediaPlaying: false,
            HasTrack: false);

        var command = _router.Route("pause it", context);
        Assert.IsType<AssistantCommand.PauseTimer>(command);
    }

    [Fact]
    public void Route_PauseIt_MediaPlayingOnly_RoutesToPauseMedia()
    {
        var context = new CommandContext(
            IsTimerActive: false,
            IsTimerRunning: false,
            IsMediaPlaying: true,
            HasTrack: true);

        var command = _router.Route("pause it", context);
        Assert.IsType<AssistantCommand.PauseMedia>(command);
    }

    [Fact]
    public void Route_ResumeIt_WhenBothPaused_RequiresClarification()
    {
        var context = new CommandContext(
            IsTimerActive: true,
            IsTimerRunning: false, // Timer paused
            IsMediaPlaying: false,
            HasTrack: true); // Media has track & paused

        var command = _router.Route("resume it", context);
        var unknown = Assert.IsType<AssistantCommand.Unknown>(command);
        Assert.Contains("both timer and music are paused", unknown.Reason, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("what is the weather today in Tokyo")]
    [InlineData("write a python script for binary search")]
    public void Route_UnknownQuery_ReturnsUnknown(string input)
    {
        var command = _router.Route(input, DefaultContext);
        Assert.IsType<AssistantCommand.Unknown>(command);
    }
}
