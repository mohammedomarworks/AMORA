namespace AMORA.Orbit.Models;

public enum MediaSourceType
{
    None,
    Spotify,
    AppleMusic,
    YouTube,
    System
}

public record MediaTrack(
    string Title,
    string Artist,
    string Album = "",
    MediaSourceType Source = MediaSourceType.None,
    bool IsPlaying = false,
    bool IsAvailable = true,
    TimeSpan Elapsed = default,
    TimeSpan Duration = default
)
{
    public static MediaTrack None => new(
        Title: "No Media Playing",
        Artist: "None",
        Album: string.Empty,
        Source: MediaSourceType.None,
        IsPlaying: false,
        IsAvailable: false,
        Elapsed: TimeSpan.Zero,
        Duration: TimeSpan.Zero
    );

    public double ElapsedSeconds => Elapsed.TotalSeconds;
    public double TotalDurationSeconds => Duration.TotalSeconds;

    public double ProgressFraction => Duration > TimeSpan.Zero
        ? Math.Clamp(Elapsed.TotalSeconds / Duration.TotalSeconds, 0.0, 1.0)
        : 0.0;

    public double ProgressPercent => ProgressFraction;

    public string FormattedElapsed => FormatTime(Elapsed);
    public string FormattedDuration => FormatTime(Duration);

    private static string FormatTime(TimeSpan ts)
    {
        if (ts <= TimeSpan.Zero) return "0:00";

        var totalMinutes = (int)ts.TotalMinutes;
        return $"{totalMinutes:00}:{ts.Seconds:00}";
    }
}
