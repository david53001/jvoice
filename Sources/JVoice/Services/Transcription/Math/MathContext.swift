import Foundation

/// Dictation-level context for Greek-letter NAMES ("find the value of lambda" → "… of λ").
///
/// A Greek letter is weak: inside a run something else activated it renders ("lambda equals
/// 5" → "λ = 5"), on its own it stays a word ("Lambda, the pie is really tasty."). This file
/// holds the one exception, **context promotion**: a curated name may still become its letter
/// outside an activated run when the WHOLE dictation shows it is mathematics —
///
///   (a) EVIDENCE: some segment converted with a real letter operand in it ("x = 5", not
///       "2 + 1"), or the name sits in an ANCHOR slot ("value of λ", "solve for θ");
///   (b) no VETO applies to it (casing, the word before/after, anti-cue words anywhere);
///   (c) its own segment did not already convert.
///
/// It never activates anything, and with no candidate name in the dictation `MathSpeech.convert`
/// takes exactly the old path. `MathSpeech.Emitter.promote` applies it; this enum is only the
/// word lists and the pure checks (Strings and Bools — the lexer's types stay private), so
/// tuning means editing these sets. Design: docs/math-context-design.md. Any change here must be
/// swept against `.build/math-context/everyday.txt` (0 new changed lines) and the S/M rows of
/// `context.tsv` — see the area brief, invariant 4.
enum MathContext {
    // ─────────────────────────────── candidates ───────────────────────────────

    /// Names that are run-only (never promoted) on purpose: delta (Delta Airlines, "what's the
    /// delta"), bare sigma (∑, "sigma male"), eta (ETA), iota ("not one iota"), kappa (the
    /// emote), nu ("new"), xi (Xi Jinping), omicron (the variant), psi (tyre pressure).
    private static let lowerNames: [String] = [
        "alpha", "beta", "gamma", "epsilon", "varepsilon", "zeta", "theta", "vartheta", "lambda",
        "lamda", "mu", "rho", "varrho", "tau", "upsilon", "phi", "varphi", "chi", "omega", "pi",
    ]

    /// Every Greek name the vocabulary knows — "capital X" / "uppercase X" are said
    /// deliberately, so all of them are promotable in those forms.
    private static let allNames: [String] = [
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta",
        "vartheta", "iota", "kappa", "lambda", "lamda", "mu", "nu", "xi", "omicron", "pi", "rho",
        "varrho", "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
    ]

    private static let deliberateWords = ["capital", "uppercase"]

    /// The spoken phrases (lower-case, single-spaced) context may promote. "big X" is ordinary
    /// English ("that's a big delta"), so it only exists for the lower-case names and goes
    /// through every veto like them.
    static let promotable: Set<String> = {
        var s = Set(lowerNames)
        s.formUnion(["lowercase sigma", "small sigma", "lower case sigma"])
        for name in lowerNames { s.insert("big " + name) }
        for word in deliberateWords {
            for name in allNames { s.insert(word + " " + name) }
        }
        return s
    }()

    /// "capital lambda" / "uppercase omega": checked against casing (V1) only.
    static func isDeliberateCapital(_ phrase: String) -> Bool {
        deliberateWords.contains { phrase.hasPrefix($0 + " ") }
    }

    /// The letter a phrase names, for the per-letter lists: "lamda" → "lambda", "big pi" → "pi",
    /// "small sigma" → "sigma".
    static func letter(of phrase: String) -> String {
        let name = phrase.split(separator: " ").last.map(String.init) ?? phrase
        return name == "lamda" ? "lambda" : name
    }

    // ─────────────────────────────── vetoes ───────────────────────────────

    /// V2 — the word right before makes it a name or a thing: "a lambda", "my Pi", "AWS Lambda".
    static let vetoBefore: Set<String> = [
        "a", "an", "my", "your", "his", "her", "our", "their", "hey", "aws", "amazon", "raspberry",
        "happy", "tai",
    ]

    /// V3 — the word right after makes it a compound noun: "lambda function", "gamma rays".
    static let vetoAfter: Set<String> = [
        "function", "functions", "expression", "expressions", "calculus", "layer", "layers",
        "handler", "handlers", "labs", "male", "males", "female", "grindset", "watch", "watches",
        "seamaster", "release", "releases", "version", "versions", "build", "builds", "tester",
        "testers", "test", "tests", "testing", "ray", "rays", "radiation", "burst", "decay",
        "particle", "particles", "blocker", "blockers", "carotene", "centauri", "wave", "waves",
        "channel", "day", "network", "coin", "fraternity", "sorority",
    ]

    /// V5 — a word ANYWHERE in the dictation that says these names are not maths. "*" = all.
    private static let antiCues: [String: [String]] = {
        var d: [String: [String]] = [:]
        func add(_ letters: [String], _ words: [String]) {
            for w in words { d[w, default: []].append(contentsOf: letters) }
        }
        add(["*"], ["fraternity", "fraternities", "sorority", "sororities", "frat"])
        add(["lambda"], ["aws", "amazon", "serverless", "deploy", "deployed", "deploying", "deployment",
                         "python", "javascript", "typescript", "java", "api", "endpoint", "lambdas"])
        add(["pi"], ["raspberry", "arduino"])
        add(["alpha", "beta"], ["release", "released", "tester", "testers", "testing", "version",
                                "versions", "male", "males", "centauri", "alphago", "alphafold"])
        add(["gamma"], ["radiation", "rays", "hulk"])
        add(["omega"], ["watch", "seamaster", "fatty", "oil"])
        add(["chi"], ["tai", "qi"])
        return d
    }()

    /// The letter names V5 blocks for this dictation ("*" = every name). `cores` are the
    /// punctuation-stripped words of the whole dictation.
    static func dictationVetoes(cores: [String]) -> Set<String> {
        var blocked: Set<String> = []
        for core in cores {
            if let letters = antiCues[core.lowercased()] { blocked.formUnion(letters) }
        }
        return blocked
    }

    /// V1 — the word is written like a name: all capitals ("PI", "ETA"), or capitalised where a
    /// sentence does not start ("AWS Lambda", "my cat Pi").
    static func nameLike(core: String, sentenceInitial: Bool) -> Bool {
        guard let first = core.first else { return false }
        if core.count >= 2 && core.allSatisfy({ $0.isUppercase }) { return true }
        return first.isUppercase && !sentenceInitial
    }

    /// V1–V4 minus the number rule: this occurrence NAMES SOMETHING (a person, a product, a
    /// compound noun) — "AWS Lambda", "a lambda", "lambda function", "Pi Day", "Lambda Chi".
    /// One word means one thing per dictation, so the emitter then blocks every occurrence of
    /// that letter ("we had pi on pi day"). `before`/`after` are the neighbouring words inside
    /// the candidate's stretch (nil when punctuation or the dictation's edge is there).
    static func namesSomething(phrase: String, firstCore: String, sentenceInitial: Bool,
                               before: String?, after: String?, besideGreek: Bool) -> Bool {
        if nameLike(core: firstCore, sentenceInitial: sentenceInitial) { return true }   // V1
        if isDeliberateCapital(phrase) { return false }
        if let before, vetoBefore.contains(before.lowercased()) { return true }          // V2
        if let after {
            if vetoAfter.contains(after.lowercased()) { return true }                     // V3
            // V4: "Lambda Labs", "Pi Day" — but "I'm"/"I'll" are no names.
            if let first = after.first, first.isUppercase, after.count > 1,
               !(after.hasPrefix("I'") || after.hasPrefix("I’")) { return true }
        }
        return besideGreek                                                                 // V4
    }

    /// The remaining vetoes for an occurrence that names nothing. `quoted`: a quotation mark
    /// touches it (`say "lowercase sigma"`) — a word MENTIONED, not used (added 2026-10-04
    /// after the prose sweep). `afterIsNumber`: "omega 3", "lambda 1" (V4). `blocked`: the
    /// letters V5 and the per-dictation name rule block ("*" = all).
    static func vetoed(phrase: String, quoted: Bool, afterIsNumber: Bool, blocked: Set<String>) -> Bool {
        if quoted { return true }
        if isDeliberateCapital(phrase) { return false }
        if afterIsNumber { return true }                                                   // V4
        return blocked.contains("*") || blocked.contains(letter(of: phrase))               // V5
    }

    // ─────────────────────────────── anchors ───────────────────────────────

    /// E2 — slots only mathematics uses: "value(s) of λ", "solve for θ", "in terms of π",
    /// "let λ be", "eigenvalue(s) λ". `before` holds up to three words before the candidate
    /// inside its stretch, NEAREST FIRST; `after` the word after it in the stretch.
    static func anchored(before: [String], after: String?) -> Bool {
        let b = before.map { $0.lowercased() }
        func at(_ k: Int) -> String { k < b.count ? b[k] : "" }
        if at(0) == "of" && (at(1) == "value" || at(1) == "values") { return true }
        if at(0) == "for" && at(1) == "solve" { return true }
        if at(0) == "of" && at(1) == "terms" && at(2) == "in" { return true }
        if at(0) == "let" && after?.lowercased() == "be" { return true }
        return at(0) == "eigenvalue" || at(0) == "eigenvalues"
    }
}
