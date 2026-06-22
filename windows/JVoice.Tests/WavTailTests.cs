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
}
