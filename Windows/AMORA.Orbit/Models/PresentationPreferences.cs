namespace AMORA.Orbit.Models;

public sealed record PresentationPreferences(
    string Theme = "Midnight", double MascotSize = 32, double SurfaceOpacity = .85,
    double MotionIntensity = 1, bool HoverToExpand = true, double AutoCollapseSeconds = 3,
    bool SleepMode = true, double IdleTimeoutSeconds = 300, bool AvoidFullscreen = true,
    bool SoundEnabled = true, double SoundVolume = .5,
    bool MusicEnabled = true, bool TimerEnabled = true, bool BatteryEnabled = true,
    bool SystemMonitorEnabled = true, bool BrowserBridgeEnabled = false)
{
    public static readonly string[] Themes = ["Midnight", "Ocean", "Bubblegum", "Matrix", "Minimal"];
    public static string AccentFor(string theme) => theme switch
    {
        "Ocean" => "#24C4CB", "Bubblegum" => "#FF72B6", "Matrix" => "#35EF78", "Minimal" => "#DDE2EE", _ => "#52CCFF"
    };
    public PresentationPreferences Validate()
    {
        if (!Themes.Contains(Theme) || !Valid(MascotSize, 24, 48) || !Valid(SurfaceOpacity, .5, 1) ||
            !Valid(MotionIntensity, 0, 1) || !Valid(AutoCollapseSeconds, .5, 15) ||
            !Valid(IdleTimeoutSeconds, 30, 1800) || !Valid(SoundVolume, 0, 1))
            throw new ArgumentException("Presentation preferences are outside their supported range.");
        return this;
    }
    private static bool Valid(double value, double min, double max) => double.IsFinite(value) && value >= min && value <= max;
}
