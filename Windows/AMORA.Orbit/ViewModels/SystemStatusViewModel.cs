using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class SystemStatusViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IBatteryService _batteryService;
    private readonly ISystemTelemetryService _telemetryService;
    private BatterySnapshot _battery;
    private SystemTelemetrySnapshot _telemetry;
    private readonly CancellationTokenSource _refreshCts = new();

    public SystemStatusViewModel(IBatteryService batteryService, ISystemTelemetryService telemetryService)
    {
        _batteryService = batteryService ?? throw new ArgumentNullException(nameof(batteryService));
        _telemetryService = telemetryService ?? throw new ArgumentNullException(nameof(telemetryService));

        _battery = _batteryService.GetSnapshot();
        _telemetry = _telemetryService.GetSnapshot();

        StartRefreshLoop();
    }

    public BatterySnapshot Battery => _battery;
    public SystemTelemetrySnapshot Telemetry => _telemetry;

    // Battery properties
    public int BatteryPercent => _battery.Percentage;
    public bool IsCharging => _battery.IsCharging;
    public bool IsDesktopAC => _battery.IsDesktopAC;
    public string BatteryStatusText => _battery.Description;

    public string BatteryGlyph
    {
        get
        {
            if (_battery.IsDesktopAC) return "\uE703"; // Power plug glyph
            if (_battery.IsCharging) return "\uEA93";  // Battery charging
            if (_battery.Percentage > 80) return "\uEBAA";
            if (_battery.Percentage > 60) return "\uEBA8";
            if (_battery.Percentage > 40) return "\uEBA6";
            if (_battery.Percentage > 20) return "\uEBA4";
            return "\uEBA0"; // Low battery
        }
    }

    public string BatteryFillColor
    {
        get
        {
            if (_battery.IsDesktopAC) return "#52CCFF";
            if (_battery.IsCharging) return "#30D158"; // Green
            if (_battery.Percentage <= 15) return "#FF453A"; // Red
            if (_battery.Percentage <= 30) return "#FF9F0A"; // Amber
            return "#52CCFF"; // Cyan
        }
    }

    // Telemetry properties
    public double CpuPercent => _telemetry.CpuUsagePercent;
    public string CpuFormatted => $"{Math.Round(_telemetry.CpuUsagePercent)}%";

    public double RamPercent => _telemetry.MemoryUsagePercent;
    public string RamFormatted => $"{Math.Round(_telemetry.MemoryUsagePercent)}%";
    public string RamUsageDetail => $"{_telemetry.UsedRamGb:F1} / {_telemetry.TotalRamGb:F1} GB";

    public event PropertyChangedEventHandler? PropertyChanged;

    public void RefreshNow()
    {
        _battery = _batteryService.GetSnapshot();
        _telemetry = _telemetryService.GetSnapshot();

        OnPropertyChanged(nameof(Battery));
        OnPropertyChanged(nameof(Telemetry));
        OnPropertyChanged(nameof(BatteryPercent));
        OnPropertyChanged(nameof(IsCharging));
        OnPropertyChanged(nameof(IsDesktopAC));
        OnPropertyChanged(nameof(BatteryStatusText));
        OnPropertyChanged(nameof(BatteryGlyph));
        OnPropertyChanged(nameof(BatteryFillColor));
        OnPropertyChanged(nameof(CpuPercent));
        OnPropertyChanged(nameof(CpuFormatted));
        OnPropertyChanged(nameof(RamPercent));
        OnPropertyChanged(nameof(RamFormatted));
        OnPropertyChanged(nameof(RamUsageDetail));
    }

    private void StartRefreshLoop()
    {
        var token = _refreshCts.Token;
        _ = Task.Run(async () =>
        {
            using var periodicTimer = new PeriodicTimer(TimeSpan.FromSeconds(2));
            while (!token.IsCancellationRequested && await periodicTimer.WaitForNextTickAsync(token))
            {
                RefreshNow();
            }
        }, token);
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        _refreshCts.Cancel();
        _refreshCts.Dispose();
    }
}
