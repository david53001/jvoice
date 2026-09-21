#if canImport(Testing)
import Testing
@testable import JVoice

/// The SPEC for spoken-mathematics conversion — the Swift side of the Windows port's
/// `MathSpeechTests.cs`, case for case.
///
/// `converts` is what the feature must produce; `leavesAlone` is the half that matters
/// more — ordinary talking has to come back byte-identical. Both lists are the contract
/// every later change to `MathSymbols`, `SpokenNumbers` or `MathSpeech` has to keep green.

private let mathConverts: [(String, String)] = [
    // ── the ask ──
    ("a subscript n equals 1 plus 7n", "aₙ = 1 + 7n"),
    ("x subscript i plus 1", "xᵢ + 1"),
    ("a subscript b equals 2", "a_b = 2"),
    // ── powers & roots ──
    ("x squared plus y squared equals z squared", "x² + y² = z²"),
    ("x to the power of n", "xⁿ"),
    ("e to the power of x equals 2", "eˣ = 2"),
    ("x superscript 10", "x¹⁰"),
    ("the square root of 16 equals 4", "the √16 = 4"),
    ("the cube root of 27", "the ∛27"),
    ("the fourth root of 16", "the ∜16"),
    ("the nth root of x", "the ⁿ√x"),
    // ── arithmetic & relations ──
    ("two plus two equals four", "2 + 2 = 4"),
    ("x equals negative 5", "x = -5"),
    ("3 x squared minus 2 x plus 1 equals 0", "3x² - 2x + 1 = 0"),
    ("n is greater than 100", "n > 100"),
    ("x is greater than or equal to 5", "x ≥ 5"),
    ("twenty five divided by five equals five", "25 ÷ 5 = 5"),
    ("3 over 4 plus 1 over 4 equals 1", "¾ + ¼ = 1"),
    ("n factorial equals 120", "n! = 120"),
    // ── spoken numbers ──
    ("x equals twenty five", "x = 25"),
    ("three point one four times r squared", "3.14 · r²"),
    ("one half plus one quarter equals three quarters", "½ + ¼ = ¾"),
    ("x equals two thirds", "x = ⅔"),
    ("two million five hundred thousand divided by 2", "2500000 ÷ 2"),
    // ── implicit multiplication ──
    ("delta x equals 5", "δx = 5"),
    ("x y equals 12", "xy = 12"),
    ("f of x equals a x squared plus b x plus c", "f(x) = ax² + bx + c"),
    // ── greek, constants, sets ──
    ("alpha plus beta equals gamma", "α + β = γ"),
    ("theta equals 30 degrees", "θ = 30°"),
    ("pi times r squared", "π · r²"),
    ("x is an element of the reals", "x ∈ ℝ"),
    // ── big operators, calculus ──
    ("the sum from n equals 1 to infinity of 1 over n squared", "the ∑ₙ₌₁^∞ 1 ÷ n²"),
    ("the integral from 0 to 1 of x squared dx", "the ∫₀¹ x² dx"),
    ("the derivative of y with respect to x", "the dy/dx"),
    ("the partial derivative of f with respect to x equals 0", "the ∂f/∂x = 0"),
    ("the limit as x approaches 0 of sine of x over x equals 1", "the lim_(x→0) sin(x) ÷ x = 1"),
    // ── powers spoken the short way, logs, combinatorics ──
    ("e to the x plus 1", "eˣ + 1"),
    ("2 to the 10 equals 1024", "2¹⁰ = 1024"),
    ("log base 2 of x equals 5", "log₂(x) = 5"),
    ("n choose k equals 10", "C(n, k) = 10"),
    ("x equals the square root of 2", "x = √2"),
    ("the absolute value of x equals 5", "the |x| = 5"),
    ("the integral from 0 to the square root of 2 of x dx", "the ∫₀^(√2) x dx"),
    // ── textbook shapes ──
    ("the sum from i equals 1 to n of i equals n times n plus 1 over 2", "the ∑ᵢ₌₁ⁿ i = n · n + ½"),
    ("sine squared theta plus cosine squared theta equals 1", "sin²(θ) + cos²(θ) = 1"),
    ("e to the power of i pi plus 1 equals 0", "e^(iπ) + 1 = 0"),
    ("the derivative of x cubed with respect to x equals 3 x squared", "the d(x³)/dx = 3x²"),
    ("open parenthesis a plus b close parenthesis squared equals a squared plus 2 a b plus b squared",
     "(a + b)² = a² + 2ab + b²"),
    ("x subscript 1 plus x subscript 2 equals 10", "x₁ + x₂ = 10"),
    // ── weak "i" ──
    ("the sum from i equals 1 to n of i squared converges", "the ∑ᵢ₌₁ⁿ i² converges"),
    ("i equals the square root of negative 1", "i = √-1"),
    // ── grouping & functions ──
    ("open parenthesis x plus 1 close parenthesis squared", "(x + 1)²"),
    ("f of x equals x squared", "f(x) = x²"),
    ("y equals cosine of theta", "y = cos(θ)"),
    // ── mathematics inside a sentence ──
    ("so basically x equals 5 and that's it", "so basically x = 5 and that's it"),
    ("the formula is a subscript n equals 2n, which is neat", "the formula is aₙ = 2n, which is neat"),
    ("x equals 5.", "x = 5."),
    // ── the 2026-08-30 batch ──
    ("3 times 4 equals 12", "3 · 4 = 12"),
    ("x equals 2 times y", "x = 2 · y"),
    ("a cross product b equals c", "a × b = c"),
    ("1 over 2 plus 1 over 3", "½ + ⅓"),
    ("22 over 7 is approximately pi", "²²⁄₇ ≈ π"),
    ("x over n equals 2", "ˣ⁄ₙ = 2"),
    ("x over y equals 2", "x ÷ y = 2"),
    ("10 divided by 2 equals 5", "10 ÷ 2 = 5"),
    ("1 over n squared", "1 ÷ n²"),
    ("log base 2 of 8", "log₂(8)"),
    ("log base 10 of 1000 equals 3", "log₁₀(1000) = 3"),
    ("log sub 2 of x", "log₂(x)"),
    ("so we take log base 2 of x and then move on", "so we take log₂(x) and then move on"),
    ("log base n of x equals 5", "logₙ(x) = 5"),
    ("u n equals 1 plus 7n", "uₙ = 1 + 7n"),
    ("u 1 equals 70000", "u₁ = 70000"),
    ("u n plus 1 equals 2 u n", "uₙ + 1 = 2uₙ"),
    ("a n equals a 1 times r to the power of n", "aₙ = a₁ · rⁿ"),
    ("5000 parentheses open, 1 plus 1.03 over 100 parentheses close", "5000 (1 + 1.03 ÷ 100)"),
    ("x equals open paren a plus b close paren times c", "x = (a + b) · c"),
    // ── explicit escape hatch ──
    ("start equation capital sigma end equation", "Σ"),
    ("write start equation alpha end equation here", "write α here"),
]

private let mathLeavesAlone: [String] = [
    "this is a subscript of the value",
    "the subscript was hard to read",
    "two times a day keeps the doctor away",
    "plus I think we should go now",
    "in less than a minute we were done",
    "he was over there by the tree",
    "let's go over the plan one more time",
    "she scored an A plus on the test",
    "sixty times better than before",
    "I have more than enough time",
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
    "go to the store and buy some milk",
    "listen to the alpha version tomorrow",
    "the base of the mountain was covered in snow",
    "I had to choose between the two options",
    "the highest you can look up is negative 90 degrees in minecraft",
    "let's say between 60 and negative 50 for now",
    "the ratio of boys to girls is 3 to 2",
    "I'll be there from 5 to 7 tomorrow",
    "the temperature dropped to minus 5 degrees",
    "we went over budget by a lot this quarter",
    "that is less than ideal for us",
    "x, y, and z are the variables",
    "f(x) = 3 is already written out",
    "three quarters of the class passed the test",
    "I ate half of the pizza and a hundred wings",
    "he said 50 plus i think it was more",
    "it was 3 because i wanted it",
    "so genesis one because i feel like it matters",
    "I woke up at seven and made coffee",
    "there were about a hundred people there",
    "give me a minute or two and I'll be ready",
    "he read chapter three verse sixteen out loud",
    "i think u n is fine the way it is",
    "we counted u 1 and u 2 by hand",
    "the log of the tree was rotten through",
    "we need to log in with the email first",
    "she went over to plan b 2 instead",
]


@Test func convertsSpokenMathematics() {
    for (spoken, expected) in mathConverts {
        #expect(MathSpeech.convert(spoken) == expected, "\(spoken)")
    }
}

@Test func leavesOrdinarySpeechByteIdentical() {
    for prose in mathLeavesAlone {
        #expect(MathSpeech.convert(prose) == prose, "\(prose)")
    }
}

@Test func emptyAndBlankInputAreReturnedUnchanged() {
    #expect(MathSpeech.convert("") == "")
    #expect(MathSpeech.convert("   ") == "   ")
}

@Test func conversionIsIdempotent() {
    // Converting already-converted text must be a no-op — otherwise re-processing a
    // transcript (or a symbol that lexes back into a construct) could compound.
    for (spoken, _) in mathConverts {
        let once = MathSpeech.convert(spoken)
        #expect(MathSpeech.convert(once) == once, "\(spoken)")
    }
}

@Test func aRealParagraphConvertsOnlyItsMathematics() {
    let spoken = """
        okay so I was working through the homework and the first problem says find x where \
        x squared minus 5 x plus 6 equals 0, which factors into open parenthesis x minus 2 \
        close parenthesis times open parenthesis x minus 3 close parenthesis, so x equals 2 \
        or x equals 3, and honestly that took me way longer than it should have
        """
    let expected = """
        okay so I was working through the homework and the first problem says find x where \
        x² - 5x + 6 = 0, which factors into (x - 2) · (x - 3), so x = 2 \
        or x = 3, and honestly that took me way longer than it should have
        """
    #expect(MathSpeech.convert(spoken) == expected)
}

@Test func aRealBibleStudyParagraphIsUntouched() {
    let spoken = """
        alright so for the Bible study tonight we are in John chapter 3 verse 16, for God so \
        loved the world that he gave his only begotten son, and I want to talk about what \
        that means for us today, because a lot of people read that verse a hundred times \
        and never actually stop to think about it
        """
    #expect(MathSpeech.convert(spoken) == spoken)
}

/// David's real 2026-09-21 dictation, the one that exposed the parity gap: the physics
/// converts and the thinking-out-loud around it does not.
@Test func davidsSuvatDictationConvertsOnlyItsEquations() {
    let spoken = "I'm going to think this out loud. So for the first person, the first "
        + "runner, that is going at 6 meters per second, to find the suvet, we're just "
        + "going to use S equals U plus V divided by 2 times T. Basically, since the "
        + "initial and final velocities are both 6, it would be 12 over 2T equals 400. "
        + "So 400 divided by 6 equals 66.66 recurring seconds, which then equals to T."
    let expected = "I'm going to think this out loud. So for the first person, the first "
        + "runner, that is going at 6 meters per second, to find the suvet, we're just "
        + "going to use S = U + V ÷ 2 · T. Basically, since the "
        + "initial and final velocities are both 6, it would be 12 ÷ 2T = 400. "
        + "So 400 ÷ 6 = 66.66 recurring seconds, which then equals to T."
    #expect(MathSpeech.convert(spoken) == expected)
}

@Test func scriptTablesArePaired() {
    // Every character that can be super/subscripted must have exactly one mapping.
    #expect(MathScript.superscript("2") == "²")
    #expect(MathScript.subscriptText("n") == "ₙ")
    #expect(MathScript.superscript("n+1") == "ⁿ⁺¹")
    #expect(MathScript.subscriptText("b") == nil)       // no Unicode subscript b
    #expect(MathScript.superscript("q") == nil)         // no Unicode superscript q
    #expect(MathScript.attach("x", "b", superscript: false) == "x_b")
    #expect(MathScript.attach("lim", "x→0", superscript: false) == "lim_(x→0)")
    #expect(MathScript.attach("e", "iπ", superscript: true) == "e^(iπ)")
}

@Test func vocabularyNeverShadowsAConstructTheEngineParses() {
    #expect(!MathSymbols.reservedPhrases.isEmpty)
    for reserved in MathSymbols.reservedPhrases {
        #expect(MathSymbols.phrases[reserved] == nil,
                "\(reserved) is parsed structurally by MathSpeech — it must not be a vocabulary key")
    }
}
#endif
