namespace JVoice.Core.Text;

/// An ALWAYS-ON capitalization pack for God / Jesus / popular Biblical proper nouns:
/// canonical capitalized spellings keyed by the lower-cased forms Whisper tends to emit
/// (it frequently renders "god"/"jesus"/"the lord" in lower case mid-sentence).
///
/// Unlike <see cref="DeveloperTerms"/> — which is an opt-out toggle — this pack has **no
/// setting and no mode gate**: it is folded into the correction dictionary UNCONDITIONALLY
/// at the transcription call site (<c>VoiceCoordinator</c>), so a term like "god" → "God" or
/// "jesus christ" → "Jesus Christ" is fixed in EVERY tone (Casual, Formal, Very Casual, Code).
/// Very Casual lower-cases the whole transcript first, but corrections run AFTER that lowering
/// (see <see cref="TextProcessor.Process"/>), so the capitals survive there too.
///
/// It feeds the same UNBOUNDED post-processing correction channel as the developer pack — NOT
/// the 40-word decoder prompt (<see cref="VocabularyPrompt"/>). Keys are lower-cased "heard"
/// forms; <see cref="TextProcessor.ApplyCorrections"/> matches them case-insensitively with
/// internal spaces treated as <c>\s+</c> between <c>\b</c> word boundaries, and replaces with
/// the literal canonical value. Corrections apply longest-key-first, so multi-word phrases
/// ("son of god" → "Son of God") land before the bare "god" → "God" rule re-confirms the tail.
///
/// ── Curation policy ──────────────────────────────────────────────────────────────────────
/// David asked for "every single term related to God and Jesus and Biblical terms that is
/// supposed to be capitalized" to be capitalized automatically. So this pack is INTENTIONALLY
/// more assertive than the conservative developer pack: it DOES capitalize "god" and "lord"
/// even though each has a lower-case common-noun sense ("a Greek god", "the House of Lords",
/// "lord it over someone"). In dictation from someone who wants this feature those senses are
/// far rarer than references to the monotheistic God / the Lord, and the word-boundary matcher
/// already protects compounds ("godzilla", "goddess", "landlord", "warlord", "lordship" never
/// match). The trade-off is accepted deliberately; a user who dictates the common-noun sense a
/// lot can add a custom correction rule, which outranks this pack.
///
/// Terms are nonetheless EXCLUDED where auto-capitalization would corrupt ordinary text more
/// than it helps — locked by <c>Map_ExcludesDangerousWords</c>:
///   • Reverential pronouns (he/him/his/thee/thou/thy/thine) — capitalizing these is a
///     stylistic choice, not "supposed to be", and would wreck almost every sentence.
///   • Book names that are also everyday English or common first names — "numbers", "acts",
///     "kings", "judges", "job", "mark", "john", "luke", "matthew", "james", "revelation",
///     "genesis", "exodus". "Job"/"a job" alone makes the whole book-name category unsafe.
///   • Bare abstractions & role words that are ordinary English or personal names — "father",
///     "son", "spirit", "grace", "faith", "hope", "cross", "word", "king", "creator"
///     ("content creator"!), "devil". These stay reachable only inside explicit phrases
///     ("Holy Spirit", "Son of God", "Word of God") or via the user's own rules.
///   • Optional / stylistically-lower-cased words — "heaven", "hell", "amen", "hallelujah",
///     "holy" (bare), "divine", "blessed", "sacred", bare "almighty" (an adjective).
///
/// Like the rest of the brain this is intended to be ported 1:1 to the macOS app later
/// (cf. <see cref="DeveloperTerms"/>).
public static class BiblicalTerms
{
    /// Heard form (lower-cased) → canonical capitalized replacement.
    public static readonly IReadOnlyDictionary<string, string> Map = new Dictionary<string, string>
    {
        // ---- Deity: names & titles ----
        ["god"] = "God",
        ["lord"] = "Lord",
        ["jesus"] = "Jesus",
        ["christ"] = "Christ",
        ["jesus christ"] = "Jesus Christ",
        ["messiah"] = "Messiah",
        ["yahweh"] = "Yahweh",
        ["jehovah"] = "Jehovah",
        ["emmanuel"] = "Emmanuel",
        ["immanuel"] = "Immanuel",
        ["savior"] = "Savior",
        ["saviour"] = "Saviour",
        ["redeemer"] = "Redeemer",

        // ---- Trinity / the Spirit ----
        ["holy spirit"] = "Holy Spirit",
        ["holy ghost"] = "Holy Ghost",
        ["holy trinity"] = "Holy Trinity",
        ["trinity"] = "Trinity",

        // ---- Titles / phrases naming God or Christ ----
        ["son of god"] = "Son of God",
        ["lamb of god"] = "Lamb of God",
        ["word of god"] = "Word of God",
        ["kingdom of god"] = "Kingdom of God",
        ["king of kings"] = "King of Kings",
        ["prince of peace"] = "Prince of Peace",
        ["almighty god"] = "Almighty God",

        // ---- Scripture ----
        ["bible"] = "Bible",
        ["holy bible"] = "Holy Bible",
        ["scripture"] = "Scripture",
        ["scriptures"] = "Scriptures",
        ["gospel"] = "Gospel",
        ["gospels"] = "Gospels",
        ["old testament"] = "Old Testament",
        ["new testament"] = "New Testament",
        ["ten commandments"] = "Ten Commandments",
        ["garden of eden"] = "Garden of Eden",

        // ---- The adversary ----
        ["satan"] = "Satan",
        ["lucifer"] = "Lucifer",

        // ---- Christian identity ----
        ["christian"] = "Christian",
        ["christians"] = "Christians",
        ["christianity"] = "Christianity",
    };

    /// Returns <paramref name="baseDict"/> with the pack laid in UNDERNEATH it: every pack
    /// entry is added, but a key already present in <paramref name="baseDict"/> keeps the base
    /// value (the user's own custom words / correction rules and the developer pack all win
    /// over this generic pack). Mirrors <see cref="DeveloperTerms.Augment"/>; the builtin
    /// <see cref="TextProcessor.CorrectionDictionary"/> still overrides everything inside
    /// <see cref="TextProcessor.ApplyCorrections"/>.
    public static IReadOnlyDictionary<string, string> Augment(IReadOnlyDictionary<string, string> baseDict)
    {
        var dict = new Dictionary<string, string>(Map);          // pack is the floor
        foreach (var kv in baseDict) dict[kv.Key] = kv.Value;    // callers' own entries win
        return dict;
    }
}
