using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class PositioningServiceTests
{
    [Fact]
    public void CalculateCenteredBounds_CentersHorizontallyInWorkArea()
    {
        var service = new WindowsWindowPositioningService();
        var workArea = new NativeMethods.RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1040 };

        // Collapsed capsule (width: 240, height: 38, topMargin: 6)
        var bounds = service.CalculateCenteredBounds(workArea, isExpanded: false, dpiScale: 1.0);

        Assert.Equal(38, bounds.Height);
        Assert.Equal(240, bounds.Width);
        Assert.Equal(6, bounds.Y); // Top + margin
        // Center: 0 + (1920 - 240) / 2 = 840
        Assert.Equal(840, bounds.X);
    }

    [Fact]
    public void CalculateCenteredBounds_ExpandedSize_IsCalculatedAndCentered()
    {
        var service = new WindowsWindowPositioningService();
        var workArea = new NativeMethods.RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1040 };

        var bounds = service.CalculateCenteredBounds(workArea, isExpanded: true, dpiScale: 1.0);

        Assert.Equal(660, bounds.Width);
        Assert.Equal(500, bounds.Height);
        Assert.Equal(6, bounds.Y);
        // Center: 0 + (1920 - 660) / 2 = 630
        Assert.Equal(630, bounds.X);
    }

    [Fact]
    public void CalculateCenteredBounds_ClampsToWorkArea_WhenWorkAreaIsSmall()
    {
        var service = new WindowsWindowPositioningService();
        // Very small display/work area (e.g. 600x400)
        var workArea = new NativeMethods.RECT { Left = 0, Top = 0, Right = 600, Bottom = 400 };

        var bounds = service.CalculateCenteredBounds(workArea, isExpanded: true, dpiScale: 1.0);

        // Clamped to 95% of 600 = 570
        Assert.True(bounds.Width <= 570);
        // Clamped to 90% of 400 = 360
        Assert.True(bounds.Height <= 360);
        // Must stay inside work area
        Assert.True(bounds.X >= 0);
        Assert.True(bounds.X + bounds.Width <= 600);
    }

    [Theory]
    [InlineData(96, 1.0)]
    [InlineData(144, 1.5)]
    [InlineData(192, 2.0)]
    public void DpiHelper_ComputesCorrectScaleFactor(uint dpi, double expectedScale)
    {
        double scale = DpiHelper.GetScaleFactor(dpi);
        Assert.Equal(expectedScale, scale, precision: 2);
    }

    [Fact]
    public void DpiHelper_ConvertsDipToPhysicalPixels()
    {
        int physical = DpiHelper.DipToPhysical(100, 1.5);
        Assert.Equal(150, physical);
    }

    [Fact]
    public void DpiHelper_ConvertsPhysicalToDip()
    {
        double dip = DpiHelper.PhysicalToDip(150, 1.5);
        Assert.Equal(100.0, dip, precision: 2);
    }
}
