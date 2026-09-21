import Foundation

/// How a symbol behaves when `MathSpeech` lays an expression out — and, crucially,
/// whether meeting it is on its own enough to switch a run of spoken words into
/// mathematics.
///
/// Only `relation`, `operatorSymbol` and `prefix` ACTIVATE, and even then only once
/// their operands are actually present (see `MathSymbol.activates` and the operand
/// rules in `MathSpeech`). Everything else is "weak": it renders inside an
/// already-activated run and is left as plain words otherwise. That asymmetry is what
/// keeps "I'm 100 percent sure" and "this is a subscript of the value" untouched.
///
/// Ported 1:1 from the Windows port's `JVoice.Core/Math/MathSymbol.cs`.
public enum MathKind: Equatable, Sendable {
    /// Spaced infix comparison — "=", "≤", "≠". Needs an operand on BOTH sides. ACTIVATING.
    case relation
    /// Spaced infix operation — "+", "×", "∪". Needs an operand on BOTH sides. ACTIVATING.
    case operatorSymbol
    /// Binds the operand that FOLLOWS — "√", "∫", "¬", "-" (negation). ACTIVATING.
    case prefix
    /// Attaches tight to the operand BEFORE it — "!", "°", "%", "′". Weak.
    case postfix
    /// A value — "π", "∞", "ℝ", "α". Weak.
    case operand
    /// Applied to the operand that follows — "sin", "log", "det". Weak.
    case function
    /// An opening bracket — "(", "[", "{". Weak.
    case open
    /// A closing bracket — ")", "]", "}". Weak.
    case close
}

/// One entry of the spoken-mathematics vocabulary: the literal text to emit plus how it
/// binds. Immutable data — all the behaviour lives in `MathSpeech`.
public struct MathSymbol: Equatable, Sendable {
    public let text: String
    public let kind: MathKind

    public init(_ text: String, _ kind: MathKind) {
        self.text = text
        self.kind = kind
    }

    /// True when finding this symbol (with its operands satisfied) is enough to turn the
    /// surrounding run of words into mathematics.
    public var activates: Bool {
        kind == .relation
            || kind == .operatorSymbol
            || (kind == .prefix && !MathSymbols.weakPrefixes.contains(text))
    }

    /// Big operators take their body after a space ("∑ᵢ₌₁ⁿ i²"); every other prefix binds
    /// tight to its operand ("√x", "-5", "¬p").
    public var isBigOperator: Bool {
        kind == .prefix && MathSymbols.bigOperators.contains(text)
    }
}
