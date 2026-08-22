using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

/// The SPEC for spoken-mathematics conversion (§7 #47).
///
/// <see cref="Converts"/> is what the feature must produce; <see cref="LeavesSpeechAlone"/> is
/// the half that matters more — ordinary talking has to come back byte-identical. Both lists
/// are the contract every later change to <see cref="MathSymbols"/>, <see cref="SpokenNumbers"/>
/// or <see cref="MathSpeech"/> has to keep green.
public class MathSpeechTests
{
    public static TheoryData<string, string> Converts() => new()
    {
        // ── the ask ──
        { "a subscript n equals 1 plus 7n", "aₙ = 1 + 7n" },
        { "x subscript i plus 1", "xᵢ + 1" },
        { "a subscript b equals 2", "a_b = 2" },              // no Unicode subscript b → plain fallback

        // ── powers & roots ──
        { "x squared plus y squared equals z squared", "x² + y² = z²" },
        { "x to the power of n", "xⁿ" },
        { "e to the power of x equals 2", "eˣ = 2" },
        { "x superscript 10", "x¹⁰" },
        { "the square root of 16 equals 4", "the √16 = 4" },
        { "the cube root of 27", "the ∛27" },
        { "the fourth root of 16", "the ∜16" },
        { "the nth root of x", "the ⁿ√x" },

        // ── arithmetic & relations ──
        { "two plus two equals four", "2 + 2 = 4" },
        { "x equals negative 5", "x = -5" },
        { "3 x squared minus 2 x plus 1 equals 0", "3x² - 2x + 1 = 0" },
        { "n is greater than 100", "n > 100" },
        { "x is greater than or equal to 5", "x ≥ 5" },
        { "twenty five divided by five equals five", "25 ÷ 5 = 5" },
        { "3 over 4 plus 1 over 4 equals 1", "3/4 + 1/4 = 1" },
        { "n factorial equals 120", "n! = 120" },

        // ── spoken numbers (SpokenNumbers feeds the lexer; a fraction is ONE operand) ──
        { "x equals twenty five", "x = 25" },
        { "three point one four times r squared", "3.14 × r²" },
        { "one half plus one quarter equals three quarters", "1/2 + 1/4 = 3/4" },
        { "x equals two thirds", "x = 2/3" },
        { "two million five hundred thousand divided by 2", "2500000 ÷ 2" },

        // ── implicit multiplication: atomic operands close up ──
        { "delta x equals 5", "δx = 5" },
        { "x y equals 12", "xy = 12" },
        { "f of x equals a x squared plus b x plus c", "f(x) = ax² + bx + c" },

        // ── greek, constants, sets ──
        { "alpha plus beta equals gamma", "α + β = γ" },
        { "theta equals 30 degrees", "θ = 30°" },
        { "pi times r squared", "π × r²" },
        { "x is an element of the reals", "x ∈ ℝ" },

        // ── big operators, calculus ──
        { "the sum from n equals 1 to infinity of 1 over n squared", "the ∑ₙ₌₁^∞ 1/n²" },
        { "the integral from 0 to 1 of x squared dx", "the ∫₀¹ x² dx" },
        { "the derivative of y with respect to x", "the dy/dx" },
        { "the partial derivative of f with respect to x equals 0", "the ∂f/∂x = 0" },
        { "the limit as x approaches 0 of sine of x over x equals 1", "the lim_(x→0) sin(x)/x = 1" },

        // ── powers spoken the short way, logs, combinatorics ──
        { "e to the x plus 1", "eˣ + 1" },
        { "2 to the 10 equals 1024", "2¹⁰ = 1024" },
        { "log base 2 of x equals 5", "log₂(x) = 5" },
        { "n choose k equals 10", "C(n, k) = 10" },
        { "x equals the square root of 2", "x = √2" },
        { "the absolute value of x equals 5", "the |x| = 5" },
        { "the integral from 0 to the square root of 2 of x dx", "the ∫₀^(√2) x dx" },

        // ── textbook shapes (found by sweeping real equations through the engine) ──
        { "the sum from i equals 1 to n of i equals n times n plus 1 over 2", "the ∑ᵢ₌₁ⁿ i = n × n + 1/2" },
        { "sine squared theta plus cosine squared theta equals 1", "sin²(θ) + cos²(θ) = 1" },
        { "e to the power of i pi plus 1 equals 0", "e^(iπ) + 1 = 0" },
        { "the derivative of x cubed with respect to x equals 3 x squared", "the d(x³)/dx = 3x²" },
        { "open parenthesis a plus b close parenthesis squared equals a squared plus 2 a b plus b squared",
          "(a + b)² = a² + 2ab + b²" },
        { "x subscript 1 plus x subscript 2 equals 10", "x₁ + x₂ = 10" },

        // ── grouping & functions ──
        { "open parenthesis x plus 1 close parenthesis squared", "(x + 1)²" },
        { "f of x equals x squared", "f(x) = x²" },
        { "y equals cosine of theta", "y = cos(θ)" },

        // ── mathematics inside a sentence: only the equation moves ──
        { "so basically x equals 5 and that's it", "so basically x = 5 and that's it" },
        { "the formula is a subscript n equals 2n, which is neat", "the formula is aₙ = 2n, which is neat" },
        { "x equals 5.", "x = 5." },

        // ── explicit escape hatch ──
        { "start equation capital sigma end equation", "Σ" },
        { "write start equation alpha end equation here", "write α here" },
    };

    public static TheoryData<string> LeavesSpeechAlone() => new()
    {
        // the exact overflow David asked about
        "this is a subscript of the value",
        "the subscript was hard to read",
        // ordinary uses of operator words
        "two times a day keeps the doctor away",
        "plus I think we should go now",
        "in less than a minute we were done",
        "he was over there by the tree",
        "let's go over the plan one more time",
        "she scored an A plus on the test",
        "sixty times better than before",
        "I have more than enough time",
        // ordinary uses of noun-like symbols
        "I'm 100 percent sure about this",
        "it's 30 degrees outside today",
        "the sum of my fears is nothing",
        "we need to sum up the results",
        "an integral part of the plan",
        "root cause analysis takes time",
        "the square root of all evil",
        "the alpha version ships tomorrow",
        "God is the alpha and the omega",
        "the power of positive thinking",
        "a lot of people over the years",
        "one of them said something else",
        "I got 5 of 10 questions right",
        // "to the" / "base" / "choose" are constructs only with real operands around them
        "go to the store and buy some milk",
        "listen to the alpha version tomorrow",
        "the base of the mountain was covered in snow",
        "I had to choose between the two options",
        // a spoken SIGN is a number form, not evidence of mathematics (measured on real dictation)
        "the highest you can look up is negative 90 degrees in minecraft",
        "let's say between 60 and negative 50 for now",
        // bounds words ("from"/"to") and relations outside a real equation
        "the ratio of boys to girls is 3 to 2",
        "I'll be there from 5 to 7 tomorrow",
        "the temperature dropped to minus 5 degrees",
        "we went over budget by a lot this quarter",
        "that is less than ideal for us",
        "x, y, and z are the variables",
        "f(x) = 3 is already written out",
        // numbers and fractions in ordinary speech (weak — they never open a run)
        "three quarters of the class passed the test",
        "I ate half of the pizza and a hundred wings",
        // narrative prose that mentions numbers
        "I woke up at seven and made coffee",
        "there were about a hundred people there",
        "give me a minute or two and I'll be ready",
        "he read chapter three verse sixteen out loud",
    };

    [Theory]
    [MemberData(nameof(Converts))]
    public void ConvertsSpokenMathematics(string spoken, string expected)
        => Assert.Equal(expected, MathSpeech.Convert(spoken));

    [Theory]
    [MemberData(nameof(LeavesSpeechAlone))]
    public void LeavesOrdinarySpeechByteIdentical(string prose)
        => Assert.Same(prose, MathSpeech.Convert(prose));

    [Fact]
    public void EmptyAndBlankInputAreReturnedUnchanged()
    {
        Assert.Same("", MathSpeech.Convert(""));
        Assert.Same("   ", MathSpeech.Convert("   "));
    }

    [Theory]
    [MemberData(nameof(Converts))]
    public void ConversionIsIdempotent(string spoken, string expected)
    {
        // Converting already-converted text must be a no-op — otherwise re-processing a
        // transcript (or a symbol that lexes back into a construct) could compound.
        _ = expected;
        string once = MathSpeech.Convert(spoken);
        Assert.Equal(once, MathSpeech.Convert(once));
    }

    [Fact]
    public void ScriptTablesArePaired()
    {
        // Every character that can be super/subscripted must have exactly one mapping.
        Assert.Equal("²", MathScript.Super("2"));
        Assert.Equal("ₙ", MathScript.Sub("n"));
        Assert.Equal("ⁿ⁺¹", MathScript.Super("n+1"));
        Assert.Null(MathScript.Sub("b"));       // no Unicode subscript b
        Assert.Null(MathScript.Super("q"));     // no Unicode superscript q
        Assert.Equal("x_b", MathScript.Attach("x", "b", superscript: false));
        Assert.Equal("lim_(x→0)", MathScript.Attach("lim", "x→0", superscript: false));
        Assert.Equal("e^(iπ)", MathScript.Attach("e", "iπ", superscript: true));
    }

    [Fact]
    public void VocabularyNeverShadowsAConstructTheEngineParses()
    {
        foreach (var reserved in MathSymbols.ReservedPhrases)
            Assert.False(MathSymbols.Phrases.ContainsKey(reserved),
                $"\"{reserved}\" is parsed structurally by MathSpeech — it must not be a vocabulary key.");
    }
}
