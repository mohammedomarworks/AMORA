using System.Runtime.InteropServices;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsWindowPositioningService : IWindowPositioningService
{
    public DisplayWorkArea GetCurrentWorkArea(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero)
        {
            return new DisplayWorkArea(0, 0, 1920, 1080, 96, 1.0);
        }

        var hMonitor = NativeMethods.MonitorFromWindow(windowHandle, NativeMethods.MONITOR_DEFAULTTONEAREST);
        var monitorInfo = new NativeMethods.MONITORINFO
        {
            cbSize = Marshal.SizeOf<NativeMethods.MONITORINFO>()
        };

        if (NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo))
        {
            var dpi = NativeMethods.GetDpiForWindow(windowHandle);
            if (dpi == 0) dpi = DpiHelper.StandardDpi;
            var scale = (double)dpi / DpiHelper.StandardDpi;

            return new DisplayWorkArea(
                monitorInfo.rcWork.Left,
                monitorInfo.rcWork.Top,
                monitorInfo.rcWork.Width,
                monitorInfo.rcWork.Height,
                dpi,
                scale
            );
        }

        return new DisplayWorkArea(0, 0, 1920, 1080, 96, 1.0);
    }

    public (int X, int Y, int Width, int Height) CalculateCapsuleBounds(
        IntPtr windowHandle,
        bool isExpanded,
        int requestedExpandedWidth = 560,
        int requestedExpandedHeight = 440,
        int collapsedWidth = 190,
        int collapsedHeight = 36)
    {
        var workArea = GetCurrentWorkArea(windowHandle);
        var scale = workArea.DpiScaleFactor;

        int targetWidthDip = isExpanded ? requestedExpandedWidth : collapsedWidth;
        int targetHeightDip = isExpanded ? requestedExpandedHeight : collapsedHeight;

        // Scale to physical pixels
        int physicalWidth = DpiHelper.LogicalToPhysicalPixels(targetWidthDip, scale);
        int physicalHeight = DpiHelper.LogicalToPhysicalPixels(targetHeightDip, scale);

        // Max bound safety: never let the expanded panel exceed 95% of work area width or 90% of height
        int maxWidth = (int)(workArea.Width * 0.95);
        int maxHeight = (int)(workArea.Height * 0.90);

        physicalWidth = Math.Min(physicalWidth, maxWidth);
        physicalHeight = Math.Min(physicalHeight, maxHeight);

        // Center horizontally on active work area
        int x = workArea.X + (workArea.Width - physicalWidth) / 2;

        // Position at the very top of the active display's work area with an elegant 6px margin
        int topMarginPhysical = DpiHelper.LogicalToPhysicalPixels(6, scale);
        int y = workArea.Y + topMarginPhysical;

        // Bounds clamp
        if (x < workArea.X) x = workArea.X;
        if (x + physicalWidth > workArea.X + workArea.Width)
        {
            x = workArea.X + workArea.Width - physicalWidth;
        }

        return (x, y, physicalWidth, physicalHeight);
    }

    public bool IsFullscreenAppActive(IntPtr windowHandle)
    {
        var fgHwnd = NativeMethods.GetForegroundWindow();
        if (fgHwnd == IntPtr.Zero || fgHwnd == windowHandle) return false;

        var hMonitor = NativeMethods.MonitorFromWindow(fgHwnd, NativeMethods.MONITOR_DEFAULTTONEAREST);
        var monitorInfo = new NativeMethods.MONITORINFO
        {
            cbSize = Marshal.SizeOf<NativeMethods.MONITORINFO>()
        };

        if (NativeMethods.GetMonitorInfo(hMonitor, ref monitorInfo))
        {
            if (NativeMethods.GetWindowRect(fgHwnd, out var fgRect))
            {
                // Fullscreen detection: window covers or exceeds the entire monitor rectangle
                return fgRect.Left <= monitorInfo.rcMonitor.Left &&
                       fgRect.Top <= monitorInfo.rcMonitor.Top &&
                       fgRect.Right >= monitorInfo.rcMonitor.Right &&
                       fgRect.Bottom >= monitorInfo.rcMonitor.Bottom;
            }
        }

        return false;
    }
}
