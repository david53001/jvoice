using System.Collections.Concurrent;
using System.IO;
using System.Text;

namespace JVoice.Core.Diagnostics;

/// The diagnostic log's file handling (review round 3 #1). Callers only queue lines; a pool thread appends them, so a
/// log call never does file I/O on the UI thread. The file is capped: past <see cref="Cap"/> bytes it moves to
/// <c>NAME.old.log</c> (one generation). A file already over twice the cap predates the cap (the uncapped log JVoice
/// kept until October 2026) and is parked once as <c>NAME.before-cap.log</c> instead, so a normal roll can't overwrite
/// it. <see cref="Clear"/> deletes all three (Recent Transcripts "Clear all" and Restore Defaults).
public sealed class RollingLog
{
    public const long DefaultCap = 1_000_000;

    private readonly object _gate = new();
    private readonly ConcurrentQueue<string> _pending = new();
    private int _draining;

    public RollingLog(string directory, long cap = DefaultCap, string name = "diagnostic")
    {
        Current = Path.Combine(directory, name + ".log");
        Previous = Path.Combine(directory, name + ".old.log");
        BeforeCap = Path.Combine(directory, name + ".before-cap.log");
        Cap = cap;
    }

    public string Current { get; }
    public string Previous { get; }
    public string BeforeCap { get; }
    public long Cap { get; }

    /// Queues one line (with its newline) for a pool thread to append.
    public void Enqueue(string line)
    {
        _pending.Enqueue(line);
        if (Interlocked.Exchange(ref _draining, 1) == 0)
            ThreadPool.UnsafeQueueUserWorkItem(_ => Drain(), null);
    }

    private void Drain()
    {
        do
        {
            Flush();
            Volatile.Write(ref _draining, 0);
            // A line queued between the last Flush and the reset found _draining == 1 and scheduled nothing.
        } while (!_pending.IsEmpty && Interlocked.Exchange(ref _draining, 1) == 0);
    }

    /// Writes everything queued so far, on the calling thread (the drain, and once at process exit).
    public void Flush()
    {
        lock (_gate)
        {
            var text = new StringBuilder();
            while (_pending.TryDequeue(out var line)) text.Append(line);
            if (text.Length == 0) return;
            try
            {
                RollIfFull();
                File.AppendAllText(Current, text.ToString(), Encoding.UTF8);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* diagnostics never break the app */ }
        }
    }

    private void RollIfFull()
    {
        var info = new FileInfo(Current);
        if (!info.Exists || info.Length < Cap) return;
        string target = info.Length > 2 * Cap && !File.Exists(BeforeCap) ? BeforeCap : Previous;
        File.Move(Current, target, overwrite: true);
    }

    /// Drops anything queued and deletes the log and its rolled copies.
    public void Clear()
    {
        lock (_gate)
        {
            _pending.Clear();
            foreach (var path in new[] { Current, Previous, BeforeCap })
            {
                try { File.Delete(path); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
        }
    }

    /// How dictated text appears in the log: only its length, unless raw logging was opted into (the maths
    /// calibration sweeps need the words; nobody else's log should hold them).
    public static string Redact(string? text, bool keepText) =>
        keepText ? "\"" + text + "\"" : $"<{text?.Length ?? 0} chars>";
}
