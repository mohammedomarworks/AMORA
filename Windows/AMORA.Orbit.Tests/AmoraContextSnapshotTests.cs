using System;
using AMORA.Orbit.Models;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AmoraContextSnapshotTests
{
    [Fact]
    public void ToCompactSummary_WithAllActiveComponents_FormatsCorrectSummary()
    {
        var timer = new TimerSnapshot(
            Status: TimerStatus.Running,
            Remaining: TimeSpan.FromMinutes(18) + TimeSpan.FromSeconds(45),
            TotalDuration: TimeSpan.FromMinutes(25),
            Label: "Deep Work"
        );

        var media = new MediaTrack(
            Title: "Midnight City",
            Artist: "M83",
            Album: "Hurry Up, We're Dreaming",
            Source: MediaSourceType.Spotify,
            IsPlaying: true,
            IsAvailable: true
        );

        var battery = new BatterySnapshot(
            Percentage: 88,
            IsCharging: true,
            IsPluggedIn: true,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromHours(2) + TimeSpan.FromMinutes(15)
        );

        var telemetry = new SystemTelemetrySnapshot(
            CpuUsagePercent: 14.2,
            MemoryUsagePercent: 52.8,
            TotalPhysicalMemoryBytes: 16UL * 1024 * 1024 * 1024,
            AvailablePhysicalMemoryBytes: 8UL * 1024 * 1024 * 1024
        );

        var snapshot = new AmoraContextSnapshot(timer, media, battery, telemetry, DateTimeOffset.UtcNow);
        string summary = snapshot.ToCompactSummary();

        Assert.Contains("Timer: 18:45 remaining of 25m (Deep Work) [running]", summary);
        Assert.Contains("Media: Midnight City by M83 [playing]", summary);
        Assert.Contains("Power: 88% [charging, ~2h 15m remaining]", summary);
        Assert.Contains("System: CPU 14%", summary);
        Assert.Contains("RAM", summary);
    }

    [Fact]
    public void ToCompactSummary_WithNoActiveComponents_ReportsInactiveHonesty()
    {
        var snapshot = AmoraContextSnapshot.Empty;
        string summary = snapshot.ToCompactSummary();

        Assert.Contains("Timer: None active", summary);
        Assert.Contains("Media: No active session", summary);
        Assert.Contains("Power: Desktop AC (no battery)", summary);
        Assert.DoesNotContain("CPU", summary);
    }

    [Fact]
    public void ToCompactSummary_DesktopPC_ReportsDirectACWithoutBattery()
    {
        var snapshot = new AmoraContextSnapshot(
            Timer: TimerSnapshot.None,
            Media: MediaTrack.None,
            Battery: BatterySnapshot.DesktopAC,
            Telemetry: SystemTelemetrySnapshot.Empty,
            CapturedAt: DateTimeOffset.UtcNow
        );

        string summary = snapshot.ToCompactSummary();

        Assert.Contains("Power: Desktop AC (no battery)", summary);
        Assert.DoesNotContain("%", summary);
    }

    [Fact]
    public void ToCompactSummary_PausedMediaAndTimer_ReportsPausedStatesTruthfully()
    {
        var timer = new TimerSnapshot(
            Status: TimerStatus.Paused,
            Remaining: TimeSpan.FromMinutes(5),
            TotalDuration: TimeSpan.FromMinutes(15),
            Label: "Tea"
        );

        var media = new MediaTrack(
            Title: "Podcast Episode 42",
            Artist: "Tech Talk",
            IsPlaying: false,
            IsAvailable: true
        );

        var snapshot = new AmoraContextSnapshot(
            Timer: timer,
            Media: media,
            Battery: BatterySnapshot.DesktopAC,
            Telemetry: SystemTelemetrySnapshot.Empty,
            CapturedAt: DateTimeOffset.UtcNow
        );

        string summary = snapshot.ToCompactSummary();

        Assert.Contains("Timer: 05:00 remaining of 15m (Tea) [paused]", summary);
        Assert.Contains("Media: Podcast Episode 42 by Tech Talk [paused]", summary);
    }

    [Fact]
    public void ToCompactSummary_ContainsZeroPrivateData()
    {
        var timer = new TimerSnapshot(TimerStatus.Running, TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(10), "Work");
        var media = new MediaTrack("Song", "Artist", IsPlaying: true, IsAvailable: true);
        var battery = BatterySnapshot.DesktopAC;
        var telemetry = new SystemTelemetrySnapshot(10.0, 50.0, 16UL * 1024 * 1024 * 1024, 8UL * 1024 * 1024 * 1024);

        var snapshot = new AmoraContextSnapshot(timer, media, battery, telemetry, DateTimeOffset.UtcNow);
        string summary = snapshot.ToCompactSummary();

        // Privacy assertion: must never contain file paths, clipboard, window titles, or keystrokes
        Assert.DoesNotContain("C:\\", summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("/Users/", summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("clipboard", summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("window", summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("password", summary, StringComparison.OrdinalIgnoreCase);
    }
}
