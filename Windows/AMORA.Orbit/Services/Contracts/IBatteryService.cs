using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IBatteryService
{
    BatterySnapshot CurrentSnapshot { get; }

    event EventHandler<BatterySnapshot>? BatteryUpdated;

    void Refresh();
    BatterySnapshot GetSnapshot() => CurrentSnapshot;
}
