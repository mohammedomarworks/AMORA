using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Separated preview system telemetry provider for UI testing.
/// </summary>
public class PreviewSystemTelemetryService : ISystemTelemetryService
{
    private SystemTelemetrySnapshot _current;
    public SystemTelemetrySnapshot CurrentSnapshot => _current;

    public event EventHandler<SystemTelemetrySnapshot>? TelemetryUpdated;

    public PreviewSystemTelemetryService(SystemTelemetrySnapshot? initial = null)
    {
        _current = initial ?? new SystemTelemetrySnapshot(
            CpuUsagePercent: 18.0,
            MemoryUsagePercent: 44.0,
            TotalPhysicalMemoryBytes: 32UL * 1024 * 1024 * 1024,
            AvailablePhysicalMemoryBytes: 18UL * 1024 * 1024 * 1024
        );
    }

    public void SetState(SystemTelemetrySnapshot snapshot)
    {
        _current = snapshot;
        TelemetryUpdated?.Invoke(this, _current);
    }

    public void Refresh()
    {
        TelemetryUpdated?.Invoke(this, _current);
    }
}
