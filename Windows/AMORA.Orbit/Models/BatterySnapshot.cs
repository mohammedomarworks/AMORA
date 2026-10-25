namespace AMORA.Orbit.Models;

public record BatterySnapshot(
    int Percentage,
    bool IsCharging,
    bool IsPluggedIn,
    bool HasBattery,
    TimeSpan? EstimatedRemaining
)
{
    public bool IsDesktopAC => !HasBattery;
    public TimeSpan? EstimatedTimeRemaining => EstimatedRemaining;

    public static BatterySnapshot DesktopAC => new(
        Percentage: 100,
        IsCharging: false,
        IsPluggedIn: true,
        HasBattery: false,
        EstimatedRemaining: null
    );

    public static BatterySnapshot DesktopAC() => DesktopAC;

    // Alternative constructor matching named parameters in tests
    public BatterySnapshot(
        int Percentage,
        bool IsCharging,
        bool IsPluggedIn,
        bool IsDesktopAC,
        TimeSpan? EstimatedTimeRemaining
    ) : this(
        Percentage,
        IsCharging,
        IsPluggedIn,
        HasBattery: !IsDesktopAC,
        EstimatedRemaining: EstimatedTimeRemaining
    )
    {
    }

    public string Description
    {
        get
        {
            if (IsDesktopAC) return "Desktop PC (Direct AC)";
            if (IsCharging) return $"{Percentage}% (Charging)";
            if (EstimatedRemaining.HasValue && EstimatedRemaining.Value.TotalMinutes > 0)
            {
                var h = (int)EstimatedRemaining.Value.TotalHours;
                var m = EstimatedRemaining.Value.Minutes;
                return $"{Percentage}% (~{h}h {m}m remaining)";
            }
            if (IsPluggedIn) return $"{Percentage}% (Plugged in)";
            return $"{Percentage}% (On battery)";
        }
    }

    public string StatusText => Description;

    public string DetailedDescription
    {
        get
        {
            if (IsDesktopAC) return "No battery detected (Direct AC Power)";
            if (IsCharging) return "Charging power connected";
            if (EstimatedRemaining.HasValue && EstimatedRemaining.Value.TotalMinutes > 0)
            {
                var h = (int)EstimatedRemaining.Value.TotalHours;
                var m = EstimatedRemaining.Value.Minutes;
                return $"{h}h {m}m estimated remaining";
            }
            return "Calculating battery time...";
        }
    }
}
