namespace AMORA.Orbit.Interop;

public static class DpiHelper
{
    public const uint StandardDpi = 96;

    public static double GetScaleFactorForWindow(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero) return 1.0;
        try
        {
            var dpi = NativeMethods.GetDpiForWindow(windowHandle);
            return dpi > 0 ? (double)dpi / StandardDpi : 1.0;
        }
        catch
        {
            return 1.0;
        }
    }

    public static double GetScaleFactor(uint dpi)
    {
        return dpi > 0 ? (double)dpi / StandardDpi : 1.0;
    }

    public static int DipToPhysical(double dip, double scaleFactor)
    {
        return (int)Math.Round(dip * scaleFactor);
    }

    public static int LogicalToPhysicalPixels(double logicalPixels, double scaleFactor)
    {
        return DipToPhysical(logicalPixels, scaleFactor);
    }

    public static double PhysicalToDip(int physicalPixels, double scaleFactor)
    {
        return scaleFactor > 0 ? physicalPixels / scaleFactor : physicalPixels;
    }

    public static double PhysicalToLogicalPixels(int physicalPixels, double scaleFactor)
    {
        return PhysicalToDip(physicalPixels, scaleFactor);
    }
}
