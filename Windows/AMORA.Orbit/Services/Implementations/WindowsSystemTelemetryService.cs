using System.Runtime.InteropServices;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsSystemTelemetryService : ISystemTelemetryService
{
    private SystemTelemetrySnapshot _current = SystemTelemetrySnapshot.Empty;
    public SystemTelemetrySnapshot CurrentSnapshot => _current;
    public SystemTelemetrySnapshot GetSnapshot() => CurrentSnapshot;

    public event EventHandler<SystemTelemetrySnapshot>? TelemetryUpdated;

    private ulong _previousIdleTime;
    private ulong _previousKernelTime;
    private ulong _previousUserTime;
    private bool _hasPreviousCpuSample;

    public WindowsSystemTelemetryService()
    {
        Refresh();
    }

    public void Refresh()
    {
        double cpuPercent = SampleCpuUsage();
        var (memoryPercent, totalMemory, availableMemory) = SampleMemoryUsage();

        _current = new SystemTelemetrySnapshot(
            CpuUsagePercent: cpuPercent,
            MemoryUsagePercent: memoryPercent,
            TotalPhysicalMemoryBytes: totalMemory,
            AvailablePhysicalMemoryBytes: availableMemory
        );

        TelemetryUpdated?.Invoke(this, _current);
    }

    private double SampleCpuUsage()
    {
        try
        {
            if (NativeMethods.GetSystemTimes(out var idleTime, out var kernelTime, out var userTime))
            {
                ulong currentIdle = idleTime.ToUInt64();
                ulong currentKernel = kernelTime.ToUInt64();
                ulong currentUser = userTime.ToUInt64();

                if (_hasPreviousCpuSample)
                {
                    ulong diffIdle = currentIdle - _previousIdleTime;
                    ulong diffKernel = currentKernel - _previousKernelTime;
                    ulong diffUser = currentUser - _previousUserTime;

                    ulong totalSystemTime = diffKernel + diffUser;
                    if (totalSystemTime > 0 && totalSystemTime >= diffIdle)
                    {
                        ulong busyTime = totalSystemTime - diffIdle;
                        double percent = (busyTime * 100.0) / totalSystemTime;

                        _previousIdleTime = currentIdle;
                        _previousKernelTime = currentKernel;
                        _previousUserTime = currentUser;

                        return Math.Clamp(percent, 0.0, 100.0);
                    }
                }

                _previousIdleTime = currentIdle;
                _previousKernelTime = currentKernel;
                _previousUserTime = currentUser;
                _hasPreviousCpuSample = true;
            }
        }
        catch
        {
            // Fallback gracefully on non-Win32 environments
        }

        return 0.0;
    }

    private static (double percent, ulong total, ulong available) SampleMemoryUsage()
    {
        try
        {
            var memStatus = new NativeMethods.MEMORYSTATUSEX
            {
                dwLength = (uint)Marshal.SizeOf<NativeMethods.MEMORYSTATUSEX>()
            };

            if (NativeMethods.GlobalMemoryStatusEx(ref memStatus))
            {
                return (memStatus.dwMemoryLoad, memStatus.ullTotalPhys, memStatus.ullAvailPhys);
            }
        }
        catch
        {
            // Fallback gracefully
        }

        return (0.0, 0, 0);
    }
}
