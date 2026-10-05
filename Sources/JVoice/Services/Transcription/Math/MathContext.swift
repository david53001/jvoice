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
///       determiner or possessive before it ("the λ", "a λ", "our θ") vetoes it unless the name's
///       OWN neighbourhood is maths (`Determiner`, design §10.7): "Where's the λ in this equation
///       for x = 5?" promotes, "The lambda is down when x = 2." does not;
///   (c) its own segment did not already convert.
///
/// It never activates anything, and with no candidate name in the dictation `MathSpeech.convert`
/// takes exactly the old path. `MathSpeech.Emitter.promote` applies it; this enum is only the
/// word lists and the pure checks (Strings and Bools — the lexer's types stay private), so
/// tuning means editing these sets. Design: docs/math-context-design.md (§9, §10, §10.7). Any change
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

    /// Names promoted ONLY as a term of an equation whisper wrote whose other side has a real
    /// letter term of its own (round 3): "|x - 2| < delta", "delta = b² - 4ac" → δ — never
    /// "Delta = 0.5", "the delta = 5 points", "Delta Airlines". Bare "delta" stays run-only
    /// everywhere else.
    static let windowOnlyNames: Set<String> = ["delta"]

    /// The spoken phrases (lower-case, single-spaced) context may promote. "big X" is NOT one
    /// (2026-10-04 verify): "big alpha energy", "big pi slice" are English.
    static let promotable: Set<String> = {
        var s = Set(lowerNames).union(windowOnlyNames)
        s.formUnion(["lowercase sigma", "small sigma", "lower case sigma"])
        // the vacuum constants ε₀, μ₀ ("the permittivity epsilon 0")
        for name in ["epsilon", "mu"] {
            for index in ["naught", "nought", "zero", "0"] { s.insert(name + " " + index) }
        }
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
        if phrase.hasPrefix("epsilon ") { return "epsilon" }   // "epsilon naught" → ε₀
        if phrase.hasPrefix("mu ") { return "mu" }
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
        // fix round (2026-10-04): a name for a thing ("Project lambda", "Team omega", "the server
        // omega", "the boat lambda") and slang adjectives ("very beta", "He's alpha")
        "project", "team", "operation", "codename", "server", "boat", "very", "pretty", "super",
        "quite", "totally", "he's", "she's", "i'm", "you're", "they're", "we're", "he’s", "she’s",
        "i’m", "you’re", "they’re", "we’re", "thanks", "thank", "bye", "hi", "hello", "dear", "love",
        "hate", "loves", "hates", "meet",
    ]

    /// V2 (fix round, 2026-10-04) — a determiner or possessive before a name ("the lambda", "our
    /// theta", "my alpha", "his omega") makes it a THING unless the name's own neighbourhood is
    /// mathematics (`MathSpeech.Emitter.determinerLifted`: the letter written as a symbol, a
    /// value statement "the λ is 3 and …", "the λ in this equation / in 3y + 3z = 5", a question
    /// or command "where's/find the λ" with an equation in its stretch, a condition "… when x = 5"
    /// in its stretch, or — not for the everyday letters — an equation plus a maths word in its
    /// sentence). An equation merely elsewhere in the dictation, or "and x = 2" in the same
    /// stretch, no longer lifts it: "The lambda is called with n = 0 and throws." is AWS talk.
    /// `article`: the/this/that/these/those/our/your/a/an/my (and "in" before an everyday letter);
    /// `possessive`: his/her/their — a person's thing, lifted only by a written letter.
    enum Determiner { case article, possessive }

    private static let articleWords: Set<String> = [
        "the", "this", "that", "these", "those", "our", "your", "a", "an", "my",
    ]
    private static let possessiveWords: Set<String> = ["his", "her", "their"]

    static func determiner(_ before: String, letter: String) -> Determiner? {
        let word = before.lowercased()
        if possessiveWords.contains(word) { return .possessive }
        if articleWords.contains(word) { return .article }
        if word == "in" && everydayLetters.contains(letter) { return .article }
        return nil
    }

    /// Before "that": a preposition makes it a determiner ("in that λ"); anything else a
    /// conjunction ("we know that λ is 3", "given that θ is acute").
    static let prepositions: Set<String> = [
        "in", "of", "for", "on", "at", "with", "from", "to", "by", "into", "about", "is", "was",
    ]
    /// The words between a name and its value: "the λ is 3", "my α can't be 4", "an ω of 3".
    static let valueLinks: Set<String> = [
        "is", "was", "equals", "equal", "becomes", "be", "can", "can't", "can’t", "cannot", "has",
        "to", "must", "should", "will", "of", "isn't", "isn’t", "not", "=", "≠", "gets", "just",
        "then", "here", "came", "comes", "come", "out", "as", "turns", "turned", "up", "ends",
        "ended", "now", "only", "always", "still", "supposed",
    ]
    /// A sign as the value: "is the λ supposed to be negative?"
    static let signWords: Set<String> = ["negative", "positive", "zero", "nonzero", "undefined"]
    /// Units a value may carry: "the θ is 30 degrees, so …", "a λ of 500 nanometers and …".
    static let valueUnits: Set<String> = [
        "degrees", "degree", "radians", "radian", "rad", "nanometers", "nanometres", "nm", "metres",
        "meters", "m", "seconds", "s", "hertz", "hz", "kg", "n", "newtons", "j", "joules", "v",
        "volts", "percent", "%", "rad/s", "rad/s²", "m/s", "m/s²", "ms⁻¹", "km/h", "kg/m³", "a",
    ]
    /// A thing's status, not a letter's ("the λ is down", "the ω for x = 2 is fine", "ω is the
    /// best"): within six words after a name it stops every lift but a written letter.
    static let statusWords: Set<String> = [
        "down", "slow", "fast", "late", "broken", "crashed", "crashes", "crash", "crashing", "fine",
        "working", "dead", "offline", "online", "live", "deployed", "timing", "throws", "throwing",
        "failing", "failed", "fails", "cheap", "expensive", "ready", "released", "mine", "tomorrow",
        "cool", "best", "worst", "favourite", "favorite", "good", "bad", "great", "nice", "awesome",
        "amazing", "sold", "shipping", "shipped", "buggy", "laggy", "lagging", "up", "strong",
        "tiny", "old", "new", "called", "named", "busy", "open", "closed", "full", "empty",
        "available", "installed", "running",
    ]

    /// After "let ⟨name⟩ be": a definition ("let θ be the angle", "let λ be any real number").
    static let definitionWords: Set<String> = [
        "the", "a", "an", "any", "some", "equal", "positive", "negative", "real", "constant", "zero",
        "nonzero", "our", "this", "that", "such",
    ]

    /// Words that close a clause after a value ("the λ is 3 AND …").
    static let connectives: Set<String> = [
        "and", "so", "then", "but", "because", "which", "when", "if", "since", "while", "whereas", "or",
        "means", "gives", "makes",
    ]
    /// A question or command about the name: "where's the λ", "what's this θ", "find the λ".
    static let askWords: Set<String> = [
        "where's", "wheres", "where", "what's", "whats", "what", "find", "solve", "calculate",
        "determine", "compute", "get", "which", "where’s", "what’s", "need", "put", "plug", "use",
        "stuck", "isolate", "eliminate", "substitute", "pick", "choose", "about",
    ]
    /// A condition that introduces an equation: "… when x = 5", "if x = 5", "for x = 5", "such
    /// that 2x + y = 0".
    static let conditionWords: Set<String> = [
        "when", "if", "for", "where", "given", "once", "whenever", "unless", "that", "because",
        "since", "gives", "give", "makes", "make", "means", "mean",
    ]

    /// A number or letter term as whisper writes it ("3", "-2", "½", "x", "5x", "π/2").
    static func isValueToken(_ core: String) -> Bool {
        let c = notationClass(core, previous: nil, previousCore: nil)
        return c == "N" || c == "L"
    }

    /// A determiner veto that makes the occurrence a NAME, blocking the letter in the whole
    /// dictation (V2): every possessive, and an article before an everyday letter ("the beta is
    /// out" — one word, one thing). An article before any other letter only stops that occurrence.
    static func determinerNames(_ before: String, letter: String) -> Bool {
        guard let kind = determiner(before, letter: letter) else { return false }
        return kind == .possessive || everydayLetters.contains(letter)
    }

    /// V3 — the ONLY ordinary words that may follow a promoted name inside its stretch. Any other
    /// word makes it a compound noun ("alpha team", "beta keys", "lambda sensor", "omega sale",
    /// "lambda function", "gamma rays"), so this allowlist replaced the old blocklist (2026-10-04
    /// verify). Maths items (numbers, letters, operators, keywords like "of"/"over") always may.
    static let continuation: Set<String> = [
        "is", "isn't", "are", "aren't", "was", "were", "be", "been", "being", "equals", "equal",
        "and", "or", "but", "nor", "if", "then", "so", "where", "when", "whereas", "which", "that",
        "such", "since", "because", "as", "for", "in", "on", "at", "by", "with", "within", "into", "given",
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
        // fix round (2026-10-04): "where's this λ coming from", "the λ getting bigger", "the λ
        // disappears", "positive when x = 5"
        "coming", "going", "doing", "getting", "changing", "increasing", "decreasing", "becoming",
        "tending", "approaching", "varying", "growing", "staying", "appearing", "disappearing",
        "disappears", "disappear", "positive", "zero", "nonzero", "real", "large", "small", "big",
        "doesn’t", "can’t", "isn’t", "won’t", "don’t", "didn’t",
        "=", "÷", "·", "×", "≠", "/",
        // round 3: "the λ sits in the denominator"
        "sits", "sit", "sat", "belongs", "fits",
        // round 3b: "the λ drops out when you subtract the two equations"
        "drops", "drop", "dropped", "vanishes", "vanish", "factors",
        // round 3b (verify 2): "Is λ an eigenvalue of A?" — an article opens a definition, never a compound
        "an",
    ]

    /// Round 3 — a noun that makes a maths COMPOUND with one letter: "the γ factor" (Lorentz) is
    /// physics, so V3 lets it follow and it lifts a determiner; "the alpha factor", "gamma rays"
    /// stay compound nouns.
    static let mathsCompounds: [String: Set<String>] = ["gamma": ["factor"]]

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
        // round 3b: sentence openers before a coefficient ("Because 2 lambda = -4.", "Since 3 theta = 90°.")
        "because", "since", "if", "when", "but", "now", "here", "also", "okay", "ok", "well", "wait",
        "check", "given", "suppose", "assume", "therefore", "thus", "solve", "substitute", "plug", "put",
        "set", "take", "said", "say", "says", "think", "know", "get", "got",
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
                    "git", "npm", "checkout", "server", "servers", "name", "named", "codename", "config", "project",
                    "haskell", "c++", "kotlin", "closure", "closures", "lisp", "code", "coding", "syntax",
                    "crypto", "token", "coin", "symbol", "symbols", "character", "characters", "pokemon",
                    "card", "company", "marketing", "boss", "hp",
                    "env"])
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
        add(["gamma"], ["hulk", "pokemon",
                        // round 3: a display's gamma ("the gamma factor of my monitor is 2.2")
                        "monitor", "monitors", "screen", "screens", "display", "displays", "photo",
                        "photos", "camera", "tv", "brightness", "contrast", "hdr", "srgb"])
        // round 3: a Linux distribution's alpha/beta ("the beta of the distribution is out")
        add(["alpha", "beta"], ["linux", "ubuntu", "distro", "fedora", "debian"])
        add(["omega"], ["seamaster", "fatty", "oil", "supplement", "supplements", "acids", "steam", "sale",
                        "rolex", "seiko", "swatch", "tissot", "watches", "wrist"])
        add(["chi"], ["tai", "qi", "yoga", "energy"])
        add(["mu"], ["cow", "cows", "moo"])
        add(["tau"], ["protein", "proteins", "brain", "alzheimer", "alzheimer's"])
        add(["theta"], ["healing", "brainwaves"])
        add(["epsilon"], ["brand", "coffee"])
        add(["delta"], ["flight", "flights", "airline", "airlines", "airport", "variant", "river", "force",
                        "game", "games", "loop", "frame", "frames", "unity", "engine"])
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
    /// builds", "omega 3 every") — checked like `after`. `determinerLifted`: the name's own
    /// neighbourhood is mathematics (lifts the determiner veto, see `Determiner`);
    /// `stretchMaths`: an equation sits in its own stretch and no capitalised word stands right
    /// before it (lifts V1 for a capitalised letter without an everyday sense: "Where's the
    /// Lambda in 3y + 3z = 5?" — never "AWS Lambda").
    static func namesSomething(phrase: String, firstCore: String, sentenceInitial: Bool,
                               before: String?, labelBefore: Bool, after: String?, afterIsWord: Bool,
                               afterNumberWord: String?, greekGroupOK: Bool, determinerLifted: Bool,
                               stretchMaths: Bool) -> Bool {
        let letter = letter(of: phrase)
        if nameLike(core: firstCore, sentenceInitial: sentenceInitial) {                  // V1
            let allCaps = firstCore.count >= 2 && firstCore.allSatisfy { $0.isUppercase || !$0.isLetter }
            if allCaps || !stretchMaths || everydayLetters.contains(letter)
                || isDeliberateCapital(phrase) { return true }
        }
        if let before, vetoBefore.contains(before.lowercased()) { return true }          // V2
        if let before, !determinerLifted, determinerNames(before, letter: letter) { return true } // V2
        if labelBefore { return true }                                                     // V2
        if let afterNumberWord, !continuation.contains(afterNumberWord.lowercased()) { return true } // V3
        if isDeliberateCapital(phrase), let before,
           !capitalBefore.contains(before.lowercased()) { return true }                   // V2 (capital)
        if let after {
            if afterIsWord && !continuation.contains(after.lowercased())
                && !(mathsCompounds[letter]?.contains(after.lowercased()) ?? false) { return true }  // V3
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
        // fix round (2026-10-04): the IB physics quantities ("the coefficient of friction μ",
        // "the density ρ", "the angular speed ω", "the phase difference φ")
        "friction", "density", "resistivity", "efficiency", "flux", "emf", "torque", "temperature",
        "conductivity", "permittivity", "permeability", "phase",
    ]
    /// "the angular speed ω", "the phase difference φ": a cue noun after its qualifier.
    private static let qualifiedCues: [String: Set<String>] = [
        "angular": ["speed", "frequency", "velocity", "acceleration", "displacement"],
        "phase": ["difference", "angle", "constant", "shift"],
        // round 3: "the Lorentz factor γ", "the significance level α"
        "lorentz": ["factor"],
        "significance": ["level"],
    ]
    /// Nouns a name is "in"/"of" in maths only: "the λ in this equation", "λ of the system".
    static let mathsNouns: Set<String> = [
        "equation", "equations", "formula", "formulas", "formulae", "expression", "expressions",
        "system", "matrix", "polynomial", "inequality", "inequalities", "determinant",
        "denominator", "numerator", "fraction", "exponent", "integral", "derivative", "triangle",
        "circle", "graph", "diagram", "question", "bracket", "brackets",
    ]
    /// Statistics nouns (round 3b): maths only when the name is GIVEN A VALUE through them — "the μ
    /// of the distribution is 50", "the μ of the sample is 12" — never "the alpha of the population
    /// is the leader" or "the sample folder" (round 3 had them as maths nouns: a bleed).
    static let statsNouns: Set<String> = ["distribution", "population", "sample"]

    // ─────────────────────── round 3 (2026-10-04, design §11) ───────────────────────

    /// Places INSIDE mathematics a name can be "in" that are also everyday nouns — counted only
    /// when the phrase ends with them ("the λ is in the power", "the θ is in the second quadrant";
    /// never "the alpha in the power struggle").
    static let placeNouns: Set<String> = [
        "quadrant", "quadrants", "interval", "intervals", "power", "powers", "term", "terms", "sum",
        "vector", "vectors", "sequence", "identity", "expansion", "integrand", "argument",
        // round 3b: maths places v3 converted and round 3's place rule lost ("the λ is in the
        // second row", "… in the parametric form", "… inside the square root", "… on the left
        // hand side", "… in the range 0 to 360", "… in the first column", "… in the limit")
        "row", "rows", "column", "columns", "form", "limit", "limits", "root", "roots", "function",
        "functions", "side", "answer", "answers", "range", "solution", "solutions", "quadratic",
        "coefficient", "coefficients", "product", "quotient", "result",
    ]
    /// Round 3b — "in ⟨noun⟩" with no article is an idiom, not a maths place: "in power now", "in
    /// question", "in series", "in order", "in line".
    static let placeIdioms: Set<String> = ["power", "question", "series", "order", "line", "place", "time", "charge"]
    /// Round 3b — nouns that only make a phrase maths: "the angle BETWEEN THE TWO VECTORS", "the
    /// angle OF THE LINE", "the mean OF THE DISTRIBUTION" (a definition's tail, `mathsTail`).
    static let tailNouns: Set<String> = [
        "vector", "vectors", "line", "lines", "axis", "axes", "x-axis", "y-axis", "horizontal",
        "vertical", "incline", "inclined", "curve", "function", "plane", "planes", "normal", "tangent",
        "origin", "chord", "radius", "hypotenuse", "triangle", "graph", "distribution", "sample",
        "population", "data", "matrix", "wave", "waves", "light", "spring", "pendulum", "slit", "slits",
        "surface", "lens", "mirror", "particle", "body", "mass", "block", "box", "ball", "system",
        "oscillation", "oscillator", "beam", "ray", "rays", "photon", "photons", "electron", "electrons",
        "regression", "model", "equation", "equations", "variable", "variables", "decay", "fluid",
        "liquid", "gas", "material", "wire", "medium", "glass", "water", "air", "string",
        // round 3b (verify 2): "the ω is in the argument of the sine"
        "sine", "cosine", "sin", "cos", "tan", "log", "logarithm", "exponential",
    ]

    /// A name LOCATED somewhere: "the λ is in the cloud", "the ω is in my bag", "the λ lives in
    /// the cloud". The emitter reads "⟨name⟩ [verb] in/on/at/inside ⟨place⟩" as a THING (like a
    /// status word) unless the place is mathematics (a maths/place noun, a number or a letter
    /// term: "the λ is in the denominator", "… in equation 2", "… in 3y + 3z = 5").
    static let locationVerbs: Set<String> = [
        "is", "was", "are", "were", "lives", "live", "lived", "sits", "sit", "sat", "stays", "stayed",
        "lies", "lay", "stored", "kept", "runs", "ran", "living", "sitting", "running", "still",
    ]
    static let locationPrepositions: Set<String> = ["in", "on", "at", "inside", "into"]

    /// STRONG maths vocabulary (round 3): words and phrases only mathematics or physics uses. A
    /// sentence holding one counts as evidence for the names IN THAT SENTENCE (an everyday letter
    /// needs it in its own stretch, or its own maths slot) — "λ is an eigenvalue of A", "Is it θ or
    /// 2θ in the double angle formula?", "The standard deviation is 3 and μ is 10." Weaker words
    /// (angle, factor, formula, level, mean, solve) are NOT here: they are everyday English too.
    /// Lower-case, single-spaced, one to three words; matched only inside one stretch.
    static let strongTerms: Set<String> = [
        // single words — deliberately NOT: integrate/differentiate ("integrate beta into the
        // pipeline"), integral ("λ is integral to our stack"), derivative(s) (finance, "a
        // derivative of the old design"), orthogonal, variance, hypothesis, simultaneous, h1 (HTML)
        "eigenvalue", "eigenvalues", "eigenvector", "eigenvectors", "perpendicular", "quadratic",
        "discriminant", "polynomial", "polynomials", "determinant", "radians", "asymptote",
        "asymptotes", "h0", "h₀", "refractive", "diffraction", "lorentz", "trigonometric",
        "logarithm", "logarithms", "frictional",
        "both sides by", "each side by", "double angle", "compound angle", "standard deviation",
        "significance level", "null hypothesis", "angular velocity", "angular speed",
        "angular frequency", "angular momentum", "angular displacement", "angular acceleration",
        "coefficient of friction", "unit circle", "characteristic equation", "characteristic polynomial",
        "reject the null", "line of best fit", "normal distribution",
        "expected value", "confidence interval", "decay constant", "spring constant",
        "phase difference", "simple harmonic", "divide both sides", "multiply both sides",
        "two equations", "add the equations", "subtract the equations", "time dilation", "test statistic", "critical value",
        "p-value", "p value", "hand side", "scalar product", "dot product", "cross product",
        "position vector", "direction vector", "parametric form", "the derivative of",
        "first derivative", "second derivative", "integral of", "definite integral",
        "indefinite integral",
    ]

    /// Token indices where a strong term starts. `ends[k]`: token k ends with punctuation (a
    /// term never spans it). Linear in the dictation.
    static func strongTermStarts(cores: [String], ends: [Bool]) -> [Int] {
        var out: [Int] = []
        let words = cores.map { $0.lowercased() }
        // Round 3b: "both sides by" / "each side by" only before an operand ("both sides by 2",
        // "… by λ") — "Both sides by now want omega gone." is English.
        func operandAt(_ k: Int) -> Bool {
            guard k < words.count else { return false }
            let w = words[k]
            return w.first.map { $0.isNumber || $0 == "-" || $0 == "−" } == true || w.count == 1 || promotable.contains(w)
                || lowerNames.contains(where: { w.hasPrefix($0) })
        }
        // Round 3b (verify 2): a term that MODIFIES an everyday noun is no maths ("after the
        // eigenvalue quiz", "the eigenvalue joke from class") — the student talks ABOUT school.
        func modifies(_ k: Int) -> Bool {
            !ends[k] && k + 1 < words.count && termModifiedNouns.contains(words[k + 1])
        }
        for i in words.indices {
            var phrase = words[i]
            if strongTerms.contains(phrase) { if !modifies(i) { out.append(i) }; continue }
            // "At the 5% level α is 0.05."
            if !ends[i], i + 1 < words.count, words[i + 1] == "level",
               phrase.range(of: "^[0-9]+(\\.[0-9]+)?%$", options: .regularExpression) != nil { out.append(i); continue }
            var k = i
            while k + 1 < words.count, k - i < 2, !ends[k] {
                k += 1
                phrase += " " + words[k]
                if strongTerms.contains(phrase) {
                    if phrase.hasSuffix(" by") && (ends[k] || !operandAt(k + 1)) { break }
                    if !modifies(k) { out.append(i) }
                    break
                }
            }
        }
        return out
    }

    /// Round 3b (verify 2) — everyday nouns a strong term can modify: "the eigenvalue QUIZ", "the
    /// double angle HOMEWORK", "the expected value LECTURE" (`strongTermStarts`).
    static let termModifiedNouns: Set<String> = [
        "quiz", "quizzes", "test", "tests", "exam", "exams", "lecture", "lectures", "lesson", "lessons",
        "class", "classes", "homework", "joke", "jokes", "meme", "memes", "stuff", "video", "videos",
        "notes", "worksheet", "worksheets", "teacher", "teachers", "club", "song", "movie", "lab", "labs",
        "project", "projects", "assignment", "assignments", "presentation", "guy", "guys", "people",
        "kid", "kids", "nerd", "nerds", "unit", "topic", "chapter", "grade", "grades", "mark", "marks",
        "fan", "fans",
    ]

    /// Round 3b (verify 2) — what a PERSON does: after a name, these make it someone, so strong
    /// vocabulary elsewhere in its stretch never makes it a letter ("Theta went home after the
    /// eigenvalue quiz", "The expected value is low, so lambda left").
    static let personVerbs: Set<String> = [
        "left", "cried", "texted", "called", "said", "says", "agrees", "agreed", "wanted",
        "wants", "likes", "liked", "loves", "loved", "hates", "hated", "bought", "buys", "arrived",
        "laughed", "slept", "ate", "missed", "studied", "studies", "messaged", "replied", "told",
        "thinks", "thought", "knows", "knew", "lives", "lived", "walked", "drove", "played", "won",
        "lost", "smiled", "joined", "quit", "skipped", "failed", "passed",
    ]

    /// Round 3b (verify 2) — units only science writes: with one of THIS letter's units the
    /// quantity stands whatever the sentence says next ("λ is 700 nm, so it's red."). Everyday
    /// units (degrees, m, cm) still need the sentence to end or go on in maths.
    static let scientificUnits: Set<String> = [
        "nm", "nanometres", "nanometers", "nanometre", "nanometer", "μm", "µm", "micrometres", "micrometers",
        "micrometre", "micrometer", "microns", "micron", "pm", "picometres", "picometers", "rad", "rads",
        "radians", "radian", "rad/s", "rad s⁻¹", "rads⁻¹", "rad s^-1", "radians per second", "rad per second",
        "kg/m³", "kg m⁻³", "kgm⁻³", "g/cm³", "kg/m^3", "kilograms per cubic metre", "Ωm", "ω m",
        "ohm metres", "ohm meters", "n m", "n·m", "newton metres", "newton meters", "rad/s²", "rad s⁻²",
    ]

    /// Round 3b (verify 2) — a noun a maths sentence may define a letter AS ("λ is the WAVELENGTH",
    /// "θ is the ANGLE", "μ is the SAME", "λ is the ANSWER"): any maths list, a physical quantity or
    /// a neutral noun. "ω is the restaurant", "λ, ω and θ are the groups" use none.
    static func mathsish(_ word: String) -> Bool {
        if mathsNouns.contains(word) || placeNouns.contains(word) || tailNouns.contains(word)
            || statsNouns.contains(word) || definitionNouns.contains(word) || strongTerms.contains(word)
            || cueNouns.contains(word) || definesMaths(word) || isMathsWord(word)
            || neutralNouns.contains(word) || word.hasSuffix("est") { return true }
        return false
    }
    private static let neutralNouns: Set<String> = [
        "same", "one", "ones", "answer", "answers", "value", "values", "number", "numbers", "thing",
        "things", "bit", "part", "solution", "solutions", "result", "unknown", "unknowns", "variable",
        "variables", "constant", "constants", "coefficient", "key", "reason", "problem", "difference",
        "ratio", "rate", "factor", "root", "limit", "sum", "product", "term", "power", "index", "base",
        "mean", "mode", "median", "average", "range", "total", "size", "length", "height", "width",
        "distance", "area", "volume", "speed", "time", "period", "weight", "mass", "force", "energy",
        "charge", "current", "voltage", "resistance", "temperature", "pressure", "angle", "side",
        "scale", "step", "gradient", "slope", "multiplier", "parameter", "exponent", "input", "output",
        "argument", "first", "second", "third", "last", "opposite", "inverse", "reciprocal", "negative",
        "positive", "other", "only", "unit", "units", "amplitude", "frequency", "phase", "displacement",
        "velocity", "acceleration", "momentum", "wavelength", "work", "efficiency", "probability",
        "proportion", "percentage", "fraction", "estimate", "approximation", "bound", "limit", "error",
        "uncertainty", "gradient", "intercept", "vertex", "centre", "center", "radius", "diameter",
    ]

    /// QUANTITY statement (round 3): a value with a unit THIS letter stands for is the letter —
    /// "θ is 30 degrees", "the λ is 600 nm", "ω is 3 rad/s", "the ρ of water is 1000 kg/m³". Never
    /// a price, a percentage, a size in mm/MB, a time: "the beta is 30% off", "the omega is 40 mm",
    /// "the lambda is 512 MB", "the lambda is 30 seconds" (AWS) stay. Units of one to three words.
    static let quantityUnits: [String: Set<String>] = {
        let angle: Set<String> = ["degrees", "degree", "°", "radians", "radian", "rad", "rads"]
        return [
            "theta": angle, "phi": angle, "alpha": angle.union(["rad/s²", "rad s⁻²"]), "beta": angle,
            "gamma": angle,
            "lambda": ["nm", "nanometres", "nanometers", "nanometre", "nanometer", "μm", "µm", "um",
                       "micrometres", "micrometers", "micrometre", "micrometer", "microns", "micron",
                       "pm", "picometres", "picometers", "m", "metres", "meters", "metre", "meter", "cm"],
            "omega": ["rad/s", "rad s⁻¹", "rads⁻¹", "rad s^-1", "radians per second", "rad per second"],
            "rho": ["kg/m³", "kg m⁻³", "kgm⁻³", "g/cm³", "kg/m^3", "kilograms per cubic metre", "Ωm", "ω m",
                    "ohm metres", "ohm meters"],
            // "Nm" (newton metres) is checked case-sensitively: "1 nm" is a nanometre (round 3b)
            "tau": ["nm", "n m", "n·m", "newton metres", "newton meters"],
        ]
    }()

    /// The words between a name and its value that a RELATIVE clause adds: "the θ WE GOT was
    /// 0.93 rad", "the λ we measured is 650 nm".
    static let clauseSubjects: Set<String> = ["we", "i", "you", "they"]
    static let clauseVerbs: Set<String> = [
        "got", "get", "found", "find", "measured", "calculated", "obtained", "have", "had", "used",
        "use", "worked", "need", "needed", "chose", "picked",
    ]

    /// Filler between a name and its definition: "the β HERE is the coefficient", "the α is NOW
    /// the unknown", "the β is BASICALLY the coefficient".
    static let fillerWords: Set<String> = [
        "here", "now", "just", "basically", "really", "actually", "simply", "also", "then", "over",
        "there", "front", "in", "right",
    ]
    /// The verb of a definition: "λ IS an eigenvalue", "θ REPRESENTS the angle".
    static let copulas: Set<String> = ["is", "was", "are", "were", "represents", "denotes", "means", "'s", "’s"]
    /// Nouns that DEFINE a letter on their own — a definition "⟨name⟩ is the ⟨noun⟩" anchors it
    /// ("λ is an eigenvalue of A", "θ is the angle between the two vectors", "Is μ the mean of
    /// the distribution?"). An everyday letter needs evidence or a strong term in its sentence too
    /// ("Pi is the best angle for photos" stays: a status word stops the walk).
    static let definitionNouns: Set<String> = [
        "eigenvalue", "eigenvalues", "eigenvector", "eigenvectors", "angle", "angles", "coefficient",
        "coefficients", "gradient", "slope", "exponent", "wavelength", "mean", "variance", "multiplier",
        "parameter", "scalar", "density", "wavelengths", "frequency", "resistivity", "permittivity",
    ]
    /// Round 3b — the definition nouns that are ALSO everyday English (a ski slope, a story's
    /// angle, an XP multiplier, a URL parameter, "the golden mean"): with no evidence near, they
    /// anchor only with a maths tail ("θ is the angle BETWEEN THE TWO VECTORS", "μ is the mean OF
    /// THE DISTRIBUTION", "θ is the angle at B") — never "Lambda is the angle for this story".
    static let everydayDefinitionNouns: Set<String> = [
        "angle", "angles", "coefficient", "coefficients", "gradient", "slope", "exponent", "mean",
        "variance", "multiplier", "parameter", "density", "frequency",
    ]
    /// What may follow a definition noun — "θ is the angle BETWEEN …", "μ is the mean OF …", "the β
    /// here is the coefficient," — never "Lambda is the mean one".
    static let definitionTails: Set<String> = [
        "of", "for", "between", "at", "in", "and", "so", "then", "when", "if", "which", "that", "we", "here",
    ]
    /// Weaker nouns a definition may still use next to evidence ("the β here is the gradient, y =
    /// βx + 3"): `definitionNouns` plus every maths noun/word.
    static func definesLetter(_ word: String, strong: Bool) -> Bool {
        definitionNouns.contains(word) || (!strong && (definesMaths(word) || ["intercept", "ratio"].contains(word)))
    }

    /// MATHS VERB (round 3): "multiply/divide ⟨object⟩ by ⟨name⟩" — the name is an operand when the
    /// object is maths ("both sides", "everything", "the first equation", "through", nothing):
    /// "Multiply both sides by λ.", "Divide by λ.", "Now divide through by λ." — never "multiply
    /// your savings by beta", "divide the team by alpha".
    static let operationVerbs: Set<String> = [
        "multiply", "multiplied", "multiplying", "divide", "divided", "dividing", "scale", "scaled",
    ]
    static let operationObjects: Set<String> = [
        "both", "sides", "side", "each", "everything", "it", "this", "that", "the", "equation",
        "equations", "whole", "thing", "top", "bottom", "and", "numerator", "denominator", "through",
        "first", "second", "third", "row", "line", "expression", "term", "terms", "all", "out",
        "we", "you", "i", "can", "now", "then", "so", "just",
    ]
    /// Round 3b — verbs of working-out that make the rest of a sentence maths ("Now multiply by λ
    /// and ADD 5x", "θ is 30 degrees, so SUBSTITUTE …").
    static let mathsVerbs: Set<String> = [
        "add", "subtract", "multiply", "divide", "simplify", "solve", "expand", "rearrange", "factorise",
        "factorize", "substitute", "differentiate", "integrate", "square", "cancel", "isolate", "collect",
    ]
    /// Round 3b — units no Greek letter stands for in IB maths/physics: a price, a time, a size, a
    /// score ("the β is 2 weeks away", "the π is 5 euros", "λ is 512 MB", "the α is 3 points ahead").
    static let everydayUnits: Set<String> = [
        "off", "euros", "euro", "eur", "dollars", "dollar", "usd", "bucks", "pounds", "lei", "ron", "cents",
        "quid", "yen", "weeks", "week", "days", "day", "hours", "hour", "hrs", "minutes", "minute", "mins",
        "seconds", "second", "secs", "ms", "months", "month", "years", "year", "yrs", "mb", "gb", "kb", "tb",
        "gigs", "megabytes", "gigabytes", "mm", "km", "miles", "mile", "ft", "feet", "inches", "points",
        "point", "pts", "people", "players", "kids", "users", "followers", "likes", "views", "times",
        "done", "battery", "left", "ahead", "behind", "away", "late", "early", "kilos", "kg", "lbs",
    ]
    /// Round 3b: after "Beta, …" at a sentence start, an order or a question to a person.
    static let vocativeFollowers: Set<String> = [
        "solve", "do", "did", "can", "could", "please", "go", "come", "finish", "eat", "are", "have", "you",
        "your", "stop", "don't", "don’t", "listen", "look", "wait", "tell", "give", "get", "take", "help",
        "check", "call", "put", "make", "let", "try", "sit", "open", "close", "show", "bring", "find", "where",
        "what", "why", "how", "when", "beta", "come", "hurry", "first",
    ]
    /// Round 3b: words that make "Find λ such that …" a maths condition.
    static let conditionTerms: Set<String> = [
        "intersect", "intersects", "parallel", "perpendicular", "root", "roots", "inverse", "solution",
        "solutions", "converges", "tangent", "continuous", "differentiable", "maximum", "minimum",
        "integer", "positive", "negative", "zero", "points", "point", "lines", "vectors", "angle", "area",
        "triangle", "circle", "curve", "graph", "function", "sum", "product", "series", "sequence",
        // round 3b (verify 2): physics conditions ("Find the value of ω such that the period is 2 s.")
        "period", "frequency", "amplitude", "speed", "velocity", "acceleration", "force", "energy",
        "momentum", "tension", "displacement", "wavelength", "equilibrium", "magnitude", "gradient",
        "slope", "vector", "matrix", "determinant", "equation", "equations", "system",
    ]
    static let timeUnits: Set<String> = ["seconds", "second", "secs", "ms", "minutes", "minute", "hours", "hour"]
    /// "θ is 30 degrees WARMER", "the ω is 300 m WATER resistant": a weather or product value.
    static let everydayComparatives: Set<String> = [
        "warmer", "colder", "hotter", "cooler", "outside", "today", "tonight", "inside", "water", "deep",
        "tall", "high", "long", "wide", "away", "warm", "hot", "cold",
    ]

    /// An expression whisper wrote with no relation is evidence after these commands ("Expand (x
    /// + λ)^2.", "Factorise λ² - 5λ + 6.") — or when it holds a bracket with a power ("(x + λ)²").
    static let expressionVerbs: Set<String> = [
        "expand", "simplify", "factorise", "factorize", "factor", "differentiate", "integrate",
        "evaluate", "rationalise", "rationalize",
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
                         deliberateCapital: Bool, mathsVocabulary: Bool = false, valueStated: Bool = false) -> Bool {
        let b = before.map { $0.lowercased() }
        let a = after.map { $0.lowercased() }
        func at(_ k: Int) -> String { k < b.count ? b[k] : "" }
        let commanded = b.contains { commands.contains($0) }
        // "substitute the value of θ" (not "use": "use the value of beta from the survey")
        let valueCommanded = commanded || b.contains { $0 == "substitute" }
        // "What's the value of λ?" — a question that ENDS on the name.
        let valueAsked = sentenceFinal && b.contains { ["what's", "whats", "what"].contains($0) }
        // "capital sigma" is said on purpose; its own vetoes (capitalBefore, V3) already ran.
        if deliberateCapital { return true }
        if afterTrig { return true }
        if cueNouns.contains(at(0)) { return true }
        // Round 3b: "The mean μ is 12." — "mean" is an adjective too, so only with a value.
        if at(0) == "mean" && valueStated { return true }
        if let qualified = qualifiedCues[at(1)], qualified.contains(at(0)) { return true }
        // "For which λ does the system …?", "for what values of λ …"
        if at(0) == "which" && at(1) == "for" { return true }
        // "What is λ in this equation?", "the λ of the system": a name in/of a maths noun.
        // Round 3b: "Plug λ back into the first equation.", "Substitute θ into the second equation."
        let placed = a.first == "back" ? Array(a.dropFirst()) : a
        if let first = placed.first, first == "in" || first == "of" || first == "into" {
            let rest = placed.dropFirst().drop { ["this", "the", "that", "our", "each", "every", "my", "first", "second",
                                                  "third", "other", "same", "last", "both"].contains($0) }
            if let noun = rest.first, mathsNouns.contains(noun) { return true }
            // "The μ of the distribution is 50." — a statistics noun only with a value
            if first == "of", let noun = rest.first, statsNouns.contains(noun), valueStated { return true }
        }
        // Round 3b: "Find λ such that the lines intersect.", "Find μ given that the box doesn't move."
        if stretchStartsClause, !b.isEmpty, b.count <= 2, b.allSatisfy({ commands.contains($0) }),
           a.count >= 2, ["such", "given", "so"].contains(a[0]), a[1] == "that" { return true }
        // "let λ be 3", "let λ equal 3" — a number must follow; "let beta be honest" is English.
        if at(0) == "let", let first = a.first, ["be", "equal", "equals"].contains(first),
           afterAfterIsNumber { return true }
        // "Express λ in terms of k."
        if at(0) == "express" && a.starts(with: ["in", "terms", "of"]) { return true }
        // "Find the value of λ", "substitute the value of θ" — never "the value of beta
        // access" (V3 already vetoed that) nor "I don't see the value of beta." (no command).
        // "The value of λ is 3." (`valueStated`) — fix round.
        if at(0) == "of" && (at(1) == "value" || at(1) == "values")
            && (valueCommanded || mathsVocabulary || valueAsked || valueStated) {
            return true
        }
        if at(0) == "for" && at(1) == "solve" { return true }
        // "So λ can't be 2 because then the denominator is 0": a value given beside maths words.
        if valueStated && mathsVocabulary { return true }
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
        // fix round (2026-10-04)
        "matrix", "matrices", "singular", "discriminant", "eigenvalue", "eigenvalues", "eigenvector",
        "eigenvectors", "formula", "quadratic", "polynomial", "inequality", "roots", "radians",
    ]

    /// A noun that makes the phrase around a name maths: "the θ is the ANGLE", "the α makes the
    /// DENOMINATOR 0", "our α is the SIGNIFICANCE level".
    static func definesMaths(_ word: String) -> Bool {
        cueNouns.contains(word) || mathsNouns.contains(word) || mathsWords.contains(word)
    }

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
    /// 3z = 5 - 3λ" → lambda): such a name is maths here, whatever stands before it. `cores` are
    /// only the tokens written as a LETTER TERM (`Written.letterTerms`): the μ of a unit ("50 μs",
    /// "10 μg") is no letter.
    static func writtenLetters(cores: [String]) -> Set<String> {
        var out: Set<String> = []
        for core in cores where core.utf8.contains(where: { $0 >= 0xCE && $0 <= 0xCF }) {   // Greek block
            for c in core { if let name = nameOfSymbol[c] { out.insert(name) } }
        }
        return out
    }

    /// A Greek name with whisper's notation glued on: "lambda's", "Lambda²", "lambda=3",
    /// "theta₁" — or, since the fix round, after whisper's minus or an opening bracket: "-lambda",
    /// "-omega²", "sin(theta", "N(mu", "e^(-lambda". Returns the name (lower-case), the prefix and
    /// the suffix to keep, or nil. "=N" is not accepted for the everyday letters ("alpha=1" is a
    /// config flag).
    static func gluedName(_ core: String) -> (name: String, prefix: String, suffix: String)? {
        // Fast path (this runs on every word the lexer sees): a plain ASCII word has no prefix or
        // suffix (it needs an apostrophe, "=", "-", "(", or a non-ASCII character).
        // Round 3 adds "/" ("pi/4"), ")" and "^" ("lambda)^2", "lambda^2") and a digit ("3pi/2").
        guard core.utf8.contains(where: { $0 >= 0x80 || $0 == 0x27 || $0 == 0x3D || $0 == 0x2D || $0 == 0x28
                                          || $0 == 0x2F || $0 == 0x29 || $0 == 0x5E || $0 == 0x7C
                                          || (0x30...0x39).contains($0) })
        else { return nil }
        if let found = gluedName(core, prefixPattern: gluedPrefix) { return found }
        // Round 3b: a fraction's denominator — "c/lambda", "hc/lambda", "2pi/omega" (whisper's
        // physics formulas); tried second so "pi/4" stays π with the suffix "/4".
        guard core.utf8.contains(0x2F) else { return nil }
        return gluedName(core, prefixPattern: gluedSlashPrefix)
    }

    private static func gluedName(_ core: String, prefixPattern: NSRegularExpression) -> (name: String, prefix: String, suffix: String)? {
        var prefix = ""
        if let m = whole(prefixPattern, core), let r = Range(m.range, in: core) { prefix = String(core[r]) }
        let body = String(core.dropFirst(prefix.count))
        let lower = body.lowercased()
        for name in lowerNames where lower.hasPrefix(name) {
            let suffix = String(body.dropFirst(name.count))
            if suffix.isEmpty { return prefix.isEmpty ? nil : (name, prefix, suffix) }
            if suffix == "'s" || suffix == "’s" { return (name, prefix, suffix) }
            if suffix.allSatisfy({ "⁰¹²³⁴⁵⁶⁷⁸⁹ⁿ₀₁₂₃₄₅₆₇₈₉".contains($0) }) { return (name, prefix, suffix) }
            // round 3: a closing bracket and/or a power ("(x + lambda)^2", "lambda)²", "lambda^2"),
            // a slash and a number or one letter ("pi/4", "3pi/2", "pi/T" — never "alpha/beta")
            if whole(gluedPowerSuffix, suffix) != nil || whole(gluedSlashSuffix, suffix) != nil
                || whole(gluedBracketSuffix, suffix) != nil {
                return (name, prefix, suffix)
            }
            if suffix.first == "=", suffix.count >= 2, !everydayLetters.contains(name),
               suffix.dropFirst().range(of: "^[-−]?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil {
                return (name, prefix, suffix)
            }
        }
        return nil
    }

    /// Whisper's minus, or an opening bracket after at most a short function name ("sin(", "N(",
    /// "e^(-") — what may stand glued before a name.
    /// Round 3b adds an absolute-value bar ("|lambda|") and a bracket product or quotient
    /// ("1)(lambda", "1)/(lambda").
    private static let gluedPrefix = regex("^(\\||[-−]|[0-9A-Za-z]{0,3}\\)/?\\([-−]?|[0-9]+(?=[a-z])|[A-Za-z]{0,4}\\^?\\([-−]?)")
    /// Round 3b: a numerator and a slash ("c/", "hc/", "2pi/").
    private static let gluedSlashPrefix = regex("^(?![wW]/)([0-9]+([A-Za-z]|pi)?|[A-Za-z]|hc|pi)/")
    /// Round 3b: "alpha)(x", "pi)/2", "lambda|".
    private static let gluedBracketSuffix = regex("^\\)(/[0-9A-Za-z]+|\\([-−]?[0-9A-Za-z]*)$|^\\|$")
    private static let gluedPowerSuffix = regex("^\\)?(\\^[-−]?[0-9]+|\\^\\([^)]*\\)|[²³⁴⁵⁶⁷⁸⁹ⁿ]+)$|^\\)[²³⁴⁵⁶⁷⁸⁹ⁿ]*$")
    private static let gluedSlashSuffix = regex("^/([0-9]+|[A-Za-z])$")

    /// "pi/4", "3pi/2": whisper's fraction of π is its own evidence (round 3) — nobody writes it
    /// outside mathematics. Other letters' slash forms ("beta/2", "alpha/1") need evidence.
    /// Round 3b: also "2pi/T", and any name UNDER a slash ("c/lambda", "2pi/omega") or in an
    /// exponent ("e^(-lambda").
    static func isPiFraction(name: String, suffix: String?, prefix: String = "") -> Bool {
        if prefix.hasSuffix("/") || prefix.contains("^(") { return true }
        guard name == "pi", let suffix else { return false }
        return suffix.range(of: "^/([0-9]+|[A-Za-z])$", options: .regularExpression) != nil
    }

    /// Round 3b: whisper's glued text around a promoted name, with the other Greek names in it
    /// written as letters too ("2pi/" → "2π/", in "2pi/omega" → "2π/ω").
    static func greekified(_ text: String) -> String {
        guard text.contains(where: { $0.isLetter }) else { return text }
        var out = ""
        var run = ""
        func flushRun() {
            if lowerNames.contains(run.lowercased()), let symbol = MathSymbols.phrases[run.lowercased()]?.text {
                out += symbol
            } else {
                out += run
            }
            run = ""
        }
        for c in text {
            if c.isASCII && c.isLetter { run.append(c) } else { flushRun(); out.append(c) }
        }
        flushRun()
        return out
    }

    /// Round 3b: the glued text around a name holds a term of its own ("2pi/T", "c/", "1)(") — so a
    /// written window made of such names is still an equation ("omega = 2pi/T").
    static func gluedOwnTerm(prefix: String, suffix: String) -> Bool {
        if prefix.isEmpty && suffix.isEmpty { return false }
        if (prefix + suffix).contains(where: { $0.isASCII && $0.isNumber }) { return true }
        var rest = prefix + "|" + suffix
        for name in lowerNames where rest.contains(name) { rest = rest.replacingOccurrences(of: name, with: "") }
        return rest.contains { ($0.isASCII && $0.isLetter) }
    }

    /// Whisper's signed coefficient: "-2", "−0.5".
    static func isSignedNumber(_ core: String) -> Bool {
        core.range(of: "^[-−][0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil
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
        regex("^[-−±]?[0-9]+([.,][0-9]+)?$"), regex("^[-−]?[0-9⁰¹²³⁴⁵⁶⁷⁸⁹]*⁄[0-9₀₁₂₃₄₅₆₇₈₉]+$"),
        regex("^[-−]?[½⅓⅔¼¾⅕⅙⅛]$"), regex("^[-−]?√[0-9.]+$"),
        // fix round: "30°", "1/3", "10^-3"
        regex("^[-−]?[0-9]+(\\.[0-9]+)?°$"), regex("^[-−]?[0-9]+/[0-9]+$"),
        regex("^[0-9]+(\\.[0-9]+)?\\^[-−]?[0-9]+$"),
    ]
    private static let letterPatterns = [
        regex("^[-−]?([0-9]+(\\.[0-9]+)?)?[A-Za-zα-ωΑ-Ω][²³⁴ⁿ]?$"), regex("^[-−]?√[A-Za-z]$"),
        // round 3: arc/hyperbolic functions and inverses ("arctan(3/4)", "tan^-1(3/4)", "sin⁻¹(0.6)")
        regex("^[-−]?[0-9]*([A-Za-z]|sin|cos|tan|sec|csc|cot|arcsin|arccos|arctan|sinh|cosh|tanh|log|ln|exp|det|sqrt|abs)?(\\^-1|\\^\\(-1\\)|⁻¹)?\\([-−]?[0-9A-Za-zα-ω.²³+−*/^-]*\\)?$"),
        // fix round: "mc²", "ab²"; "x1", "v0", "N0"; "π/6", "5π/6", "h/p", "c/f"
        regex("^[A-Za-z]{1,3}[²³]$"), regex("^[a-z][0-9]$|^[A-Z]0$"),
        // a short product holding a Greek letter: "λv", "2λx", "Aω" — never a μ unit ("μs", "μg")
        regex("^[-−]?[0-9]*(?!μ[a-zA-Z]{1,2}$)(?=[A-Za-z]{0,2}[α-ω])[A-Za-zα-ω]{2,3}[²³]?$"),
        regex("^[-−]?([0-9]+(\\.[0-9]+)?)?([A-Za-z]{1,2}|[α-ωΑ-Ω√])*[²³]?([/^*][-−]?([0-9]+(\\.[0-9]+)?)?([A-Za-z]{1,2}|[α-ωΑ-Ω√])*[²³]?)+$"),
    ]
    /// Unit fractions — no letter terms ("v = 3 m/s" is evidence through "v = 3" anyway).
    private static let unitWords: Set<String> = ["w/o", "km/h", "m/s", "m/s²", "kg/m³", "g/cm³", "km/s", "rad/s", "rad/s²", "mi/h"]
    private static let coefficientPattern = regex("^[-−]?([0-9]+)(\\.[0-9]+)?([a-z]{1,2})[²³]?$")
    /// One side of a glued equation ("y=mx+c"): a sum of short terms. The left side must be one
    /// letter (fix round: "lr=0.01", "bs=32" are config keys, "x=2", "n=100" are equations).
    private static let equationSide: NSRegularExpression = {
        let term = "([0-9]+(\\.[0-9]+)?)?([a-z]{1,2}|[A-Z]|[α-ω])?[²³]?"
        return regex("^[-−]?\(term)([-+−*/^]\(term))*$")
    }()
    private static let equationLeft = regex("^[-−]?([0-9]+(\\.[0-9]+)?)?([A-Za-z]|[α-ω])[²³]?$")
    private static let functionNames: Set<String> = ["sin", "cos", "tan", "sec", "csc", "cot", "log", "ln", "exp"]

    /// Words that put a single capital letter in a LABEL ("Plan B = 20", "Gate B = 4", "Row A =
    /// 12"): any capitalised word but a sentence opener or a maths noun, and these.
    private static let labelNouns: Set<String> = [
        "plan", "option", "options", "row", "seat", "gate", "room", "grade", "tier", "block", "section",
        "building", "platform", "terminal", "level", "vitamin", "type", "size", "class", "group",
        "team", "zone", "wing", "floor", "bus", "route", "hall", "lot", "exit", "door", "box", "bay",
    ]
    /// Capitalised words before a single letter that do not make it a label: "So X = 5", "Let A
    /// = 3", "Point A = (1, 2)".
    private static let letterOpeners: Set<String> = [
        "so", "then", "let", "if", "and", "where", "for", "find", "now", "but", "here", "since", "when",
        "because", "hence", "thus", "solve", "set", "put", "say", "take", "given", "assume", "suppose",
        "with", "or", "is", "was", "what's", "what", "where's", "why", "how", "also", "okay", "ok",
        "yes", "no", "well", "wait", "check", "plug", "substitute", "use", "write", "point", "matrix",
        "vector", "line", "plane", "triangle", "angle", "segment", "circle", "function", "case",
        "equation", "therefore", "make", "making", "makes", "until", "unless", "once", "whenever",
    ]

    private static func whole(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    /// `previous`: the class of the token before inside the current window (nil at its start);
    /// `previousCore`: the word right before (any class), for labels.
    private static func notationClass(_ raw: String, previous: Character?, previousCore: String?) -> Character {
        // Round 3: an absolute-value bar or a bracket whisper glued on ("|x", "2|", "1)²", "(2x") is
        // read through — the term inside is what counts.
        let core = raw.utf8.contains(where: { $0 == 0x7C || $0 == 0x28 || $0 == 0x29 }) ? unbracketed(raw) : raw
        guard !core.isEmpty else { return "W" }
        let utf8 = core.utf8
        if core.unicodeScalars.count == 1, let c = core.unicodeScalars.first {
            // round 3b (verify 2): "~" — "X ~ N(μ, 4)" (a distribution, IB statistics)
            if "=≠<>≤≥≈~".unicodeScalars.contains(c) { return "R" }
            if "+-−×·÷±^–*/".unicodeScalars.contains(c) { return "O" }
            // "I" is the pronoun — except as a factor after notation ("λ I", "A - λ I")
            if c == "I" { return previous.map { "ORL".contains($0) } == true ? "L" : "W" }
        }
        // Fast paths for plain words and plain numbers, which are almost every token.
        if !utf8.isEmpty, utf8.allSatisfy({ (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }) {
            if core.count == 1 {
                // "Plan B = 20", "Gate B = 4": a capital after a label word is a name, not a letter.
                if let p = previousCore, core.first!.isUppercase, let f = p.first, f.isLetter {
                    let word = p.lowercased()
                    if labelNouns.contains(word) || (f.isUppercase && !letterOpeners.contains(word)) { return "W" }
                }
                return "L"
            }
            if functionNames.contains(core) { return "F" }
            // "λ max", "λ min" keep the term going
            if previous == "L", ["max", "min"].contains(core) { return "L" }
            if let previous, "RO".contains(previous), core.count <= 3,
               !shortWords.contains(core.lowercased()) { return "l" }
            return "W"
        }
        if !utf8.isEmpty, utf8.allSatisfy({ (0x30...0x39).contains($0) }) { return "N" }
        if unitWords.contains(core) { return "W" }
        if numberPatterns.contains(where: { whole($0, core) != nil }) { return "N" }
        if letterPatterns.contains(where: { whole($0, core) != nil }) {
            return core.contains(where: { $0.isLetter || $0 == "π" }) ? "L" : "N"
        }
        // "5x", "3xy", "2x²" — a coefficient, unless the letters are a unit or ordinal ("5km",
        // "2nd"), or the number is no coefficient anyone writes ("1x", "100m": a speed-up, a
        // distance).
        if let m = whole(coefficientPattern, core), let r = Range(m.range(at: 3), in: core),
           let n = Range(m.range(at: 1), in: core), !numberSuffixes.contains(String(core[r])),
           m.range(at: 2).location != NSNotFound || (core[n] != "1" && core[n].count < 3) { return "L" }
        if core.filter({ $0 == "=" }).count == 1 {
            let sides = core.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
            if sides.count == 2, sides.allSatisfy({ !$0.isEmpty && whole(equationSide, $0) != nil }),
               whole(equationLeft, sides[0]) != nil,
               !sides.contains(where: { shortWords.contains($0) }) {
                return "G"
            }
        }
        return "W"
    }

    private static let bracketEdges = regex("^[|(]+|[|)]+(\\^[-−]?[0-9]+|[²³⁴]+)?$")
    private static let bracketPower = regex("\\)(\\^[-−]?[0-9]+|\\^\\(|[²³⁴])")
    /// "|x" → "x", "2|" → "2", "1)²" → "1" — but "f(x)" and "sin(x" keep their own brackets.
    private static func unbracketed(_ core: String) -> String {
        if core.first != "|" && core.first != "(" && !core.contains("|"),
           core.filter({ $0 == "(" }).count == core.filter({ $0 == ")" }).count, core.range(of: ")^") == nil,
           core.range(of: ")²") == nil, core.range(of: ")³") == nil { return core }
        let ns = core as NSString
        let stripped = bracketEdges.stringByReplacingMatches(in: core, range: NSRange(location: 0, length: ns.length),
                                                            withTemplate: "")
        return stripped.isEmpty ? core : stripped
    }
    /// A bracket closed with a power after it ("(x + λ)^2", "1)²"): whisper wrote algebra.
    static func closesPoweredBracket(_ core: String) -> Bool {
        core.contains(")") && bracketPower.firstMatch(in: core, range: NSRange(core.startIndex..., in: core)) != nil
    }

    /// What `writtenEquations` found. Window starts: `letter` (a relation and a letter term — "x
    /// = 5", "5x + 7z = 5", "F = ma", "tan x = √3", "λ = -3"), `numeric` (numbers only — "0 =
    /// 0"), `expression` (an operator and a letter term, no relation — "2 - λ", evidence only in
    /// a sentence with a maths word: "the denominator 2 - λ can't be zero"). `letterTerms`: the
    /// tokens whisper wrote as a letter term ("3λ", "β"), for `writtenLetters`.
    struct Written {
        var letter: [Int] = []
        var numeric: [Int] = []
        var expression: [Int] = []
        var letterTerms: [Int] = []
        /// Round 3: every token of a window counted as LETTER evidence ("|x - 2| < delta"), for
        /// `windowOnlyNames`.
        var letterWindowToks: Set<Int> = []
    }

    /// Equations whisper already WROTE as symbols, which the lexer leaves as words: windows of
    /// notation tokens holding a relation with something on both sides (or "÷" between letter
    /// terms: "v ÷ r"), plus glued equations ("x=2", "y=mx+c"). Scores ("3-1"), times ("2:30"),
    /// code ("a == b", "i++", "key=lambda") and env vars ("BETA=1", "lr=0.01") are single words,
    /// so they never form a window; a capital after a label word ("Plan B = 20") is a name, and a
    /// window whose letters are all capitals ordered by < or > ("S > A > B") is a ranking.
    /// `ends[k]`: token k ends with punctuation, which closes a window. `letters`: tokens of the
    /// Greek NAMES in the dictation, each a letter term here ("lambda = -3", "lambda² - 4 = 0",
    /// "sin(theta) = 0.5"). Linear in the dictation.
    static func writtenEquations(cores: [String], ends: [Bool], letters: Set<Int> = [],
                                 termNames: Set<Int> = []) -> Written {
        var out = Written()
        var window: [Character] = []
        var start = 0
        func close() {
            defer { window.removeAll() }
            guard window.count >= 3 else { return }
            let inner = window.indices.dropFirst().dropLast()
            let relation = inner.contains { window[$0] == "R" }
            let strong = window.contains("L")
            // Round 3: a window holding a Greek name needs a term of its own besides it — a number,
            // a letter, a function, a two-letter product: "lambda = -3", "theta = h/p", "lambda = mg",
            // never "Lambda = arn".
            // Round 3b: a name with glued terms ("2pi/T", "1)(lambda") is a term of its own, and
            // algebra after a command or with a powered bracket ("Expand (alpha + beta)².") needs none.
            let commanded = start >= 1 && !ends[start - 1] && expressionVerbs.contains(cores[start - 1].lowercased())
            if window.indices.contains(where: { letters.contains(start + $0) }),
               !commanded, !window.indices.contains(where: { closesPoweredBracket(cores[start + $0]) }),
               !window.indices.contains(where: { k in
                   (!letters.contains(start + k) || termNames.contains(start + k))
                       && ("NLGF".contains(window[k]) || (window[k] == "l" && cores[start + k].count <= 2))
               }) {
                return
            }
            func letterWindow() {
                out.letter.append(start)
                for k in window.indices { out.letterWindowToks.insert(start + k) }
            }
            if relation && strong {
                // "S > A > B", "A > B": a ranking, not an inequality between letters.
                let ranking = !window.indices.contains { window[$0] == "R" && ["=", "≠", "≈"].contains(cores[start + $0]) }
                    && window.indices.allSatisfy { k in
                        window[k] != "L" || (cores[start + k].count == 1 && cores[start + k].first!.isUppercase)
                    }
                if !ranking { letterWindow() }
                return
            }
            if !relation, strong, inner.contains(where: { window[$0] == "O" && cores[start + $0] == "÷" }) {
                letterWindow(); return
            }
            // Round 3: algebra with no relation — after a command ("Expand (x + λ)^2.", "Factorise
            // λ² - 5λ + 6.") or with a powered bracket ("(x + λ)²").
            if !relation, strong, window.contains("O"),
               (start >= 1 && !ends[start - 1] && expressionVerbs.contains(cores[start - 1].lowercased()))
                || window.indices.contains(where: { closesPoweredBracket(cores[start + $0]) }) {
                letterWindow(); return
            }
            if !relation, strong, window.contains("O") {
                // "x is 3 - λ", "λ is 3 - x": a letter, "is", the expression — an equation said with
                // "is" ("the score is 3 - 1" has no letter before it).
                if start >= 2, !ends[start - 1], !ends[start - 2], ["is", "was", "be"].contains(cores[start - 1].lowercased()),
                   letters.contains(start - 2)
                    || (cores[start - 2].count == 1 && notationClass(cores[start - 2], previous: nil, previousCore: nil) == "L"
                        && cores[start - 2] != "I" && cores[start - 2].lowercased() != "a") {
                    letterWindow(); return
                }
                out.expression.append(start); return
            }
            if relation && window.allSatisfy({ "NOR".contains($0) }) && window.contains("N") { out.numeric.append(start) }
        }
        for (k, core) in cores.enumerated() {
            var c: Character
            if letters.contains(k) {
                c = core.contains("=") ? "G" : "L"
            } else {
                c = notationClass(core, previous: window.last, previousCore: k > 0 ? cores[k - 1] : nil)
                if c == "L" || c == "G" { out.letterTerms.append(k) }
            }
            if c == "G" {
                close()
                if core.contains(where: { $0.isLetter }) { out.letter.append(k) } else { out.numeric.append(k) }
                continue
            }
            if c == "W" { close(); continue }
            if window.isEmpty { start = k }
            window.append(c)
            if ends[k] { close() }
        }
        close()
        return out
    }
}
