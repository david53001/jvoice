using System.IO;
using JVoice.Core.Diagnostics;
using Xunit;

namespace JVoice.Tests;

/// Review round 3 #1: the diagnostic log holds no dictated words by default, stays small, and "Clear all" clears it.
/// Every test works in its own temp folder — never the real %APPDATA%\JVoice profile.
public class RollingLogTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "jvoice-rollinglog-" + Guid.NewGuid().ToString("N"));

    public RollingLogTests() => Directory.CreateDirectory(_dir);

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Fact]
    public void Dictated_text_is_only_its_length_unless_opted_in()
    {
        Assert.Equal("<11 chars>", RollingLog.Redact("my password", keepText: false));
        Assert.Equal("<0 chars>", RollingLog.Redact(null, keepText: false));
        Assert.Equal("\"my password\"", RollingLog.Redact("my password", keepText: true));
    }

    [Fact]
    public void Lines_reach_the_file_in_order_without_the_caller_writing()
    {
        var log = new RollingLog(_dir);
        for (int i = 0; i < 200; i++) log.Enqueue($"line {i}\n");
        log.Flush();
        var lines = File.ReadAllLines(log.Current);
        Assert.Equal(200, lines.Length);
        Assert.Equal("line 0", lines[0]);
        Assert.Equal("line 199", lines[^1]);
    }

    [Fact]
    public void A_full_log_rolls_to_one_old_copy()
    {
        var log = new RollingLog(_dir, cap: 100);
        log.Enqueue(new string('a', 120) + "\n");
        log.Flush();
        log.Enqueue("second\n"); // the file is over the cap: it rolls first
        log.Flush();
        Assert.Equal("second", File.ReadAllText(log.Current).Trim());
        Assert.StartsWith("aaa", File.ReadAllText(log.Previous));

        log.Enqueue(new string('b', 120) + "\n");
        log.Flush();
        log.Enqueue("third\n");
        log.Flush();
        Assert.StartsWith("second", File.ReadAllText(log.Previous)); // one generation: the older copy is replaced
        Assert.False(File.Exists(log.BeforeCap));
    }

    [Fact]
    public void An_uncapped_log_from_before_the_cap_is_parked_once_not_overwritten()
    {
        var log = new RollingLog(_dir, cap: 100);
        File.WriteAllText(log.Current, new string('x', 500)); // the old uncapped log
        log.Enqueue("new\n");
        log.Flush();
        Assert.Equal(500, new FileInfo(log.BeforeCap).Length);

        log.Enqueue(new string('c', 120) + "\n");
        log.Flush();
        log.Enqueue("later\n");
        log.Flush();
        Assert.Equal(500, new FileInfo(log.BeforeCap).Length); // normal rolls go to .old, never over it
        Assert.True(File.Exists(log.Previous));
    }

    [Fact]
    public void Clear_deletes_the_log_and_its_copies_and_drops_queued_lines()
    {
        var log = new RollingLog(_dir, cap: 100);
        File.WriteAllText(log.BeforeCap, "old words");
        File.WriteAllText(log.Previous, "older words");
        log.Enqueue("words\n");
        log.Flush();
        log.Enqueue("queued words\n");
        log.Clear();
        log.Flush();
        Assert.False(File.Exists(log.Current));
        Assert.False(File.Exists(log.Previous));
        Assert.False(File.Exists(log.BeforeCap));
    }

    [Fact]
    public async Task Queued_lines_are_written_by_the_background_drain()
    {
        var log = new RollingLog(_dir);
        log.Enqueue("from the pool\n");
        for (int i = 0; i < 100 && !File.Exists(log.Current); i++) await Task.Delay(20);
        Assert.Equal("from the pool", File.ReadAllText(log.Current).Trim());
    }
}
