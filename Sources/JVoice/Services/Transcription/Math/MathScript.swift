import Foundation

/// Unicode super/subscript and fraction rendering, with a plain-text fallback.
///
/// Unicode only covers PART of the alphabet in each script (there is no subscript "b", no
/// superscript "q"), so every attachment is all-or-nothing: if every character of the
/// operand has a form, the pretty version is used ("x" + "2" → "x²", "a" + "n" → "aₙ");
/// otherwise the universally-readable caret/underscore notation is emitted instead
/// ("x^b", "lim_(x→0)"). Never a partial mix — "a_(i+1)" reads correctly, "aᵢ₊1" does not.
///
/// The second half of the file is the LAYOUT of the shared notation format
/// (`docs/math-notation-format.md`, 2026-09-29 — the same format BetterScreenshot's Capture
/// Text pastes): "over" is a slash fraction whose sides get parentheses when they hold a space
/// or an operator (`(a + b)/2`, `1/(x ln 2)`), a radicand is bracketed when it is more than one
/// number or letter (`√(2x)`), trig and log functions take a one-token argument after a space
/// (`sin θ`, `ln 2`, `log₂8`), and a spoken "times" is `×` between numbers but juxtaposition
/// between letter terms (`6 × 7`, `2ab`, `(n - 1)d`).
///
/// Ported from the Windows port's `JVoice.Core/Math/MathScript.cs`; the layout half is macOS-only
/// until the Windows engine mirrors it (list in `docs/math-notation-progress.md`).
public enum MathScript {
    private static let superFrom = Array("0123456789+-=()abcdefghijklmnoprstuvwxyzABDEGHIJKLMNOPRTUVW")
    private static let superTo = Array("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ")

    private static let subFrom = Array("0123456789+-=()aehijklmnoprstuvxβγρφχ")
    private static let subTo = Array("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵦᵧᵨᵩᵪ")

    private static let superMap: [Character: Character] = makeMap(superFrom, superTo)
    private static let subMap: [Character: Character] = makeMap(subFrom, subTo)

    private static func makeMap(_ from: [Character], _ to: [Character]) -> [Character: Character] {
        precondition(from.count == to.count, "MathScript: script table lengths disagree")
        var map: [Character: Character] = [:]
        for (index, character) in from.enumerated() {
            map[character] = to[index]
        }
        return map
    }

    /// The operand rendered as superscript characters, or nil when any character lacks one.
    public static func superscript(_ plain: String) -> String? { map(plain, superMap) }

    /// The operand rendered as subscript characters, or nil when any character lacks one.
    public static func subscriptText(_ plain: String) -> String? { map(plain, subMap) }

    /// Fractions Unicode has a single precomposed glyph for — the best-looking form and the
    /// most widely supported. The recent additions (⅐ ⅑ ⅒ ↉) are deliberately absent: too
    /// many fonts still draw them as a blank box, and the built form ("¹⁄₇") reads the same
    /// everywhere.
    private static let vulgar: [String: String] = [
        "1/2": "½",
        "1/3": "⅓", "2/3": "⅔",
        "1/4": "¼", "3/4": "¾",
        "1/5": "⅕", "2/5": "⅖", "3/5": "⅗", "4/5": "⅘",
        "1/6": "⅙", "5/6": "⅚",
        "1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞",
    ]

    /// U+2044, the typographic fraction slash — it leans further than "/" and tells a font
    /// that these digits are a fraction.
    private static let fractionSlash: Character = "⁄"

    /// The two operands written as ONE stacked fraction — "½", "²²⁄₇", "ˣ⁄ₙ" — or nil when
    /// they cannot be: either side that is not a plain number or a single letter, or a
    /// letter with no script form (there is no subscript "y"), would produce something less
    /// readable than the division sign the caller falls back to. "sin(x) over x" is exactly
    /// that case: "ˢⁱⁿ⁽ˣ⁾⁄ₓ" is technically renderable and completely illegible.
    ///
    /// UNUSED by `MathSpeech` since 2026-09-29: the shared format writes "over" as a slash
    /// (`slashFraction`) because many fonts draw the stacked form badly and it cannot be
    /// edited. Kept (not deleted) for the Windows engine, which still uses it.
    public static func fraction(_ numerator: String, _ denominator: String) -> String? {
        guard isAtomic(numerator), isAtomic(denominator) else { return nil }
        if let glyph = vulgar[numerator + "/" + denominator] { return glyph }
        guard let top = superscript(numerator), let bottom = subscriptText(denominator) else { return nil }
        return top + String(fractionSlash) + bottom
    }

    private static func isAtomic(_ operand: String) -> Bool {
        guard !operand.isEmpty else { return false }
        if operand.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
        return operand.count == 1 && operand.first!.isLetter
    }

    /// `baseText` with `operand` attached as a script. Falls back to "^"/"_" (bracketing
    /// anything longer than one character) when the operand cannot be rendered in Unicode.
    public static func attach(_ baseText: String, _ operand: String, superscript isSuper: Bool) -> String {
        if let pretty = isSuper ? superscript(operand) : subscriptText(operand) {
            return baseText + pretty
        }

        // A single character needs no brackets ("a_b"); anything longer only reaches this
        // fallback because it contains something unscriptable, and reads far better closed
        // ("e^(iπ)", "lim_(x→0)", "∫₀^(√2)") than run together.
        let marker = isSuper ? "^" : "_"
        return operand.count == 1
            ? "\(baseText)\(marker)\(operand)"
            : "\(baseText)\(marker)(\(operand))"
    }

    // ─────────────────────── layout (docs/math-notation-format.md) ───────────────────────
    //
    // Every test below walks Unicode SCALARS, not Characters: each symbol it looks for is a
    // single scalar, and scalar iteration skips grapheme breaking — which matters because
    // a long chain ("x squared squared …", "1 over 2 over 2 …") re-tests a growing operand
    // at every step.

    /// Operators that make an operand "more than one term" when they sit at its top level.
    private static let groupingOperators: Set<Unicode.Scalar> = [
        "+", "-", "×", "÷", "±", "∓", "·", "/", "*", "=", "<", ">", "≤", "≥", "≠", "≈", "→",
        "∈", "∉", "∪", "∩", "∖", "∣", "⇒", "⇔", "≡", "∝",
    ]
    private static let openers: Set<Unicode.Scalar> = ["(", "[", "{", "⟨", "⌊", "⌈"]
    private static let closers: Set<Unicode.Scalar> = [")", "]", "}", "⟩", "⌋", "⌉"]

    /// Script characters and postfixes that decorate a single number or letter without
    /// making it a second one: the "2" of "x²", the "n" of "aₙ", "!", "′", "°".
    private static let decorations: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for character in superTo + subTo + Array("′″‴!°%ᵀ†") {
            set.formUnion(character.unicodeScalars)
        }
        return set
    }()

    private static func isDecoration(_ scalar: Unicode.Scalar) -> Bool {
        decorations.contains(scalar) || scalar.properties.generalCategory == .nonspacingMark
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isAlphabetic }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.isASCII && ("0"..."9").contains(scalar) }

    /// True when `operand` holds a space or an operator OUTSIDE every bracket and |bars| —
    /// the test for "more than one term" (spec principle 6, and BetterScreenshot §8.2: "a
    /// numerator or denominator gets parentheses when it holds a space or an operator").
    /// A leading sign counts only when `leadingSign` is true (a denominator, `1/(-3)`); a
    /// numerator keeps `-b/2`. A slash counts only when `slash` is true: a numerator that is
    /// itself a fraction needs no brackets ("a/b/c" is already (a/b)/c).
    public static func needsGrouping(_ operand: String, leadingSign: Bool = true, slash: Bool = true) -> Bool {
        var depth = 0
        var inBars = false
        var first = true
        for scalar in operand.unicodeScalars {
            let atStart = first
            first = false
            if openers.contains(scalar) { depth += 1; continue }
            if closers.contains(scalar) { depth -= 1; continue }
            if scalar == "|" { inBars.toggle(); continue }
            guard depth == 0, !inBars else { continue }
            if scalar == " " { return true }
            if groupingOperators.contains(scalar) {
                if atStart && !leadingSign && (scalar == "-" || scalar == "+" || scalar == "±") { continue }
                if scalar == "/" && !slash { continue }
                return true
            }
        }
        return false
    }

    /// True when the whole operand sits inside ONE pair of brackets or bars: "(x + 1)",
    /// "|x - 1|" — not "(a)(b)" or "|a||b|".
    public static func isWrapped(_ operand: String) -> Bool {
        isWrapped(operand.unicodeScalars[...])
    }

    private static func isWrapped(_ scalars: Substring.UnicodeScalarView) -> Bool {
        guard let first = scalars.first, let last = scalars.last, scalars.count >= 2 else { return false }
        if first == "|" { return last == "|" && scalars.lazy.filter({ $0 == "|" }).count == 2 }
        guard openers.contains(first), closers.contains(last) else { return false }
        var depth = 0
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if openers.contains(scalar) {
                depth += 1
            } else if closers.contains(scalar) {
                depth -= 1
                if depth == 0 && scalars.index(after: index) != scalars.endIndex { return false }
            }
            index = scalars.index(after: index)
        }
        return depth == 0
    }

    /// A named function applied in brackets: "f(x)", "C(n, k)", "P(A ∣ B)", "log₂(x + 1)".
    public static func isApplication(_ operand: String) -> Bool {
        let scalars = operand.unicodeScalars[...]
        guard scalars.last == ")", let open = scalars.firstIndex(of: "("), open != scalars.startIndex,
              let initial = scalars.first, isLetter(initial), !decorations.contains(initial) else { return false }
        for scalar in scalars[scalars.startIndex..<open]
        where !(isLetter(scalar) || isDigit(scalar) || isDecoration(scalar) || scalar == "_") {
            return false
        }
        return isWrapped(scalars[open...])
    }

    /// Contains no letter at all — "7", "2.5", "10⁸", "5!", "½", "√2" — so a "divided by"
    /// between two of them keeps the school ÷ (spec §3: "6 × 7 ÷ 2").
    public static func isNumeric(_ operand: String) -> Bool {
        !operand.isEmpty && !operand.unicodeScalars.contains(where: isLetter)
    }

    /// "over" (and "divided by" in algebra) as a slash: "π/6", "(a + b)/2", "1/(x ln 2)",
    /// "(sin x)/x". A side gets parentheses when it holds a space or an operator — and a
    /// DENOMINATOR also when it is a juxtaposed product ("1/(2a)", "12/(2T)"), because
    /// "x/2a" reads as (x/2)·a everywhere a formula is evaluated; a numerator product needs
    /// none ("2x/3" is the same either way). DECISION PENDING (docs/math-notation-progress.md):
    /// BetterScreenshot §8.2's wording ("a space or an operator") would paste "/2a".
    public static func slashFraction(_ numerator: String, _ denominator: String) -> String {
        let top = needsGrouping(numerator, leadingSign: false, slash: false) ? "(\(numerator))" : numerator
        let bottom = needsGrouping(denominator) || isJuxtaposedProduct(denominator)
            ? "(\(denominator))" : denominator
        return top + "/" + bottom
    }

    /// How many factors stand side by side at the top level: "2a" 2, "ab" 2, "2(x + 1)" 2,
    /// "πr²" 2, "(n - k)!" 1, "x²" 1, "10⁸" 1, "2.5" 1 — a bracketed group and a digit run are
    /// one factor each, script characters and postfixes none.
    private static func topLevelFactors(_ scalars: Substring.UnicodeScalarView) -> Int {
        var factors = 0
        var inNumber = false
        var depth = 0
        var afterChange = false
        for scalar in scalars where !isDecoration(scalar) {
            // "Δx" is one quantity, the change in x: Δ and its letter are a single factor.
            if scalar == "Δ" { afterChange = true; factors += 1; inNumber = false; continue }
            if afterChange { afterChange = false; if isLetter(scalar) { continue } }
            if openers.contains(scalar) {
                if depth == 0 { factors += 1 }
                depth += 1
                inNumber = false
                continue
            }
            if closers.contains(scalar) { depth -= 1; continue }
            if depth > 0 { continue }
            if isDigit(scalar) || scalar == "." {
                if !inNumber { factors += 1 }
                inNumber = true
            } else {
                inNumber = false
                if isLetter(scalar) { factors += 1 }
            }
        }
        return factors
    }

    /// Two or more factors standing together with no operator: "2a", "ab", "2π", "πr²",
    /// "2√3". Not a single decorated atom ("x²", "aₙ", "10⁸"), a differential ("dx"), an
    /// application ("f(x)", "C(52, 5)"), a bracketed group, or a caret/underscore fallback.
    private static func isJuxtaposedProduct(_ operand: String) -> Bool {
        if isWrapped(operand) || isApplication(operand) || isDifferential(operand) { return false }
        if operand.unicodeScalars.contains(where: { $0 == "_" || $0 == "^" }) { return false }
        return topLevelFactors(operand.unicodeScalars[...]) >= 2
    }

    /// "√14", "√x", "√x²", "√-1" — and "√(2x)", "√(b² - 4ac)": the radicand is bracketed
    /// when it is more than one number or letter (BetterScreenshot §8.2).
    public static func radical(_ sign: String, _ radicand: String) -> String {
        radicandNeedsBrackets(radicand) ? "\(sign)(\(radicand))" : sign + radicand
    }

    private static func radicandNeedsBrackets(_ radicand: String) -> Bool {
        if isWrapped(radicand) { return false }
        if needsGrouping(radicand, leadingSign: false) { return true }
        var core = radicand.unicodeScalars[...]
        if let sign = core.first, sign == "-" || sign == "+" || sign == "±" { core = core.dropFirst() }
        if isWrapped(core) || isApplication(String(core)) { return false }
        return topLevelFactors(core) >= 2
    }

    /// Functions written WITHOUT brackets around a one-token argument (spec §3, BetterScreenshot
    /// §8.2): "sin θ", "cos 2θ", "ln 2" — and tight after a script, "sin²θ", "log₂8". Every
    /// other function keeps its brackets: "f(x)", "det(A)", "max(x)".
    private static let spacedFunctions: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cot", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "coth", "arcsinh", "arccosh", "arctanh", "log", "ln",
    ]

    private static func asciiLetterPrefix(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix { $0.isASCII && isLetter($0) }))
    }

    private static func spacedFunctionName(_ text: String) -> Bool {
        spacedFunctions.contains(asciiLetterPrefix(text))
    }

    /// `name` applied to `argument`: "sin θ", "sin²θ", "log₂8", "sin(x + 1)", "log_b(x)",
    /// "f(x)". The brackets appear only when the argument is more than one term, or the name
    /// needs them.
    public static func applyFunction(_ name: String, _ argument: String) -> String {
        if argument.unicodeScalars.first == "(" && isWrapped(argument) { return name + argument }
        let bare = asciiLetterPrefix(name)
        guard spacedFunctions.contains(bare), !needsGrouping(argument) else {
            return "\(name)(\(argument))"
        }
        let script = name.unicodeScalars.dropFirst(bare.unicodeScalars.count)
        if script.isEmpty { return "\(name) \(argument)" }
        // A fallback base or power ("log_b", "sin^(…)") would run into the argument.
        if script.contains(where: { $0 == "_" || $0 == "^" }) { return "\(name)(\(argument))" }
        return name + argument
    }

    /// How a spoken "times" joins its two sides (spec principle 4): "×" between numbers and
    /// wherever standing together would misread ("x × 2", "V/2 × T", "C(26, 4) × C(10, 3)"),
    /// a space before a trig/log function or a differential ("2 sin x cos x", "x² dx"), and
    /// nothing at all otherwise — letters, brackets and roots multiply by juxtaposition ("2y",
    /// "ab", "(n - 1)d", "(x - 2)(x - 3)", "3√2").
    public static func productSeparator(_ left: String, _ right: String) -> String {
        let cross = " × "
        guard let r = right.first, let l = left.last else { return cross }
        if r.isNumber || "+-±∓.∞".contains(r) { return cross }
        if l == "%" || l == "°" || containsTopLevelSlash(left) { return cross }
        // "√K³" then "Kx²": standing together they would read as one radicand, √(K³Kx²).
        if endsInOpenRadical(left) { return cross }
        if spacedFunctionName(right) || isDifferential(right) { return " " }
        if isApplication(left) || isApplication(right) { return cross }
        if needsGrouping(left, leadingSign: false) || needsGrouping(right) { return cross }
        return ""
    }

    /// What a power attaches to: a slash fraction is bracketed first — "5 over 6 to the
    /// fourth" is (5/6)⁴, never 5/6⁴.
    public static func powerBase(_ base: String) -> String {
        containsTopLevelSlash(base) ? "(\(base))" : base
    }

    private static func isDifferential(_ operand: String) -> Bool {
        let scalars = operand.unicodeScalars
        guard scalars.count == 2, let first = scalars.first, let last = scalars.last else { return false }
        return first == "d" && isLetter(last)
    }

    /// A root sign at the top level whose radicand is NOT bracketed ("√K³", "3√2"): whatever
    /// is written straight after it would look like more radicand.
    private static func endsInOpenRadical(_ operand: String) -> Bool {
        let scalars = Array(operand.unicodeScalars)
        var depth = 0
        for (index, scalar) in scalars.enumerated() {
            if openers.contains(scalar) { depth += 1 } else if closers.contains(scalar) { depth -= 1 }
            guard depth == 0, scalar == "√" || scalar == "∛" || scalar == "∜" else { continue }
            if index + 1 < scalars.count, scalars[index + 1] != "(" { return true }
        }
        return false
    }

    private static func containsTopLevelSlash(_ operand: String) -> Bool {
        var depth = 0
        for scalar in operand.unicodeScalars {
            if openers.contains(scalar) { depth += 1 } else if closers.contains(scalar) { depth -= 1 }
            if scalar == "/" && depth == 0 { return true }
        }
        return false
    }

    /// A grouped script is written without its brackets or its spaces: "x to the quantity n
    /// plus 1" → "xⁿ⁺¹", "a sub open paren n plus 1 close paren" → "aₙ₊₁" (principle 3:
    /// nothing goes inside scripts but the script).
    public static func scriptOperand(_ operand: String) -> String {
        var scalars = Array(operand.unicodeScalars)
        if scalars.first == "(" && isWrapped(operand) { scalars = Array(scalars.dropFirst().dropLast()) }
        var out = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            if scalar == " " {
                let before: Unicode.Scalar = index > 0 ? scalars[index - 1] : " "
                let after: Unicode.Scalar = index + 1 < scalars.count ? scalars[index + 1] : " "
                if groupingOperators.contains(before) || groupingOperators.contains(after) { continue }
            }
            out.append(scalar)
        }
        return String(out)
    }

    private static func map(_ plain: String, _ table: [Character: Character]) -> String? {
        guard !plain.isEmpty else { return nil }
        var out = ""
        out.reserveCapacity(plain.count)
        for character in plain {
            guard let mapped = table[character] else { return nil }
            out.append(mapped)
        }
        return out
    }
}
