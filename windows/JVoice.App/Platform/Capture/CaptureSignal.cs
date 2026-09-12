using System.IO;
using JVoice.Core;
using JVoice.Core.Audio;

namespace JVoice.App.Platform;

/// Measures a finished recording for the "did the microphone actually send anything?" check.
/// Counts exact-zero 16-bit samples only — see <see cref="SilentCaptureDetector"/> for why this
/// is deliberately NOT an amplitude/RMS measurement (the retired RMS gate rejected real quiet
/// dictation; §7 #21). Used solely to pick a truthful error message once a transcript already
/// came back empty, so a misread here can never cost the user a transcript.
public static class CaptureSignal
{
    /// Reads the WAV and reports total/non-zero sample counts. Returns null when the file is
    /// missing or isn't the 16 kHz/mono/16-bit PCM we wrote (then the caller just keeps its
    /// existing message).
    public static CaptureSignalStats? Measure(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var header = new byte[WavTail.HeaderProbeBytes];
            int headerRead = stream.Read(header, 0, header.Length);
            if (headerRead <= 0) return null;

            WavInfo? info = WavTail.ParseHeader(header.AsSpan(0, headerRead));
            if (info is not { } wav) return null;

            stream.Position = wav.DataOffset;
            long total = 0, nonZero = 0;
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                // Whole samples only; a trailing odd byte (mid-write) is ignored.
                for (int i = 0; i + 1 < read; i += 2)
                {
                    total++;
                    if (buffer[i] != 0 || buffer[i + 1] != 0) nonZero++;
                }
            }

            double seconds = wav.SampleRate > 0 ? (double)total / wav.SampleRate : 0d;
            return new CaptureSignalStats(total, nonZero, seconds);
        }
        catch
        {
            return null; // unreadable — caller keeps its existing message
        }
    }
}
