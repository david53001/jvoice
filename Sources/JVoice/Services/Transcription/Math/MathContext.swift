import Foundation

/// Dictation-level context for Greek-letter NAMES ("find the value of lambda" → "… of λ").
///
/// A Greek letter is weak: inside a run something else activated it renders ("lambda equals
/// 5" → "λ = 5"), on its own it stays a word ("Lambda, the pie is really tasty."). This file
/// holds the one exception, **context promotion**: a curated name may still become its letter
/// outside an activated run when the dictation shows it is mathematics —
///
///   (a) EVIDENCE: some segment converted with a real letter operand AND a real maths construct
///       in it ("x = 5", "x²", "c/λ" — not "T - 10", "X + Y", "n + 1"), or an equation whisper
///       already WROTE as symbols ("x = 5", "5x + 7z = 5", "y=mx+c", `writtenEquations`), which
///       promotes every passing name in the dictation; a numbers-only equation ("0 = 0") counts
///       only next to maths vocabulary ("solutions", "denominator", …); or the name itself sits
///       in an ANCHOR slot ("find the value of λ", "solve for θ", "the angle θ"), which promotes
///       that letter and the names of its own sentence only;
///   (b) no VETO applies to it (casing, the word before/after, anti-cue words anywhere) — a
///       determiner or possessive before it ("the λ", "a λ", "our θ") vetoes only the letters
///       with everyday senses, and not even those when its own sentence holds evidence;
///   (c) its own segment did not already convert.
///
/// It never activates anything, and with no candidate name in the dictation `MathSpeech.convert`
/// takes exactly the old path. `MathSpeech.Emitter.promote` applies it; this enum is only the
/// word lists and the pure checks (Strings and Bools — the lexer's types stay private), so
/// tuning means editing these sets. Design: docs/math-context-design.md (§9, §10). Any change
/// here must be swept against `.build/math-context/everyday.txt`, `everyday-adversarial.txt`,
/// `everyday-whisper.txt` (0 new changed lines), the S rows of `wordings.tsv` and the S/M rows
/// of `context.tsv` — see the area brief, invariant 4.
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
        if phrase.hasPrefix("delta ") { return "delta" }   // "delta x" → Δx (recall rework)
        let name = phrase.split(separator: " ").last.map(String.init) ?? phrase
        return name == "lamda" ? "lambda" : name
    }

    // ─────────────────────────────── vetoes ───────────────────────────────

    /// Letters whose names are ALSO everyday nouns — a release stage, a dog, a device, a setting
    /// ("the beta is out", "the alpha of the pack", "the pi in my room", "turn up the gamma"). Only
    /// these are vetoed by a determiner, and by a number after them ("beta 2", "omega 3").
    static let everydayLetters: Set<String> = ["alpha", "beta", "gamma", "pi"]

    /// V2 — the word right before ALWAYS makes it a name or a thing: "AWS Lambda", "hey lambda",
    /// "an absolute alpha", "closed beta", "portfolio beta", "the cow says mu".
    static let vetoBefore: Set<String> = [
        "hey", "aws", "amazon", "raspberry", "happy", "tai", "absolute", "closed", "open", "early",
        "public", "private", "stock", "portfolio", "says", "say", "said",
    ]

    /// V2 (recall rework, 2026-10-04) — a determiner, possessive or preposition before a name
    /// vetoes only the letters listed for it: "the λ in this equation", "our θ", "a μ of 0.3" are
    /// ordinary maths speech, "the beta is out", "a lambda" (code), "my Pi" are not. Even these are
    /// lifted when the name's own SENTENCE holds evidence or whisper already wrote that letter as a
    /// symbol (`localMaths`): "So my α is 4 and z = 5/x - 4." The ablation that set these lists
    /// is in docs/math-context-design.md §10.
    private static let determinerVetoes: [String: Set<String>] = {
        var d: [String: Set<String>] = [:]
        for w in ["the", "this", "that", "these", "those", "our", "your", "in"] { d[w] = everydayLetters }
        // "use a lambda", "pass a lambda", "an alpha", "my omega 3s" — code chat and slang
        for w in ["a", "an", "my"] { d[w] = everydayLetters.union(["lambda", "omega"]) }
        // "his beta", "their omega": a person's thing, whatever the letter
        for w in ["his", "her", "their"] { d[w] = ["*"] }
        return d
    }()

    static func determinerVetoes(_ before: String, letter: String) -> Bool {
        guard let letters = determinerVetoes[before.lowercased()] else { return false }
        return letters.contains("*") || letters.contains(letter)
    }

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
        // recall rework (2026-10-04, ablation): verbs and words that follow a letter in real
        // dictations ("the λ goes in…", "λ can't be 0", "λ's value"), and whisper's operators
        "goes", "go", "went", "gone", "come", "comes", "came", "mean", "means", "meant", "make",
        "makes", "made", "stay", "stays", "stayed", "cancel", "cancels", "cancelled", "change",
        "changed", "take", "takes", "took", "taken", "can't", "cannot", "won't", "doesn't", "don't",
        "didn't", "isn't", "wasn't", "shouldn't", "couldn't", "supposed", "needs", "need", "needed",
        "works", "work", "appears", "appear", "got", "get", "gets", "i", "it", "using", "back",
        "first", "there", "out", "again", "value", "values", "term", "terms", "bigger", "smaller",
        "greater", "less", "add", "adds", "comma", "part", "different", "matrix", "right", "wrong",
        "free", "just", "-", "−", "+",
        "=", "÷", "·", "×", "≠", "/",
    ]

    /// After a promoted name and a one-digit number, these make the number an INDEX: "What's λ₁
    /// if x = 5?", "So λ₁ is 2" — but "Is λ 2 then?" asks for a value.
    static let indexFollowers: Set<String> = [
        "is", "was", "if", "equals", "=", "goes", "gives", "has", "when",
    ]

    /// A word right after a relation left dangling at the end of a run: "what is λ equal to WHEN
    /// x = 2" asks a question, it is no half-converted equation.
    static let clauseWords: Set<String> = ["when", "if", "where", "for", "so", "then", "because", "since"]

    /// For "capital X": the word right before "capital" must be one of these (or nothing — the
    /// stretch starts there). "venture capital beta", "working capital beta", "at capital alpha
    /// partners" are finance.
    static let capitalBefore: Set<String> = [
        "is", "are", "was", "of", "and", "or", "find", "where", "so", "then", "let", "by", "equals",
        "call", "called", "use", "using", "write", "denote", "denotes", "with", "as", "be", "to",
        "plus", "minus", "times", "over", "hence", "calculate", "determine", "the", "what's", "what",
    ]

    /// Before a number that starts a promoted group, these make the number a LABEL, not a
    /// coefficient: "question 2 lambda is 5" keeps "2 λ", never "2λ".
    static let labelWords: Set<String> = [
        "question", "questions", "part", "page", "problem", "exercise", "step", "chapter", "number",
        "no", "room", "level", "lesson", "unit", "section", "figure", "table", "example", "line",
        "grade", "year", "version", "season", "episode", "patch", "build",
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
        // the name mentioned as a word, not used as a letter ("the ω is the last letter")
        add(["*"], ["letter", "letters", "alphabet", "word", "pronounced", "spell", "spelling"])
        // a pet, a character, a brand or a logo called by the name; code tooling
        add(["*"], ["nickname", "cat", "cats", "dog", "dogs", "puppy",
                    "kitten", "pet", "logo", "logos", "brand", "brands", "tattoo", "sticker", "shirt",
                    "git", "npm", "checkout"])
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
        add(["delta"], ["flight", "flights", "airline", "airlines", "airport", "variant", "river", "force"])
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
    /// builds", "omega 3 every") — checked like `after`. `localMaths`: its sentence holds evidence
    /// or whisper wrote this letter as a symbol somewhere (lifts the determiner veto);
    /// `stretchMaths`: an equation sits in its own stretch and no capitalised word stands right
    /// before it (lifts V1 for a capitalised letter without an everyday sense: "Where's the
    /// Lambda in 3y + 3z = 5?" — never "AWS Lambda").
    static func namesSomething(phrase: String, firstCore: String, sentenceInitial: Bool,
                               before: String?, labelBefore: Bool, after: String?, afterIsWord: Bool,
                               afterNumberWord: String?, greekGroupOK: Bool, localMaths: Bool,
                               stretchMaths: Bool) -> Bool {
        let letter = letter(of: phrase)
        if nameLike(core: firstCore, sentenceInitial: sentenceInitial) {                  // V1
            let allCaps = firstCore.count >= 2 && firstCore.allSatisfy { $0.isUppercase || !$0.isLetter }
            if allCaps || !stretchMaths || everydayLetters.contains(letter)
                || isDeliberateCapital(phrase) { return true }
        }
        if let before, vetoBefore.contains(before.lowercased()) { return true }          // V2
        if let before, !localMaths, determinerVetoes(before, letter: letter) { return true } // V2
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
    /// a letter in use; whisper's minus "-" is no dash ("x = ⁴⁄₃ - lambda"). `afterIsNumber`:
    /// "omega 3", "beta 2" (V4) — only for the letters with everyday senses plus omega, unless
    /// `indexed` (the dictation numbers this letter at least twice: "alpha 1 and alpha 2");
    /// "Is λ 2?" asks for a value. `blocked`: the letters V5 and the per-dictation name rule
    /// block ("*" = all).
    static func vetoed(phrase: String, mention: Bool, afterIsNumber: Bool, indexed: Bool,
                       blocked: Set<String>) -> Bool {
        if mention { return true }
        let letter = letter(of: phrase)
        if afterIsNumber && !indexed && (everydayLetters.contains(letter) || letter == "omega") { return true } // V4
        return blocked.contains("*") || blocked.contains(letter)                           // V5
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
    /// - `mathsVocabulary`: the dictation says "denominator", "solutions", "system", …
    ///   (`isMathsWord`) — then "the value of λ" needs no command word.
    static func anchored(before: [String], stretchStartsClause: Bool, after: [String],
                         afterAfterIsNumber: Bool, sentenceFinal: Bool, afterTrig: Bool,
                         deliberateCapital: Bool, mathsVocabulary: Bool = false) -> Bool {
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
        if at(0) == "of" && (at(1) == "value" || at(1) == "values") && (valueCommanded || mathsVocabulary) {
            return true
        }
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

    // ─────────────────────── whisper-written notation (recall rework) ───────────────────────

    /// Words that only maths homework uses around a numbers-only equation: "0 = 0, so there are
    /// infinite solutions", "the denominator gives 0 = 0". With one of them in the dictation a
    /// numbers-only equation is evidence; without, "2 + 2 = 4 and the alpha squad lost" or "5 = 5
    /// on the scoreboard" are not. Also lets "the value of λ" anchor without a command word.
    private static let mathsWords: Set<String> = [
        "equation", "equations", "solution", "solutions", "solve", "solved", "solving",
        "denominator", "numerator", "system", "substitute", "substituted", "unknown", "unknowns",
        "coefficient", "coefficients", "variable", "variables", "parameter", "simultaneous",
        "determinant", "significance",
    ]

    static func isMathsWord(_ core: String) -> Bool {
        mathsWords.contains(core) || (core.first?.isUppercase == true && mathsWords.contains(core.lowercased()))
    }

    /// The Greek letter symbol → its curated name ("λ" → "lambda"), for letters whisper wrote.
    static let nameOfSymbol: [Character: String] = {
        var d: [Character: String] = [:]
        for name in lowerNames + ["delta"] {
            if let text = MathSymbols.phrases[name]?.text, text.count == 1, let c = text.first, d[c] == nil {
                d[c] = name
            }
        }
        return d
    }()

    /// The curated names whose letters whisper already wrote somewhere in the dictation ("So
    /// 3z = 5 - 3λ" → lambda): such a name is maths here, whatever stands before it.
    static func writtenLetters(cores: [String]) -> Set<String> {
        var out: Set<String> = []
        for core in cores where core.utf8.contains(where: { $0 >= 0xCE && $0 <= 0xCF }) {   // Greek block
            for c in core { if let name = nameOfSymbol[c] { out.insert(name) } }
        }
        return out
    }

    /// A Greek name with whisper's notation glued on: "lambda's", "Lambda²", "lambda=3",
    /// "theta₁". Returns the name (lower-case) and the suffix to keep, or nil.
    static func gluedName(_ core: String) -> (name: String, suffix: String)? {
        // Fast path (this runs on every word the lexer sees): a plain ASCII word has no suffix
        // (it needs an apostrophe, "=", or a non-ASCII script character).
        guard core.utf8.contains(where: { $0 >= 0x80 || $0 == 0x27 || $0 == 0x3D }) else { return nil }
        let lower = core.lowercased()
        for name in lowerNames where lower.hasPrefix(name) && lower.count > name.count {
            let suffix = String(core.dropFirst(name.count))
            if suffix == "'s" || suffix == "’s" { return (name, suffix) }
            if suffix.allSatisfy({ "⁰¹²³⁴⁵⁶⁷⁸⁹ⁿ₀₁₂₃₄₅₆₇₈₉".contains($0) }) { return (name, suffix) }
            if suffix.first == "=", suffix.count >= 2,
               suffix.dropFirst().range(of: "^[-−]?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil {
                return (name, suffix)
            }
        }
        return nil
    }

    /// A letter with a power whisper wrote ("r²", "x³"): a letter term, not an English word —
    /// "pi r²" is the product πr².
    static func isPoweredLetter(_ core: String) -> Bool {
        core.range(of: "^[A-Za-z][²³]$", options: .regularExpression) != nil
    }

    private static let shortWords: Set<String> = [
        "of", "to", "in", "on", "at", "by", "be", "so", "if", "as", "an", "no", "or", "is", "it", "me",
        "my", "we", "he", "us", "up", "do", "go", "am", "oh", "ok", "id", "the", "and", "for", "but",
        "are", "was", "has", "had", "can", "you", "not", "its", "our", "out", "all", "any", "get",
        "got", "one", "two", "six", "ten", "yes", "she", "her", "him", "his", "who", "why", "how",
        "now", "new", "old", "way", "day", "see", "say", "did", "use", "set", "run", "let", "put",
        "end", "off", "per", "via", "too", "add", "app", "api", "url", "log", "bug", "fix", "pm",
    ]

    /// Unit and ordinal endings glued to a number ("5km", "2nd", "10am") — not a coefficient.
    private static let numberSuffixes: Set<String> = [
        "am", "pm", "th", "st", "nd", "rd", "km", "kg", "cm", "mm", "ml", "mg", "gb", "mb", "kb", "ms",
        "k", "hz", "fps", "px", "mph", "kph",
    ]

    /// One token of whisper-written notation: R relation, O operator, N number, L a letter term
    /// (`x`, `5x`, `x²`, `-3y`, `λ`, `f(x`, `sin(x`), l a short letter group right after an
    /// operator ("ma" in "F = ma"), F a function name, G a glued equation ("x=2", "y=mx+c"),
    /// W anything else.
    /// Compiled once: `notationClass` runs on every token of a dictation that holds a name.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals below; a typo is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern)
    }
    private static let numberPatterns = [
        regex("^[-−]?[0-9]+([.,][0-9]+)?$"), regex("^[-−]?[0-9⁰¹²³⁴⁵⁶⁷⁸⁹]*⁄[0-9₀₁₂₃₄₅₆₇₈₉]+$"),
        regex("^[½⅓⅔¼¾⅕⅙⅛]$"), regex("^√[0-9.]+$"),
    ]
    private static let letterPatterns = [
        regex("^[-−]?([0-9]+(\\.[0-9]+)?)?[A-Za-zα-ωΑ-Ω][²³⁴ⁿ]?$"), regex("^√[A-Za-z]$"),
        regex("^([A-Za-z]|sin|cos|tan|log|ln|exp)\\([-−]?[0-9A-Za-zα-ω.²³+−*/^-]*\\)?$"),
    ]
    private static let coefficientPattern = regex("^[-−]?[0-9]+(\\.[0-9]+)?([a-z]{1,2})[²³]?$")
    private static let equationSide: NSRegularExpression = {
        let term = "([0-9]+(\\.[0-9]+)?)?([a-z]{1,2}|[A-Z]|[α-ω])?[²³]?"
        return regex("^[-−]?\(term)([-+−*/^]\(term))*$")
    }()
    private static let functionNames: Set<String> = ["sin", "cos", "tan", "sec", "csc", "cot", "log", "ln", "exp"]

    private static func whole(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func notationClass(_ core: String, previous: Character?) -> Character {
        let utf8 = core.utf8
        if core.unicodeScalars.count == 1, let c = core.unicodeScalars.first {
            if "=≠<>≤≥≈".unicodeScalars.contains(c) { return "R" }
            if "+-−×·÷±^–*/".unicodeScalars.contains(c) { return "O" }
            if c == "I" { return "W" }
        }
        // Fast paths for plain words and plain numbers, which are almost every token.
        if !utf8.isEmpty, utf8.allSatisfy({ (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }) {
            if core.count == 1 { return "L" }
            if functionNames.contains(core) { return "F" }
            if let previous, "RO".contains(previous), core.count <= 3, core.allSatisfy({ $0.isLowercase }),
               !shortWords.contains(core) { return "l" }
            return "W"
        }
        if !utf8.isEmpty, utf8.allSatisfy({ (0x30...0x39).contains($0) }) { return "N" }
        if numberPatterns.contains(where: { whole($0, core) != nil }) { return "N" }
        if letterPatterns.contains(where: { whole($0, core) != nil }) { return "L" }
        // "5x", "3xy", "2x²" — a coefficient, unless the letters are a unit or ordinal ("5km", "2nd").
        if let m = whole(coefficientPattern, core), let r = Range(m.range(at: 2), in: core),
           !numberSuffixes.contains(String(core[r])) { return "L" }
        if core.filter({ $0 == "=" }).count == 1 {
            let sides = core.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
            if sides.count == 2, sides.allSatisfy({ !$0.isEmpty && whole(equationSide, $0) != nil }),
               !sides.contains(where: { shortWords.contains($0) }) {
                return "G"
            }
        }
        return "W"
    }

    /// Equations whisper already WROTE as symbols, which the lexer leaves as words: windows of
    /// notation tokens holding a relation with something on both sides (or "÷" between letter
    /// terms: "v ÷ r"), plus glued equations ("x=2", "y=mx+c"). `letter`: the token indices of
    /// windows with a letter term ("x = 5", "5x + 7z = 5", "F = ma", "tan x = √3"); `numeric`:
    /// numbers only ("0 = 0", "2 + 2 = 4") — evidence only next to `mathsVocabulary`. Scores
    /// ("3-1"), times ("2:30"), dates ("3/14"), code ("a == b", "i++", "key=lambda") and env
    /// vars ("BETA=1") are single words, so they never form a window. `ends[k]`: token k ends
    /// with punctuation, which closes a window. Linear in the dictation.
    static func writtenEquations(cores: [String], ends: [Bool]) -> (letter: [Int], numeric: [Int]) {
        var letter: [Int] = []
        var numeric: [Int] = []
        var window: [Character] = []
        var start = 0
        func close() {
            defer { window.removeAll() }
            guard window.count >= 3 else { return }
            let inner = window.indices.dropFirst().dropLast()
            let relation = inner.contains { window[$0] == "R" }
            let strong = window.contains("L")
            if relation && strong { letter.append(start); return }
            if !relation, strong, inner.contains(where: { window[$0] == "O" && cores[start + $0] == "÷" }) {
                letter.append(start); return
            }
            if relation && window.allSatisfy({ "NOR".contains($0) }) && window.contains("N") { numeric.append(start) }
        }
        for (k, core) in cores.enumerated() {
            let c = notationClass(core, previous: window.last)
            if c == "G" {
                close()
                if core.contains(where: { $0.isLetter }) { letter.append(k) } else { numeric.append(k) }
                continue
            }
            if c == "W" { close(); continue }
            if window.isEmpty { start = k }
            window.append(c)
            if ends[k] { close() }
        }
        close()
        return (letter, numeric)
    }
}
