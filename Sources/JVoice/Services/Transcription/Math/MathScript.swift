import Foundation

/// Unicode super/subscript and fraction rendering, with a plain-text fallback.
///
/// Unicode only covers PART of the alphabet in each script (there is no subscript "b", no
/// superscript "q"), so every attachment is all-or-nothing: if every character of the
/// operand has a form, the pretty version is used ("x" + "2" → "x²", "a" + "n" → "aₙ");
/// otherwise the universally-readable caret/underscore notation is emitted instead
/// ("x^b", "lim_(x→0)"). Never a partial mix — "a_(i+1)" reads correctly, "aᵢ₊1" does not.
///
/// `fraction` follows the same all-or-nothing discipline for the stacked form ("1 over 2"
/// → "½", "22 over 7" → "²²⁄₇"); when the two sides are not both small enough to stack it
/// returns nil and `MathSpeech` writes "÷" instead.
///
/// Ported 1:1 from the Windows port's `JVoice.Core/Math/MathScript.cs`.
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
