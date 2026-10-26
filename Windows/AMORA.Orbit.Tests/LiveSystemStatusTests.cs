using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class LiveSystemStatusTests
{
    [Fact]
    public void UnknownPowerFlagsAndApiFailureDoNotPretendDesktopPower()
    {
        var unknown = WindowsBatteryService.FromNativeStatus(new NativeMethods.SYSTEM_POWER_STATUS
            { BatteryFlag = 255, ACLineStatus = 255, BatteryLifePercent = 255 });
        Assert.False(unknown.IsAvailable);
        Assert.False(unknown.IsDesktopAC);
        Assert.Contains("unavailable", unknown.Description);
        var failed = new WindowsBatteryService(() => null);
        Assert.False(failed.CurrentSnapshot.IsAvailable);
        Assert.False(failed.CurrentSnapshot.IsDesktopAC);
        var context = AmoraContextSnapshot.Empty with { Battery = unknown };
        Assert.Contains("Power: Unavailable", context.ToCompactSummary());
        Assert.DoesNotContain("Desktop AC", context.ToCompactSummary());
    }

    [Fact]
    public void UnknownChargeLevelKeepsPhysicalBatteryDistinctFromDesktop()
    {
        var battery = WindowsBatteryService.FromNativeStatus(new NativeMethods.SYSTEM_POWER_STATUS
            { BatteryFlag = 1, BatteryLifePercent = 255, ACLineStatus = 1, BatteryLifeTime = -1 });
        Assert.True(battery.HasBattery);
        Assert.False(battery.HasPercentage);
        Assert.False(battery.IsDesktopAC);
        Assert.Equal("Battery level unavailable", battery.Description);
        Assert.DoesNotContain("-1%", (AmoraContextSnapshot.Empty with { Battery = battery }).ToCompactSummary());
    }

    [Fact]
    public void OnlyNativeNoBatteryFlagAndKnownAcReportDesktopPower()
    {
        var desktop = WindowsBatteryService.FromNativeStatus(new NativeMethods.SYSTEM_POWER_STATUS
            { BatteryFlag = 128, BatteryLifePercent = 255, ACLineStatus = 1 });
        Assert.True(desktop.IsDesktopAC);
        var emptyBattery = WindowsBatteryService.FromNativeStatus(new NativeMethods.SYSTEM_POWER_STATUS
            { BatteryFlag = 4, BatteryLifePercent = 0, ACLineStatus = 0 });
        Assert.True(emptyBattery.HasPercentage);
        Assert.Equal(0, emptyBattery.Percentage);
        Assert.False(emptyBattery.IsDesktopAC);
    }

    [Fact]
    public void CpuNeedsTwoValidSamplesAndNativeFailuresClearAvailability()
    {
        var samples = new Queue<(ulong Idle, ulong Kernel, ulong User)?>(new (ulong, ulong, ulong)?[]
            { (100, 200, 100), (150, 270, 130), null, (300, 400, 200), (10, 20, 10) });
        var service = new WindowsSystemTelemetryService(() => samples.Dequeue(), () => (1000UL, 250UL));
        Assert.False(service.CurrentSnapshot.HasCpuSample);
        Assert.Equal("Unavailable", service.CurrentSnapshot.CpuDisplayText);
        Assert.Equal(75, service.CurrentSnapshot.MemoryUsagePercent);
        service.Refresh();
        Assert.True(service.CurrentSnapshot.HasCpuSample);
        Assert.Equal(50, service.CurrentSnapshot.CpuUsagePercent);
        service.Refresh();
        Assert.False(service.CurrentSnapshot.HasCpuSample);
        Assert.True(service.CurrentSnapshot.HasMemorySample);
        service.Refresh();
        Assert.False(service.CurrentSnapshot.HasCpuSample); // re-establish baseline after failure
        service.Refresh();
        Assert.False(service.CurrentSnapshot.HasCpuSample); // counter reset
    }

    [Fact]
    public void MemoryFailureIsNotDisplayedAsZeroUsage()
    {
        var service = new WindowsSystemTelemetryService(() => null, () => (100UL, 101UL));
        Assert.False(service.CurrentSnapshot.HasMemorySample);
        Assert.Equal("Memory Unavailable", service.CurrentSnapshot.MemoryDetailedText);
        Assert.Equal("Unavailable", service.CurrentSnapshot.MemoryDisplayText);
    }

    [Fact]
    public void RefreshSamplesServicesAndPublishesThroughUiDispatcher()
    {
        var battery = new CountingBattery();
        var telemetry = new CountingTelemetry();
        var queued = new Queue<Action>();
        using var vm = new SystemStatusViewModel(battery, telemetry, action => queued.Enqueue(action));
        int notifications = 0;
        vm.PropertyChanged += (_, _) => notifications++;
        vm.RefreshNow();
        Assert.Equal(1, battery.Refreshes);
        Assert.Equal(1, telemetry.Refreshes);
        Assert.Equal(0, notifications);
        queued.Dequeue()();
        Assert.True(notifications > 0);
        Assert.Equal("42%", vm.BatteryHeadline);
        Assert.Equal("25%", vm.CpuFormatted);
        Assert.Equal("50%", vm.RamFormatted);
    }

    [Fact]
    public void DisposalSuppressesQueuedNotificationsAndFurtherSampling()
    {
        var battery = new CountingBattery();
        var telemetry = new CountingTelemetry();
        var queued = new Queue<Action>();
        var vm = new SystemStatusViewModel(battery, telemetry, action => queued.Enqueue(action));
        int notifications = 0;
        vm.PropertyChanged += (_, _) => notifications++;
        vm.RefreshNow();
        vm.Dispose();
        queued.Dequeue()();
        vm.RefreshNow();
        vm.Dispose();
        Assert.Equal(0, notifications);
        Assert.Equal(1, battery.Refreshes);
        Assert.Equal(1, telemetry.Refreshes);
    }

    private sealed class CountingBattery : IBatteryService
    {
        public int Refreshes { get; private set; }
        public BatterySnapshot CurrentSnapshot { get; private set; } = BatterySnapshot.Unavailable;
        public event EventHandler<BatterySnapshot>? BatteryUpdated;
        public void Refresh()
        {
            Refreshes++;
            CurrentSnapshot = new(42, false, false, true, null);
            BatteryUpdated?.Invoke(this, CurrentSnapshot);
        }
    }

    private sealed class CountingTelemetry : ISystemTelemetryService
    {
        public int Refreshes { get; private set; }
        public SystemTelemetrySnapshot CurrentSnapshot { get; private set; } = SystemTelemetrySnapshot.Empty;
        public event EventHandler<SystemTelemetrySnapshot>? TelemetryUpdated;
        public void Refresh()
        {
            Refreshes++;
            CurrentSnapshot = new(25, 50, 16UL * 1024 * 1024 * 1024, 8UL * 1024 * 1024 * 1024);
            TelemetryUpdated?.Invoke(this, CurrentSnapshot);
        }
    }
}
