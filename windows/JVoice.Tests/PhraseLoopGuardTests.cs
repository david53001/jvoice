using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the §7 #42 phrase-loop guard (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported 2026-07-20, reproduced deterministically on the real clip
/// capture-20260720-225708-670.wav): on a 97 s Bible-study dictation the vocabulary-PROMPTED
/// whole-file decode locked into a repetition loop — "You're not a man of Caesar." × 16 —
/// mid-transcript, swallowing the real words ("Now John 19.", "You oppose Caesar.") while
/// claiming full timestamp coverage (segs=32 lastEnd=97.10s audio=97.10s), so the tail
/// guard was blind. RepetitionGuard was blind too, by construction: it only strips a
/// TRAILING vocab/loop-dense run, and this loop sits mid-text with loop-token density
/// 3/6 = 0.5 < 0.7 ("you're not a man of Caesar" is stopword-heavy). The UNPROMPTED decode
/// of the same audio was clean and complete — same prompt-failure class RegurgitationRecovery
/// contains, hence the same remedy: detect → witness re-decode without the prompt →
/// deterministic collapse as the last line.
public class PhraseLoopGuardTests
{
    // The real failure, verbatim shape: prefix + 16 identical sentences + suffix.
    private const string CaesarPhrase = "You're not a man of Caesar.";
    private static readonly string CaesarLoop =
        "And then from there, the Jewish leader said that if you let this man go, " +
        "you're not a friend of Caesar. " +
        string.Concat(Enumerable.Repeat(CaesarPhrase + " ", 16)).TrimEnd() +
        " And when Pilate heard this, he just brought Jesus out and gave him to the Jews.";

    // The second real failure (David-reported 2026-07-24, pasted live from the streaming
    // path of capture-20260724-020028-378.wav): a 21-TOKEN phrase looped 6× inside a chunk
    // decode — beyond the original MaxPhraseTokens=12 window, so HasLoop stayed false and
    // the looped chunk pasted. The whole-file decode of the same clip is clean (793 chars,
    // the phrase spoken ONCE), so detection alone heals it: the chunk throws
    // DegenerateDecode → lossless whole-file fallback. Verbatim from diagnostic.log.
    private static readonly string LonelinessLoop =
        "so on this part it's crazy because in 2026 there was " +
        string.Concat(Enumerable.Repeat(
            "a big male loneliness epidemic and i used to have a girlfriend " +
            "but now i don't so i feel like it's ", 6)) +
        "a big male loneliness epidemic and i feel like it's " +
        "a big male loneliness epidemic and i feel like it's " +
        "a big male loneliness epidemic and i feel like it's " +
        "a big male and that's kinda like, you know, there's a lot of that";

    // ---- constants (calibrated against the real loops; change = recalibrate) ----

    [Fact]
    public void Constants_AreLocked()
    {
        Assert.Equal(4, PhraseLoopGuard.MinRepeats);
        Assert.Equal(32, PhraseLoopGuard.MaxPhraseTokens);
    }

    // ---- Collapse: the real loop ----

    [Fact]
    public void Collapse_RealCaesarLoop_CollapsesToOneOccurrence()
    {
        var result = PhraseLoopGuard.Collapse(CaesarLoop);
        Assert.True(result.FoundLoop);
        // Exactly ONE "man of Caesar" survives; the genuine "friend of Caesar" stays.
        Assert.Equal(1, CountOf(result.Text, "man of Caesar"));
        Assert.Contains("you're not a friend of Caesar.", result.Text);
        Assert.StartsWith("And then from there, the Jewish leader said", result.Text);
        Assert.EndsWith("gave him to the Jews.", result.Text);
    }

    // ---- Collapse: the real 2026-07-24 LONG-period loop (21 tokens — the #42 window missed it) ----

    [Fact]
    public void Collapse_RealLonelinessLoop_Detected()
    {
        var result = PhraseLoopGuard.Collapse(LonelinessLoop);
        Assert.True(result.FoundLoop);
        // Exactly ONE full phrase survives the collapsed run; prefix and suffix stay.
        Assert.Equal(1, CountOf(result.Text, "girlfriend"));
        Assert.StartsWith("so on this part it's crazy", result.Text);
        Assert.EndsWith("there's a lot of that", result.Text);
    }

    [Fact]
    public void HasLoop_TrueOnRealLonelinessLoop() => Assert.True(PhraseLoopGuard.HasLoop(LonelinessLoop));

    [Fact] // The detection window covers long periods: a 21-token phrase ×4 is a loop.
    public void Collapse_LongPeriodPhrase_Collapsed()
    {
        string phrase = "a big male loneliness epidemic and i used to have a girlfriend " +
                        "but now i don't so i feel like it's";
        var result = PhraseLoopGuard.Collapse(string.Join(" ", Enumerable.Repeat(phrase, 4)));
        Assert.True(result.FoundLoop);
        Assert.Equal(phrase, result.Text);
    }

    // ---- Collapse: genuine repetition below the threshold is untouched ----

    [Theory]
    [InlineData("It was said, \"Crucify him, crucify him.\" But Pilate found no basis.")] // 2× — Scripture
    [InlineData("Holy, holy, holy, Lord God Almighty.")]                                  // 3× — Isaiah 6:3
    [InlineData("Verily, verily, I say unto thee.")]                                      // 2×
    [InlineData("He said no, no, no to all three of them.")]                              // 3×
    public void Collapse_GenuineRepetition_Unchanged(string text)
    {
        var result = PhraseLoopGuard.Collapse(text);
        Assert.False(result.FoundLoop);
        Assert.Equal(text, result.Text);
    }

    [Fact] // Clean prose passes through IDENTICALLY — original whitespace preserved.
    public void Collapse_CleanText_ReturnsOriginalString()
    {
        string text = "Now, throughout this chapter,\nit's important to say that Pilate\t" +
                      "he didn't really want to give up Jesus.";
        var result = PhraseLoopGuard.Collapse(text);
        Assert.False(result.FoundLoop);
        Assert.Same(text, result.Text);
    }

    // ---- Collapse: the MinRepeats boundary ----

    [Fact]
    public void Collapse_ThreeRepeats_Kept()
    {
        var result = PhraseLoopGuard.Collapse("go away go away go away");
        Assert.False(result.FoundLoop);
    }

    [Fact]
    public void Collapse_FourRepeats_Collapsed()
    {
        var result = PhraseLoopGuard.Collapse("go away go away go away go away");
        Assert.True(result.FoundLoop);
        Assert.Equal("go away", result.Text);
    }

    // ---- Collapse: matching is case- and punctuation-insensitive, keeps the FIRST verbatim ----

    [Fact]
    public void Collapse_IgnoresCaseAndPunctuation()
    {
        var result = PhraseLoopGuard.Collapse("Stop. stop, STOP stop!");
        Assert.True(result.FoundLoop);
        Assert.Equal("Stop.", result.Text);
    }

    // ---- Collapse: phrase-length behavior ----

    [Fact] // Multi-token phrase loops collapse to the first occurrence.
    public void Collapse_MultiTokenPhrase()
    {
        var result = PhraseLoopGuard.Collapse("to be or not to be or not to be or not to be or not");
        Assert.True(result.FoundLoop);
        Assert.Equal("to be or not", result.Text);
    }

    [Fact] // The smallest repeating period wins ("again then" ×4, not "again then again then" ×2).
    public void Collapse_PicksSmallestPeriod()
    {
        var result = PhraseLoopGuard.Collapse("again then again then again then again then");
        Assert.True(result.FoundLoop);
        Assert.Equal("again then", result.Text);
    }

    [Fact] // Phrases longer than MaxPhraseTokens are never treated as loops.
    public void Collapse_PhraseAboveTokenCap_Kept()
    {
        // 33 tokens — one above the cap.
        string phrase = string.Join(" ", Enumerable.Range(1, 33).Select(i => $"w{i}"));
        string text = string.Join(" ", Enumerable.Repeat(phrase, 4));
        var result = PhraseLoopGuard.Collapse(text);
        Assert.False(result.FoundLoop);
        Assert.Same(text, result.Text);
    }

    // ---- Collapse: run edges ----

    [Fact] // A trailing PARTIAL repeat after a collapsed run is left in place (deliberate:
           // absorbing it could eat a genuine sentence start that shares the first words).
    public void Collapse_TrailingPartialRepeat_Stays()
    {
        var result = PhraseLoopGuard.Collapse("yes sir yes sir yes sir yes sir yes");
        Assert.True(result.FoundLoop);
        Assert.Equal("yes sir yes", result.Text);
    }

    [Fact] // Text that is ENTIRELY a loop collapses to the single phrase, never to empty.
    public void Collapse_AllLoop_KeepsOnePhrase()
    {
        var result = PhraseLoopGuard.Collapse("no no no no no no");
        Assert.True(result.FoundLoop);
        Assert.Equal("no", result.Text);
    }

    [Fact] // Two independent loops in one text both collapse.
    public void Collapse_TwoSeparateLoops()
    {
        var result = PhraseLoopGuard.Collapse(
            "left left left left middle words here right right right right");
        Assert.True(result.FoundLoop);
        Assert.Equal("left middle words here right", result.Text);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("one two three")]
    public void Collapse_ShortOrEmpty_Unchanged(string text)
    {
        var result = PhraseLoopGuard.Collapse(text);
        Assert.False(result.FoundLoop);
        Assert.Same(text, result.Text);
    }

    // ---- HasLoop ----

    [Fact]
    public void HasLoop_TrueOnRealLoop() => Assert.True(PhraseLoopGuard.HasLoop(CaesarLoop));

    [Theory]
    [InlineData("It was said, \"Crucify him, crucify him.\" But Pilate found no basis.")]
    [InlineData("Holy, holy, holy, Lord God Almighty.")]
    [InlineData("")]
    public void HasLoop_FalseOnCleanText(string text) => Assert.False(PhraseLoopGuard.HasLoop(text));

    // ---- Resolve: the witness (unprompted re-decode) is PREFERRED ----
    // Unlike SilenceHallucinationGate.Resolve (witness only vouches; prompted text wins),
    // here the looped primary is known-LOSSY — the loop overwrote real speech — so the
    // witness IS the recovery, exactly like RegurgitationRecovery returns the unprompted
    // decode wholesale. Verified on the real clip: the unprompted decode restored
    // "Now John 19." and "You oppose Caesar.", both absent from the looped primary.

    [Fact]
    public void Resolve_PrefersCleanWitness()
    {
        string witness = "if you let this man go, you're not a friend of Caesar. You oppose Caesar.";
        Assert.Equal(witness, PhraseLoopGuard.Resolve(CaesarLoop, witness));
    }

    [Theory] // No witness (prompt was off / decode empty) → deterministic collapse of the primary.
    [InlineData("")]
    [InlineData("   ")]
    public void Resolve_EmptyWitness_CollapsesPrimary(string witness)
    {
        string resolved = PhraseLoopGuard.Resolve(CaesarLoop, witness);
        Assert.Equal(1, CountOf(resolved, "man of Caesar"));
        Assert.Contains("friend of Caesar", resolved);
    }

    [Fact] // A witness that ALSO loops is collapsed before use — spam can never survive.
    public void Resolve_LoopedWitness_IsCollapsed()
    {
        string witness = "He said wait wait wait wait wait and left.";
        Assert.Equal("He said wait and left.", PhraseLoopGuard.Resolve(CaesarLoop, witness));
    }

    private static int CountOf(string text, string needle)
    {
        int count = 0, at = 0;
        while ((at = text.IndexOf(needle, at, StringComparison.Ordinal)) >= 0) { count++; at += needle.Length; }
        return count;
    }
}
