namespace JVoice.Core.Text;

/// How a symbol behaves when <see cref="MathSpeech"/> lays an expression out — and,
/// crucially, whether meeting it is on its own enough to switch a run of spoken words
/// into mathematics.
///
/// Only <see cref="Relation"/>, <see cref="Operator"/> and <see cref="Prefix"/> ACTIVATE,
/// and even then only once their operands are actually present (see
/// <see cref="MathSymbol.Activates"/> and the operand rules in <see cref="MathSpeech"/>).
/// Everything else is "weak": it renders inside an already-activated run and is left as
/// plain words otherwise. That asymmetry is what keeps "I'm 100 percent sure" and
/// "this is a subscript of the value" untouched.
public enum MathKind
{
    /// Spaced infix comparison — "=", "≤", "≠". Needs an operand on BOTH sides. ACTIVATING.
    Relation,

    /// Spaced infix operation — "+", "×", "∪". Needs an operand on BOTH sides. ACTIVATING.
    Operator,

    /// Binds the operand that FOLLOWS — "√", "∫", "¬", "-" (negation). ACTIVATING.
    Prefix,

    /// Attaches tight to the operand BEFORE it — "!", "°", "%", "′". Weak.
    Postfix,

    /// A value — "π", "∞", "ℝ", "α". Weak.
    Operand,

    /// Applied to the operand that follows — "sin", "log", "det". Weak.
    Function,

    /// An opening bracket — "(", "[", "{". Weak.
    Open,

    /// A closing bracket — ")", "]", "}". Weak.
    Close,
}

/// One entry of the spoken-mathematics vocabulary: the literal text to emit plus how it
/// binds. Immutable data — all the behaviour lives in <see cref="MathSpeech"/>.
public sealed record MathSymbol(string Text, MathKind Kind)
{
    /// True when finding this symbol (with its operands satisfied) is enough to turn the
    /// surrounding run of words into mathematics.
    public bool Activates => Kind is MathKind.Relation or MathKind.Operator or MathKind.Prefix;

    /// Big operators take their body after a space ("∑ᵢ₌₁ⁿ i²"); every other prefix binds
    /// tight to its operand ("√x", "-5", "¬p").
    public bool IsBigOperator => Kind == MathKind.Prefix && MathSymbols.BigOperators.Contains(Text);
}
