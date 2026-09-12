using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the §7 #38 silence-hallucination gate policy. Thresholds and cases come from the
/// 2026-07-02 on-device calibration (nospeech-probe --analyze over 17 real capture clips,
/// David's mic + large-v3-turbo + his live vocab prompt):
///   - every SILENT press measured rawRMS ≤ 0.0003, yet the PROMPTED decode confidently
///     invented text ("you", "you're welcome.", "app", "you can't believe it, but you
///     can't believe it.") while the UNPROMPTED decode always collapsed to stock
///     "Thank you." → blocklist → empty;
///   - David's QUIET real speech measured rawRMS 0.0005–0.0101 and the unprompted decode
///     kept the real sentence on all 7/7 clips.
/// So: near-silence is only a TRIGGER for a witness decode without the prompt — the MODEL
/// (witness reducing to empty) makes the reject decision, never the RMS level itself
/// (the retired-RMS-gate rule from §7 #21 stands).
public class SilenceHallucinationGateTests
{
    // ---- ShouldVerify: trigger on near-silent clips that still produced text ----

    [Theory]
    // Measured silent presses (all hallucinated under the prompt).
    [InlineData(0.0000f, "you're welcome.")]
    [InlineData(0.0001f, "you")]
    [InlineData(0.0003f, "and then we'll see you next time.")]
    [InlineData(0.0000f, "you can't believe it, but you can't believe it.")]
    // Measured QUIET real speech below the trigger — verification runs and passes via Resolve.
    [InlineData(0.0005f, "Currently my AD is not working")]
    [InlineData(0.0016f, "Hello, my name is David and I have $330.00.")]
    [InlineData(0.0028f, "I want to run three terminals in VS Code")]
    public void ShouldVerify_NearSilentWithText_True(float rawRms, string prompted)
        => Assert.True(SilenceHallucinationGate.ShouldVerify(rawRms, prompted));

    [Theory]
    // Measured louder real speech — at/above the trigger, no verification (zero extra cost).
    [InlineData(0.0052f, "Hello, my name is David and I'm running a claude code session currently.")]
    [InlineData(0.0086f, "yo what's up")]
    [InlineData(0.0101f, "Now that still doesn't work in terminal")]
    [InlineData(0.0040f, "boundary: exactly at the trigger is NOT quiet")]
    public void ShouldVerify_LoudEnough_False(float rawRms, string prompted)
        => Assert.False(SilenceHallucinationGate.ShouldVerify(rawRms, prompted));

    [Theory]
    // Nothing to verify when the guarded transcript is already empty/blank
    // (RegurgitationRecovery + NonSpeechAnnotation handled it).
    [InlineData(0.0000f, "")]
    [InlineData(0.0000f, "   ")]
    public void ShouldVerify_EmptyTranscript_False(float rawRms, string prompted)
        => Assert.False(SilenceHallucinationGate.ShouldVerify(rawRms, prompted));

    [Fact] // A pathological NaN level counts as quiet (verify — the safe side; never rejects by itself).
    public void ShouldVerify_NaNRms_True()
        => Assert.True(SilenceHallucinationGate.ShouldVerify(float.NaN, "you're welcome."));

    // ---- Resolve: the WITNESS (unprompted, fully reduced) decides ----

    [Theory]
    // Witness collapsed to nothing → the prompted text was a silence hallucination → no-speech.
    [InlineData("you're welcome.", "")]
    [InlineData("you", "")]
    [InlineData("app", "   ")]
    public void Resolve_EmptyWitness_RejectsAsNoSpeech(string prompted, string witness)
        => Assert.Equal("", SilenceHallucinationGate.Resolve(prompted, witness));

    [Theory]
    // Witness kept real words → keep the PROMPTED transcript (the vocab-accurate one),
    // even when the two decodes word differently.
    [InlineData("Yo, what's up?", "Yo, what's up?")]
    [InlineData("Currently my AD is not working", "currently my ad is not working")]
    [InlineData("I am running 2 o'clock on sessions", "I am running two o'clock on sessions")]
    public void Resolve_RealWitness_KeepsPromptedTranscript(string prompted, string witness)
        => Assert.Equal(prompted, SilenceHallucinationGate.Resolve(prompted, witness));
}
