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
    /// Calculates the optimal X, Y, Width, and Height for the top-center capsule in either collapsed or expanded state.
    /// Guarantees the capsule is centered on the active display and never exceeds available work area bounds.
    /// </summary>
    (int X, int Y, int Width, int Height) CalculateCapsuleBounds(
        IntPtr windowHandle,
        bool isExpanded,
        int requestedExpandedWidth = 560,
        int requestedExpandedHeight = 440,
        int collapsedWidth = 190,
        int collapsedHeight = 36
    );

    /// <summary>
    /// Returns true if any active window on the current monitor is running in exclusive or borderless fullscreen.
    /// </summary>
    bool IsFullscreenAppActive(IntPtr windowHandle);
}
