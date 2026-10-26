using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsBatteryService : IBatteryService
{
    private readonly Func<NativeMethods.SYSTEM_POWER_STATUS?> _readStatus;
    private BatterySnapshot _current = BatterySnapshot.Unavailable;
    public BatterySnapshot CurrentSnapshot => _current;
    public BatterySnapshot GetSnapshot() => CurrentSnapshot;
    public event EventHandler<BatterySnapshot>? BatteryUpdated;

    public WindowsBatteryService(Func<NativeMethods.SYSTEM_POWER_STATUS?>? readStatus = null)
    {
        _readStatus = readStatus ?? ReadNativeStatus;
        Refresh();
    }

    public void Refresh()
    {
        BatterySnapshot next;
        try
        {
            var result = _readStatus();
            next = result.HasValue ? FromNativeStatus(result.Value) : BatterySnapshot.Unavailable;
        }
        catch
        {
            next = BatterySnapshot.Unavailable;
        }
        _current = next;
        BatteryUpdated?.Invoke(this, next);
    }

    public static BatterySnapshot FromNativeStatus(NativeMethods.SYSTEM_POWER_STATUS status)
    {
        // 255 is unknown, not a collection of battery flags. Only 128 proves no battery.
        if (status.BatteryFlag == 255) return BatterySnapshot.Unavailable;
        if ((status.BatteryFlag & 128) != 0)
        {
            return status.ACLineStatus == 1 ? BatterySnapshot.DesktopAC : BatterySnapshot.Unavailable;
        }

        bool isCharging = (status.BatteryFlag & 8) != 0;
        return new BatterySnapshot(
            Percentage: status.BatteryLifePercent <= 100 ? status.BatteryLifePercent : -1,
            IsCharging: isCharging,
            IsPluggedIn: status.ACLineStatus == 1,
            HasBattery: true,
            EstimatedRemaining: !isCharging && status.BatteryLifeTime > 0
                ? TimeSpan.FromSeconds(status.BatteryLifeTime) : null);
    }

    private static NativeMethods.SYSTEM_POWER_STATUS? ReadNativeStatus() =>
        NativeMethods.GetSystemPowerStatus(out var status) ? status : null;
}
