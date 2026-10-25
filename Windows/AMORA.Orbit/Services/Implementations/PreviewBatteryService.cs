using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Deterministic battery service for UI previews, testing, or sandbox environments.
/// Clearly separated from live Win32 power providers.
/// </summary>
public class PreviewBatteryService : IBatteryService
{
    private BatterySnapshot _current;
    public BatterySnapshot CurrentSnapshot => _current;
    public BatterySnapshot GetSnapshot() => CurrentSnapshot;

    public event EventHandler<BatterySnapshot>? BatteryUpdated;

    public PreviewBatteryService(BatterySnapshot? initial = null)
    {
        _current = initial ?? new BatterySnapshot(
            Percentage: 88,
            IsCharging: false,
            IsPluggedIn: false,
            HasBattery: true,
            EstimatedRemaining: TimeSpan.FromHours(4).Add(TimeSpan.FromMinutes(22))
        );
    }

    public void SetState(BatterySnapshot snapshot)
    {
        _current = snapshot;
        BatteryUpdated?.Invoke(this, _current);
    }

    public void Refresh()
    {
        BatteryUpdated?.Invoke(this, _current);
    }
}
