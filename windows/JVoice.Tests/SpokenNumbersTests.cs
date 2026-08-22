using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

/// The spec for the spoken-number parser behind <see cref="MathSpeech"/> (§7 #47).
///
/// Two things are being locked here, and the second one matters more:
///   • the DIGITS — every magnitude, the connective "and", decimals, ordinals;
///   • the CONSUMED count — how many of the caller's words vanish into the number. The
///     caller owns the token stream, so a count that is one too large silently eats the
///     user's speech ("five and my friend" must never swallow the "and").
///
/// The end-to-end block at the bottom proves both halves through the real engine: numbers
/// land correctly in equations, and prose that merely mentions numbers comes back the very
/// same string instance.
public class SpokenNumbersTests
{
    private static string[] Words(string spoken)
        => spoken.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    private static (string Digits, int Consumed)? Read(string spoken)
        => SpokenNumbers.TryRead(Words(spoken), 0);

    // ===== cardinals =====

    [Theory]
    // units, teens, tens
    [InlineData("zero", "0")]
    [InlineData("one", "1")]
    [InlineData("nine", "9")]
    [InlineData("ten", "10")]
    [InlineData("eleven", "11")]
    [InlineData("nineteen", "19")]
    [InlineData("twenty", "20")]
    [InlineData("ninety", "90")]
    // compounds, spaced and hyphenated — whisper writes both
    [InlineData("twenty five", "25")]
    [InlineData("twenty-five", "25")]
    [InlineData("forty two", "42")]
    [InlineData("ninety nine", "99")]
    // hundreds
    [InlineData("hundred", "100")]
    [InlineData("one hundred", "100")]
    [InlineData("a hundred", "100")]
    [InlineData("three hundred", "300")]
    [InlineData("nine hundred ninety nine", "999")]
    // the spoken connective "and"
    [InlineData("one hundred and five", "105")]
    [InlineData("one hundred five", "105")]
    [InlineData("a hundred and one", "101")]
    [InlineData("two hundred and fifty six", "256")]
    [InlineData("two thousand and five", "2005")]
    // thousands and beyond
    [InlineData("one thousand", "1000")]
    [InlineData("a thousand", "1000")]
    [InlineData("thousand", "1000")]
    [InlineData("seven hundred thousand", "700000")]
    [InlineData("twenty three thousand four hundred and fifty six", "23456")]
    [InlineData("five hundred and twenty three thousand", "523000")]
    [InlineData("two million", "2000000")]
    [InlineData("two million five hundred thousand", "2500000")]
    [InlineData("three billion", "3000000000")]
    [InlineData("one trillion", "1000000000000")]
    // decimals — the digits after "point" are spoken one at a time
    [InlineData("three point one four", "3.14")]
    [InlineData("zero point five", "0.5")]
    [InlineData("zero point zero one", "0.01")]
    [InlineData("one point two five", "1.25")]
    [InlineData("two point five million", "2500000")]
    // already numeric as transcribed
    [InlineData("7", "7")]
    [InlineData("0", "0")]
    [InlineData("3.14", "3.14")]
    [InlineData("1,000", "1000")]
    [InlineData("1,234,567", "1234567")]
    [InlineData("1000000", "1000000")]
    [InlineData("3 million", "3000000")]
    public void Reads(string spoken, string digits)
        => Assert.Equal(digits, Read(spoken)?.Digits);

    /// "nineteen eighty four" is NOT read as the year 1984: a teens value cannot be extended
    /// by a tens value, so the number ends and "eighty four" is a second number. Year reading
    /// needs context this parser does not have, and it could only ever fire inside an
    /// equation — where two spoken groups do not mean a year. Prose is untouched either way
    /// (see <see cref="LeavesProseByteIdentical"/>).
    [Fact]
    public void YearsReadAsTwoNumbers_NotAsAYear()
    {
        Assert.Equal(("19", 1), Read("nineteen eighty four"));
        Assert.Equal(("84", 2), SpokenNumbers.TryRead(Words("nineteen eighty four"), 1));
    }

    // ===== consumption: the number must end exactly where the speech does =====

    [Theory]
    [InlineData("five apples", 1)]
    [InlineData("twenty five apples", 2)]
    [InlineData("twenty-five apples", 1)]               // one hyphenated token
    [InlineData("a hundred people", 2)]
    [InlineData("one hundred and five apples", 4)]
    [InlineData("three point one four times r squared", 4)]
    [InlineData("two point five million dollars", 4)]
    [InlineData("3 million dollars", 2)]
    [InlineData("7 apples", 1)]
    public void ConsumesExactly(string spoken, int consumed)
        => Assert.Equal(consumed, Read(spoken)?.Consumed);

    /// "and" belongs to the number only when it joins a sub-hundred tail onto a magnitude.
    [Theory]
    [InlineData("five and I left", 1)]
    [InlineData("seven and made coffee", 1)]
    [InlineData("one hundred and my friend", 2)]
    [InlineData("one hundred and", 2)]
    [InlineData("one hundred and two hundred", 2)]      // the tail starts a NEW number
    public void NeverEatsAnOrdinaryAnd(string spoken, int consumed)
        => Assert.Equal(consumed, Read(spoken)?.Consumed);

    /// "point" is a decimal point only when spoken digits follow it.
    [Theory]
    [InlineData("three point fourteen", "3", 1)]        // digits after a point are read singly
    [InlineData("five point of order", "5", 1)]
    [InlineData("nine point", "9", 1)]
    public void NeverEatsAnOrdinaryPoint(string spoken, string digits, int consumed)
        => Assert.Equal((digits, consumed), Read(spoken));

    [Fact]
    public void ReadsAtAnyIndex_AndNeverPastTheEnd()
    {
        var words = Words("x equals twenty five point five");
        var read = SpokenNumbers.TryRead(words, 2);
        Assert.Equal(("25.5", 4), read);
        Assert.True(2 + read!.Value.Consumed <= words.Length);
    }

    // ===== not a number =====

    [Theory]
    [InlineData("hello world")]
    [InlineData("and five")]                            // "and" can never START a number
    [InlineData("point five")]                          // nor can a bare decimal point
    [InlineData("a minute")]                            // "a" is only an implicit one before a magnitude
    [InlineData("a lot of people")]
    [InlineData("five-year plan")]                      // a hyphenated token is all-or-nothing
    [InlineData("-")]
    [InlineData("x")]
    public void NotANumber(string spoken)
        => Assert.Null(Read(spoken));

    [Fact]
    public void OutOfRangeAndEmptyInputAreNull()
    {
        var words = Words("twenty five");
        Assert.Null(SpokenNumbers.TryRead(words, -1));
        Assert.Null(SpokenNumbers.TryRead(words, 2));
        Assert.Null(SpokenNumbers.TryRead(Array.Empty<string>(), 0));
        Assert.Null(SpokenNumbers.TryReadOrdinal(Array.Empty<string>(), 0));
        Assert.Null(SpokenNumbers.TryReadFraction(Array.Empty<string>(), 0));
    }

    // ===== IsDigits =====

    [Theory]
    [InlineData("7")]
    [InlineData("0")]
    [InlineData("3.14")]
    [InlineData("1,000")]
    [InlineData("1000000")]
    public void IsDigits_AcceptsTranscribedNumbers(string word)
        => Assert.True(SpokenNumbers.IsDigits(word));

    [Theory]
    [InlineData("")]
    [InlineData("seven")]
    [InlineData("7n")]                                  // a coefficient, handled by the engine
    [InlineData("-5")]                                  // "negative" is a prefix symbol, not a digit
    [InlineData("1st")]
    [InlineData(".")]
    [InlineData("x")]
    public void IsDigits_RejectsEverythingElse(string word)
        => Assert.False(SpokenNumbers.IsDigits(word));

    // ===== ordinals =====

    [Theory]
    [InlineData("first", "1")]
    [InlineData("second", "2")]
    [InlineData("third", "3")]
    [InlineData("fourth", "4")]
    [InlineData("fifth", "5")]
    [InlineData("ninth", "9")]
    [InlineData("twelfth", "12")]
    [InlineData("nineteenth", "19")]
    [InlineData("twentieth", "20")]
    [InlineData("thirtieth", "30")]
    [InlineData("ninetieth", "90")]
    [InlineData("hundredth", "100")]
    // numeric forms
    [InlineData("1st", "1")]
    [InlineData("2nd", "2")]
    [InlineData("3rd", "3")]
    [InlineData("4th", "4")]
    [InlineData("21st", "21")]
    [InlineData("11th", "11")]
    // a lettered degree stays a letter: "the nth root of x" → ⁿ√x
    [InlineData("nth", "n")]
    [InlineData("n-th", "n")]
    [InlineData("kth", "k")]
    public void ReadsOrdinals(string spoken, string degree)
        => Assert.Equal((degree, 1), SpokenNumbers.TryReadOrdinal(Words(spoken), 0));

    [Theory]
    [InlineData("twenty first", "21")]
    [InlineData("thirty second", "32")]
    [InlineData("ninety ninth", "99")]
    public void ReadsCompoundOrdinals(string spoken, string degree)
        => Assert.Equal((degree, 2), SpokenNumbers.TryReadOrdinal(Words(spoken), 0));

    [Fact]
    public void ReadsHyphenatedCompoundOrdinalsAsOneWord()
        => Assert.Equal(("21", 1), SpokenNumbers.TryReadOrdinal(Words("twenty-first"), 0));

    [Theory]
    [InlineData("root")]
    [InlineData("the")]
    [InlineData("one")]
    [InlineData("5")]
    [InlineData("th")]
    [InlineData("twenty")]                              // a bare tens word is a cardinal
    public void NotAnOrdinal(string spoken)
        => Assert.Null(SpokenNumbers.TryReadOrdinal(Words(spoken), 0));

    // ===== fractions (not wired into MathSpeech yet) =====

    [Theory]
    [InlineData("one half", "1/2", 2)]
    [InlineData("three quarters", "3/4", 2)]
    [InlineData("two thirds", "2/3", 2)]
    [InlineData("two-thirds", "2/3", 1)]
    [InlineData("five eighths", "5/8", 2)]
    [InlineData("twenty five hundredths", "25/100", 3)]
    public void ReadsFractions(string spoken, string fraction, int consumed)
        => Assert.Equal((fraction, consumed), SpokenNumbers.TryReadFraction(Words(spoken), 0));

    [Theory]
    [InlineData("half")]                                // no numerator
    [InlineData("a half")]                              // "a" is not an implicit one here
    [InlineData("two seconds")]                         // "second" is a duration far more often
    [InlineData("three point five thirds")]             // a decimal numerator is not speech
    [InlineData("two apples")]
    public void NotAFraction(string spoken)
        => Assert.Null(SpokenNumbers.TryReadFraction(Words(spoken), 0));

    // ===== end to end: the numbers land in real equations =====

    [Theory]
    [InlineData("x equals twenty five", "x = 25")]
    [InlineData("x equals twenty-five", "x = 25")]
    [InlineData("x equals one hundred and five", "x = 105")]
    [InlineData("two point five plus one point five equals four", "2.5 + 1.5 = 4")]
    [InlineData("n is greater than a thousand", "n > 1000")]
    [InlineData("x equals two point five million", "x = 2500000")]
    [InlineData("three point one four times r squared", "3.14 × r²")]
    [InlineData("x subscript twenty", "x₂₀")]
    [InlineData("the fifth root of 32", "the ⁵√32")]
    [InlineData("the twenty first root of x", "the ²¹√x")]
    public void ConvertsEquations(string spoken, string expected)
        => Assert.Equal(expected, MathSpeech.Convert(spoken));

    /// Prose that merely mentions numbers has to come back the very same string instance —
    /// a run that is nothing but a number never activates, so nothing is rewritten.
    [Theory]
    [InlineData("we had about twenty five people over for dinner")]
    [InlineData("he turned twenty one last week")]
    [InlineData("there were a hundred and five people in line")]
    [InlineData("it cost me a thousand dollars and some change")]
    [InlineData("the meeting is at three thirty in the afternoon")]
    [InlineData("nineteen eighty four was a good year")]
    [InlineData("she ate two thirds of the pizza")]
    [InlineData("give me five minutes and I'll call you back")]
    [InlineData("chapter twenty two verse one")]
    [InlineData("point taken but I still disagree")]
    [InlineData("at some point five people left the room")]
    [InlineData("a quarter of the students passed")]
    public void LeavesProseByteIdentical(string prose)
        => Assert.Same(prose, MathSpeech.Convert(prose));
}
