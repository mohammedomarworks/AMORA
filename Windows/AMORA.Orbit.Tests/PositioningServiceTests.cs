using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class PositioningServiceTests
{
    [Theory]
    [InlineData(false, 176, 34)]
    [InlineData(true, 860, 300)]
    public void Island_UsesCompactTopCenteredGeometry(bool expanded, int width, int height)
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            0, 0, 1920, 1080, 1, expanded);
        Assert.Equal(width, bounds.Width);
        Assert.Equal(height, bounds.Height);
        Assert.Equal((1920 - width) / 2, bounds.X);
        Assert.Equal(6, bounds.Y);
    }

    [Theory]
    [InlineData(1.0, 176, 34, 6)]
    [InlineData(1.25, 220, 42, 8)]
    [InlineData(1.5, 264, 51, 9)]
    [InlineData(2.0, 352, 68, 12)]
    public void Capsule_RespectsDpi(double scale, int width, int height, int margin)
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            0, 0, 1920, 1080, scale, false);
        Assert.Equal(width, bounds.Width);
        Assert.Equal(height, bounds.Height);
        Assert.Equal(margin, bounds.Y);
    }

    [Fact]
    public void NegativeSecondaryMonitorAndTopTaskbar_AreRespected()
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            -1920, -1080 + 48, 1920, 1032, 1.5, true);
        Assert.Equal(-1605, bounds.X);
        Assert.Equal(-1023, bounds.Y);
        Assert.Equal(1290, bounds.Width);
        Assert.Equal(450, bounds.Height);
    }

    [Theory]
    [InlineData(600, 400, 570, 300)]
    [InlineData(600, 200, 570, 180)]
    [InlineData(1, 1, 1, 1)]
    public void SmallDisplays_ClampBothAxes(int width, int height, int expectedWidth, int expectedHeight)
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            200, -100, width, height, 1, true);
        Assert.Equal(expectedWidth, bounds.Width);
        Assert.Equal(expectedHeight, bounds.Height);
        Assert.InRange(bounds.X, 200, 200 + width - bounds.Width);
        Assert.InRange(bounds.Y, -100, -100 + height - bounds.Height);
    }

    [Fact]
    public void WorkspaceHeight_IsIndependentOfHomeHeightAndStillClamped()
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            0, 0, 1280, 600, 1.5, true, expandedHeightDip: 520);
        Assert.Equal(540, bounds.Height);
        Assert.Equal(1216, bounds.Width);
        Assert.InRange(bounds.Y + bounds.Height, 1, 600);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    public void InvalidDpi_RecoversToStandardScale(double scale)
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(0, 0, 1920, 1080, scale, false);
        Assert.Equal(176, bounds.Width);
        Assert.Equal(34, bounds.Height);
    }

    [Fact]
    public void InvalidWorkArea_IsRejectedInsteadOfGeneratingOffscreenBounds()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(0, 0, 0, 1080, 1, false));
    }

    [Theory]
    [InlineData("Progman")]
    [InlineData("WorkerW")]
    [InlineData("Shell_TrayWnd")]
    [InlineData("Shell_SecondaryTrayWnd")]
    public void DesktopWindows_AreExcludedFromFullscreenSuppression(string className) =>
        Assert.True(WindowsWindowPositioningService.IsDesktopWindowClass(className));

    [Fact]
    public void FullscreenDetection_RequiresCoverageOfWholeMonitor()
    {
        var monitor = new NativeMethods.RECT { Left = -1920, Top = 0, Right = 0, Bottom = 1080 };
        Assert.True(WindowsWindowPositioningService.CoversMonitor(monitor, monitor));
        Assert.False(WindowsWindowPositioningService.CoversMonitor(
            new NativeMethods.RECT { Left = -1920, Top = 0, Right = 0, Bottom = 1032 }, monitor));
        Assert.False(WindowsWindowPositioningService.CoversMonitor(default, monitor));
        Assert.False(WindowsWindowPositioningService.IsDesktopWindowClass("GameWindow"));
    }

    [Fact]
    public void MaximizedCaptionedApp_IsNotFullscreenEvenWithAutoHiddenTaskbar()
    {
        var monitor = new NativeMethods.RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1080 };
        Assert.False(WindowsWindowPositioningService.ShouldSuppressForegroundWindow(
            monitor, monitor, "NormalApplication", NativeMethods.WS_CAPTION | 0x00080000));
        Assert.True(WindowsWindowPositioningService.ShouldSuppressForegroundWindow(
            monitor, monitor, "BorderlessPresentation", 0x80000000));
        Assert.False(WindowsWindowPositioningService.ShouldSuppressForegroundWindow(
            monitor, monitor, "Progman", 0x80000000));
    }

    [Theory]
    [InlineData(96, 1.0)]
    [InlineData(144, 1.5)]
    [InlineData(192, 2.0)]
    public void DpiHelper_ComputesScale(uint dpi, double scale) =>
        Assert.Equal(scale, DpiHelper.GetScaleFactor(dpi));

    [Fact]
    public void DpiHelper_RoundTrip_PreservesValue() =>
        Assert.Equal(480, DpiHelper.PhysicalToDip(DpiHelper.DipToPhysical(480, 1.5), 1.5));
}
