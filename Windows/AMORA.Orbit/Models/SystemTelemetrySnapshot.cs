namespace AMORA.Orbit.Models;

public record SystemTelemetrySnapshot(
    double CpuUsagePercent,
    double MemoryUsagePercent,
    ulong TotalPhysicalMemoryBytes,
    ulong AvailablePhysicalMemoryBytes
)
{
    public static SystemTelemetrySnapshot Empty => new(0.0, 0.0, 0, 0);

    public double TotalRamGb => TotalPhysicalMemoryBytes / (1024.0 * 1024.0 * 1024.0);
    public double UsedRamGb => TotalPhysicalMemoryBytes >= AvailablePhysicalMemoryBytes
        ? (TotalPhysicalMemoryBytes - AvailablePhysicalMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
        : 0.0;

    public string CpuDisplayText => $"{CpuUsagePercent:F0}%";
    public string MemoryDisplayText => $"{MemoryUsagePercent:F0}%";

    public string MemoryDetailedText
    {
        get
        {
            if (TotalPhysicalMemoryBytes == 0) return "Memory Unavailable";
            return $"{UsedRamGb:F1} / {TotalRamGb:F1} GB";
        }
    }
}
