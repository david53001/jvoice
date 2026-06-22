using System.Buffers.Binary;
using System.Text;

namespace JVoice.Core.Audio;

public readonly record struct WavInfo(int DataOffset, int SampleRate, int Channels, int BytesPerSample);

/// Header parsing for a WAV that the recorder is *currently writing*.
/// Faithful port of WavTail.swift: walks chunks (CoreAudio/NAudio may pad before
/// `data`), treats payload as [dataOffset, EOF), and accepts only PCM/16-bit/mono/16 kHz.
public static class WavTail
{
    public const int HeaderProbeBytes = 16384;

    public static WavInfo? ParseHeader(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 12 || FourCC(bytes, 0) != "RIFF" || FourCC(bytes, 8) != "WAVE")
            return null;

        // `offset`/`size` are 64-bit like Swift's `Int`: a 32-bit chunk size with the high bit set
        // (a stale/garbage header) must jump FORWARD past EOF so the loop exits and we return null —
        // never wrap to a negative Int32 (which would drive `offset` negative and throw on the slice).
        long offset = 12;
        (int rate, int channels, int bits)? format = null;
        while (offset + 8 <= bytes.Length)
        {
            int off = (int)offset; // safe: offset + 8 <= bytes.Length, so offset is in range
            string? id = FourCC(bytes, off);
            long size = BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(off + 4, 4));
            int payload = off + 8;
            if (id == "fmt ")
            {
                if (payload + 16 > bytes.Length) return null;
                int audioFormat = BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload, 2));
                if (audioFormat != 1) return null; // PCM only
                format = (
                    rate: (int)BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(payload + 4, 4)),
                    channels: BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload + 2, 2)),
                    bits: BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload + 14, 2)));
            }
            else if (id == "data")
            {
                if (format is { } f && f.channels == 1 && f.rate == 16000 && f.bits == 16)
                    return new WavInfo(payload, f.rate, 1, 2);
                return null;
            }
            // Non-`data` chunks carry a real size and are word-aligned.
            offset = payload + size + (size % 2);
        }
        return null;
    }

    public static float[] FloatSamples(ReadOnlySpan<short> samples)
    {
        var result = new float[samples.Length];
        for (int i = 0; i < samples.Length; i++) result[i] = samples[i] / 32768f;
        return result;
    }

    private static string? FourCC(ReadOnlySpan<byte> bytes, int offset)
    {
        if (offset + 4 > bytes.Length) return null;
        return Encoding.ASCII.GetString(bytes.Slice(offset, 4));
    }
}

/// Incremental sample access to a growing WAV. Opens a fresh handle per read
/// (the file is being appended by another writer). Faithful port of WavTailReader.
public sealed class WavTailReader
{
    public string Path { get; }
    public WavInfo Info { get; }

    private WavTailReader(string path, WavInfo info) { Path = path; Info = info; }

    public static WavTailReader? Open(string path)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var probe = new byte[WavTail.HeaderProbeBytes];
            int read = fs.Read(probe, 0, probe.Length);
            var info = WavTail.ParseHeader(probe.AsSpan(0, read));
            return info is { } i ? new WavTailReader(path, i) : null;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// All samples from `sampleOffset` to EOF. `[]` = no new data; `null` = gone/unreadable.
    public short[]? Samples(int sampleOffset)
    {
        try
        {
            using var fs = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            long byteOffset = Info.DataOffset + (long)sampleOffset * Info.BytesPerSample;
            if (byteOffset > fs.Length) return Array.Empty<short>();
            fs.Seek(byteOffset, SeekOrigin.Begin);
            using var ms = new MemoryStream();
            fs.CopyTo(ms);
            int len = (int)ms.Length;
            byte[] data = ms.GetBuffer();
            int usable = len - (len % 2); // a trailing odd byte is a mid-sample write
            if (usable <= 0) return Array.Empty<short>();
            var result = new short[usable / 2];
            for (int i = 0; i < result.Length; i++)
                result[i] = BinaryPrimitives.ReadInt16LittleEndian(data.AsSpan(i * 2, 2));
            return result;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }
}
