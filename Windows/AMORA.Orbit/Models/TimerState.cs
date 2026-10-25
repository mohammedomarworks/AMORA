namespace AMORA.Orbit.Models;

public enum TimerStatus
{
    None,
    Idle,
    Running,
    Paused,
    Completed
}

public record TimerSnapshot(
    TimerStatus Status,
    TimeSpan Remaining,
    TimeSpan TotalDuration,
    string Label = ""
)
{
    public static TimerSnapshot Idle => new(TimerStatus.None, TimeSpan.Zero, TimeSpan.Zero, string.Empty);
    public static TimerSnapshot None => Idle;

    public int TotalSeconds => (int)TotalDuration.TotalSeconds;
    public int RemainingSeconds => (int)Remaining.TotalSeconds;

    public bool IsActive => Status is TimerStatus.Running or TimerStatus.Paused;

    public double ProgressPercent => TotalDuration > TimeSpan.Zero
        ? Math.Clamp((TotalDuration.TotalSeconds - Remaining.TotalSeconds) / TotalDuration.TotalSeconds, 0.0, 1.0)
        : 0.0;

    public double ProgressFraction => ProgressPercent;

    public string FormattedRemaining
    {
        get
        {
            var minutes = (int)Remaining.TotalMinutes;
            var seconds = Remaining.Seconds;
            return $"{minutes:D2}:{seconds:D2}";
        }
    }

    public string FormattedTime => FormattedRemaining;
}
