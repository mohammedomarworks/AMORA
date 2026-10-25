using System.Runtime.InteropServices;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
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

    public CapsuleBounds CalculateCapsuleBounds(
        IntPtr windowHandle,
        bool isExpanded,
        int collapsedWidth = 240,
        int collapsedHeight = 38,
        int expandedWidth = 660,
        int expandedHeight = 500
    )
    {
        var workArea = GetCurrentWorkArea(windowHandle);

        return CalculateCapsuleBoundsFromWorkArea(
            workArea.X,
            workArea.Y,
            workArea.Width,
            workArea.Height,
            workArea.DpiScaleFactor,
            isExpanded,
            collapsedWidth,
            collapsedHeight,
            expandedWidth,
            expandedHeight
        );
    }

    /// <summary>
    /// Pure geometry helper: computes top-center capsule bounds from explicit work-area
    /// coordinates (in physical pixels) and a DPI scale factor. The width/height parameters
    /// are in DIPs (device-independent pixels).
    /// </summary>
    public static CapsuleBounds CalculateCapsuleBoundsFromWorkArea(
        int workAreaX,
        int workAreaY,
        int workAreaWidth,
        int workAreaHeight,
        double dpiScale,
        bool isExpanded,
        int collapsedWidthDip = 240,
        int collapsedHeightDip = 38,
        int expandedWidthDip = 660,
        int expandedHeightDip = 500
    )
    {
        int targetWidthDip = isExpanded ? expandedWidthDip : collapsedWidthDip;
        int targetHeightDip = isExpanded ? expandedHeightDip : collapsedHeightDip;

        // Scale DIPs to physical pixels
        int physicalWidth = DpiHelper.DipToPhysical(targetWidthDip, dpiScale);
        int physicalHeight = DpiHelper.DipToPhysical(targetHeightDip, dpiScale);

        // Max bound safety: never let the expanded panel exceed 95% of work area width or 90% of height
        int maxWidth = (int)(workAreaWidth * 0.95);
        int maxHeight = (int)(workAreaHeight * 0.90);

        physicalWidth = Math.Min(physicalWidth, maxWidth);
        physicalHeight = Math.Min(physicalHeight, maxHeight);

        // Center horizontally on active work area (in physical pixels)
        int x = workAreaX + (workAreaWidth - physicalWidth) / 2;

        // Position at the very top of the active display's work area with a 6px margin (scaled)
        int topMarginPhysical = DpiHelper.DipToPhysical(6, dpiScale);
        int y = workAreaY + topMarginPhysical;

        // Bounds clamp
        if (x < workAreaX) x = workAreaX;
        if (x + physicalWidth > workAreaX + workAreaWidth)
        {
            x = workAreaX + workAreaWidth - physicalWidth;
        }

        return new CapsuleBounds(x, y, physicalWidth, physicalHeight);
    }

    public bool IsForegroundAppFullscreen(IntPtr windowHandle)
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
