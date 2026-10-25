using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ISystemTelemetryService
{
    SystemTelemetrySnapshot CurrentSnapshot { get; }

    event EventHandler<SystemTelemetrySnapshot>? TelemetryUpdated;

    void Refresh();
    SystemTelemetrySnapshot GetSnapshot() => CurrentSnapshot;
}
