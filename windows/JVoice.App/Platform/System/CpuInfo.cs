using System.Runtime.InteropServices;

namespace JVoice.App.Platform;

/// Physical CPU core count (not logical/hyperthreaded). whisper.cpp throughput peaks at the
/// physical core count and regresses past it (Discussion #403), and .NET only exposes the
/// LOGICAL count, so we read the topology from Win32. Falls back to the logical count on any
/// failure. Computed once.
internal static class CpuInfo
{
    public static int PhysicalCoreCount { get; } = Compute();

    private const int RelationProcessorCore = 0;

    private static int Compute()
    {
        try
        {
            uint len = 0;
            GetLogicalProcessorInformation(IntPtr.Zero, ref len);
            if (len == 0) return Environment.ProcessorCount;

            int size = Marshal.SizeOf<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>();
            int count = (int)(len / size);
            var buffer = new SYSTEM_LOGICAL_PROCESSOR_INFORMATION[count];
            if (!GetLogicalProcessorInformation(buffer, ref len))
                return Environment.ProcessorCount;

            int cores = 0;
            for (int i = 0; i < count; i++)
                if (buffer[i].Relationship == RelationProcessorCore) cores++;
            return cores > 0 ? cores : Environment.ProcessorCount;
        }
        catch
        {
            return Environment.ProcessorCount;
        }
    }

    // x64 layout: ProcessorMask(8) + Relationship(4) + pad(4) + union(16) = 32 bytes.
    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEM_LOGICAL_PROCESSOR_INFORMATION
    {
        public UIntPtr ProcessorMask;
        public int Relationship;   // LOGICAL_PROCESSOR_RELATIONSHIP
        public ulong UnionPart0;   // union payload (only Relationship is read)
        public ulong UnionPart1;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformation(
        IntPtr buffer, ref uint returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformation(
        [Out] SYSTEM_LOGICAL_PROCESSOR_INFORMATION[] buffer, ref uint returnLength);
}
