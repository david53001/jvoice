using System.Text.RegularExpressions;

namespace JVoice.Core.Text;

/// Detects whisper.cpp's NON-SPEECH ANNOTATION output — the reliable, level-independent
/// no-speech signal that replaces the old absolute-RMS pre-gate (HighPassSilence).
///
/// On audio with no speech, whisper.cpp never emits a plausible sentence — it emits an
/// annotation token: "[BLANK_AUDIO]", "[Music]", "[Sigh]", "[Applause]", "(birds
/// chirping)", "(wind blowing)", etc. (verified on-device, windows/tools/nospeech-probe,
/// 2026-06-23, for digital silence / 60 Hz mains hum / low-freq rumble / white noise,
/// with and without a vocabulary prompt). Genuine speech — even captured ~20× too quiet —
/// decodes to its words. So "did the user actually speak?" is answered by whisper's
/// OUTPUT, not by the signal level: a transcript that is ENTIRELY annotation groups is
/// no-speech at ANY capture level.
///
/// This is the discriminator David's low-level mic needs: his quiet speech and his room
/// hum sit at the SAME raw RMS (~0.004), so no level/spectral floor can separate them —
/// but whisper transcribes the speech and annotates the hum.
///
/// `Core.Text.TextProcessor.StripDecoderArtifacts` (1:1 with macOS) only removes ALL-CAPS
/// bracket tokens (`[BLANK_AUDIO]`), so the mixed-case (`[Music]`, `[Sigh]`) and
/// parenthetical (`(birds chirping)`) forms survive it — those are what this catches.
/// Windows-only (whisper.cpp behavior); the macOS brain has no equivalent — same status
/// as <see cref="JVoice.Core.Audio.HighPassSilence"/>.
public static class NonSpeechAnnotation
{
    // A single bracketed [...], parenthetical (...), or asterisk-delimited *...* group
    // (non-greedy, no nesting — whisper annotations never nest). The *...* form is
    // whisper's third annotation delimiter ("*coughs*", "*music*"); it slipped through
    // the original [] / () pair and pasted verbatim on 2026-07-23 — a 3.7 s near-silent
    // press decoded to just "*referred*" (§7 #44). Requires a closing '*', so a lone
    // dictated asterisk ("use the * wildcard") never forms a group; a real sentence
    // containing a pair keeps its text outside the group and survives, same as ().
    private static readonly Regex AnnotationGroup =
        new(@"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*", RegexOptions.Compiled);

    /// True when `text` is non-empty but, once every annotation group is removed, contains
    /// no letters or digits — i.e. the whole transcript is whisper's no-speech annotation
    /// (and/or lone punctuation). A real sentence that merely *contains* a parenthetical
    /// keeps text outside the group, so it returns false and is never reduced.
    ///
    /// Returns false for the empty string (emptiness is handled by the caller's existing
    /// empty-transcript path; "" is not itself an annotation).
    public static bool IsAnnotationOnly(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        string stripped = AnnotationGroup.Replace(text, " ");
        foreach (char c in stripped)
            if (char.IsLetterOrDigit(c)) return false;
        return true;
    }

    /// `""` when `text` is whisper no-speech annotation (see <see cref="IsAnnotationOnly"/>);
    /// otherwise `text` unchanged. The decode paths call this so an annotation-only decode
    /// becomes an empty transcript ("No speech detected.").
    public static string Reduce(string text) => IsAnnotationOnly(text) ? "" : text;
}
