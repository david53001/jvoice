using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class WavTailTests
{
    private static byte[] Ascii(string s) => System.Text.Encoding.ASCII.GetBytes(s);

    private static byte[] BuildWav(int sampleRate, int channels, int bits, int dataBytes, bool withFllr)
    {
        var ms = new MemoryStream();
        void U32(int v) => ms.Write(BitConverter.GetBytes((uint)v));
        void U16(int v) => ms.Write(BitConverter.GetBytes((ushort)v));
        ms.Write(Ascii("RIFF")); U32(0); ms.Write(Ascii("WAVE"));   // sizes deliberately 0/stale
        ms.Write(Ascii("fmt ")); U32(16);
        U16(1);                       // PCM
        U16(channels);
        U32(sampleRate);
        U32(sampleRate * channels * bits / 8);
        U16(channels * bits / 8);
        U16(bits);
        if (withFllr) { ms.Write(Ascii("FLLR")); U32(8); ms.Write(new byte[8]); }
        ms.Write(Ascii("data")); U32(dataBytes);
        ms.Write(new byte[dataBytes]);
        return ms.ToArray();
    }

    [Fact]
    public void ParseHeader_Valid_16k_Mono_16bit()
    {
        var info = WavTail.ParseHeader(BuildWav(16000, 1, 16, 100, withFllr: false));
        Assert.NotNull(info);
        Assert.Equal(16000, info!.Value.SampleRate);
        Assert.Equal(1, info.Value.Channels);
        Assert.Equal(2, info.Value.BytesPerSample);
    }

    [Fact]
    public void ParseHeader_ToleratesFllrPadding()
    {
        var info = WavTail.ParseHeader(BuildWav(16000, 1, 16, 100, withFllr: true));
        Assert.NotNull(info);
        Assert.True(info!.Value.DataOffset > 44); // pushed past the FLLR chunk
    }

    [Theory]
    [InlineData(44100, 1, 16)] // wrong rate
    [InlineData(16000, 2, 16)] // stereo
    [InlineData(16000, 1, 8)]  // 8-bit
    public void ParseHeader_RejectsWrongFormat(int rate, int ch, int bits)
        => Assert.Null(WavTail.ParseHeader(BuildWav(rate, ch, bits, 100, withFllr: false)));

    [Fact]
    public void ParseHeader_RejectsNonRiff()
        => Assert.Null(WavTail.ParseHeader(Ascii("NOPEnotawav....")));

    [Fact]
    public void FloatSamples_Normalizes()
    {
        short[] s = { 0, 32767, -32768 };
        var f = WavTail.FloatSamples(s);
        Assert.Equal(0f, f[0]);
        Assert.True(f[1] is > 0.99f and < 1.0f);
        Assert.Equal(-1f, f[2]);
    }

    [Fact]
    public void Reader_ReadsGrowingFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvtail-{Guid.NewGuid():N}.wav");
        try
        {
            File.WriteAllBytes(path, BuildWav(16000, 1, 16, 8, withFllr: false));
            var reader = WavTailReader.Open(path);
            Assert.NotNull(reader);
            var samples = reader!.Samples(0);
            Assert.NotNull(samples);
            Assert.Equal(4, samples!.Length); // 8 data bytes = 4 shorts
        }
        finally { File.Delete(path); }
    }

    // ===== Bug #3: a chunk size with the high bit set must not overflow / throw =====

    // Swift reads chunk size as a 64-bit Int and jumps forward past EOF (-> nil). C# cast it to a
    // signed Int32, so >= 0x80000000 went negative, drove `offset` negative, and threw
    // ArgumentOutOfRangeException out of ParseHeader (uncaught by WavTailReader.Open).
    [Fact]
    public void ParseHeader_HighBitChunkSize_ReturnsNull_DoesNotThrow()
    {
        var ms = new MemoryStream();
        ms.Write(Ascii("RIFF")); ms.Write(BitConverter.GetBytes((uint)0)); ms.Write(Ascii("WAVE"));
        ms.Write(Ascii("JUNK")); ms.Write(BitConverter.GetBytes(0x80000000u)); // high-bit size
        Assert.Null(WavTail.ParseHeader(ms.ToArray()));
    }

    [Fact]
    public void ParseHeader_MaxUintChunkSize_ReturnsNull_DoesNotThrow()
    {
        var ms = new MemoryStream();
        ms.Write(Ascii("RIFF")); ms.Write(BitConverter.GetBytes((uint)0)); ms.Write(Ascii("WAVE"));
        ms.Write(Ascii("LIST")); ms.Write(BitConverter.GetBytes(0xFFFFFFFFu));
        ms.Write(new byte[64]); // some trailing bytes so the loop would keep walking if it could
        Assert.Null(WavTail.ParseHeader(ms.ToArray()));
    }

    // ParseHeader must NEVER throw on arbitrary bytes (it parses a file another process is writing).
    [Fact]
    public void Fuzz_ParseHeader_NeverThrows()
    {
        var rng = new Random(20260623);
        var prefix = new List<byte>();
        prefix.AddRange(Ascii("RIFF")); prefix.AddRange(new byte[4]); prefix.AddRange(Ascii("WAVE"));
        for (int iter = 0; iter < 600; iter++)
        {
            int n = rng.Next(0, 200);
            var buf = new byte[n];
            rng.NextBytes(buf);
            // Half the cases get a valid RIFF/WAVE prefix so the chunk-walk loop is actually exercised.
            byte[] bytes = (iter % 2 == 0) ? prefix.Concat(buf).ToArray() : buf;
            var ex = Record.Exception(() => WavTail.ParseHeader(bytes));
            Assert.Null(ex);
        }
    }

    // ===== Adversarial header edges =====

    [Theory]
    [InlineData(0)]
    [InlineData(4)]
    [InlineData(11)] // < 12 bytes: too short for RIFF/WAVE
    public void ParseHeader_TooShort_ReturnsNull(int len)
        => Assert.Null(WavTail.ParseHeader(new byte[len]));

    [Fact]
    public void ParseHeader_TruncatedFmt_ReturnsNull()
    {
        // "fmt " chunk declared but the 16-byte body is cut off.
        var ms = new MemoryStream();
        ms.Write(Ascii("RIFF")); ms.Write(BitConverter.GetBytes((uint)0)); ms.Write(Ascii("WAVE"));
        ms.Write(Ascii("fmt ")); ms.Write(BitConverter.GetBytes((uint)16));
        ms.Write(new byte[4]); // only 4 of 16 fmt bytes present
        Assert.Null(WavTail.ParseHeader(ms.ToArray()));
    }

    [Fact]
    public void ParseHeader_DataBeforeFmt_ReturnsNull()
    {
        // A `data` chunk reached before any `fmt ` => no format => null.
        var ms = new MemoryStream();
        ms.Write(Ascii("RIFF")); ms.Write(BitConverter.GetBytes((uint)0)); ms.Write(Ascii("WAVE"));
        ms.Write(Ascii("data")); ms.Write(BitConverter.GetBytes((uint)0));
        Assert.Null(WavTail.ParseHeader(ms.ToArray()));
    }

    [Fact]
    public void ParseHeader_OddSizeChunk_IsWordAligned()
    {
        // An odd-size (5) junk chunk before fmt must be skipped with a 1-byte pad (word alignment),
        // so fmt/data are still found and the format validates.
        var ms = new MemoryStream();
        ms.Write(Ascii("RIFF")); ms.Write(BitConverter.GetBytes((uint)0)); ms.Write(Ascii("WAVE"));
        ms.Write(Ascii("JUNK")); ms.Write(BitConverter.GetBytes((uint)5)); ms.Write(new byte[5]); ms.Write(new byte[1]); // +1 pad
        ms.Write(Ascii("fmt ")); ms.Write(BitConverter.GetBytes((uint)16));
        ms.Write(BitConverter.GetBytes((ushort)1));      // PCM
        ms.Write(BitConverter.GetBytes((ushort)1));      // mono
        ms.Write(BitConverter.GetBytes((uint)16000));    // rate
        ms.Write(BitConverter.GetBytes((uint)32000));    // byte rate
        ms.Write(BitConverter.GetBytes((ushort)2));      // block align
        ms.Write(BitConverter.GetBytes((ushort)16));     // bits
        ms.Write(Ascii("data")); ms.Write(BitConverter.GetBytes((uint)10)); ms.Write(new byte[10]);
        var info = WavTail.ParseHeader(ms.ToArray());
        Assert.NotNull(info);
        Assert.Equal(16000, info!.Value.SampleRate);
    }

    [Fact]
    public void Reader_OddTrailingByte_IsDropped()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvtail-{Guid.NewGuid():N}.wav");
        try
        {
            File.WriteAllBytes(path, BuildWav(16000, 1, 16, 9, withFllr: false)); // 9 data bytes (odd)
            var reader = WavTailReader.Open(path);
            Assert.NotNull(reader);
            var samples = reader!.Samples(0);
            Assert.NotNull(samples);
            Assert.Equal(4, samples!.Length); // 9 -> 8 usable -> 4 shorts (trailing byte dropped)
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Reader_SampleOffsetPastEof_ReturnsEmpty()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvtail-{Guid.NewGuid():N}.wav");
        try
        {
            File.WriteAllBytes(path, BuildWav(16000, 1, 16, 8, withFllr: false)); // 4 samples
            var reader = WavTailReader.Open(path);
            Assert.NotNull(reader);
            var samples = reader!.Samples(1000); // way past EOF
            Assert.NotNull(samples);
            Assert.Empty(samples!);
        }
        finally { File.Delete(path); }
    }
}
