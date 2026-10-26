using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public record DisplayWorkArea(
    int X,
    int Y,
    int Width,
    int Height,
    uint Dpi,
    double DpiScaleFactor
);

public interface IWindowPositioningService
{
    DisplayWorkArea GetCurrentWorkArea(IntPtr windowHandle);

    /// <summary>
    /// Calculates the optimal bounds for the top-center capsule in either collapsed or expanded state.
    /// Guarantees the capsule is centered on the active display and never exceeds available work area bounds.
    /// </summary>
    CapsuleBounds CalculateCapsuleBounds(
        IntPtr windowHandle,
        bool isExpanded,
        int collapsedWidth = 176,
        int collapsedHeight = 34,
        int expandedWidth = 860,
        int expandedHeight = 300
    );

    /// <summary>
    /// Returns true if the foreground application on the current monitor is running in exclusive or borderless fullscreen.
    /// </summary>
    bool IsForegroundAppFullscreen(IntPtr windowHandle);
}
