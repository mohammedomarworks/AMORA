namespace AMORA.Orbit.Models;

public record BatterySnapshot(
    int Percentage,
    bool IsCharging,
    bool IsPluggedIn,
    bool HasBattery,
    TimeSpan? EstimatedRemaining,
    bool IsAvailable = true
)
{
    public bool IsDesktopAC => IsAvailable && !HasBattery;
    public bool HasPercentage => IsAvailable && HasBattery && Percentage is >= 0 and <= 100;
    public static BatterySnapshot Unavailable => new(-1, false, false, false, null, IsAvailable: false);
    public TimeSpan? EstimatedTimeRemaining => EstimatedRemaining;

    public static BatterySnapshot DesktopAC => new(
        Percentage: 100,
        IsCharging: false,
        IsPluggedIn: true,
        HasBattery: false,
        EstimatedRemaining: null
    );

    /// <summary>
    /// Convenience factory where <paramref name="isDesktopAC"/> determines whether a physical
    /// battery is present. Pass <c>true</c> for a desktop PC on direct AC power, or <c>false</c>
    /// for a laptop with a real battery at <paramref name="percentage"/>.
    /// </summary>
    public static BatterySnapshot FromBatteryState(
        int percentage,
        bool isCharging,
        bool isPluggedIn,
        bool isDesktopAC,
        TimeSpan? estimatedTimeRemaining = null) => new(
            Percentage: percentage,
            IsCharging: isCharging,
            IsPluggedIn: isPluggedIn,
            HasBattery: !isDesktopAC,
            EstimatedRemaining: estimatedTimeRemaining
        );

    public string Description
    {
        get
        {
            if (!IsAvailable) return "Power status unavailable";
            if (IsDesktopAC) return "Desktop PC (Direct AC)";
            if (!HasPercentage) return "Battery level unavailable";
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
            if (!IsAvailable) return "Windows could not read power status";
            if (IsDesktopAC) return "No battery detected (Direct AC Power)";
            if (IsCharging) return "Charging power connected";
            if (EstimatedRemaining.HasValue && EstimatedRemaining.Value.TotalMinutes > 0)
            {
                var h = (int)EstimatedRemaining.Value.TotalHours;
                var m = EstimatedRemaining.Value.Minutes;
                return $"{h}h {m}m estimated remaining";
            }
            return IsPluggedIn ? "Power connected" : "Time remaining unavailable";
        }
    }
}
