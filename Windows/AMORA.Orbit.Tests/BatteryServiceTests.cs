using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class BatteryServiceTests
{
    [Fact]
    public void DesktopAC_ReportsAccurately()
    {
        var snapshot = BatterySnapshot.DesktopAC();

        Assert.True(snapshot.IsDesktopAC);
        Assert.True(snapshot.IsPluggedIn);
        Assert.False(snapshot.IsCharging);
        Assert.Equal(100, snapshot.Percentage);
        Assert.Equal("Desktop PC (Direct AC)", snapshot.Description);
    }

    [Fact]
    public void LaptopBattery_Charging_ReportsAccurately()
    {
        var snapshot = new BatterySnapshot(
            Percentage: 85,
            IsCharging: true,
            IsPluggedIn: true,
            IsDesktopAC: false,
            EstimatedTimeRemaining: null);

        Assert.False(snapshot.IsDesktopAC);
        Assert.True(snapshot.IsCharging);
        Assert.Equal("85% (Charging)", snapshot.Description);
    }

    [Fact]
    public void LaptopBattery_Discharging_WithEstimate_ReportsAccurately()
    {
        var snapshot = new BatterySnapshot(
            Percentage: 62,
            IsCharging: false,
            IsPluggedIn: false,
            IsDesktopAC: false,
            EstimatedTimeRemaining: TimeSpan.FromHours(3.5));

        Assert.Equal("62% (~3h 30m remaining)", snapshot.Description);
    }

    [Fact]
    public void PreviewBatteryService_ReturnsValidSnapshot()
    {
        var service = new PreviewBatteryService();
        var snapshot = service.GetSnapshot();

        Assert.NotNull(snapshot);
        Assert.True(snapshot.Percentage >= 0 && snapshot.Percentage <= 100);
        Assert.NotEmpty(snapshot.Description);
    }
}
