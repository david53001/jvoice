import Foundation

/// Catches text the model INVENTS on a press with no speech in it. Ported from the
/// Windows port (`windows/JVoice.Core/Policy/SilenceHallucinationGate.cs`,
/// docs/HANDOFF-WINDOWS.md §7 #38), with two changes the macOS pipeline requires.
///
/// Failure mode: with the vocabulary prompt on, the decode of breath, hiss, hum or
/// keyboard clicks can come back as a confident, plausible phrase that no blocklist
/// can predict. Whisper's own confidence is INVERTED here (Windows measured
/// hallucinations at up to 0.96), so no confidence threshold works. What does work
/// is a WITNESS: decode the same audio again WITHOUT the prompt. Real speech comes
/// back as the same words either way (only the spelling of vocabulary words
/// changes); no-speech comes back as nothing, or as unrelated words.
///
/// Change 1 — the trigger level. `RecordingManager.isSilentRecording` already
/// REJECTS a recording whose peak 0.3 s-window RMS is below
/// `ChunkPlanner.Config.silenceRMSFloor` (0.005) before any decode. That is the
/// same measure as the Windows trigger (0.004), so every clip the Windows gate
/// verifies is rejected here before it is decoded. What reaches the macOS decoder
/// is noisy non-speech ABOVE the floor (2026-09-23 synthetic clips: hum 0.020,
/// hiss 0.022, breath 0.041; synthetic `say` speech 0.10–0.25), so the trigger
/// sits above it. `quietRMSTrigger` is PROVISIONAL until measured on real
/// recordings: it only decides which decodes pay for a witness, never what is kept.
///
/// Change 2 — the verdict. Windows rejects only an EMPTY witness, because there
/// the unprompted decode of silence always collapsed to a blocklisted "Thank you.".
/// On the Mac (large-v3 turbo, 2026-09-23) hiss decoded to a seven-word phrase with
/// the prompt and to "so" without it — a non-empty witness, so the Windows rule
/// would paste the phrase. Here the prompted text is ALSO rejected when the
/// witness shares no word with it. Measured on the same run: across 52 real-speech
/// clips the two decodes always shared at least 7 words; the 3 no-speech clips
/// shared none. Both sides first go through `PhoneticMatcher` with the user's
/// vocabulary, because respelling those words is exactly what the prompt does
/// ("Versil" without it, "Vercel" with it) — without that, a one-word dictation
/// of a custom word would share nothing and be dropped.
///
/// The RMS level is only the TRIGGER; the reject decision is always the model's
/// (the witness). A quiet real sentence is verified and kept — the rule from the
/// Windows port (§7 #21) that no level floor may reject speech holds.
public enum SilenceHallucinationGate {
    /// Peak 0.3 s-window RMS (full scale 1.0) below which a non-empty prompted
    /// decode is verified by a witness. PROVISIONAL — see "Change 1" above.
    public static let quietRMSTrigger: Float = 0.05

    /// The trigger's measure: the loudest 0.3 s window's RMS, over samples scaled
    /// to ±1.0 (`WavTail.floatSamples`). The same number `ChunkPlanner.isSilent`
    /// compares against `silenceRMSFloor`, so the two thresholds share one scale.
    public static func peakWindowRMS(_ samples: [Float]) -> Float {
        let config = ChunkPlanner.Config()
        let window = max(1, Int(config.silenceWindowSeconds * Double(config.sampleRate)))
        var peak: Float = 0
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            var sum: Double = 0
            for i in start..<end { sum += Double(samples[i]) * Double(samples[i]) }
            peak = max(peak, Float((sum / Double(end - start)).squareRoot()))
            start = end
        }
        return peak
    }

    /// True when the prompted transcript needs a witness decode: the audio is
    /// quiet (below `quietRMSTrigger`; NaN counts as quiet — the safe side) and the
    /// decode still produced text. A blank transcript needs no witness — it is
    /// already reported as "No speech detected."
    public static func shouldVerify(peakRMS: Float, prompted: String) -> Bool {
        !prompted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(peakRMS >= quietRMSTrigger)
    }

    /// Decide from the witness — the same audio decoded WITHOUT the prompt and
    /// cleaned like any decode. "" (no speech) when the witness has no words, or
    /// shares none with the prompted transcript; otherwise the PROMPTED transcript,
    /// which is the one that spells the user's vocabulary right.
    public static func resolve(prompted: String, witness: String, vocabulary: [String]) -> String {
        let witnessWords = words(witness, vocabulary: vocabulary)
        guard !witnessWords.isEmpty,
              !witnessWords.isDisjoint(with: words(prompted, vocabulary: vocabulary)) else { return "" }
        return prompted
    }

    /// Lower-cased words (letters, numbers and apostrophes) after the vocabulary's
    /// sound-alikes are respelled by `PhoneticMatcher`.
    static func words(_ text: String, vocabulary: [String]) -> Set<String> {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let respelled = PhoneticMatcher.correct(normalized, vocabulary: vocabulary).lowercased()
        let tokens = respelled.split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}") }
        return Set(tokens.filter { $0.contains { $0.isLetter || $0.isNumber } }.map(String.init))
    }
}
