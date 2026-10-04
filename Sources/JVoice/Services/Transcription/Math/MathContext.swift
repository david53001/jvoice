import Foundation

/// Dictation-level context for Greek-letter NAMES ("find the value of lambda" → "… of λ").
///
/// A Greek letter is weak: inside a run something else activated it renders ("lambda equals
/// 5" → "λ = 5"), on its own it stays a word ("Lambda, the pie is really tasty."). This file
/// holds the one exception, **context promotion**: a curated name may still become its letter
/// outside an activated run when the dictation shows it is mathematics —
///
///   (a) EVIDENCE: some segment converted with a real letter operand AND a real maths construct
///       in it ("x = 5", "x²", "c/λ" — not "T - 10", "X + Y", "n + 1"), which promotes every
///       passing name in the dictation; or the name itself sits in an ANCHOR slot ("find the
///       value of λ", "solve for θ", "the angle θ"), which promotes that letter and the names
///       of its own sentence only;
///   (b) no VETO applies to it (casing, the word before/after, anti-cue words anywhere);
///   (c) its own segment did not already convert.
///
/// It never activates anything, and with no candidate name in the dictation `MathSpeech.convert`
/// takes exactly the old path. `MathSpeech.Emitter.promote` applies it; this enum is only the
/// word lists and the pure checks (Strings and Bools — the lexer's types stay private), so
/// tuning means editing these sets. Design: docs/math-context-design.md. Any change here must be
/// swept against `.build/math-context/everyday.txt` + `everyday-adversarial.txt` (0 new changed
/// lines) and the S/M rows of `context.tsv` — see the area brief, invariant 4.
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
    /// deliberately, so all of them are promotable in those forms (through every veto, plus
    /// `capitalBefore`: "venture capital beta" is finance).
    private static let allNames: [String] = [
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta",
        "vartheta", "iota", "kappa", "lambda", "lamda", "mu", "nu", "xi", "omicron", "pi", "rho",
        "varrho", "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
    ]

    private static let deliberateWords = ["capital", "uppercase"]

    /// The spoken phrases (lower-case, single-spaced) context may promote. "big X" is NOT one
    /// (2026-10-04 verify): "big alpha energy", "big pi slice" are English.
    static let promotable: Set<String> = {
        var s = Set(lowerNames)
        s.formUnion(["lowercase sigma", "small sigma", "lower case sigma"])
        for word in deliberateWords {
            for name in allNames { s.insert(word + " " + name) }
        }
        return s
    }()

    /// "capital lambda" / "uppercase omega".
    static func isDeliberateCapital(_ phrase: String) -> Bool {
        deliberateWords.contains { phrase.hasPrefix($0 + " ") }
    }

    /// The letter a phrase names, for the per-letter lists: "lamda" → "lambda", "capital pi" →
    /// "pi", "small sigma" → "sigma".
    static func letter(of phrase: String) -> String {
        let name = phrase.split(separator: " ").last.map(String.init) ?? phrase
        return name == "lamda" ? "lambda" : name
    }

    // ─────────────────────────────── vetoes ───────────────────────────────

    /// V2 — the word right before makes it a name or a thing: "a lambda", "my Pi", "AWS Lambda",
    /// "the alpha of the group", "still in beta", "an absolute alpha", "closed beta".
    static let vetoBefore: Set<String> = [
        "a", "an", "my", "your", "his", "her", "our", "their", "hey", "aws", "amazon", "raspberry",
        "happy", "tai", "the", "this", "these", "those", "in", "absolute", "closed", "open", "early",
        "public", "private", "stock", "portfolio", "says", "say", "said",
    ]

    /// V3 — the ONLY ordinary words that may follow a promoted name inside its stretch. Any other
    /// word makes it a compound noun ("alpha team", "beta keys", "lambda sensor", "omega sale",
    /// "lambda function", "gamma rays"), so this allowlist replaced the old blocklist (2026-10-04
    /// verify). Maths items (numbers, letters, operators, keywords like "of"/"over") always may.
    static let continuation: Set<String> = [
        "is", "isn't", "are", "aren't", "was", "were", "be", "been", "being", "equals", "equal",
        "and", "or", "but", "nor", "if", "then", "so", "where", "when", "whereas", "which", "that",
        "such", "since", "because", "as", "for", "in", "on", "at", "by", "with", "within", "into",
        "between", "than", "satisfies", "satisfy", "represents", "represent", "denotes", "denote",
        "gives", "give", "lies", "lie", "tends", "approaches", "becomes", "increases", "decreases",
        "doubles", "halves", "triples", "changes", "varies", "remains", "must", "should", "can",
        "could", "will", "would", "may", "might", "has", "have", "had", "does", "do", "did",
        "we", "you", "hence", "therefore", "thus", "radians", "radian", "degrees", "degree", "max",
        "min", "plus", "minus", "times", "divided", "multiplied", "squared", "cubed", "naught",
        "nought", "prime", "hat", "bar", "dot", "itself", "only", "too", "also", "here", "now",
        "above", "below", "under", "beneath", "across", "along", "around", "through", "after",
        "before", "behind", "near", "inside", "outside", "against", "towards", "toward", "per",
        "sin", "cos", "tan", "sec", "cot", "cosec", "csc",
    ]

    /// For "capital X": the word right before "capital" must be one of these (or nothing — the
    /// stretch starts there). "venture capital beta", "working capital beta", "at capital alpha
    /// partners" are finance.
    static let capitalBefore: Set<String> = [
        "is", "are", "was", "of", "and", "or", "find", "where", "so", "then", "let", "by", "equals",
        "call", "called", "use", "using", "write", "denote", "denotes", "with", "as", "be", "to",
        "plus", "minus", "times", "over", "hence", "calculate", "determine",
    ]

    /// Before a number that starts a promoted group, these make the number a LABEL, not a
    /// coefficient: "question 2 lambda is 5" keeps "2 λ", never "2λ".
    static let labelWords: Set<String> = [
        "question", "questions", "part", "page", "problem", "exercise", "step", "chapter", "number",
        "no", "room", "level", "lesson", "unit", "section", "figure", "table", "example", "line",
        "grade", "year", "version", "season", "episode",
    ]

    /// V5 — a word ANYWHERE in the dictation that says these names are not maths. "*" = all.
    /// Deliberately NOT here (2026-10-04 verify): "testing", "released", "version(s)",
    /// "male(s)", "watch", "rays", "radiation" — they are ordinary IB maths/physics words
    /// ("hypothesis testing", "a ball is released"); V2/V3 still catch "alpha release",
    /// "Omega watch", "gamma rays" right next to the name.
    private static let antiCues: [String: [String]] = {
        var d: [String: [String]] = [:]
        func add(_ letters: [String], _ words: [String]) {
            for w in words { d[w, default: []].append(contentsOf: letters) }
        }
        add(["*"], ["fraternity", "fraternities", "sorority", "sororities", "frat", "call sign",
                    "callsign"])
        // finance: the option "greeks", "chasing alpha", "portfolio beta", "venture capital"
        add(["*"], ["stock", "stocks", "portfolio", "portfolios", "options", "hedge", "fund", "funds",
                    "investor", "investors", "investing", "trading", "trader", "traders", "equity",
                    "venture", "earnings", "market", "markets", "shares"])
        add(["lambda"], ["aws", "amazon", "serverless", "deploy", "deployed", "deploying", "deployment",
                         "python", "javascript", "typescript", "java", "api", "endpoint", "lambdas",
                         "sensor", "probe", "mechanic", "engine", "exhaust", "logo"])
        add(["pi"], ["raspberry", "arduino"])
        add(["alpha", "beta"], ["tester", "testers", "centauri", "alphago", "alphafold", "game", "games",
                                "gaming", "discord", "steam", "waitlist", "app", "apps", "software",
                                "climb", "climbing", "route", "boulder", "bouldering", "fish", "gym",
                                "wolf", "wolves", "pack", "bravo", "charlie", "squad"])
        add(["gamma"], ["hulk", "pokemon"])
        add(["omega"], ["seamaster", "fatty", "oil", "supplement", "supplements", "acids", "steam", "sale"])
        add(["chi"], ["tai", "qi", "yoga", "energy"])
        add(["mu"], ["cow", "cows", "moo"])
        add(["tau"], ["protein", "proteins", "brain", "alzheimer", "alzheimer's"])
        add(["theta"], ["healing", "brainwaves"])
        add(["epsilon"], ["brand", "coffee"])
        return d
    }()

    /// The letter names V5 blocks for this dictation ("*" = every name). `cores` are the
    /// punctuation-stripped words of the whole dictation; a two-word cue ("call sign") matches
    /// two neighbouring words.
    static func dictationVetoes(cores: [String]) -> Set<String> {
        var blocked: Set<String> = []
        let words = cores.map { $0.lowercased() }
        for (i, word) in words.enumerated() {
            if let letters = antiCues[word] { blocked.formUnion(letters) }
            if i + 1 < words.count, let letters = antiCues[word + " " + words[i + 1]] { blocked.formUnion(letters) }
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
    /// compound noun) — "AWS Lambda", "a lambda", "lambda function", "alpha team", "Pi Day",
    /// "Lambda Chi Alpha". One word means one thing per dictation, so the emitter then blocks
    /// every occurrence of that letter ("we had pi on pi day"). `before`/`after` are the
    /// neighbouring words inside the candidate's stretch (nil when punctuation or the
    /// dictation's edge is there); `afterIsWord` says the item after is an ordinary word (not a
    /// number, letter, operator or keyword); for a deliberate capital `before` is the word
    /// before "capital"/"uppercase" and must be in `capitalBefore`. The Greek items touching it in the
    /// stretch, itself included; `greekGroupOK` is false when such a group is a name — anything
    /// but two curated lower-case names ("alpha beta" → αβ; "Lambda Chi Alpha", "phi beta kappa").
    /// `labelBefore`: a number right before it follows a label word ("room 1 alpha", "question 2
    /// alpha"). `afterNumberWord`: the ordinary word after the number that follows it ("alpha 2
    /// builds", "omega 3 every") — checked like `after`.
    static func namesSomething(phrase: String, firstCore: String, sentenceInitial: Bool,
                               before: String?, labelBefore: Bool, after: String?, afterIsWord: Bool,
                               afterNumberWord: String?, greekGroupOK: Bool) -> Bool {
        if nameLike(core: firstCore, sentenceInitial: sentenceInitial) { return true }   // V1
        if let before, vetoBefore.contains(before.lowercased()) { return true }          // V2
        if labelBefore { return true }                                                     // V2
        if let afterNumberWord, !continuation.contains(afterNumberWord.lowercased()) { return true } // V3
        if isDeliberateCapital(phrase), let before,
           !capitalBefore.contains(before.lowercased()) { return true }                   // V2 (capital)
        if let after {
            if afterIsWord && !continuation.contains(after.lowercased()) { return true }  // V3
            // V4: "Lambda Labs", "Pi Day" — but "I'm"/"I'll" are no names.
            if let first = after.first, first.isUppercase, after.count > 1,
               !(after.hasPrefix("I'") || after.hasPrefix("I’")) { return true }
        }
        return !greekGroupOK                                                               // V4
    }

    /// The remaining vetoes for an occurrence that names nothing. `mention`: a quotation mark,
    /// a square bracket, a dash or a colon right after touches it (`say "lowercase sigma"`,
    /// "[beta] tag", "— alpha —", "Alpha: the first letter") — a word MENTIONED or a label, not
    /// a letter in use. `afterIsNumber`: "omega 3", "lambda 1" (V4), unless
    /// `indexed` (the dictation numbers this letter at least twice: "lambda 1 and lambda 2").
    /// `blocked`: the letters V5 and the per-dictation name rule block ("*" = all).
    static func vetoed(phrase: String, mention: Bool, afterIsNumber: Bool, indexed: Bool,
                       blocked: Set<String>) -> Bool {
        if mention { return true }
        if afterIsNumber && !indexed { return true }                                       // V4
        return blocked.contains("*") || blocked.contains(letter(of: phrase))               // V5
    }

    // ─────────────────────────────── anchors ───────────────────────────────

    /// IB command terms that open a question ("Find λ.", "Hence find θ.").
    private static let commands: Set<String> = [
        "find", "calculate", "determine", "state", "deduce", "hence", "evaluate", "compute", "obtain",
        "write", "show",
    ]

    /// Nouns that name a quantity the next letter stands for ("the wavelength λ", "the angle θ",
    /// "the eigenvalues λ").
    private static let cueNouns: Set<String> = [
        "wavelength", "wavelengths", "angle", "angles", "eigenvalue", "eigenvalues", "constant",
    ]

    /// E2 — a slot only mathematics uses. An anchor promotes ITS OWN letter only (every passing
    /// occurrence of it — never the rest of the dictation: "In terms of beta access" must not turn
    /// "alpha team" into α), and the looser slots need a command word or the name to END its
    /// sentence, so "I don't see the value of beta." and "In terms of pi, I prefer apple" stay
    /// English (2026-10-04 verify). V3 has already vetoed "the value of beta access".
    ///
    /// - `before`: every word before the candidate inside its stretch, NEAREST FIRST.
    /// - `stretchStartsClause`: the stretch's first word starts a sentence or clause.
    /// - `after`: up to three words after it inside the stretch.
    /// - `afterAfterIsNumber`: the item after the first word after is a number that closes the
    ///   clause ("let λ be 3.", "let λ be 3, so …" — not "let beta be 2 hours late").
    /// - `sentenceFinal`: ".", "?", "!" right after the name, or the dictation ends there.
    /// - `afterTrig`: the item right before is sine/cosine/tangent/… ("find tan θ").
    static func anchored(before: [String], stretchStartsClause: Bool, after: [String],
                         afterAfterIsNumber: Bool, sentenceFinal: Bool, afterTrig: Bool,
                         deliberateCapital: Bool) -> Bool {
        let b = before.map { $0.lowercased() }
        let a = after.map { $0.lowercased() }
        func at(_ k: Int) -> String { k < b.count ? b[k] : "" }
        let commanded = b.contains { commands.contains($0) }
        // "substitute the value of θ" (not "use": "use the value of beta from the survey")
        let valueCommanded = commanded || b.contains { $0 == "substitute" }
        // "capital sigma" is said on purpose; its own vetoes (capitalBefore, V3) already ran.
        if deliberateCapital { return true }
        if afterTrig { return true }
        if cueNouns.contains(at(0)) { return true }
        // "let λ be 3", "let λ equal 3" — a number must follow; "let beta be honest" is English.
        if at(0) == "let", let first = a.first, ["be", "equal", "equals"].contains(first),
           afterAfterIsNumber { return true }
        // "Express λ in terms of k."
        if at(0) == "express" && a.starts(with: ["in", "terms", "of"]) { return true }
        // "Find the value of λ", "substitute the value of θ" — never "the value of beta
        // access" (V3 already vetoed that) nor "I don't see the value of beta." (no command).
        if at(0) == "of" && (at(1) == "value" || at(1) == "values") && valueCommanded { return true }
        if at(0) == "for" && at(1) == "solve" { return true }
        guard sentenceFinal else { return false }
        // "Express your answer in terms of π." / "Express y in terms of θ." — not "Express
        // yourself in terms of beta."
        if at(0) == "of" && at(1) == "terms" && at(2) == "in" {
            if b.contains(where: { ["answer", "answers", "exact"].contains($0) }) { return true }
            if let k = b.firstIndex(of: "express"), k >= 4, b[k - 1].count == 1 || promotable.contains(b[k - 1]) {
                return true
            }
        }
        // "find tan θ." — whisper writes the bare abbreviation, which the vocabulary leaves
        // as a word ("my sin", "'cos"), so it only counts in a command that ends there.
        if ["tan", "sin", "cos"].contains(at(0)) && commanded { return true }
        // "Find λ." / "Hence find θ." / "Calculate λ." — the whole clause is the command.
        return stretchStartsClause && !b.isEmpty && b.count <= 2 && b.allSatisfy { commands.contains($0) }
    }
}
