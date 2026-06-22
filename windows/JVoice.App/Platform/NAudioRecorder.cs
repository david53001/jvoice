using System.IO;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace JVoice.App.Platform;

/// Records the microphone to %TEMP%\jvoice-<guid>.wav as 16 kHz / mono / 16-bit
/// PCM, written incrementally so Phase 1's WavTailReader can stream the growing
/// file. Faithful port of RecordingManager.swift: orphan sweep, usable-recording
/// check, permission probe, teardown-on-failure (a failed recording never leaves
/// raw audio behind). Picks a non-Bluetooth capture device when the default is BT
/// (AudioInputRouter) to keep the user's headset music in A2DP.
public sealed class NAudioRecorder : IAudioRecorder, IDisposable
{
    // Target format the brain expects (overview §1, §6.2): 16 kHz, mono, 16-bit PCM LE.
    private const int TargetSampleRate = 16_000;
    // Flush the WAV writer roughly this often so WavTailReader sees fresh samples.
    private static readonly TimeSpan FlushInterval = TimeSpan.FromMilliseconds(250);

    private readonly object _gate = new();
    private WasapiCapture? _capture;
    private WaveFileWriter? _writer;
    private BufferedWaveProvider? _buffer;
    private ISampleProvider? _resampledMono;
    private SampleToWaveProvider16? _to16;
    private System.Threading.Timer? _pumpTimer;
    private MMDevice? _device;

    public string? CurrentPath { get; private set; }
    public bool IsRecording { get; private set; }
    public DateTime? StartedAt { get; private set; }

    public event Action<string>? Failed;

    public bool TryStart(out string? error)
    {
        lock (_gate)
        {
            if (IsRecording) { error = null; return false; }
            error = null;
            try
            {
                _device = ResolveCaptureDevice();
                _capture = new WasapiCapture(_device, useEventSync: true);

                string path = MakeTemporaryRecordingPath();
                CurrentPath = path;

                var captureFormat = _capture.WaveFormat;
                _buffer = new BufferedWaveProvider(captureFormat)
                {
                    DiscardOnBufferOverflow = true,
                    BufferDuration = TimeSpan.FromSeconds(5),
                    // CRITICAL: ReadFully defaults to true, which makes Read() zero-pad
                    // to the requested count forever (the buffer never reports "empty").
                    // That turns the PumpToWriter while-loop into an infinite zero-writing
                    // busy loop. false => Read returns only what's buffered (0 when drained),
                    // so the pump drains available samples and stops.
                    ReadFully = false,
                };

                // capture format -> float samples -> mono -> 16 kHz -> 16-bit PCM
                ISampleProvider sampleSource = _buffer.ToSampleProvider();
                if (captureFormat.Channels > 1)
                    sampleSource = new StereoToMonoSampleProvider(sampleSource) { LeftVolume = 0.5f, RightVolume = 0.5f };
                _resampledMono = sampleSource.WaveFormat.SampleRate == TargetSampleRate
                    ? sampleSource
                    : new WdlResamplingSampleProvider(sampleSource, TargetSampleRate);
                _to16 = new SampleToWaveProvider16(_resampledMono);

                _writer = new WaveFileWriter(path, _to16.WaveFormat); // 16k/mono/16-bit header

                _capture.DataAvailable += OnDataAvailable;
                _capture.RecordingStopped += OnRecordingStopped;

                _capture.StartRecording();

                _pumpTimer = new System.Threading.Timer(_ => PumpToWriter(), null, FlushInterval, FlushInterval);

                IsRecording = true;
                StartedAt = DateTime.UtcNow;
                return true;
            }
            catch (Exception ex)
            {
                error = $"Could not start the microphone: {ex.Message}";
                TearDownLocked(deleteFile: true);
                return false;
            }
        }
    }

    public string? Stop()
    {
        lock (_gate)
        {
            if (!IsRecording) return CurrentPath;
            string? path = CurrentPath;
            try
            {
                _capture?.StopRecording();   // triggers OnRecordingStopped (drains + disposes)
            }
            catch { /* ignore */ }
            PumpToWriter();                  // final drain of anything buffered
            FinalizeWriterLocked();
            IsRecording = false;
            StartedAt = null;
            DisposeCaptureLocked();
            CurrentPath = null;
            return path; // caller checks usability via IsUsableRecording
        }
    }

    /// Probe microphone access. There's no synchronous Windows API; the reliable
    /// probe is to briefly open a capture client and see whether it initializes.
    /// A denied mic (privacy gate off) throws on Init/Start with E_ACCESSDENIED.
    public Task<bool> RequestPermissionAsync()
    {
        return Task.Run(() =>
        {
            try
            {
                using var enumerator = new MMDeviceEnumerator();
                if (!enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
                    return false; // no mic at all
                using var dev = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
                using var probe = new WasapiCapture(dev, useEventSync: true);
                // Initializing the client is enough to surface the privacy denial.
                _ = probe.WaveFormat;
                probe.StartRecording();
                probe.StopRecording();
                return true;
            }
            catch (UnauthorizedAccessException) { return false; }
            catch (System.Runtime.InteropServices.COMException com)
            {
                // E_ACCESSDENIED (0x80070005) => privacy gate denies desktop apps.
                return com.HResult != unchecked((int)0x80070005);
            }
            catch { return false; }
        });
    }

    // capture callbacks

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        try
        {
            lock (_gate)
            {
                _buffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
            }
        }
        catch { /* buffered overflow is discarded; ignore */ }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is null) return; // clean stop handled by Stop()
        // Mid-recording failure: tear down the partial file and notify (Swift parity:
        // a broken recording must not be transcribed and must not orphan a WAV).
        string message = $"Recording stopped unexpectedly: {e.Exception.Message}";
        lock (_gate)
        {
            TearDownLocked(deleteFile: true);
            IsRecording = false;
            StartedAt = null;
        }
        Failed?.Invoke(message);
        SystemActions.ReportError(message);
    }

    // writer pumping

    /// Move buffered capture samples through the resampler into the WAV file and
    /// flush, so the growing file is continuously readable by WavTailReader.
    private void PumpToWriter()
    {
        lock (_gate)
        {
            if (_writer is null || _to16 is null) return;
            try
            {
                var temp = new byte[16384];
                int read;
                // Read everything currently available without blocking.
                while ((read = _to16.Read(temp, 0, temp.Length)) > 0)
                {
                    _writer.Write(temp, 0, read);
                    if (read < temp.Length) break;
                }
                _writer.Flush(); // critical: flush so the tail reader sees new bytes
            }
            catch (Exception ex)
            {
                string message = $"Recording write failed: {ex.Message}";
                TearDownLocked(deleteFile: true);
                IsRecording = false;
                StartedAt = null;
                Failed?.Invoke(message);
                SystemActions.ReportError(message);
            }
        }
    }

    private void FinalizeWriterLocked()
    {
        try { _writer?.Flush(); } catch { }
        try { _writer?.Dispose(); } catch { }
        _writer = null;
        _pumpTimer?.Dispose();
        _pumpTimer = null;
        _buffer = null;
        _resampledMono = null;
        _to16 = null;
    }

    private void DisposeCaptureLocked()
    {
        if (_capture is not null)
        {
            _capture.DataAvailable -= OnDataAvailable;
            _capture.RecordingStopped -= OnRecordingStopped;
            try { _capture.Dispose(); } catch { }
            _capture = null;
        }
        try { _device?.Dispose(); } catch { }
        _device = null;
    }

    /// Stop+dispose everything; optionally delete the partial WAV (failure path).
    private void TearDownLocked(bool deleteFile)
    {
        try { _capture?.StopRecording(); } catch { }
        FinalizeWriterLocked();
        DisposeCaptureLocked();
        if (deleteFile && CurrentPath is not null)
        {
            try { File.Delete(CurrentPath); } catch { }
            CurrentPath = null;
        }
    }

    public void Dispose()
    {
        lock (_gate) TearDownLocked(deleteFile: IsRecording);
    }

    // device selection

    private static MMDevice ResolveCaptureDevice()
    {
        var enumerator = new MMDeviceEnumerator();
        string? preferredId = AudioInputRouter.PreferredCaptureDeviceId();
        if (preferredId is not null)
        {
            try { return enumerator.GetDevice(preferredId); } catch { /* fall through */ }
        }
        return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
    }

    // static helpers (port of RecordingManager statics)

    private static string MakeTemporaryRecordingPath()
        => Path.Combine(PlatformPaths.TempDirectory,
            $"{PlatformPaths.RecordingPrefix}{Guid.NewGuid():N}{PlatformPaths.RecordingExtension}");

    /// Launch-time sweep of recordings orphaned by a crash/force-quit. Safe at
    /// startup (nothing is recording yet) and scoped to our jvoice-*.wav pattern.
    public static void SweepOrphanedRecordings()
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(
                         PlatformPaths.TempDirectory, PlatformPaths.RecordingSweepPattern))
            {
                try { File.Delete(file); } catch { /* best effort */ }
            }
        }
        catch { /* temp dir unreadable — nothing to sweep */ }
    }

    /// True if `path` is large enough to plausibly contain audio. 1024 bytes is
    /// roughly the minimum a non-empty 16 kHz/16-bit WAV occupies (header + ~32 ms).
    public static bool IsUsableRecording(string path, int minBytes = 1024)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists && info.Length >= minBytes;
        }
        catch { return false; }
    }
}
