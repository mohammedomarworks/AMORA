using System.Runtime.InteropServices;
using System.Text;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsWindowPositioningService : IWindowPositioningService
{
    public DisplayWorkArea GetCurrentWorkArea(IntPtr windowHandle)
    {
        // Before the HWND exists, use the display containing the pointer. Once it
        // exists, retain its display instead of jumping to a fictitious 1080p screen.
        var monitor = GetTargetMonitor(windowHandle);
        var info = new NativeMethods.MONITORINFO { cbSize = Marshal.SizeOf<NativeMethods.MONITORINFO>() };
        var dpi = windowHandle == IntPtr.Zero ? 0 : NativeMethods.GetDpiForWindow(windowHandle);
        if (dpi == 0 && NativeMethods.GetDpiForMonitor(monitor, 0, out var monitorDpi, out _) == 0)
            dpi = monitorDpi;
        if (dpi == 0) dpi = DpiHelper.StandardDpi;

        if (NativeMethods.GetMonitorInfo(monitor, ref info) && info.rcWork.Width > 0 && info.rcWork.Height > 0)
            return new DisplayWorkArea(info.rcWork.Left, info.rcWork.Top, info.rcWork.Width,
                info.rcWork.Height, dpi, DpiHelper.GetScaleFactor(dpi));

        // Display removal can race the lookup. Recover to the real primary work
        // area, respecting taskbars, instead of retaining off-screen coordinates.
        if (NativeMethods.SystemParametersInfo(NativeMethods.SPI_GETWORKAREA, 0, out var work, 0)
            && work.Width > 0 && work.Height > 0)
            return new DisplayWorkArea(work.Left, work.Top, work.Width, work.Height, dpi, DpiHelper.GetScaleFactor(dpi));

        return new DisplayWorkArea(0, 0, Math.Max(1, NativeMethods.GetSystemMetrics(0)),
            Math.Max(1, NativeMethods.GetSystemMetrics(1)), dpi, DpiHelper.GetScaleFactor(dpi));
    }

    private static IntPtr GetTargetMonitor(IntPtr windowHandle)
    {
        if (windowHandle != IntPtr.Zero)
            return NativeMethods.MonitorFromWindow(windowHandle, NativeMethods.MONITOR_DEFAULTTONEAREST);
        NativeMethods.GetCursorPos(out var pointer);
        return NativeMethods.MonitorFromPoint(pointer, NativeMethods.MONITOR_DEFAULTTONEAREST);
    }

    public CapsuleBounds CalculateCapsuleBounds(IntPtr windowHandle, bool isExpanded,
        int collapsedWidth = 176, int collapsedHeight = 34, int expandedWidth = 860, int expandedHeight = 300)
    {
        var work = GetCurrentWorkArea(windowHandle);
        return CalculateCapsuleBoundsFromWorkArea(work.X, work.Y, work.Width, work.Height,
            work.DpiScaleFactor, isExpanded, collapsedWidth, collapsedHeight, expandedWidth, expandedHeight);
    }

    /// <summary>Top-centered physical bounds from a physical work area and DIP dimensions.</summary>
    public static CapsuleBounds CalculateCapsuleBoundsFromWorkArea(int workAreaX, int workAreaY,
        int workAreaWidth, int workAreaHeight, double dpiScale, bool isExpanded,
        int collapsedWidthDip = 176, int collapsedHeightDip = 34,
        int expandedWidthDip = 860, int expandedHeightDip = 300)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(workAreaWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(workAreaHeight);
        var widthDip = isExpanded ? expandedWidthDip : collapsedWidthDip;
        var heightDip = isExpanded ? expandedHeightDip : collapsedHeightDip;
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(widthDip);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(heightDip);
        if (!double.IsFinite(dpiScale) || dpiScale <= 0) dpiScale = 1;

        var maxWidth = Math.Max(1, (int)(workAreaWidth * 0.95));
        var maxHeight = Math.Max(1, (int)(workAreaHeight * 0.90));
        // Clamp before conversion to int, including malformed/extreme scale values.
        var width = (int)Math.Clamp(Math.Round(widthDip * dpiScale), 1, maxWidth);
        var height = (int)Math.Clamp(Math.Round(heightDip * dpiScale), 1, maxHeight);
        var margin = (int)Math.Clamp(Math.Round(6 * dpiScale), 0, workAreaHeight - height);
        return new CapsuleBounds(workAreaX + (workAreaWidth - width) / 2,
            workAreaY + margin, width, height);
    }

    public bool IsForegroundAppFullscreen(IntPtr windowHandle)
    {
        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground == IntPtr.Zero || foreground == windowHandle || NativeMethods.IsIconic(foreground)) return false;

        var monitor = NativeMethods.MonitorFromWindow(foreground, NativeMethods.MONITOR_DEFAULTTONEAREST);
        if (monitor != GetTargetMonitor(windowHandle)) return false;

        // The desktop is also a monitor-sized window; it must not hide AMORA.
        var className = new StringBuilder(256);
        NativeMethods.GetClassName(foreground, className, className.Capacity);
        var info = new NativeMethods.MONITORINFO { cbSize = Marshal.SizeOf<NativeMethods.MONITORINFO>() };
        return NativeMethods.GetMonitorInfo(monitor, ref info)
            && NativeMethods.GetWindowRect(foreground, out var bounds)
            && ShouldSuppressForegroundWindow(bounds, info.rcMonitor, className.ToString(),
                NativeMethods.GetWindowLongPtr(foreground, NativeMethods.GWL_STYLE).ToInt64());
    }

    public static bool ShouldSuppressForegroundWindow(NativeMethods.RECT window, NativeMethods.RECT monitor,
        string className, long windowStyle) =>
        // With an auto-hidden taskbar, maximized ordinary apps can cover every
        // monitor pixel. Their caption style distinguishes them from a borderless
        // fullscreen game/presentation, avoiding an unexpected disappearing island.
        !IsDesktopWindowClass(className) && (windowStyle & NativeMethods.WS_CAPTION) != NativeMethods.WS_CAPTION &&
        CoversMonitor(window, monitor);

    public static bool IsDesktopWindowClass(string className) =>
        className is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";

    public static bool CoversMonitor(NativeMethods.RECT window, NativeMethods.RECT monitor) =>
        monitor.Width > 0 && monitor.Height > 0 && window.Width > 0 && window.Height > 0 &&
        window.Left <= monitor.Left && window.Top <= monitor.Top &&
        window.Right >= monitor.Right && window.Bottom >= monitor.Bottom;
}
