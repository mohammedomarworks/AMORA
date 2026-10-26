using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class SystemStatusViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IBatteryService _batteryService;
    private readonly ISystemTelemetryService _telemetryService;
    private readonly Action<Action> _dispatch;
    private readonly object _refreshLock = new();
    private BatterySnapshot _battery;
    private SystemTelemetrySnapshot _telemetry;
    private readonly CancellationTokenSource _refreshCts = new();
    private volatile bool _disposed;

    public SystemStatusViewModel(IBatteryService batteryService, ISystemTelemetryService telemetryService,
        Action<Action>? dispatch = null)
    {
        _batteryService = batteryService ?? throw new ArgumentNullException(nameof(batteryService));
        _telemetryService = telemetryService ?? throw new ArgumentNullException(nameof(telemetryService));
        var context = SynchronizationContext.Current;
        _dispatch = dispatch ?? (action =>
        {
            if (context == null) action();
            else context.Post(_ => action(), null);
        });
        _battery = _batteryService.GetSnapshot();
        _telemetry = _telemetryService.GetSnapshot();
        _ = RunRefreshLoopAsync(_refreshCts.Token);
    }

    public BatterySnapshot Battery => _battery;
    public SystemTelemetrySnapshot Telemetry => _telemetry;
    public int BatteryPercent => _battery.HasPercentage ? _battery.Percentage : 0;
    public bool IsCharging => _battery.IsAvailable && _battery.IsCharging;
    public bool IsDesktopAC => _battery.IsDesktopAC;
    public string BatteryStatusText => _battery.Description;
    public string BatteryHeadline => !_battery.IsAvailable ? "Power unavailable"
        : _battery.IsDesktopAC ? "AC power" : _battery.HasPercentage ? $"{_battery.Percentage}%" : "Battery";
    public string BatteryDetail => _battery.DetailedDescription;

    public string BatteryGlyph => !_battery.IsAvailable ? "\uE9CE"
        : _battery.IsDesktopAC ? "\uE703"
        : _battery.IsCharging ? "\uEA93"
        : !_battery.HasPercentage ? "\uE9CE"
        : _battery.Percentage > 80 ? "\uEBAA"
        : _battery.Percentage > 60 ? "\uEBA8"
        : _battery.Percentage > 40 ? "\uEBA6"
        : _battery.Percentage > 20 ? "\uEBA4" : "\uEBA0";

    public string BatteryFillColor => !_battery.IsAvailable ? "#707E94"
        : _battery.IsDesktopAC ? "#52CCFF"
        : _battery.IsCharging ? "#30D158"
        : !_battery.HasPercentage ? "#707E94"
        : _battery.Percentage <= 15 ? "#FF453A"
        : _battery.Percentage <= 30 ? "#FF9F0A" : "#52CCFF";

    public double CpuPercent => _telemetry.HasCpuSample ? _telemetry.CpuUsagePercent : 0;
    public string CpuFormatted => _telemetry.CpuDisplayText;
    public double RamPercent => _telemetry.HasMemorySample ? _telemetry.MemoryUsagePercent : 0;
    public string RamFormatted => _telemetry.MemoryDisplayText;
    public string RamUsageDetail => _telemetry.MemoryDetailedText;
    public event PropertyChangedEventHandler? PropertyChanged;

    public void RefreshNow()
    {
        lock (_refreshLock)
        {
            if (_disposed) return;
            BatterySnapshot battery;
            SystemTelemetrySnapshot telemetry;
            // Read fresh OS samples, not the initial cached snapshots.
            try { _batteryService.Refresh(); battery = _batteryService.GetSnapshot(); }
            catch { battery = BatterySnapshot.Unavailable; }
            try { _telemetryService.Refresh(); telemetry = _telemetryService.GetSnapshot(); }
            catch { telemetry = SystemTelemetrySnapshot.Empty; }
            _dispatch(() => Publish(battery, telemetry));
        }
    }

    private void Publish(BatterySnapshot battery, SystemTelemetrySnapshot telemetry)
    {
        if (_disposed) return;
        _battery = battery;
        _telemetry = telemetry;
        foreach (var name in new[] { nameof(Battery), nameof(Telemetry), nameof(BatteryPercent), nameof(IsCharging),
            nameof(IsDesktopAC), nameof(BatteryStatusText), nameof(BatteryHeadline), nameof(BatteryDetail),
            nameof(BatteryGlyph), nameof(BatteryFillColor), nameof(CpuPercent), nameof(CpuFormatted),
            nameof(RamPercent), nameof(RamFormatted), nameof(RamUsageDetail) })
            OnPropertyChanged(name);
    }

    private async Task RunRefreshLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var periodicTimer = new PeriodicTimer(TimeSpan.FromSeconds(2));
            while (await periodicTimer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
                RefreshNow();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal shutdown; never an unobserved task failure.
        }
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public void Dispose()
    {
        lock (_refreshLock)
        {
            if (_disposed) return;
            _disposed = true;
            _refreshCts.Cancel();
            _refreshCts.Dispose();
        }
        GC.SuppressFinalize(this);
    }
}
