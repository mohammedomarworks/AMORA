using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>The OS terminates the owned inference child even if AMORA crashes.</summary>
internal sealed class LocalBrainProcessJob : IDisposable
{
    private readonly SafeFileHandle _handle;
    public LocalBrainProcessJob(Process process)
    {
        _handle = CreateJobObject(IntPtr.Zero, null);
        var limits = new ExtendedLimit { BasicLimitInformation = new BasicLimit { LimitFlags = 0x2000 } }; // KILL_ON_JOB_CLOSE
        if (_handle.IsInvalid || !SetInformationJobObject(_handle, 9, ref limits, (uint)Marshal.SizeOf<ExtendedLimit>())
            || !AssignProcessToJobObject(_handle, process.Handle))
        { _handle.Dispose(); throw new InvalidOperationException("The inference process could not be safely owned."); }
    }
    public void Dispose() => _handle.Dispose();
    [StructLayout(LayoutKind.Sequential)] private struct BasicLimit
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IoCounters
    { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimit
    {
        public BasicLimit BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateJobObjectW")] private static extern SafeFileHandle CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetInformationJobObject(SafeFileHandle job, int infoClass, ref ExtendedLimit info, uint size);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
}
