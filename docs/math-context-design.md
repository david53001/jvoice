# Maths context: design (2026-10-04)

- Branch: `feat/math-context`. Worktree: `.claude/worktrees/math-context`. Base: `feat/math-format` @ `90c6836`.
- Status: IMPLEMENTED 2026-10-04 on `feat/math-context` (not merged, not installed), then REVISED the
  same day after an adversarial verify found bleeds. **§9 is the current design; where §3 disagrees
  with §9, §9 wins.** The first implementation's three deviations are in `docs/math-context-progress.md`
  (entry "implemented"); the revision is the entry "adversarial verify".
- Progress log: `docs/math-context-progress.md`.

## 1. Goal and terms

David dictates his maths homework. When he is talking mathematics, a Greek-letter name ("lambda") should
come out as the letter (λ). In ordinary speech it should stay a word. Whether he is talking mathematics is
decided from the **whole dictation**:

- "Find the value of lambda. We know that 5 equals K and X equals 5." → `Find the value of λ. We know that 5 = K and X = 5.`
- "Lambda, the pie is really tasty." → unchanged.
- "lambda equals 5" → `λ = 5`. This works today and must keep working.

**Terms.** Engine files are in `Sources/JVoice/Services/Transcription/Math/`.

| Term | Meaning |
|---|---|
| Dictation | The text passed to one `MathSpeech.convert(_:)` call: one finished transcription, after the tone style has been applied (`VoiceCoordinator.swift:817`). |
| Tok | One word split on whitespace, stored as `lead + core + trail`, where lead and trail are its punctuation. |
| Item | The lexer's unit (`MathSpeech.Item`). It covers one or more tokens. |
| Run | A stretch of consecutive items that all lex as maths. Any ordinary word or any punctuation ends a run. |
| Segment | The part of a run consumed by one `Parser.run(pos)` call, which returns `(text, activated, used)`. |
| Activated | The segment contains a construct that makes it maths and has real operands, such as `=`, `+`, a script or a fraction. Today a segment is written as maths only if it is activated, or if it sits between "start equation" and "end equation" (a **forced** span). |
| Weak | An item that renders only inside an activated segment. Every Greek letter is weak today. |
| Candidate | A Greek item that context may promote (§3.1). |
| Promotion | Writing a candidate as its symbol although its segment did not activate. |

The test corpora are in `.build/math-context/`, which is gitignored. The progress log describes them.
`real.txt` and `prose.txt` contain personal text: **never commit them**.

## 2. Alternatives considered

1. **Lexical score** (count cue words and relations before parsing). Rejected: it never checks operands,
   so "2 plus 1 free months" or "Room 5 belongs to 3" would count as maths and trigger promotions.
2. **Per-sentence window.** Rejected: it fails David's own example, "Find lambda. Okay, never mind, I'll
   write it down later. Anyway, 5 equals K and X equals 5.", where the evidence is two sentences away.
3. **Position cues only** ("value of X", "solve for X", "X is"). Rejected as the main mechanism: "X is" is
   everyday English ("Lambda is down again"), and most real cases have no fixed slot. A tiny subset
   survives as **anchors**.
4. **ML classifier.** Rejected: model download, not deterministic, and it breaks the area brief's rule
   that the no-bleed guarantee is "structural, not a classifier".
5. **Chosen: a hybrid.** Evidence comes from the parser's `activated` flag (operands already checked)
   over the whole dictation, plus a letter-operand requirement that turns away every known numeric
   bleed; narrow anchors on top; every candidate passes collocation, casing and anti-cue vetoes.

**Contract.** A candidate becomes its symbol when all three hold:
- (a) the dictation has evidence, or the candidate sits in an anchor slot;
- (b) no veto applies;
- (c) its segment did not already convert.

Promotion only ever adds. It never activates anything, never changes an item that is not Greek, and never
touches a segment that already converted. When a dictation contains no candidate, `convert` follows
exactly today's code path and returns the same string.

## 3. Design

### 3.1 Candidates

An item is a candidate when:
- `kind == .symbol`, `sym.kind == .operand` and `Parser.isGreekLetter(sym.text)`; and
- its spoken phrase is in `MathContext.promotable`. The spoken phrase is the item's token cores,
  lowercased and joined with single spaces.

`promotable` contains:
- **Lower-case names:** alpha, beta, gamma, epsilon, varepsilon, zeta, theta, vartheta, lambda,
  **lamda** (new), mu, rho, varrho, tau, upsilon, phi, varphi, chi, omega, pi.
- **Small sigma:** "lowercase sigma", "small sigma", "lower case sigma".
- **Capitals:** "capital/big/uppercase X" for every Greek name. These are said deliberately, so they are
  unambiguous.

These stay **run-only** and are not candidates. They keep today's behaviour:

| Word | Why it is excluded |
|---|---|
| delta | Delta Airlines, river delta, "what's the delta", the Delta variant; δ vs Δ is also unsettled |
| bare sigma | parsed as ∑; also "sigma male" |
| eta | ETA (estimated time of arrival) |
| iota | "not one iota" |
| kappa | Twitch emote, Cohen's kappa |
| nu | sounds like "new" |
| xi | Xi Jinping |
| omicron | Covid variant |
| psi | the tyre-pressure unit ("32 PSI") |

### 3.2 Evidence (whole dictation, no distance limit)

The dictation has evidence when either of these holds.

**E1: a strong segment.** A segment was written as maths (`(activated || anyForced) && !text.isEmpty`)
and at least one of its items is a **letter operand**. A letter operand is either:
- an item with `kind == .variable && !weak`, which excludes "a", "A" and "i"; or
- a Greek operand whose token is not name-like (V1 below).

No known bleed counts: "2 + 1", "Room 5 ∈ 3", "5 ≥ 3 times", "version 2 · 1" and "the ∂5" have no
letter operand, and "the η = 5 minutes" comes from all-caps "ETA", which is name-like.

**E2: an anchor.** A candidate that is not vetoed sits in one of these slots. Words are compared
lowercased, and the whole slot must lie inside one stretch (defined in §3.3):

| Slot | Example |
|---|---|
| `value of ⟨C⟩` or `values of ⟨C⟩` | "value of lambda" |
| `solve for ⟨C⟩` | "solve for theta" |
| `in terms of ⟨C⟩` | "in terms of pi" |
| `let ⟨C⟩ be` (the next token is exactly "be") | "let lambda be 3" |
| `eigenvalue ⟨C⟩` or `eigenvalues ⟨C⟩` | "eigenvalues lambda" |

An anchor counts as evidence for the **whole** dictation.

**Scope: whole dictation.** David asked for it, his example crosses two sentences, and one press-to-talk
is usually short. Accepted cost: "Lambda, the pie is tasty. Also x equals 5." becomes `λ, …`. Cue words
(wavelength, Poisson…) are **not** evidence yet: the corpus does not need them and each rule is one more
way to bleed (§7).

### 3.3 Vetoes

Vetoes are checked for each candidate before anchors are considered.

**Stretch.** The stretch is the tokens around the candidate with no punctuation between them. Scanning
left, it stops when the previous token has a non-empty `trail`, or when the current token has a non-empty
`lead`. Scanning right, it stops after any token whose `trail` is non-empty.

Notation: `t` is the candidate's first token, `p` is the token before it, and `n` is the token after it.
The local checks (V2 to V4) use only tokens inside the stretch.

**V1, name-like casing.** The candidate is name-like when either:
- `core(t)` is all capitals and at least 2 letters long ("PI", "ETA"); or
- `core(t)` starts with an upper-case letter and `t` is **not sentence-initial**.

`t` is sentence-initial when `t == 0`, or `toks[t-1].trail` contains any of `. ? ! : ; …`, or
`toks[t].lead` is non-empty.
- Vetoed: "AWS Lambda", "my cat Pi".
- Allowed: "Lambda. Then …".

**V2, the word before.** `p` is one of: a, an, my, your, his, her, our, their, hey, aws, amazon, raspberry,
happy, tai.

**V3, the word after.** `n` is one of: function(s), expression(s), calculus, layer(s), handler(s), labs,
male(s), female, grindset, watch(es), seamaster, release(s), version(s), build(s), tester(s), test(s),
testing, ray(s), radiation, burst, decay, particle(s), blocker(s), carotene, centauri, wave(s), channel,
day, network, coin, fraternity, sorority.

**V4, the shape of what is next to it.** Any of these vetoes the candidate:
- `n` lexes as a `.number` ("omega 3");
- `n` is capitalised, longer than one letter, and not "I…" ("Lambda Labs", "Pi Day");
- the item directly next to the candidate, inside the stretch, is any Greek item ("Lambda Chi Alpha",
  "Phi Beta Kappa").

**V5, dictation-wide anti-cues.** These match any token core anywhere in the dictation, lowercased:

| Letter | Anti-cue words |
|---|---|
| all letters | fraternity, fraternities, sorority, sororities, frat |
| lambda / lamda | aws, amazon, serverless, deploy, deployed, deploying, deployment, python, javascript, typescript, java, api, endpoint, lambdas |
| pi | raspberry, arduino |
| alpha / beta | release, released, tester, testers, testing, version, versions, male, males, centauri, alphago, alphafold |
| gamma | radiation, rays, hulk |
| omega | watch, seamaster, fatty, oil |
| chi | tai, qi |

Capital forms ("capital lambda") are checked against V1 only, on their first token.

All of these lists live in `MathContext.swift` as `Set<String>`. Tuning should only mean editing them.

### 3.4 What promotion writes

These rules apply to a segment that did not convert and that contains a candidate:

1. **Whole-segment splice.** If every item in the segment is either a passing candidate or a `.number`,
   and there is at least one candidate, splice the segment in exactly as an activated one would be:
   `toks[from].lead + text + toks[to-1].trail`.
   - "2 pi," → `2π,`
   - "Lambda." → `λ.`
2. **Item by item.** Otherwise, replace only each passing candidate's tokens with `sym.text`, keeping the
   lead of its first token and the trail of its last. The rest of the segment stays exactly as dictated.
   - "lambda of the matrix" → `λ of the matrix`
   - "from 0 to pi" → `from 0 to π`
3. **Words with `used == 0`.** A candidate copied out verbatim because `used == 0` is handled by rule 2.

When anything is promoted, set `changed = true`. Any conversion already re-joins the parts with single
spaces; promotion does the same.

### 3.5 Decisions

| Case | Decision | Reason |
|---|---|---|
| "lambda is 5" on its own | **unchanged** | "is" is not an equation, and "my dog Lambda is 5" is ordinary English. With other maths nearby it converts: "Lambda is 5. Then x equals 2 lambda." → `λ is 5. Then x = 2λ.` |
| "let lambda be 3" on its own | **`let λ be 3`** | The anchor is an unmistakable maths idiom. |
| "find the value of lambda" on its own | **`find the value of λ`** | Anchor. This is the case from David's screenshot. |
| "Lambda" at sentence start | **λ** (lower case) | Tone styles capitalise first words; activated runs already map "Lambda" → λ. Λ needs "capital lambda". Mid-sentence "Lambda" is a name (V1). |
| "lamda" (a Whisper misspelling) | **new weak alias**, promotable | `greek("λ", "Λ", "lambda", "lamda")`. Adding weak kinds is allowed under invariant 4. |
| "pie" | **run-only, never promoted** | Lexes as weak π only between a number (digits or one number word) and a single Latin letter other than a/A/I, with no punctuation: "C equals 2 pie r" → `C = 2πr`; "2 pie r" alone, "pie chart", "a pie" unchanged. Own commit; drop it if a sweep shows a bleed. |
| row, new, fee, sigh, tow, data, why, ex, sign | never | They are homophones of ordinary words. |
| "Delta x" → Δx; existing prefix and relation bleeds | out of scope | See §7. E1's letter-operand rule already stops these from counting as evidence. |

## 4. Implementation

Paths are relative to `Sources/JVoice/Services/Transcription/Math/`. `scripts/build-math-probe.sh`
compiles every `Math/*.swift` file, so a new file there needs no build changes.

1. **New file `MathContext.swift`.** Add `enum MathContext` with pure static data and functions:
   - `promotable`, the V2/V3/V5 sets, the anchor checks, `nameLike(core:sentenceInitial:)`, and
     `dictationVetoes(cores:) -> Set<String>` (the letter names that V5 blocks);
   - pass it only `String`s and `Bool`s, because `Item` and `Tok` are private to `MathSpeech`.
2. **`MathSymbols.swift`, line 362.** Add `"lamda"` to the λ `greek(...)` call. Change nothing else.
3. **`MathSpeech.convert`, lines 55–93.**
   - After `lex`, compute `contextOn = items.contains(where: isCandidate)`.
   - Pass `contextOn` to `Emitter`.
   - After the last `flush`, call `emitter.promote()` only if `contextOn` is true.
4. **`MathSpeech.lex`, the "pie" rule.** Put it before the fallback that turns an item into a word.
   Produce the same weak π item that "pi" produces.
5. **`Emitter`, lines 581–636.**
   - **New state.** Add `evidence: Bool` and `pending: [Pending]`, where
     `Pending = (partIndex, partCount, segmentText?, candidates: [(tokFrom, tokTo, sym, name)])`.
   - **Branch that writes maths.** If `contextOn` is true and the slice `buf[pos..<pos+used]` contains a
     letter operand, set `evidence = true`.
   - **Both verbatim branches** (not activated, and `used == 0`). If `contextOn` is true and the slice
     contains a candidate:
     - record `partIndex = parts.count` before calling `verbatim`, and `partCount = toTok - fromTok`;
     - set `segmentText` only when the slice qualifies for §3.4 rule 1;
     - record every candidate in the slice;
     - if a candidate sits in an anchor slot, set `evidence = true`.
   - **`promote()`.**
     1. Compute the V5 set once.
     2. If `evidence` is false, return.
     3. Walk `pending` in **reverse**, so earlier part indices stay valid. For each entry, remove the
        vetoed candidates, then splice the whole segment with `replaceSubrange` (rule 1) or replace each
        candidate's parts (rule 2).
     4. Set `changed = true` if anything was replaced.
6. **Unchanged:** `Parser`, `MathSymbol.activates` and every activation rule.

**Cost.** Toggle off: nothing runs. No candidate: one `contains` pass over the items; the same string is
returned. With candidates: O(segments) bookkeeping + one O(tokens) V5 pass + O(1) per candidate, no
re-parse. Candidates without evidence, or all vetoed: byte identical.

## 5. Brief and spec wording (same commit as the code)

**`Sources/JVoice/Services/Transcription/CLAUDE.md`, invariant 4.** Add after its first sentence:

> The single exception is **dictation-level context promotion** (`Math/MathContext.swift`,
> `docs/math-context-design.md`): a curated set of Greek-letter names (never delta, bare sigma, eta, iota,
> kappa, nu, xi, omicron, psi) may render outside an activated run, only when the dictation holds evidence
> (a converted segment with a letter operand, or an anchor such as "value of λ") and every veto passes.
> It never activates anything; with no candidate word the output is byte identical. Changes to the set,
> anchors or vetoes must be swept against `.build/math-context/everyday.txt` (0 new changed lines) and the
> S/M rows of `context.tsv`.

**The same file, `Math/` bullet.**
- Change "When nothing activates, `convert` returns the input unchanged" to end with "unless context
  promotion applies".
- Add `MathContext.swift` to the file list.

**`docs/math-notation-format.md` §6.** Add one line: a Greek name outside an equation becomes its letter
only through context promotion.

## 6. Windows mirror (`windows/JVoice.Core/Math/`, cannot be built on this Mac)

1. **New file `MathContext.cs`.** Add a `static class MathContext` that mirrors §4 step 1. Windows still maps
   bare "sigma" to σ (`MathSymbols.cs:363`), so do **not** add "sigma" to its promotable set.
2. **`MathSymbols.cs`, about line 357.** Change the λ line to `Greek("λ", "Λ", "lambda", "lamda");`.
3. **`MathSpeech.cs`.**
   - `Convert` (lines 47–85): compute `contextOn`, and call `emitter.Promote()` after the last `Flush`.
   - `Emitter` (from line 369): add `Evidence` and the pending list.
   - `Flush` (lines 381–414): record pending entries in both the `used == 0` branch and the
     `else Verbatim` branch.
   - Lexer: add the pie rule.
4. **`windows/JVoice.Tests/MathSpeechTests.cs`.** Port the assertions from §8 item 5.
5. **`windows/JVoice.Core/Math/CLAUDE.md`.** Add the exception paragraph from §5 under "The one hard
   requirement".

The Windows engine lags macOS (`docs/math-notation-progress.md`), so its outputs may differ outside the
Greek word. Log the mirror as pending.

## 7. Limitations and follow-ups (not part of this feature)

- `real.txt` line 38 (a casual remark that mentions lambda) has no evidence and stays a word. A later fix:
  cue-word evidence (two or more of wavelength, eigenvalue, decay constant, Poisson, quadratic, radians),
  added only after a sweep.
- Talk about the feature itself is promoted when it contains a spoken equation (`real.txt` line 33 before
  conversion); V1 protects a capitalised mid-sentence "Lambda".
- "lambda 1 and lambda 2" stays as words outside a run (V4 number veto).
- Existing bleeds to fix separately: all-caps ETA → η in a run; bare partial/gradient/del/radical and
  "integral" + number; "dot" between numbers; "at least", "belongs to", "is a factor of" with numbers;
  "the angle 5"; "AWS lambda equals 5". "Delta x" should print Δx.

## 8. Acceptance bar

**Build the probe:**

```
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk scripts/build-math-probe.sh .build/math-context/probe-new
```

**Sweep each corpus** with `probe-new < .build/math-context/<corpus>.txt`, then diff against
`baseline-<corpus>.out`.

1. **`everyday.txt`:** 0 new CHANGED lines. Expected, because only 2 everyday lines carry any converted
   segment, and neither contains a candidate.
2. **`context.tsv`:** at least 131/137 exact (≥95%). The S, M and K rows must all match. Log every P or
   C miss with its reason.
3. **`prose.txt` and `real.txt`:** list and justify every line that differs from baseline. Expect at most
   1 in prose, the line that quotes the feature. Expect 0 in real, because its equations are already
   symbols and "=" is not spoken.
4. **`math.txt`:** review every changed line. Only Greek words should change.
5. **Logic tests:** run
   `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk scripts/run-logic-tests.sh`.
   - All 1123 existing tests must still pass.
   - Add these cases to `Tests/JVoiceTests/MathSpeechTests.swift`:
     - **Promote:**
       - "find the value of lambda" → `find the value of λ`
       - "Solve for theta." → `Solve for θ.`
       - "Let lambda be 3." → `Let λ be 3.`
       - "Express your answer in terms of pi." → `Express your answer in terms of π.`
       - "Find the value of lambda. We know that 5 equals K and X equals 5." and "Find lambda. Okay, never
         mind, I'll write it down later. Anyway, 5 equals K and X equals 5." (expected outputs: `context.tsv`)
       - "The period is 2 pi, and x equals 3." → `The period is 2π, and x = 3.`
       - "x equals lamda" → `x = λ`
       - "C equals 2 pie r" → `C = 2πr`
     - **Identical** (`convert(s) == s`): "lambda", "Lambda.", "lambda is 5", "Lambda, the pie is really
       tasty.", "Hey lambda, come here, good girl.", "I paid 5 for the pie and the lambda function costs
       0.2 cents.", "2 pie r", "Is it Lambda or Lamda? I can never remember the spelling."
     - **Maths elsewhere, word kept:**
       - "Write a lambda function that returns x squared plus 1, and test it with x equals 5." →
         `Write a lambda function that returns x² + 1, and test it with x = 5.`
       - "I deployed it on AWS Lambda, and the cost is x equals 5 cents per call." →
         `I deployed it on AWS Lambda, and the cost is x = 5 cents per call.`
       - "Alpha decay reduces the mass number by 4, so A equals 238 minus 4." →
         `Alpha decay reduces the mass number by 4, so A = 238 - 4.`
       - "My Omega watch says 5 o'clock, and question 3 is x plus 2 equals 7." →
         `My Omega watch says 5 o'clock, and question 3 is x + 2 = 7.`
       - "The plan costs 2 plus 1 free months, theta." → `The plan costs 2 + 1 free months, theta.`
         Here numbers alone are not evidence.
6. **Timing.** Build a 10,000-line file from `math.txt` and `everyday.txt` repeated. Time each probe 3×
   with `/usr/bin/time`. The median for `probe-new` must be within 5% or 5 ms of `probe-baseline`,
   whichever is larger.
7. **Rules.**
   - Never run `swift test`.
   - Never commit `.build/`.
   - Update `docs/math-context-progress.md` after each stage.

## 9. Revision after the adversarial verify (2026-10-04)

Verifiers fed the first implementation ordinary sentences and found 12 bleed patterns (for example "In
terms of beta access, …" → `In terms of β access`, "T minus 10 … still in beta" → `still in β`, "venture
capital beta round" → `venture Β round`). The no-bleed guarantee outranks recall, so the design changed
as follows. Code: `Math/MathContext.swift` (word lists, checks) and `MathSpeech.Emitter` (`flush`,
`promote`, `rendering`, `juxtapose`).

**Terms used here.** *Stretch*: the words around a name with no punctuation between them (§3.3).
*Sentence*: the words between two `.`, `?` or `!`.

### 9.1 Evidence (replaces §3.2 E1)

A converted segment is evidence only when it has **both**:
- a letter operand: a real variable (not `a`/`A`/`i`), a Greek letter not written like a name, an
  accented letter (`x̄`) or a derivative (`dy/dx`); and
- a real construct: a relation, a function, a power or script keyword, a root, a fraction, a
  derivative, a limit, an absolute value, "choose", a big operator, a factorial. A bare `+`, `-` or `×`
  is not one. Forced spans ("start equation … end equation") need only the letter.

So "T minus 10", "press X plus Y", "hold R 1 plus X", "n plus 1 tickets" and "w times h" are no
longer evidence. Evidence still promotes every passing name in the dictation.

### 9.2 Anchors (replaces §3.2 E2)

An anchor promotes **its own letter** (every passing occurrence of it in the dictation) and every
passing name **in its own sentence**. It is never evidence for the rest of the dictation. Slots:

| Slot | Extra condition |
|---|---|
| `value(s) of ⟨C⟩` | a command word earlier in the stretch: find, calculate, determine, state, deduce, hence, evaluate, compute, obtain, write, show, substitute |
| `solve for ⟨C⟩` | none |
| `in terms of ⟨C⟩` | ⟨C⟩ ends the sentence, and the stretch has "answer(s)"/"exact", or "express" + one letter/name ("Express y in terms of θ.") |
| `let ⟨C⟩ be/equal(s) N` | N is a number that ends the clause (punctuation, the end, or and/so/then/where/when/if/since/because) |
| `express ⟨C⟩ in terms of` | none |
| command clause | the stretch is only 1–2 command words + ⟨C⟩, starts a clause, and ⟨C⟩ ends the sentence: "Find λ.", "Hence find θ." |
| cue noun | the word before is angle(s), wavelength(s), eigenvalue(s) or constant |
| trig | the item before is a sine/cosine/tangent/secant/cosecant/cotangent function, or the bare word tan/sin/cos when a command word precedes and ⟨C⟩ ends the sentence ("find tan θ.") |
| deliberate capital | "capital/uppercase ⟨X⟩" that passed its vetoes |

A pair of names ("value of lambda mu") shares the first name's slot.

### 9.3 Vetoes (changes to §3.3)

- **V2 (word before)** also: the, this, these, those, in, absolute, closed, open, early, public,
  private, stock, portfolio, say, says, said; and a number that follows a label word ("room 1 alpha",
  "question 2 alpha"; label words: question, part, page, problem, room, level, version, …).
- **V3 (word after) is now an allowlist** (`MathContext.continuation`): an ordinary word right after a
  name must be one of the connectives, verbs, prepositions, units and maths words in that list (is,
  and, of, in, where, satisfies, doubles, radians, above, cos, …). Anything else makes the name a
  compound noun ("alpha team", "beta keys", "lambda sensor", "omega sale"). The same check applies to
  the word after a number that follows the name ("alpha 2 builds").
- **V4**: "Greek beside Greek" is no longer a name when the group is exactly two curated lower-case
  names ("alpha beta" → `αβ`, a product of roots). Groups of three, groups with a run-only or
  capitalised name ("Lambda Chi Alpha", "phi beta kappa") stay names. The number rule is lifted for an
  **indexed family**: the same letter followed by at least two different indices from 0, 1, 2 and no
  other number ("lambda 1 and lambda 2" → `λ₁`, `λ₂`; "omega 3 and omega 6" stays).
- **V5** dropped "testing", "released", "version(s)", "male(s)", "watch", "rays", "radiation": they are
  ordinary IB words, and V3 already catches "alpha release", "Omega watch", "gamma rays". V5 added:
  finance words for every letter (stock, portfolio, options, hedge, fund, investor, trading, equity,
  venture, earnings, market, shares…), "call sign"/"callsign" (two-word cues are matched), and
  per-letter cues (alpha/beta: game, discord, steam, climbing, fish, gym, wolf, squad…; lambda:
  sensor, probe, engine, logo…; omega: supplements, sale…; chi: yoga, energy; mu: cow; tau: protein,
  brain; theta: healing; epsilon: brand, coffee).
- **Mentions**: a square bracket, a dash token beside the name, or a colon right after it ("Alpha: the
  first letter") vetoes it, like a quotation mark.
- **Deliberate capitals** now pass every veto (V1–V5), and the word before "capital"/"uppercase" must be
  absent or in `capitalBefore` (is, of, and, find, where, let, equals, …): "venture capital beta",
  "at capital alpha partners" stay.
- **"big X" is removed** from the promotable set ("big alpha energy", "big pi slice").
- **Capital after a comma**: a name vetoed only by its capital, right after a comma, stays a word but
  no longer blocks its letter for the whole dictation ("Find the value of lambda, Lambda is the
  wavelength" → `λ, Lambda is …`).
- **Broken equation**: when a run leaves a relation as words (past its first item — "given that θ"
  opens a clause), no name in that stretch is promoted ("theta equals pie over 2" before the pie fix,
  "sine 2 theta equals cos theta" stay words rather than half-converting).

### 9.4 What promotion writes (replaces §3.4)

Each maximal stretch of passing names, numbers, real letters (not `a`/`A`/`i`) and functions inside an
unconverted segment that holds a passing name is written as one product (`Emitter.juxtapose`): factors
side by side ("2 pi r" → `2πr`, "rho g h" → `ρgh`, "mu m g" → `μmg`, "alpha beta" → `αβ`), a function
followed by a space ("sine theta" → `sin θ`), an indexed name with a subscript ("lambda 1" → `λ₁`). A
leading number after a label word is left out ("question 2 lambda"). When the stretch is not a product
(a number after a letter, a function at the end), only the names' own words are replaced. The parser is
not used here because its sequence-term rule reads "mu m" as `μₘ`.

### 9.5 "pie" (changes §3.5)

"pie" is the weak π also after any number item ("4 thirds pie r") or a non-weak relation/operator
("A equals pie r squared"), and also before "over" ("theta equals pie over 2", "2 pie over omega") or,
after a number, "root" ("2 pie root l over g"). It stays weak, so "We had 2 pie over at grandma's"
is unchanged.

### 9.6 Still not covered (documented, not fixed)

- Bare "sigma" is ∑ by David's decision (2026-09-29), so "the standard deviation sigma" stays a word;
  σ is "lowercase sigma"/"small sigma".
- A capitalised name mid-sentence is always a name: "the value of Lambda", "Where Theta is", "4 Pi".
- Possessive/article words before a name veto it even in maths: "our theta", "your lambda", "a theta".
- One index alone ("So lambda 1 is 2") stays words; possessive/hyphenated forms ("lambda's",
  "lambda-max") are never candidates.
- Equations Whisper itself wrote as symbols ("x² = 4", "x=2", "λ = 5") are not evidence.
- "I" is never a variable ("epsilon equals I times R"), and "lambda 5 equals K" reads λ₅ (engine-wide,
  pre-existing).
- Residual risk: with real evidence in the dictation, a lower-case Greek word in an allowed slot
  ("the significance level is alpha"-shaped everyday talk such as "my favourite is alpha, x equals 2")
  still promotes.

