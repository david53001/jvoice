#if canImport(Testing)
import Testing
@testable import JVoice

/// The SPEC for spoken-mathematics conversion — the Swift side of the Windows port's
/// `MathSpeechTests.cs`, case for case.
///
/// `converts` is what the feature must produce; `leavesAlone` is the half that matters
/// more — ordinary talking has to come back byte-identical. Both lists are the contract
/// every later change to `MathSymbols`, `SpokenNumbers` or `MathSpeech` has to keep green.
///
/// Since 2026-09-29 the expected OUTPUT follows the shared notation format
/// (`docs/math-notation-format.md`: "/" fractions, × vs juxtaposition, "sin θ"), so the
/// conversion cases no longer match the Windows `MathSpeechTests.cs` symbol for symbol until
/// the Windows engine mirrors the change (list in `docs/math-notation-progress.md`).

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
    ("3 over 4 plus 1 over 4 equals 1", "3/4 + 1/4 = 1"),
    ("n factorial equals 120", "n! = 120"),
    // ── spoken numbers ──
    ("x equals twenty five", "x = 25"),
    ("three point one four times r squared", "3.14r²"),
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
    ("pi times r squared", "πr²"),
    ("x is an element of the reals", "x ∈ ℝ"),
    // ── big operators, calculus ──
    ("the sum from n equals 1 to infinity of 1 over n squared", "the ∑ₙ₌₁^∞ 1/n²"),
    ("the integral from 0 to 1 of x squared dx", "the ∫₀¹ x² dx"),
    ("the derivative of y with respect to x", "the dy/dx"),
    ("the partial derivative of f with respect to x equals 0", "the ∂f/∂x = 0"),
    ("the limit as x approaches 0 of sine of x over x equals 1", "the lim_(x→0) (sin x)/x = 1"),
    // ── powers spoken the short way, logs, combinatorics ──
    ("e to the x plus 1", "eˣ + 1"),
    ("2 to the 10 equals 1024", "2¹⁰ = 1024"),
    ("log base 2 of x equals 5", "log₂x = 5"),
    ("n choose k equals 10", "C(n, k) = 10"),
    ("x equals the square root of 2", "x = √2"),
    ("the absolute value of x equals 5", "the |x| = 5"),
    ("the integral from 0 to the square root of 2 of x dx", "the ∫₀^(√2) x dx"),
    // ── textbook shapes ──
    ("the sum from i equals 1 to n of i equals n times n plus 1 over 2", "the ∑ᵢ₌₁ⁿ i = nn + 1/2"),
    ("sine squared theta plus cosine squared theta equals 1", "sin²θ + cos²θ = 1"),
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
    ("y equals cosine of theta", "y = cos θ"),
    // ── mathematics inside a sentence ──
    ("so basically x equals 5 and that's it", "so basically x = 5 and that's it"),
    ("the formula is a subscript n equals 2n, which is neat", "the formula is aₙ = 2n, which is neat"),
    ("x equals 5.", "x = 5."),
    // ── the 2026-08-30 batch ──
    ("3 times 4 equals 12", "3 × 4 = 12"),
    ("x equals 2 times y", "x = 2y"),
    ("a cross product b equals c", "a × b = c"),
    ("1 over 2 plus 1 over 3", "1/2 + 1/3"),
    ("22 over 7 is approximately pi", "22/7 ≈ π"),
    ("x over n equals 2", "x/n = 2"),
    ("x over y equals 2", "x/y = 2"),
    ("10 divided by 2 equals 5", "10 ÷ 2 = 5"),
    ("1 over n squared", "1/n²"),
    ("log base 2 of 8", "log₂8"),
    ("log base 10 of 1000 equals 3", "log₁₀1000 = 3"),
    ("log sub 2 of x", "log₂x"),
    ("so we take log base 2 of x and then move on", "so we take log₂x and then move on"),
    ("log base n of x equals 5", "logₙx = 5"),
    ("u n equals 1 plus 7n", "uₙ = 1 + 7n"),
    ("u 1 equals 70000", "u₁ = 70000"),
    ("u n plus 1 equals 2 u n", "uₙ + 1 = 2uₙ"),
    ("a n equals a 1 times r to the power of n", "aₙ = a₁rⁿ"),
    ("5000 parentheses open, 1 plus 1.03 over 100 parentheses close", "5000 (1 + 1.03/100)"),
    ("x equals open paren a plus b close paren times c", "x = (a + b)c"),
    // ── the 2026-09-23 package (bug-hunt fixes 1–6; diverges from Windows on grouping) ──
    ("x to the 3", "x³"),
    ("2 to the power of 10", "2¹⁰"),
    ("3 x 4 equals 12", "3 × 4 = 12"),
    ("26 x 26 x 26 equals 17,576", "26 × 26 × 26 = 17576"),
    ("the probability that X is less than or equal to 3 equals 0.65", "P(X ≤ 3) = 0.65"),
    ("1 over 52 choose 5", "1/C(52, 5)"),
    ("1 over n factorial", "1/n!"),
    ("n choose n minus k", "C(n, n - k)"),
    ("n plus k minus 1 choose k", "C(n + k - 1, k)"),
    ("n choose k equals n minus 1 choose k minus 1 plus n minus 1 choose k",
     "C(n, k) = C(n - 1, k - 1) + C(n - 1, k)"),
    ("10 times 9 times 8 over 3 times 2 times 1", "(10 × 9 × 8)/(3 × 2 × 1)"),
    ("n factorial over k factorial times n minus k factorial", "n!/(k!(n - k)!)"),
    ("the probability of A given B", "P(A ∣ B)"),
    ("P of X less than 3", "P(X < 3)"),
    ("f of n equals f of n minus 1 plus f of n minus 2", "f(n) = f(n - 1) + f(n - 2)"),
    ("10 to the fifth", "10⁵"),
    ("x to the third power", "x³"),
    ("x to the 3rd", "x³"),
    // ── the shared notation format (docs/math-notation-format.md §4, 2026-09-29) ──
    // "over" is a slash; a side holding a space/operator — or a juxtaposed denominator — is bracketed
    ("a plus b over 2", "a + b/2"),
    ("a plus b all over 2", "(a + b)/2"),
    ("pi over 6", "π/6"),
    ("a over b plus c over d", "a/b + c/d"),
    ("1 over x squared", "1/x²"),
    ("x squared minus 9 all over x minus 3", "(x² - 9)/(x - 3)"),
    ("12 over 2T equals 400", "12/(2T) = 400"),
    ("5 over 6 to the fourth", "(5/6)⁴"),
    ("1 minus the quantity 5 over 6 to the 4", "1 - (5/6)⁴"),
    // "times": × between numbers, juxtaposition between letter terms; · is the dot product
    ("a sub n equals a sub 1 plus n minus 1 times d", "aₙ = a₁ + (n - 1)d"),
    ("6 times 7 divided by 2", "6 × 7 ÷ 2"),
    ("x times 2 equals 10", "x × 2 = 10"),
    ("open paren x plus 1 close paren times 2 equals 4", "(x + 1) × 2 = 4"),
    ("26 choose 4 times 10 choose 3", "C(26, 4) × C(10, 3)"),
    ("the probability of B given A times the probability of A", "P(B ∣ A) × P(A)"),
    ("2 times sine x times cosine x equals 1", "2 sin x cos x = 1"),
    ("a dot b", "a · b"),
    // "divided by" is a fraction in algebra
    ("x divided by 2 y equals 1", "x/(2y) = 1"),
    ("x divided by y squared equals 1", "x/y² = 1"),
    // functions: brackets only for a multi-term argument; smallest reading unless "the quantity"
    ("sine squared theta", "sin²θ"),
    ("cosine 2 theta equals 1", "cos 2θ = 1"),
    ("sine of x plus 1 equals 2", "sin x + 1 = 2"),
    ("sine of the quantity x plus 1", "sin(x + 1)"),
    ("natural log of 2", "ln 2"),
    ("log base 3 of x plus 1", "log₃x + 1"),
    ("log base 3 of the quantity x plus 1", "log₃(x + 1)"),
    // roots: a radicand of more than one number/letter is bracketed
    ("the square root of 2 x equals 4", "the √(2x) = 4"),
    ("the square root of x plus 1", "the √x + 1"),
    ("the square root of the quantity b squared minus 4 a c", "the √(b² - 4ac)"),
    ("x equals negative b plus or minus the square root of the quantity b squared minus 4 a c all over 2 a",
     "x = (-b ± √(b² - 4ac))/(2a)"),
    // powers
    ("10 to the power of minus 3", "10⁻³"),
    ("e to the minus x squared", "e^(-x²)"),
    ("x to the quantity n plus 1", "xⁿ⁺¹"),
    // calculus & the rest
    ("d y by d x equals 3 x squared minus 4", "dy/dx = 3x² - 4"),
    ("d y d x", "dy/dx"),
    ("the double integral of f d y d x", "the ∬ f dy dx"),
    ("f prime of x equals 2 x plus 1", "f′(x) = 2x + 1"),
    ("f double prime of x equals 6 x", "f″(x) = 6x"),
    ("f inverse of x", "f⁻¹(x)"),
    ("5 factorial", "5!"),
    ("x tends to infinity", "x → ∞"),
    ("the limit as n tends to infinity of 1 over n equals 0", "the lim_(n→∞) 1/n = 0"),
    ("20 percent of 50 equals 10", "20% of 50 = 10"),
    ("angle A B C equals 90 degrees", "∠ABC = 90°"),
    // ── David's failed dictation, 2026-09-29: bare "root of", glued "Kx", "sigma of" ──
    ("K squared plus the root of K cubed times Kx squared sigma of 3.", "K² + √K³ × Kx² ∑ 3."),
    ("k squared plus the square root of k cubed times k x squared", "k² + √k³ × kx²"),
    ("x plus the root of 2", "x + √2"),
    ("the root of K cubed", "the √K³"),
    ("k squared times Kx squared", "k²Kx²"),
    // "sigma" is the SUM SIGN (David, 2026-09-29); the letter σ is "lowercase/small sigma"
    ("the sigma from i equals 1 to n of i", "the ∑ᵢ₌₁ⁿ i"),
    ("Sigma from k equals 0 to infinity of x to the k", "∑ₖ₌₀^∞ xᵏ"),
    ("small sigma equals 2", "σ = 2"),
    ("x equals lowercase sigma of 3", "x = σ(3)"),
    ("the limit as x approaches pi of sine x", "the lim_(x→π) sin x"),
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
    // the 2026-09-23 package's leak fixes (bug-hunt fixes 1 and 7)
    "I gave 5 to the 3 kids",
    "compared 2019 to the 2020 season it was better",
    "it went from 1990 to the 2000s",
    "y is 5 more than x",
    "we got 20 more than 15 last year",
    "I'm bringing a plus one",
    "he's a plus one at the wedding",
    "the infection rate is 5 per 100,000",
    "about 3 per 1000 births",
    // the 2026-09-29 format's new words stay words in ordinary speech
    "it's a 2 by 2 factorial design",
    "a 2 factorial design with 3 levels",
    "so that's 7 factorial which is a lot",
    "the quantity of water was 5 liters",
    "the quantity 3 was wrong",
    "type 2 tends to 3 times more often",
    "plan B tends to 5 percent of cases",
    "she tends to 3 patients every morning",
    "it was all over the news",
    "there were 20 all over 5 states",
    "the natural log cabin",
    "the prime minister of 3 countries",
    "the inverse of 5 is hard to explain",
    "I'm 100 percent of the way there",
    "20 percent of 50 people said yes",
    "dx dy is a nice dance",
    "section d y and d x",
    "it went from 5 to the minus 3 degrees",
    // bare "root of", "sigma of" and two-letter words (2026-09-29 fix)
    "the root of the problem",
    "the root of 3 problems",
    "root of all evil",
    "root for the team",
    "the root of our 3 main problems is time",
    "sigma of 3 people",
    "six sigma of 3 teams",
    "Six Sigma",
    "sigma male",
    "that's so sigma",
    "he is a sigma male with 3 cars",
    "our six sigma training took 5 days",
    "Sigma is a fraternity",
    "it was 2 plus ok",
    "he got 5 plus TV",
    "5 plus me",
    "3 times is enough",
    "7 times or so",
    "we need 5 plus AI tools",
    "my PC squared",
    "Ok squared away",
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
        x² - 5x + 6 = 0, which factors into (x - 2)(x - 3), so x = 2 \
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
        + "going to use S = U + V/2 × T. Basically, since the "
        + "initial and final velocities are both 6, it would be 12/(2T) = 400. "
        + "So 400 ÷ 6 = 66.66 recurring seconds, which then equals to T."
    #expect(MathSpeech.convert(spoken) == expected)
}

/// Dictation-level context (`MathContext`, 2026-10-04, docs/math-context-design.md): a Greek
/// name outside an equation becomes its letter only when the rest of the dictation is
/// mathematics or it sits in an anchor slot ("value of λ"), and no veto applies. Mirrors the
/// "a Greek name is decided by the whole dictation" section of scripts/run-logic-tests.sh.
private let contextPromotes: [(String, String)] = [
    ("find the value of lambda", "find the value of λ"),
    ("Solve for theta.", "Solve for θ."),
    ("Let lambda be 3.", "Let λ be 3."),
    ("Express your answer in terms of pi.", "Express your answer in terms of π."),
    ("Find the value of lambda. We know that 5 equals K and X equals 5.",
     "Find the value of λ. We know that 5 = K and X = 5."),
    ("Find lambda. Okay, never mind, I'll write it down later. Anyway, 5 equals K and X equals 5.",
     "Find λ. Okay, never mind, I'll write it down later. Anyway, 5 = K and X = 5."),
    ("The period is 2 pi, and x equals 3.", "The period is 2π, and x = 3."),
    ("Solve for theta in the interval from 0 to pi, where 2 x equals 1.",
     "Solve for θ in the interval from 0 to π, where 2x = 1."),
    ("Lambda is 5. Then x equals 2 lambda.", "λ is 5. Then x = 2λ."),
    ("x equals lamda", "x = λ"),
    ("the value of capital lambda", "the value of Λ"),
    ("lambda equals 5", "λ = 5"),
    // maths elsewhere, but this word is no letter
    ("Write a lambda function that returns x squared plus 1, and test it with x equals 5.",
     "Write a lambda function that returns x² + 1, and test it with x = 5."),
    ("I deployed it on AWS Lambda, and the cost is x equals 5 cents per call.",
     "I deployed it on AWS Lambda, and the cost is x = 5 cents per call."),
    ("Alpha decay reduces the mass number by 4, so A equals 238 minus 4.",
     "Alpha decay reduces the mass number by 4, so A = 238 - 4."),
    ("My Omega watch says 5 o'clock, and question 3 is x plus 2 equals 7.",
     "My Omega watch says 5 o'clock, and question 3 is x + 2 = 7."),
    ("The plan costs 2 plus 1 free months, theta.", "The plan costs 2 + 1 free months, theta."),
    ("I'm taking omega 3 and x equals 5.", "I'm taking omega 3 and x = 5."),
    ("We joined Lambda Chi Alpha, x equals 2.", "We joined Lambda Chi Alpha, x = 2."),
    ("That's a big delta, and x equals 5.", "That's a big delta, and x = 5."),
    ("we had pi on pi day, x equals 3", "we had pi on pi day, x = 3"),
    ("say \"lowercase sigma\", and x equals 5", "say \"lowercase sigma\", and x = 5"),
    // "pie": whisper's spelling of pi, only between a number and a single letter (run-only)
    ("C equals 2 pie r", "C = 2πr"),
    ("C equals 2 pie, r", "C = 2 pie, r"),
    ("x equals 2 pie a", "x = 2 pie a"),
]

private let contextLeavesAlone: [String] = [
    "lambda", "Lambda.", "theta", "pi", "lambda is 5",
    "Lambda, the pie is really tasty.",
    "Lambda. Anyway, the pie is really tasty, you should try it.",
    "Hey lambda, come here, good girl.",
    "I paid 5 for the pie and the lambda function costs 0.2 cents.",
    "Is it Lambda or Lamda? I can never remember the spelling.",
    "The lambda function costs 0.2 cents and runs 3 times a day.",
    "Lambda, theta, sigma, these are all just names of fraternities in the movies.",
    "My uncle wears an Omega watch and I take omega 3 every morning.",
    "I signed up to be a beta tester and the alpha release is out.",
    "Happy Pi Day, I'm getting a pie after school.",
    "solve for pi day",
    "2 pie r", "I ate 2 pie r slices", "I paid 5 pie I think", "a pie chart and 2 pies",
]

@Test func greekNamesAreDecidedByTheWholeDictation() {
    for (spoken, expected) in contextPromotes {
        #expect(MathSpeech.convert(spoken) == expected, "\(spoken)")
        #expect(MathSpeech.convert(expected) == expected, "idempotent: \(spoken)")
    }
    for prose in contextLeavesAlone {
        #expect(MathSpeech.convert(prose) == prose, "\(prose)")
    }
    for runOnly in ["delta", "sigma", "eta", "iota", "kappa", "nu", "xi", "omicron", "psi", "big delta"] {
        #expect(!MathContext.promotable.contains(runOnly), "\(runOnly) must stay run-only")
    }
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
