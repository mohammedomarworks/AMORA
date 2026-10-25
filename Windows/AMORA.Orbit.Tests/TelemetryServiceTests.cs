using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class TelemetryServiceTests
{
    [Fact]
    public void SystemTelemetrySnapshot_ConvertsBytesToGbAccurately()
    {
        // 16 GB total, 8 GB used
        ulong totalBytes = 16UL * 1024 * 1024 * 1024;
        ulong availBytes = 8UL * 1024 * 1024 * 1024;

        var snapshot = new SystemTelemetrySnapshot(
            CpuUsagePercent: 24.5,
            MemoryUsagePercent: 50.0,
            TotalPhysicalMemoryBytes: totalBytes,
            AvailablePhysicalMemoryBytes: availBytes);

        Assert.Equal(16.0, snapshot.TotalRamGb, precision: 1);
        Assert.Equal(8.0, snapshot.UsedRamGb, precision: 1);
        Assert.Equal(24.5, snapshot.CpuUsagePercent, precision: 1);
        Assert.Equal(50.0, snapshot.MemoryUsagePercent, precision: 1);
    }

    [Fact]
    public void PreviewSystemTelemetryService_ReturnsValidSnapshot()
    {
        var service = new PreviewSystemTelemetryService();
        var snapshot = service.GetSnapshot();

        Assert.NotNull(snapshot);
        Assert.True(snapshot.CpuUsagePercent >= 0 && snapshot.CpuUsagePercent <= 100);
        Assert.True(snapshot.MemoryUsagePercent >= 0 && snapshot.MemoryUsagePercent <= 100);
        Assert.True(snapshot.TotalRamGb > 0);
        Assert.True(snapshot.UsedRamGb > 0);
    }
}
