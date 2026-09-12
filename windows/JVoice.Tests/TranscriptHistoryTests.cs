using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

/// Covers the pure Recent-Transcripts brain (App-layer file I/O lives in
/// TranscriptHistoryStore and is verified by build + dogfood): prepend/cap/trim,
/// per-id remove, and round-trip / corruption tolerance of the JSON.
public class TranscriptHistoryTests
{
    private static readonly IReadOnlyList<TranscriptHistoryEntry> Empty = [];

    [Fact]
    public void Add_PrependsNewestFirst()
    {
        var (l1, _)  = TranscriptHistory.Add(Empty, "first", Guid.NewGuid());
        var (l2, a2) = TranscriptHistory.Add(l1, "second", Guid.NewGuid());

        Assert.Equal(2, l2.Count);
        Assert.Equal("second", l2[0].Text);
        Assert.Equal("first", l2[1].Text);
        Assert.Equal(a2!.Id, l2[0].Id);
    }

    [Fact]
    public void Add_TrimsLeadingAndTrailingWhitespace()
    {
        var (list, added) = TranscriptHistory.Add(Empty, "  hello world \n", Guid.NewGuid());
        Assert.Equal("hello world", added!.Text);
        Assert.Equal("hello world", list[0].Text);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\t\n ")]
    public void Add_BlankIsIgnored(string blank)
    {
        var seed = TranscriptHistory.Add(Empty, "keep", Guid.NewGuid()).List;
        var (list, added) = TranscriptHistory.Add(seed, blank, Guid.NewGuid());

        Assert.Null(added);
        Assert.Same(seed, list);          // unchanged, same reference
        Assert.Single(list);
        Assert.Equal("keep", list[0].Text);
    }

    [Fact]
    public void Add_DoesNotMutateInput()
    {
        var (seed, _) = TranscriptHistory.Add(Empty, "a", Guid.NewGuid());
        int before = seed.Count;
        TranscriptHistory.Add(seed, "b", Guid.NewGuid());
        Assert.Equal(before, seed.Count);
    }

    [Fact]
    public void Add_CapsAtThirty_DroppingOldest()
    {
        IReadOnlyList<TranscriptHistoryEntry> list = Empty;
        for (int i = 0; i < 35; i++)
            list = TranscriptHistory.Add(list, $"t{i}", Guid.NewGuid()).List;

        Assert.Equal(TranscriptHistory.MaxEntries, list.Count); // 30
        Assert.Equal("t34", list[0].Text);   // newest
        Assert.Equal("t5", list[^1].Text);    // oldest surviving — t0..t4 dropped
        Assert.DoesNotContain(list, e => e.Text == "t4");
    }

    [Fact]
    public void Remove_TakesOutOnlyThatEntry()
    {
        var (l1, _) = TranscriptHistory.Add(Empty, "a", Guid.NewGuid());
        var (l2, b) = TranscriptHistory.Add(l1, "b", Guid.NewGuid());
        var (l3, _) = TranscriptHistory.Add(l2, "c", Guid.NewGuid());

        var after = TranscriptHistory.Remove(l3, b!.Id);

        Assert.Equal(2, after.Count);
        Assert.DoesNotContain(after, e => e.Id == b.Id);
        Assert.Contains(after, e => e.Text == "a");
        Assert.Contains(after, e => e.Text == "c");
    }

    [Fact]
    public void Remove_UnknownId_LeavesListUnchanged()
    {
        var (list, _) = TranscriptHistory.Add(Empty, "a", Guid.NewGuid());
        var after = TranscriptHistory.Remove(list, Guid.NewGuid());
        Assert.Equal(list.Count, after.Count);
        Assert.Equal(list[0].Id, after[0].Id);
    }

    [Fact]
    public void Serialize_Deserialize_RoundTripsIdAndTextInOrder()
    {
        IReadOnlyList<TranscriptHistoryEntry> list = Empty;
        list = TranscriptHistory.Add(list, "alpha", Guid.NewGuid()).List;
        list = TranscriptHistory.Add(list, "with \"quotes\", a \\ and a \t tab", Guid.NewGuid()).List;
        list = TranscriptHistory.Add(list, "üñîçödé é", Guid.NewGuid()).List;

        var back = TranscriptHistory.Deserialize(TranscriptHistory.Serialize(list));

        Assert.Equal(list.Count, back.Count);
        for (int i = 0; i < list.Count; i++)
        {
            Assert.Equal(list[i].Id, back[i].Id);
            Assert.Equal(list[i].Text, back[i].Text);
        }
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("    ")]
    [InlineData("{ not json")]
    [InlineData("{\"unexpected\":true}")]   // an object, not the expected array
    [InlineData("[ 42, \"x\" ]")]            // array of the wrong element types
    public void Deserialize_CorruptOrMissing_DecodesToEmpty(string? blob)
    {
        Assert.Empty(TranscriptHistory.Deserialize(blob));
    }

    [Fact]
    public void Deserialize_DropsBlankTextEntries()
    {
        string json = $"[{{\"id\":\"{Guid.NewGuid()}\",\"text\":\"keep\"}}," +
                      $"{{\"id\":\"{Guid.NewGuid()}\",\"text\":\"   \"}}]";
        var back = TranscriptHistory.Deserialize(json);
        Assert.Single(back);
        Assert.Equal("keep", back[0].Text);
    }

    [Fact]
    public void Deserialize_AssignsFreshId_WhenMissing()
    {
        var back = TranscriptHistory.Deserialize("[{\"text\":\"no id here\"}]");
        Assert.Single(back);
        Assert.NotEqual(Guid.Empty, back[0].Id);
        Assert.Equal("no id here", back[0].Text);
    }

    [Fact]
    public void Deserialize_CapsAtThirty()
    {
        var entries = Enumerable.Range(0, 50)
            .Select(i => new TranscriptHistoryEntry(Guid.NewGuid(), $"t{i}"))
            .ToList();
        var json = TranscriptHistory.Serialize(entries);
        Assert.Equal(TranscriptHistory.MaxEntries, TranscriptHistory.Deserialize(json).Count);
    }
}
