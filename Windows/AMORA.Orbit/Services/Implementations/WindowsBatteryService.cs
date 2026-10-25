using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsBatteryService : IBatteryService
{
    private BatterySnapshot _current = BatterySnapshot.DesktopAC;
    public BatterySnapshot CurrentSnapshot => _current;
    public BatterySnapshot GetSnapshot() => CurrentSnapshot;

    public event EventHandler<BatterySnapshot>? BatteryUpdated;

    public WindowsBatteryService()
    {
        Refresh();
    }

    public void Refresh()
    {
        try
        {
            if (NativeMethods.GetSystemPowerStatus(out var status))
            {
                // BatteryFlag == 128 indicates "No system battery" (Desktop PC)
                bool hasBattery = (status.BatteryFlag & 128) == 0 && status.BatteryLifePercent != 255;
                bool isCharging = (status.BatteryFlag & 8) != 0;
                bool isPluggedIn = status.ACLineStatus == 1;
                int percent = hasBattery ? Math.Clamp((int)status.BatteryLifePercent, 0, 100) : 100;
                TimeSpan? remaining = null;

                if (hasBattery && !isCharging && status.BatteryLifeTime > 0)
                {
                    remaining = TimeSpan.FromSeconds(status.BatteryLifeTime);
                }

                _current = new BatterySnapshot(
                    Percentage: percent,
                    IsCharging: isCharging,
                    IsPluggedIn: isPluggedIn,
                    HasBattery: hasBattery,
                    EstimatedRemaining: remaining
                );
            }
            else
            {
                _current = BatterySnapshot.DesktopAC;
            }
        }
        catch
        {
            _current = BatterySnapshot.DesktopAC;
        }

        BatteryUpdated?.Invoke(this, _current);
    }
}
