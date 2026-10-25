using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class PositioningServiceTests
{
    // Work area: 1920×1080 at origin, DPI scale 1.0
    private const int WorkAreaX = 0;
    private const int WorkAreaY = 0;
    private const int WorkAreaWidth = 1920;
    private const int WorkAreaHeight = 1080;

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_Collapsed_CentersHorizontallyWithTopMargin()
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            WorkAreaX, WorkAreaY, WorkAreaWidth, WorkAreaHeight,
            dpiScale: 1.0,
            isExpanded: false);

        // Collapsed: 240×38 DIPs at scale 1.0 = 240×38 physical
        Assert.Equal(240, bounds.Width);
        Assert.Equal(38, bounds.Height);
        // Top margin: 6px
        Assert.Equal(6, bounds.Y);
        // Horizontal center: (1920 - 240) / 2 = 840
        Assert.Equal(840, bounds.X);
    }

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_Expanded_CentersHorizontallyWithTopMargin()
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            WorkAreaX, WorkAreaY, WorkAreaWidth, WorkAreaHeight,
            dpiScale: 1.0,
            isExpanded: true);

        // Expanded: 660×500 DIPs at scale 1.0 = 660×500 physical
        Assert.Equal(660, bounds.Width);
        Assert.Equal(500, bounds.Height);
        Assert.Equal(6, bounds.Y);
        // Horizontal center: (1920 - 660) / 2 = 630
        Assert.Equal(630, bounds.X);
    }

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_TopCenterPlacement()
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            WorkAreaX, WorkAreaY, WorkAreaWidth, WorkAreaHeight,
            dpiScale: 1.0,
            isExpanded: false);

        // Top-center: Y is at work area top + 6px margin
        Assert.Equal(WorkAreaY + 6, bounds.Y);
    }

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_ClampsToWorkArea_WhenWorkAreaIsSmall()
    {
        // Very small display: 600×400
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            0, 0, 600, 400,
            dpiScale: 1.0,
            isExpanded: true);

        // Clamped to 95% of 600 = 570
        Assert.True(bounds.Width <= 570);
        // Clamped to 90% of 400 = 360
        Assert.True(bounds.Height <= 360);
        // Must stay inside work area
        Assert.True(bounds.X >= 0);
        Assert.True(bounds.X + bounds.Width <= 600);
    }

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_OffsetsWorkAreaByX()
    {
        // Work area starts at X=200 (e.g., taskbar on left), 1720 wide
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            200, 0, 1720, 1080,
            dpiScale: 1.0,
            isExpanded: false);

        // Centered within offset work area: 200 + (1720 - 240) / 2 = 940
        Assert.Equal(940, bounds.X);
        Assert.Equal(6, bounds.Y);
    }

    [Theory]
    [InlineData(96, 1.0, 240, 38)]
    [InlineData(144, 1.5, 360, 57)]
    [InlineData(192, 2.0, 480, 76)]
    public void CalculateCapsuleBoundsFromWorkArea_Collapsed_RespectsDpiScale(
        uint dpi, double expectedScale, int expectedWidth, int expectedHeight)
    {
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            WorkAreaX, WorkAreaY, WorkAreaWidth, WorkAreaHeight,
            dpiScale: expectedScale,
            isExpanded: false);

        // 240 DIP * scale = physical pixels
        Assert.Equal(expectedWidth, bounds.Width);
        Assert.Equal(expectedHeight, bounds.Height);

        // Top margin scales too: 6 DIP * scale
        int expectedMargin = DpiHelper.DipToPhysical(6, expectedScale);
        Assert.Equal(expectedMargin, bounds.Y);
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

    [Fact]
    public void DpiHelper_RoundTrip_PreservesValue()
    {
        int original = 480;
        double scale = 1.5;
        int physical = DpiHelper.DipToPhysical(original, scale);
        double backToDip = DpiHelper.PhysicalToDip(physical, scale);
        Assert.Equal((double)original, backToDip, precision: 1);
    }

    [Fact]
    public void CapsuleBounds_RecordEqualsByValue()
    {
        var a = new CapsuleBounds(10, 20, 100, 50);
        var b = new CapsuleBounds(10, 20, 100, 50);
        var c = new CapsuleBounds(11, 20, 100, 50);

        Assert.Equal(a, b);
        Assert.NotEqual(a, c);
    }

    [Fact]
    public void CalculateCapsuleBoundsFromWorkArea_Expanded_ClampedOnSmallDisplay()
    {
        // Small display 600×400: expanded 660×500 should clamp to 570×360
        var bounds = WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
            0, 0, 600, 400,
            dpiScale: 1.0,
            isExpanded: true);

        Assert.Equal(570, bounds.Width); // 95% of 600
        Assert.Equal(360, bounds.Height); // 90% of 400
        Assert.True(bounds.X >= 0);
        Assert.True(bounds.X + bounds.Width <= 600);
        Assert.True(bounds.Y >= 0);
    }
}
