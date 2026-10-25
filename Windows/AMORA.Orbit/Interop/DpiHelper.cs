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

    public static int LogicalToPhysicalPixels(double logicalPixels, double scaleFactor)
    {
        return (int)Math.Round(logicalPixels * scaleFactor);
    }

    public static double PhysicalToLogicalPixels(int physicalPixels, double scaleFactor)
    {
        return scaleFactor > 0 ? physicalPixels / scaleFactor : physicalPixels;
    }
}
