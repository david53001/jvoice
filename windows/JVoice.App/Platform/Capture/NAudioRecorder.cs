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
    private WaveFormat? _captureFormat;

    // Live input level (0..1 peak) for the HUD visualizer. Written from the capture
    // thread in OnDataAvailable, read from the UI render loop — `volatile` so the read
    // always sees the latest write without a lock (a single float is torn-read-safe).
    private volatile float _level;

    // TEST-ONLY seam (env-gated, zero cost when unset), following GlobalHotkey's
    // JVOICE_HOTKEY_TEST_STALL_MS precedent: JVOICE_TEST_SLOW_CAPTURE_MS=<n> widens the
    // capture thread's _gate hold in OnDataAvailable so the otherwise ~sub-1% per-stop
    // "first-recording freeze" race (Stop() joining the capture thread while it is
    // blocked on _gate) reproduces deterministically for on-device regression tests.
    private static readonly int _testSlowCaptureMs =
        int.TryParse(Environment.GetEnvironmentVariable("JVOICE_TEST_SLOW_CAPTURE_MS"), out var v) && v > 0 ? v : 0;

    public string? CurrentPath { get; private set; }
    public bool IsRecording { get; private set; }
    public DateTime? StartedAt { get; private set; }

    /// Latest microphone peak level (0..1). 0 when not recording.
    public float CurrentLevel => _level;

    public event Action<string>? Failed;

    public bool TryStart(out string? error)
    {
        (WasapiCapture? Capture, MMDevice? Device) failed = default;
        try
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
                _captureFormat = captureFormat;
                _level = 0f;
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
                failed = TearDownLocked(deleteFile: true);
                return false;
            }
        }
        }
        finally
        {
            // Runs after the lock block has exited → the gate is released here.
            DisposeDetached(failed);
        }
    }

    public string? Stop()
    {
        (WasapiCapture? Capture, MMDevice? Device) detached = default;
        try
        {
        lock (_gate)
        {
            if (!IsRecording) return CurrentPath;
            string? path = CurrentPath;
            try
            {
                _capture?.StopRecording();   // async request; the capture thread winds down on its own
            }
            catch { /* ignore */ }
            PumpToWriter();                  // final drain of anything buffered
            FinalizeWriterLocked();
            IsRecording = false;
            StartedAt = null;
            detached = DetachLocked();
            CurrentPath = null;
            return path; // caller checks usability via IsUsableRecording
        }
        }
        finally
        {
            // Dispose OUTSIDE the gate (the finally runs after the lock block exits).
            DisposeDetached(detached);
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
            // Update the live HUD meter from the raw capture buffer (cheap peak scan,
            // outside the lock — it only writes the volatile _level).
            UpdateLevel(e.Buffer, e.BytesRecorded);
            lock (_gate)
            {
                if (_testSlowCaptureMs > 0) Thread.Sleep(_testSlowCaptureMs); // test seam, see field
                // Ignore a stale capture that was already detached (teardown disposes it
                // outside this gate, so a last in-flight packet can still arrive here) —
                // its samples must not leak into a NEW recording's buffer.
                if (!ReferenceEquals(sender, _capture)) return;
                _buffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
            }
        }
        catch { /* buffered overflow is discarded; ignore */ }
    }

    /// Compute the peak amplitude (0..1) of a raw capture buffer and publish it for the
    /// visualizer. Handles the two formats WASAPI shared-mode capture actually delivers:
    /// 32-bit IEEE float (the usual mix format) and 16-bit PCM. Unknown formats leave the
    /// level at 0 (the visualizer just idles), never throwing on the capture thread.
    private void UpdateLevel(byte[] buffer, int bytes)
    {
        var fmt = _captureFormat;
        if (fmt is null || bytes <= 0) return;

        float peak = 0f;
        if (fmt.Encoding == WaveFormatEncoding.IeeeFloat || fmt.BitsPerSample == 32)
        {
            int n = bytes / 4;
            for (int i = 0; i < n; i++)
            {
                float s = BitConverter.ToSingle(buffer, i * 4);
                float a = Math.Abs(s);
                if (a > peak) peak = a;
            }
        }
        else if (fmt.BitsPerSample == 16)
        {
            int n = bytes / 2;
            for (int i = 0; i < n; i++)
            {
                short s = BitConverter.ToInt16(buffer, i * 2);
                float a = Math.Abs(s) / 32768f;
                if (a > peak) peak = a;
            }
        }
        else return; // unknown sample format — leave the meter idle

        _level = peak > 1f ? 1f : peak;
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is null) return; // clean stop handled by Stop()
        // Mid-recording failure: tear down the partial file and notify (Swift parity:
        // a broken recording must not be transcribed and must not orphan a WAV).
        string message = $"Recording stopped unexpectedly: {e.Exception.Message}";
        (WasapiCapture? Capture, MMDevice? Device) detached;
        lock (_gate)
        {
            if (!ReferenceEquals(sender, _capture)) return; // a stale, already-detached capture
            detached = TearDownLocked(deleteFile: true);
            IsRecording = false;
            StartedAt = null;
        }
        DisposeDetached(detached);
        Failed?.Invoke(message);
        SystemActions.ReportError(message);
    }

    // writer pumping

    /// Move buffered capture samples through the resampler into the WAV file and
    /// flush, so the growing file is continuously readable by WavTailReader.
    private void PumpToWriter()
    {
        (WasapiCapture? Capture, MMDevice? Device) failed = default;
        try
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
                failed = TearDownLocked(deleteFile: true);
                IsRecording = false;
                StartedAt = null;
                Failed?.Invoke(message);
                SystemActions.ReportError(message);
            }
        }
        }
        finally
        {
            // Disposed outside the gate. When this pump ran reentrantly from Stop() the
            // calling thread STILL holds the gate here — DisposeDetached defers to the
            // thread pool in that case (see Monitor.IsEntered guard).
            DisposeDetached(failed);
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
        _captureFormat = null;
        _level = 0f; // meter goes quiet the instant recording ends
    }

    /// Detach the capture + device from the recorder's fields (MUST hold _gate). The
    /// caller disposes the returned pair OUTSIDE the gate via DisposeDetached.
    private (WasapiCapture? Capture, MMDevice? Device) DetachLocked()
    {
        var c = _capture; _capture = null;
        var d = _device; _device = null;
        return (c, d);
    }

    /// Dispose a detached capture/device pair. MUST run WITHOUT _gate held: NAudio's
    /// WasapiCapture.Dispose JOINS its capture thread, and that thread may right now be
    /// blocked on _gate inside OnDataAvailable — disposing under the gate is the
    /// lock-order inversion that permanently froze the app on a stop press (the
    /// "first recording freeze"; deterministic repro via JVOICE_TEST_SLOW_CAPTURE_MS).
    /// If the current thread still holds the gate reentrantly (Stop → PumpToWriter
    /// failure), defer to the thread pool instead of joining here.
    private void DisposeDetached((WasapiCapture? Capture, MMDevice? Device) detached)
    {
        if (detached.Capture is null && detached.Device is null) return;
        if (Monitor.IsEntered(_gate))
        {
            var d = detached;
            Task.Run(() => DisposeDetached(d));
            return;
        }
        if (detached.Capture is not null)
        {
            detached.Capture.DataAvailable -= OnDataAvailable;
            detached.Capture.RecordingStopped -= OnRecordingStopped;
            try { detached.Capture.Dispose(); } catch { }
        }
        try { detached.Device?.Dispose(); } catch { }
    }

    /// Stop + finalize everything under the gate and DETACH the capture/device; the
    /// caller must dispose the returned pair outside the gate (DisposeDetached).
    /// Optionally deletes the partial WAV (failure path).
    private (WasapiCapture? Capture, MMDevice? Device) TearDownLocked(bool deleteFile)
    {
        try { _capture?.StopRecording(); } catch { }
        FinalizeWriterLocked();
        var detached = DetachLocked();
        if (deleteFile && CurrentPath is not null)
        {
            try { File.Delete(CurrentPath); } catch { }
            CurrentPath = null;
        }
        return detached;
    }

    public void Dispose()
    {
        (WasapiCapture? Capture, MMDevice? Device) detached;
        lock (_gate) detached = TearDownLocked(deleteFile: IsRecording);
        DisposeDetached(detached);
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
