using System;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class DeterministicCommandRouter : IAssistantCommandRouter
{
    private static readonly Regex AddTimeRegex = new(
        @"^(?:add|give\s+me|\+)\s*(\d+)\s*(?:m|min|mins|minute|minutes)(?:\s+(?:more|to\s+timer))?$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex TimerStartRegex = new(
        @"^(?:(?:start|set|create|run|begin)\s+(?:a\s+)?)?(?:timer\s+(?:for\s+)?)?(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)(?:\s+(?:and\s*)?(\d+)\s*(m|min|mins|minute|minutes|s|sec|secs|second|seconds))?(?:\s+(?:timer|countdown))?(?:\s+(?:for\s+)?(.+))?$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex CountdownPrefixRegex = new(
        @"^countdown\s+(\d+)\s*(s|sec|secs|second|seconds|m|min|mins)(?:\s+(?:for\s+)?(.+))?$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public AssistantCommand Route(string input, CommandContext? context = null)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return new AssistantCommand.Unknown(string.Empty, "Input was empty.");
        }

        string raw = input.Trim();
        string norm = Normalize(raw);

        context ??= new CommandContext();

        // 0. Conversation Management
        if (IsConversationReset(norm))
        {
            return new AssistantCommand.ResetConversation();
        }

        // 1. Timer Control Commands
        if (IsTimerCancel(norm))
        {
            return new AssistantCommand.CancelTimer();
        }

        if (IsTimerPause(norm))
        {
            return new AssistantCommand.PauseTimer();
        }

        if (IsTimerResume(norm))
        {
            return new AssistantCommand.ResumeTimer();
        }

        if (TryParseAddTime(norm, out var addDuration))
        {
            return new AssistantCommand.AddTimerTime(addDuration);
        }

        if (TryParseTimerStart(norm, raw, out var startDuration, out var timerLabel))
        {
            return new AssistantCommand.StartTimer(startDuration, timerLabel);
        }

        // 2. Ambiguous Contextual Pause / Resume
        if (norm is "pause" or "pause it" or "stop" or "stop it" or "hold on")
        {
            if (context.IsTimerRunning && context.IsMediaPlaying)
            {
                // Both active: ambiguous without explicit target
                return new AssistantCommand.Unknown(raw, "Both timer and music are active. Please specify 'pause timer' or 'pause music'.");
            }
            if (context.IsTimerRunning)
            {
                return new AssistantCommand.PauseTimer();
            }
            if (context.IsMediaPlaying)
            {
                return new AssistantCommand.PauseMedia();
            }
            if (context.IsTimerActive)
            {
                return new AssistantCommand.PauseTimer();
            }
        }

        if (norm is "resume" or "resume it" or "continue")
        {
            if (context.IsTimerActive && !context.IsTimerRunning && !context.IsMediaPlaying && context.HasTrack)
            {
                // Both paused: ambiguous without explicit target
                return new AssistantCommand.Unknown(raw, "Both timer and music are paused. Please specify 'resume timer' or 'play music'.");
            }
            if (context.IsTimerActive && !context.IsTimerRunning)
            {
                return new AssistantCommand.ResumeTimer();
            }
            if (!context.IsMediaPlaying && context.HasTrack)
            {
                return new AssistantCommand.PlayMedia();
            }
        }

        // 3. Media Commands
        if (IsMediaPlay(norm))
        {
            return new AssistantCommand.PlayMedia();
        }

        if (IsMediaPause(norm))
        {
            return new AssistantCommand.PauseMedia();
        }

        if (IsMediaToggle(norm))
        {
            return new AssistantCommand.TogglePlayPauseMedia();
        }

        if (IsMediaNext(norm))
        {
            return new AssistantCommand.NextTrack();
        }

        if (IsMediaPrevious(norm))
        {
            return new AssistantCommand.PreviousTrack();
        }

        // 4. Status Queries
        if (IsTimerStatusQuery(norm))
        {
            return new AssistantCommand.GetTimerStatus();
        }

        if (IsMediaQuery(norm))
        {
            return new AssistantCommand.GetMediaStatus();
        }

        if (IsBatteryQuery(norm))
        {
            return new AssistantCommand.GetBatteryStatus();
        }

        if (IsSystemQuery(norm))
        {
            return new AssistantCommand.GetSystemStatus();
        }

        // 5. Consequential / Confirmation Actions
        if (IsConsequentialAction(norm, out var actionId, out var actionDesc))
        {
            return new AssistantCommand.ConsequentialAction(
                actionId,
                actionDesc,
                () => actionId switch
                {
                    "reset_settings" => Task.FromResult(AssistantExecutionResult.Success("Settings reset to factory defaults.", MascotMood.Happy)),
                    "clear_memories" => Task.FromResult(AssistantExecutionResult.Success("All memories cleared.", MascotMood.Happy)),
                    "wipe_cache" => Task.FromResult(AssistantExecutionResult.Success("Cache wiped.", MascotMood.Happy)),
                    _ => Task.FromResult(AssistantExecutionResult.Unsupported($"Action '{actionId}' is not supported."))
                }
            );
        }

        return new AssistantCommand.Unknown(raw, "Query not recognized as a deterministic command.");
    }

    private static string Normalize(string input)
    {
        string s = input.Trim().ToLowerInvariant();
        s = s.TrimEnd('.', '!', '?', ',');
        return Regex.Replace(s, @"\s+", " ");
    }

    private static bool IsTimerCancel(string norm) =>
        norm is "cancel timer" or "stop timer" or "clear timer" or "delete timer" or "kill timer" or "reset timer";

    private static bool IsTimerPause(string norm) =>
        norm is "pause timer" or "pause the timer" or "hold timer" or "freeze timer";

    private static bool IsTimerResume(string norm) =>
        norm is "resume timer" or "resume the timer" or "unpause timer" or "continue timer";

    private static bool TryParseAddTime(string norm, out TimeSpan duration)
    {
        duration = TimeSpan.Zero;
        if (norm is "+1m" or "add 1m" or "add a minute" or "add 1 minute")
        {
            duration = TimeSpan.FromMinutes(1);
            return true;
        }

        if (norm is "+2m" or "add 2m" or "add 2 minutes")
        {
            duration = TimeSpan.FromMinutes(2);
            return true;
        }

        var match = AddTimeRegex.Match(norm);
        if (match.Success && int.TryParse(match.Groups[1].Value, out int minutes) &&
            minutes > 0 && (long)minutes * 60 <= int.MaxValue)
        {
            duration = TimeSpan.FromMinutes(minutes);
            return true;
        }

        return false;
    }

    private static bool TryParseTimerStart(string norm, string raw, out TimeSpan duration, out string label)
    {
        duration = TimeSpan.Zero;
        label = "Timer";

        if (norm is "pomodoro" or "start pomodoro" or "begin pomodoro" or "focus session")
        {
            duration = TimeSpan.FromMinutes(25);
            label = "Pomodoro";
            return true;
        }

        string rawForMatch = raw.TrimEnd('.', '!', '?', ',');
        var match = TimerStartRegex.Match(rawForMatch);
        if (!match.Success)
        {
            var cdMatch = CountdownPrefixRegex.Match(rawForMatch);
            if (cdMatch.Success && int.TryParse(cdMatch.Groups[1].Value, out int cdVal))
            {
                string cdUnit = cdMatch.Groups[2].Value;
                long secs = cdUnit.StartsWith("m", StringComparison.OrdinalIgnoreCase) ? (long)cdVal * 60 : cdVal;
                if (secs <= 0 || secs > int.MaxValue) return false;
                duration = TimeSpan.FromSeconds(secs);
                label = cdMatch.Groups[3].Success && !string.IsNullOrWhiteSpace(cdMatch.Groups[3].Value)
                    ? cdMatch.Groups[3].Value.Trim()
                    : "Countdown";
                return true;
            }
            return false;
        }

        if (!int.TryParse(match.Groups[1].Value, out int val1))
        {
            return false;
        }

        string unit1 = match.Groups[2].Value;
        int val2 = 0;
        if (match.Groups[3].Success && !int.TryParse(match.Groups[3].Value, out val2)) return false;
        string unit2 = match.Groups[4].Success ? match.Groups[4].Value : string.Empty;
        string rawLabel = match.Groups[5].Success ? match.Groups[5].Value : string.Empty;

        long totalSeconds = 0;
        foreach (var (v, u) in new[] { (val1, unit1), (val2, unit2) })
        {
            if (string.IsNullOrEmpty(u)) continue;
            if (u.StartsWith("h", StringComparison.OrdinalIgnoreCase)) totalSeconds += (long)v * 3600;
            else if (u.StartsWith("m", StringComparison.OrdinalIgnoreCase)) totalSeconds += (long)v * 60;
            else if (u.StartsWith("s", StringComparison.OrdinalIgnoreCase)) totalSeconds += v;
        }

        if (totalSeconds <= 0 || totalSeconds > int.MaxValue)
        {
            return false;
        }

        duration = TimeSpan.FromSeconds(totalSeconds);

        string normalizedLabel = Normalize(rawLabel);
        if ((string.IsNullOrWhiteSpace(rawLabel) && norm.Contains("countdown")) || normalizedLabel == "countdown")
        {
            label = "Countdown";
        }
        else if (normalizedLabel == "pomodoro")
        {
            label = "Pomodoro";
        }
        else if (normalizedLabel == "break")
        {
            label = "Break";
        }
        else if (normalizedLabel == "sprint")
        {
            label = "Sprint";
        }
        else if (!string.IsNullOrWhiteSpace(rawLabel))
        {
            string clean = rawLabel.Trim();
            if (!string.IsNullOrWhiteSpace(clean))
            {
                label = clean;
            }
        }

        return true;
    }

    private static bool IsMediaPlay(string norm) =>
        norm is "play" or "play music" or "start music" or "resume music" or "play song" or "unpause music" or "play the music";

    private static bool IsMediaPause(string norm) =>
        norm is "pause music" or "stop music" or "pause the music" or "pause song";

    private static bool IsMediaToggle(string norm) =>
        norm is "toggle music" or "play pause" or "play/pause" or "toggle playback";

    private static bool IsMediaNext(string norm) =>
        norm is "next" or "next track" or "skip" or "skip track" or "next song" or "skip song";

    private static bool IsMediaPrevious(string norm) =>
        norm is "previous" or "previous track" or "previous song" or "back track" or "last track" or "prev track";

    private static bool IsTimerStatusQuery(string norm) =>
        norm is "how much time is left" or "how much time is left on my timer" or "how much time is left on the timer"
            or "how much time left" or "time remaining" or "remaining time" or "how long is left"
            or "how long is left on my timer" or "how long is left on the timer" or "timer status"
            or "timer remaining" or "check timer" or "time left" or "how much time is on the timer"
            or "timer state" or "check focus timer";

    private static bool IsMediaQuery(string norm) =>
        norm is "what is playing" or "what's playing" or "whats playing" or "what song is this"
            or "what track is this" or "current song" or "current track" or "now playing"
            or "media status" or "music status" or "what am i listening to" or "song" or "track";

    private static bool IsBatteryQuery(string norm) =>
        norm is "battery" or "battery status" or "power status" or "how much battery" or "battery level"
            or "power level" or "charge" or "power" or "am i charging" or "is it charging"
            or "is it plugged in" or "are we charging" or "is the battery charging" or "charging status"
            or "am i on battery" or "on battery" or "plugged in" or "battery percentage" or "battery percent"
            or "power state" or "battery state" or "is my laptop charging" or "is my pc charging";

    private static bool IsSystemQuery(string norm) =>
        norm is "cpu" or "ram" or "memory" or "system" or "system status" or "hardware" or "specs" or "telemetry" or "cpu usage" or "ram usage" or "memory usage";

    private static bool IsConsequentialAction(string norm, out string actionId, out string actionDesc)
    {
        if (norm is "reset settings" or "reset all settings" or "factory reset")
        {
            actionId = "reset_settings";
            actionDesc = "reset all AMORA settings to factory defaults";
            return true;
        }

        if (norm is "clear all memories" or "clear memories" or "delete memories" or "forget everything")
        {
            actionId = "clear_memories";
            actionDesc = "permanently delete all stored assistant memories";
            return true;
        }

        if (norm is "wipe cache" or "clear cache" or "wipe data")
        {
            actionId = "wipe_cache";
            actionDesc = "wipe all cached application data";
            return true;
        }

        actionId = string.Empty;
        actionDesc = string.Empty;
        return false;
    }

    private static bool IsConversationReset(string norm) =>
        norm is "reset conversation" or "clear conversation" or "reset chat" or "clear chat"
            or "new conversation" or "start new conversation" or "clear history" or "reset history"
            or "clear conversation history" or "reset conversation history";
}
