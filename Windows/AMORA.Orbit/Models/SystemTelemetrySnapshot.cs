namespace AMORA.Orbit.Models;

public record SystemTelemetrySnapshot(
    double CpuUsagePercent,
    double MemoryUsagePercent,
    ulong TotalPhysicalMemoryBytes,
    ulong AvailablePhysicalMemoryBytes,
    bool IsCpuAvailable = true
)
{
    public static SystemTelemetrySnapshot Empty => new(0.0, 0.0, 0, 0, IsCpuAvailable: false);
    public bool HasCpuSample => IsCpuAvailable && double.IsFinite(CpuUsagePercent) && CpuUsagePercent is >= 0 and <= 100;
    public bool HasMemorySample => TotalPhysicalMemoryBytes > 0 && AvailablePhysicalMemoryBytes <= TotalPhysicalMemoryBytes
        && double.IsFinite(MemoryUsagePercent) && MemoryUsagePercent is >= 0 and <= 100;

    public double TotalRamGb => TotalPhysicalMemoryBytes / (1024.0 * 1024.0 * 1024.0);
    public double UsedRamGb => TotalPhysicalMemoryBytes >= AvailablePhysicalMemoryBytes
        ? (TotalPhysicalMemoryBytes - AvailablePhysicalMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
        : 0.0;

    public string CpuDisplayText => HasCpuSample ? $"{CpuUsagePercent:F0}%" : "Unavailable";
    public string MemoryDisplayText => HasMemorySample ? $"{MemoryUsagePercent:F0}%" : "Unavailable";

    public string MemoryDetailedText
    {
        get
        {
            if (!HasMemorySample) return "Memory Unavailable";
            return $"{UsedRamGb:F1} / {TotalRamGb:F1} GB";
        }
    }
}
