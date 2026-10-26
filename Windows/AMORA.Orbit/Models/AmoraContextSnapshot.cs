using System;
using System.Collections.Generic;

namespace AMORA.Orbit.Models;

/// <summary>
/// Compact, read-only context snapshot captured strictly from AMORA-owned service state.
/// Privacy-first: never captures screenshots, window titles, keystrokes, clipboard, or files.
/// Never persisted to disk, configuration files, or logs.
/// </summary>
public record AmoraContextSnapshot(
    TimerSnapshot Timer,
    MediaTrack Media,
    BatterySnapshot Battery,
    SystemTelemetrySnapshot Telemetry,
    DateTimeOffset CapturedAt
)
{
    public static AmoraContextSnapshot Empty => new(
        TimerSnapshot.None,
        MediaTrack.None,
        BatterySnapshot.DesktopAC,
        SystemTelemetrySnapshot.Empty,
        DateTimeOffset.UtcNow
    );

    /// <summary>
    /// Compact summary string of available AMORA service state, suitable for optional AI grounding.
    /// Excludes empty or inactive components to minimize token usage and protect privacy.
    /// </summary>
    public string ToCompactSummary()
    {
        var facts = new List<string>();

        // Timer context
        if (Timer.IsActive)
        {
            string statusStr = Timer.Status == TimerStatus.Running ? "running" : "paused";
            string labelStr = !string.IsNullOrWhiteSpace(Timer.Label) ? $" ({Timer.Label})" : "";
            facts.Add($"Timer: {Timer.FormattedRemaining} remaining of {Timer.TotalDuration.TotalMinutes:F0}m{labelStr} [{statusStr}]");
        }
        else
        {
            facts.Add("Timer: None active");
        }

        // Media context
        if (Media.IsAvailable && Media != MediaTrack.None && !string.IsNullOrWhiteSpace(Media.Title) && Media.Title != "No Media Playing")
        {
            string playState = Media.IsPlaying ? "playing" : "paused";
            string artistStr = !string.IsNullOrWhiteSpace(Media.Artist) && Media.Artist != "None" ? $" by {Media.Artist}" : "";
            facts.Add($"Media: {Media.Title}{artistStr} [{playState}]");
        }
        else
        {
            facts.Add("Media: No active session");
        }

        // Battery / Power context
        if (!Battery.IsAvailable)
        {
            facts.Add("Power: Unavailable");
        }
        else if (Battery.HasBattery)
        {
            string chargeState = Battery.IsCharging ? "charging" : (Battery.IsPluggedIn ? "plugged in" : "on battery");
            string estimateStr = Battery.EstimatedRemaining.HasValue && Battery.EstimatedRemaining.Value > TimeSpan.Zero
                ? $", ~{(int)Battery.EstimatedRemaining.Value.TotalHours}h {Battery.EstimatedRemaining.Value.Minutes}m remaining"
                : "";
            string level = Battery.HasPercentage ? $"{Battery.Percentage}%" : "Battery level unavailable";
            facts.Add($"Power: {level} [{chargeState}{estimateStr}]");
        }
        else
        {
            facts.Add("Power: Desktop AC (no battery)");
        }

        // Telemetry
        if (Telemetry.TotalPhysicalMemoryBytes > 0)
        {
            facts.Add($"System: CPU {Telemetry.CpuDisplayText}, RAM {Telemetry.MemoryDetailedText}");
        }

        return string.Join(" | ", facts);
    }
}
