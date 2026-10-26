using System.Runtime.InteropServices;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsSystemTelemetryService : ISystemTelemetryService
{
    private readonly Func<(ulong Idle, ulong Kernel, ulong User)?> _readCpu;
    private readonly Func<(ulong Total, ulong Available)?> _readMemory;
    private readonly object _sampleLock = new();
    private (ulong Idle, ulong Kernel, ulong User)? _previousCpu;
    private SystemTelemetrySnapshot _current = SystemTelemetrySnapshot.Empty;

    public SystemTelemetrySnapshot CurrentSnapshot => _current;
    public SystemTelemetrySnapshot GetSnapshot() => CurrentSnapshot;
    public event EventHandler<SystemTelemetrySnapshot>? TelemetryUpdated;

    public WindowsSystemTelemetryService(
        Func<(ulong Idle, ulong Kernel, ulong User)?>? readCpu = null,
        Func<(ulong Total, ulong Available)?>? readMemory = null)
    {
        _readCpu = readCpu ?? ReadNativeCpu;
        _readMemory = readMemory ?? ReadNativeMemory;
        Refresh();
    }

    public void Refresh()
    {
        SystemTelemetrySnapshot next;
        lock (_sampleLock)
        {
            var cpu = SampleCpu();
            (ulong Total, ulong Available)? memory;
            try { memory = _readMemory(); }
            catch { memory = null; }
            bool hasMemory = memory.HasValue && memory.Value.Total > 0 && memory.Value.Available <= memory.Value.Total;
            var total = hasMemory ? memory!.Value.Total : 0;
            var available = hasMemory ? memory!.Value.Available : 0;
            var memoryPercent = hasMemory ? (total - available) * 100.0 / total : 0;
            next = new SystemTelemetrySnapshot(cpu ?? 0, memoryPercent, total, available, cpu.HasValue);
            _current = next;
        }
        TelemetryUpdated?.Invoke(this, next);
    }

    private double? SampleCpu()
    {
        (ulong Idle, ulong Kernel, ulong User)? current;
        try { current = _readCpu(); }
        catch { current = null; }
        var previous = _previousCpu;
        _previousCpu = current;
        if (!current.HasValue || !previous.HasValue) return null;

        var c = current.Value;
        var p = previous.Value;
        // Counter reset/wrap or a zero-length sample must not appear as zero load.
        if (c.Idle < p.Idle || c.Kernel < p.Kernel || c.User < p.User) return null;
        double idle = c.Idle - p.Idle;
        double total = (double)(c.Kernel - p.Kernel) + (c.User - p.User);
        if (total <= 0 || idle > total) return null;
        return Math.Clamp((total - idle) * 100.0 / total, 0, 100);
    }

    private static (ulong Idle, ulong Kernel, ulong User)? ReadNativeCpu() =>
        NativeMethods.GetSystemTimes(out var idle, out var kernel, out var user)
            ? (idle.ToUInt64(), kernel.ToUInt64(), user.ToUInt64()) : null;

    private static (ulong Total, ulong Available)? ReadNativeMemory()
    {
        var status = new NativeMethods.MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<NativeMethods.MEMORYSTATUSEX>() };
        return NativeMethods.GlobalMemoryStatusEx(ref status) ? (status.ullTotalPhys, status.ullAvailPhys) : null;
    }
}
