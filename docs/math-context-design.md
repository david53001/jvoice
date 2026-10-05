# Maths context: design (2026-10-04)

- Branch: `feat/math-context`. Worktree: `.claude/worktrees/math-context`. Base: `feat/math-format` @ `90c6836`.
- Status: IMPLEMENTED 2026-10-04 on `feat/math-context` (not merged, not installed), then REVISED the
  same day after an adversarial verify found bleeds, then REWORKED for recall the same evening after
  David's first real dictation (§10), then FIXED the same night after a second verify found new
  bleeds and recall gaps (§10.7), then extended by round 3 (§11, workflow #3). **§11 adds to §10.7 (and changes the
  two rules it names), §10.7 overrides §10.1–10.6, §10 overrides §9, and §9 overrides §3.** The first implementation's three deviations are in `docs/math-context-progress.md`
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

## 10. Recall rework (2026-10-04, evening)

**Why.** David's first real dictation on the installed build was pasted unchanged: Whisper wrote
"Where's the lambda in this equation for x = 5?" and he expected `Where's the λ in this equation for
x = 5?`. Two causes: V2 vetoed every name after "the", and an equation Whisper had already written as
symbols ("x = 5", "5x + 7z = 5") was not evidence. Whisper large-v3-turbo writes digits and symbols
itself most of the time, so in real use the context system almost never fired (0 of the 30 dictations
in his 2026-10-04 transcript set promoted anything). §9 had traded recall away for safety.

**How it was measured.** Corpora in `.build/math-context/` (gitignored; never commit them, they hold
paraphrases of David's dictations):
- `wordings.tsv` — 467 Whisper-style rows, `input<TAB>expected`: 326 should-promote (P) and 141
  must-stay (S), grouped by `# == FAMILY:` headers. Generator in `wordings-gen/`.
- `everyday-whisper.txt` — 430 everyday sentences, each with a Greek-name word in its everyday sense,
  in Whisper's output style (digits, `=`, scores, prices, versions, code, env vars). Must not change.
- A rule ablation (`ablate-src/`, `ablate/`): every rule behind an environment flag, scored on all
  corpora plus a STRESS set (572 everyday lines with "x = 2." put before them, and the same lines with
  ", and x = 2." put after) that shows what each veto protects once a dictation has evidence.

**Terms.** *Stretch*: words with no punctuation between them. *Sentence*: words between `.`/`?`/`!`.
*Everyday letters*: alpha, beta, gamma, pi (`MathContext.everydayLetters`) — their names are also a
release stage, a dog, a device, a display setting.

### 10.1 Whisper-written notation is evidence (`MathContext.writtenEquations`)

When a dictation holds a candidate name, its tokens are classed: relation (`= ≠ < > ≤ ≥ ≈`), operator
(`+ - − × · ÷ ± ^ – * /`), number (`5`, `-2`, `0.5`, `⁴⁄₃`, `½`, `√3`), letter term (`x`, `5x`, `3xy`,
`x²`, `-3y`, `λ`, `f(x`, `sin(x`, `√x`), short letter group right after an operator (`ma` in
"F = ma"; not an English word), function name (`sin`, `tan`, …), glued equation (`x=2`, `y=mx+c` — each
side a sum of short terms) or other. A window is a run of non-"other" tokens, closed by `,.;:!?…`.
A window is **letter evidence** when it has a relation with something on both sides and a letter term,
or `÷` between letter terms ("v ÷ r"); a glued equation with a letter is letter evidence on its own.
A window of numbers, operators and a relation only ("0 = 0", "2 + 2 = 4") is **numeric evidence**,
which counts only when the dictation has a maths word (`mathsWords`: equation(s), solution(s), solve,
denominator, numerator, system, substitute, unknown(s), coefficient(s), variable(s), parameter,
simultaneous, determinant, significance) or a name sits in a "value(s) of ⟨C⟩" slot. Scores ("3-1"),
times, dates, versions, code ("a == b", "i++", "key=lambda"), env vars ("BETA=1") are single
"other" tokens and never form a window. Unit/ordinal endings ("5km", "2nd", "10am") are not
coefficients. Nothing is rewritten by this scan; it only marks evidence and runs only when a candidate
exists (byte identity otherwise holds). Also: whisper's `÷` counts as a real construct for spoken E1.

Rejected: making the lexer read `λ` and `-` as symbols (ablation GREEKSYM) — it re-joined 4
`prose.txt` lines with no candidate, breaking byte identity.

### 10.2 V2 (word before) now depends on the letter

| Word before | Vetoes | Lifted when |
|---|---|---|
| the, this, that, these, those, our, your, in | everyday letters only | local maths (below) |
| a, an, my | everyday letters + lambda, omega ("use a lambda", "omega 3s") | local maths |
| his, her, their | every letter | local maths |
| hey, aws, amazon, raspberry, happy, tai, absolute, closed, open, early, public, private, stock, portfolio, say(s), said | every letter | never |

*Local maths* = evidence in the name's own stretch ("So my α is 4 and z = 5/x - 4."), OR evidence in
its sentence when that sentence also has a maths word ("So the α is 4 and the β is 3, so 0 = 0 and
there are infinite solutions."), OR Whisper wrote this very letter somewhere in the dictation ("Is his
β right? I got 0 = β - 3."). Sentence-level lifting without the maths word was measured and rejected:
it promoted the STRESS lines "The beta is out, so you can download it now, and x = 2." and "Set the
alpha to 0.5 so the overlay is see-through, and x = 2." (+48 stress bleeds).

### 10.3 Other rule changes

- **V1 (capital mid-sentence)** is lifted when an equation is in the name's own stretch, the letter is
  not an everyday letter, it is not all capitals, and no capitalised mid-sentence word stands right
  before it: "Where's the Lambda in 3y + 3z = 5?" → λ; "AWS Lambda", "Pi Day", "My cat Pi" stay.
- **V3 continuation allowlist** gained the verbs and words that follow a letter in real dictations
  (goes, comes, means, makes, stays, cancels, takes, can't, supposed, needs, works, got, using, back,
  first, out, again, value(s), term(s), bigger, smaller, greater, less, add(s), comma, part, different,
  matrix, right, wrong, free, just, it, i) and Whisper's operators (`- − + = ÷ · × ≠ /`).
- **V4 number rule** ("omega 3", "beta 2") now vetoes only the everyday letters and omega; "Is λ 2?"
  asks a value. A single digit after a promoted name followed by is/was/if/equals/=/goes/gives/has/when
  is an index: "What's lambda 1 if x = 5?" → `λ₁` ("Is λ 2 then?" keeps its space).
- **Labels**: a number after a product name is a label, not a coefficient — "Pixel 9 beta", "iOS 27
  beta", "Spider-Man 2 beta" (a capital inside the word, or a capitalised word that is not a sentence
  opener from `capitalBefore`) and the label words patch, build. This also fixes the old "Pixel 9β".
- **V5** gained: letter(s), alphabet, word, pronounced, spell(ing) (the name mentioned, not used);
  nickname, cat(s), dog(s), puppy, kitten, pet, logo(s), brand(s), tattoo, sticker, shirt, git, npm,
  checkout; for delta: flight(s), airline(s), airport, variant, river, force.
- **Mentions**: a lone hyphen-minus `-` is Whisper's minus, not a dash ("x = ⁴⁄₃ - lambda"); em/en
  dash and `--` still are.
- **Broken equation** only for a SPOKEN relation (a word, not Whisper's `=` beside notation the lexer
  cannot read, such as "0 = β - 3"), and not for one left dangling before a clause word ("What is
  lambda equal to when x = 2?" → `What is λ equal to when x = 2?`).
- **Anchors**: "the value of ⟨C⟩" also anchors without a command word when the dictation has a maths
  word ("the value of alpha that makes the denominator zero"). A letter Whisper wrote anywhere in the
  dictation promotes its own name like an anchor ("2x = 5 - 2λ, and the lambda stays free" → `the λ
  stays free`).
- `capitalBefore` gained the, what's, what ("What's capital phi …", "The capital lambda matrix").

### 10.4 New forms

- **Glued names** (lexer step 6): a curated name with Whisper's suffix glued on — `'s`/`’s`,
  superscripts or subscripts, `=N` — stays an ordinary word for the grammar (no run changes) and is a
  candidate: "lambda's value" → `λ's value`, "lambda² = 4" → `λ² = 4`, "lambda=3" → `λ=3`.
- **Change in a quantity** (lexer step 4a, engine-wide): "delta" right before a single letter (not
  a/A/i/I) is one operand `Δ⟨letter⟩`: "delta x equals 3" → `Δx = 3` (was `δx`), "m c delta T" →
  `mcΔT`. Bare "delta" stays `δ` ("the discriminant delta"). `Δx` is a candidate for context (letter
  "delta"), and `MathScript.slashFraction` treats it as one factor (`Δx/Δt`, was `δx/(δt)`).
- **Powered letter after a name**: "pi r²" → `πr²` (the written `r²` joins the product).
- **Article before a Greek letter** (engine-wide, convert loop): a weak "a" that would open a run right
  after a word, with a Greek letter next, is the article: "Is there a lambda such that 2x + y = 0?" →
  `Is there a λ ∣ 2x + y = 0?` (was `aλ`).

### 10.5 Results (probe `.build/math-context/probe-v2`)

| Measure | installed (`probe-v1`, cf22587) | rework |
|---|---|---|
| `wordings.tsv` exact | 239/467 (51.2 %); P 98/326; S 141/141 | **460/467 (98.5 %)**; P 319/326 (97.9 %); S 141/141 (100 %) |
| `everyday.txt` / `everyday-adversarial.txt` / `everyday-whisper.txt` lines differing from `probe-baseline` | 0 / 0 / 0 | **0 / 0 / 0** |
| `context.tsv` | 137/137 | 137/137 |
| `math.txt` | — | 6 lines differ, all `δ` → `Δ` for a change (`Δx = 3`, `Q = mcΔT`, `v = Δx/Δt`) |
| `math-adversarial.txt` | 57 changed | 60 changed; 9 lines differ, all gains |
| David's real dictations | 0 promote | 6 of 30 (2026-10-04 set) promote, every change a correct letter; `real.txt` unchanged |
| `prose.txt` | — | 0 lines differ |
| STRESS (vs `probe-baseline`) | 132 | 108 |
| 10,000 lines, 5 runs | 0.72–0.73 s | 0.75 s (+3.4 %) |

The 7 P rows still missed: "Pick a lambda, then z = 3 - y." and "So for an omega of 3, v = 6." (a/an
before lambda/omega, evidence in the next stretch, no maths word); "So lambda 1 is 2 and lambda 2 is
3." (no evidence at all — an indexed family alone was tried as an anchor and dropped: "Lambda 1 and
lambda 2 are down" is server talk); "So 2 lambda - lambda is just lambda." (no relation); "Is the beta 5
then? Then 0 = 2, …" (everyday letter + number, evidence in another sentence); "The pi in this formula
…, A = 9." (everyday letter, evidence in the next stretch); "… k + 1, and the lambda was in the
bracket, k · k + 1." (no relation).

### 10.6 Still not covered / risks

- "equals to" (David says it often) is not a relation, so "alpha equals to 4" stays words and, by the
  broken-equation rule, so does the name in it. Adding it to the `=` vocabulary is engine-wide and
  should be its own change (the ablation found it converts 4 more of his real lines and 0 everyday).
- With evidence in the same STRETCH, "the/a/my + everyday letter" now promotes: "Set the alpha to 0.5
  so the overlay is see-through, x = 2" would, if said without punctuation. Measured stress: 108 lines
  differ from the baseline (132 on the installed build); every one of them needs an equation in the
  same dictation, most in the same sentence.
- "Alpha² is a band, x = 2." → `α²`: a glued power is trusted as maths.
- Glued names, `Δx`, and the Windows mirror: not ported (see §6).

### 10.7 Fix round (2026-10-04, night) — a determiner needs the name's OWN neighbourhood

**Why.** A verify of §10 (probe-v2, commit `28bcad5`) reproduced bleeds in 9 families (AWS/code chat
"the lambda is down" next to any equation; labels and config keys as evidence — "Plan B = 20",
"lr=0.01", "100m"; his/her/their/my lifted by "x = 2 and …" in the same stretch; sentence evidence +
maths word crossing a comma into "the beta is out"; names for things — "Project lambda", "the server
omega"; the μ of "50 μs"; glued "alpha=1"/"Alpha²"; "Fortnite went from alpha to beta") and recall gaps
in 17 (whisper right sides such as "-3", "½", "1/3", "30°", "π/6", "h/p", "mg", "(x + 1)"; glued
"lambda²"/"-lambda" inside their own equation; "sin(theta" and other bracket-glued names; "lambda N"
read as λ_N; "equals to"; -ing verbs; IB quantity nouns; "pie"; δ before a Greek name; the sphere's
4/(3πr³); ε₀; units glued to numbers). Measurement corpora: `.build/math-context/` — the verify inputs,
`verify2-bleed.txt` / `verify2-recall.txt`; the bleed inputs are now appended to
`everyday-whisper.txt` (511 lines) and the recall rows to `wordings.tsv` (597 rows, two new families).

**V2, rewritten.** A determiner or possessive before ANY name now vetoes it unless the name's own
neighbourhood is mathematics (`MathSpeech.Emitter.determinerLifted`, word lists in `MathContext`):

| Determiner | Lifted by |
|---|---|
| his, her, their | the letter written as a symbol (Whisper's "3λ", or a converted run's λ for a non-everyday letter), or a value statement with an equation in the stretch ("Their ω is 2 and v = 6") |
| the, this, that, these, those, our, your, a, an, my (and "in" before alpha/beta/gamma/pi) | the letter written; a VALUE STATEMENT with evidence in the same or an adjacent sentence ("the λ is 3, and …", "a μ of 0.3 means …", "the θ is 30 degrees, so …", "the μ between the box and the floor is 0.3 and …", "Is the λ 3? x² = 9"); the name IN/OF an equation or maths noun ("the λ in 3y + 3z = 5", "the λ goes in equation 3", "the π in this formula"); a maths noun within three words ("the θ is the angle …", "the α makes the denominator 0"); a QUESTION or COMMAND about it (where's/what's/find/need/put/plug/use/pick/about …) with evidence in its stretch — for the/this/that also the adjacent sentence ("I have x = 5. Where's the λ?"), for our/your/my the same sentence, for a/an and the everyday letters only the stretch |
| …and for the non-everyday letters also | a CONDITION word right before an equation in its sentence (when/if/for/where/given/because/since/makes/gives/means/that: "Why is the λ getting bigger when x = 5?", "a λ that makes x = 5"); evidence in the same/adjacent sentence plus a maths word in its own sentence |

A STATUS word within six words after the name ("down", "slow", "fine", "broken", "crashes", "best",
"favourite", "ready", "called", …: `MathContext.statusWords`) cancels every lift but the written letter:
"The lambda is down when x = 2." stays. A possessive, and an article before an everyday letter, still
block the letter in the whole dictation (a NAME); an article before any other letter only stops that
occurrence. "that" after anything but a preposition is a conjunction ("we know that λ is 3"); a capital
"A" mid-sentence is a variable ("A sin(ωt)").

**Everyday letters without a determiner** (alpha, beta, gamma, pi) promote by evidence only with
maths around them: evidence in their stretch, a maths word anywhere in the dictation, a value statement
near evidence ("Can α be 4? Then z = 5 ÷ 0."), or a number right before ("2 pi, and x = 3" → 2π).
"x = 2. He's alpha." and "x = 2. Fortnite went from alpha to beta in 2017." stay English. Any name
away from the equation's stretch with a status word after it stays ("x = 2. ω is the best.").

**Evidence (`writtenEquations`).** Greek NAMES count as letter terms inside Whisper's windows
("lambda = -3", "lambda² - 4 = 0", "sin(theta) = 0.5"), so a name with a Whisper-written right side is
its own evidence. New classes: degrees, slash and power-of-ten numbers ("30°", "1/3", "10^-3", "±2");
letter powers and short products ("mc²", "λv", "x1", "N0"); slash products ("π/6", "h/p"); "2(x", "det(A";
any 2–3-letter group after a relation/operator ("IR", "mg"); "I" after notation ("λ I"); "max"/"min"
after a letter. Never evidence: a capital after a label word ("Plan B = 20", "Gate B = 4", "Grade A";
`labelNouns`, or any capitalised word that is no sentence opener), a ranking of capitals by < or > ("S >
A > B"), a glued equation whose left side is not one letter ("lr=0.01", "bs=32"), "1x" and 3-digit
coefficients ("100m"), unit fractions ("km/h", "m/s"). An expression with an operator and no relation
("2 - λ") is evidence in a sentence with a maths word, or after "⟨letter⟩ is" ("x is 3 - λ"). The
written-letter lift and anchor only use LETTER TERMS: the μ of "50 μs" is a unit.

**Anchors added.** "for which λ", "What's the value of λ?" (a question ending on the name), "The value
of λ is 3." (a value statement), "What is λ in this equation?" (a name in/of a maths noun), a value
statement beside a maths word ("So λ can't be 2 because then the denominator is 0."), the IB quantity
cue nouns (friction, density, resistivity, efficiency, flux, emf, torque, temperature, conductivity,
permittivity, permeability, phase; "angular speed/frequency/velocity/acceleration", "phase difference").
Maths words added: matrix, matrices, singular, discriminant, eigenvalue(s)/eigenvector(s), formula,
quadratic, polynomial, inequality, roots, radians. A letter a converted run wrote anchors its name
elsewhere ("z is lambda and y is 2 minus lambda" → both λ).

**Vetoes added.** vetoBefore: project, team, operation, codename, server, boat, very, pretty, super,
quite, totally, he's/she's/I'm/you're/they're/we're, thanks/thank/bye/hi/hello/dear/love/hate/meet.
V5 for all letters: server(s), name(d), codename, config, env, project, haskell, c++, kotlin,
closure(s), lisp, code, coding, syntax, crypto, token, coin, symbol(s), character(s), pokemon, card,
company, marketing, boss, hp; omega: rolex, seiko, swatch, tissot, watches, wrist; delta: game(s),
loop, frame(s), unity, engine. Glued "=N" is never accepted for alpha/beta/gamma/pi ("alpha=1"); a
glued power or "'s" needs evidence in its stretch, or a value statement near evidence ("Alpha² is a
band, x = 2." stays). "let ⟨name⟩ be" + anything but a value or a definition word stays English.

**New forms.**
- Glued prefixes: "-lambda" → `-λ`, "-omega²" → `-ω²`, "sin(theta" → `sin(θ`, "N(mu" → `N(μ`,
  "e^(-lambda" → `e^(-λ`; inside brackets the next single letter joins ("sin(ωt + φ)", "e^(-λt)",
  "det(A - λI)"), also into a following converted run.
- Whisper's signed coefficient: "x = -2 lambda" → `-2λ`.
- A run ending in a Greek letter takes Whisper's powered letter: "A = pie r²" → `A = πr²`.

**Engine-wide changes (sweep: everyday, everyday-adversarial, everyday-whisper and prose unchanged).**
- "equals to" is "=" (David's habit; 8 of his real dictation lines gain correct conversions, 0 everyday lines).
- A relation preceded only by keywords ("beta has to equal to 3" → "to = 3") is no broken equation.
- A relation left dangling before Whisper notation the lexer cannot read ("λ such that x² + …") is no
  broken equation.
- "delta" before a lower-case Greek name is the change: "delta theta over delta t" → `Δθ/Δt`.
- "pie" is π also before a powered letter, an operator symbol, at a sentence end after a relation
  ("θ = pie."), and in "pie r squared"/"cubed" after any word ("The area is pie r squared" → `πr²`).
- A capital carries only n/k as a sequence index: "G M m" → `GMm`, "lambda N" → `λN` (was `G_M m`,
  `λ_N`; "S n" is still `Sₙ`).
- An integer other than 1 over an integer that π follows is a coefficient: "4 over 3 pi r cubed" →
  `(4/3)πr³` (also "4 ÷ 3 pi r³"); "1 over 2 pi" stays `1/(2π)`.
- "epsilon/mu naught|nought|zero|0" are `ε₀`/`μ₀`, which multiply like letters ("4πε₀r²").
- Unit letters N, J, V, W, m, s that END an equation's run after a number keep their space: "F = 12 N",
  "τ = 10 N m", "Δx = 5 m" (was "12N").

**Results (probe `.build/math-context/probe-v3`).**

| Measure | probe-v2 (`28bcad5`) | fix round |
|---|---|---|
| verify bleed families (81 inputs) | 81 bleed | **0** |
| verify recall families (130 rows) | 1 exact | **115 exact** (see below) |
| `wordings.tsv` original 467 rows | 460 (P 319/326, S 141/141) | 456 (P 315/326, S 141/141) |
| `wordings.tsv` all 597 rows | 462 | **573** (P 431/455, S 142/142) |
| everyday / everyday-adversarial / everyday-whisper (511) vs `probe-baseline` | 0 / 0 / 81 | **0 / 0 / 0** |
| `context.tsv` | 137/137 | 137/137 |
| `prose.txt` vs probe-v2 | — | 0 lines differ |
| `math.txt` vs probe-v2 | — | 7 differ, all fixes (`λN`, `GMm`, `GM`, `(4/3)πr³`, `4πε₀r²`, "density ρ", "torque τ") |
| David's real dictations | 6 of 30 promote | 10 lines differ from baseline; vs v2 only "equals to" → "=" and the half-promoted line now fully converted |
| STRESS (vs baseline) | 108 | **29** (every one a bare non-everyday name, e.g. "x = 2. Lambda, …") |
| 10,000 lines, 5 runs | 0.73–0.75 s | 0.76–0.77 s (+~3 %) |

Original P rows now missed (trade-off for the bleeds above): "So the λ is just a number, and x = …",
"That λ is the one we found, x = 2.", "Why is this β different from the one in 3y + 3z = 5?", "What's our
λ? x=2.", "The λ goes in, and then …", "When α takes the value from part A, x = 4." plus 5 of §10.5's 7
("Pick a λ, …", "λ 1 … λ 2", "2λ - λ", "Is the β 5 then?", "k · k + 1"). Not fixed on purpose: bare
"delta = b² - 4ac" (bare delta stays run-only), "3 pie"/"10 pie" with no evidence, the "rad" postfix
("2πrad"), the format spec's spaced composites ("ω² r", "sin 2θ/g", "I ω", "ω A"), "the same as" → "="
(vocabulary), solution triples with no maths word ("(2 - λ, λ, 1)"), "-N Δφ" spacing.

**Accepted risks.** A question about "the λ" right after an equation in the previous sentence promotes
even when it is a watch or a server ("x = 2. Where's the omega?") — it is exactly David's real pattern
("I have x = 5. Where's the λ?"); "The α is 0.5 and x = 2." (a value statement next to an equation)
promotes; a bare non-everyday name with evidence in another sentence still promotes unless a veto or a
status word stops it ("x = 2. Lambda, sorry, wrong chat.").


## 11. Round 3 (2026-10-04, workflow #3) — one meaning per dictation, quantities, strong vocabulary

**Why.** The final check of workflow #2 (SHIP) listed seven remaining families (P1–P7). This round closes
them as families, not sentences. Measurement corpus: `.build/math-context/round3.tsv` (259 rows, Whisper
style, `# == FAMILY:` headers as in `wordings.tsv`; per family ≥ 22 should-promote rows and ≥ 11 must-stay
rows that probe the same rule from the everyday side). Code: `MathContext.swift` (section "round 3" — every
word list is documented there) and `MathSpeech.Emitter` (`located`, `definition`, `quantity`, `operand`, the
two-pass `decide` in `promote`, the broken-equation exemption in `flush`).

Terms: *maths position* = a slot where only a letter makes sense (a value statement, "in/of" a maths noun, a
question/command about it, a definition, a quantity, the operand of a maths verb). *Converted letters* = the
letters whisper wrote, a converted run wrote, or (second pass) context promoted somewhere in the dictation.

### 11.1 The rules

| Family | Rule | Promotes | Stays |
|---|---|---|---|
| P1 place | "⟨name⟩ [is/lives/sits/…] in/on/at ⟨place⟩" is a THING (like a status word: it cancels every lift but a written letter) unless the place holds a maths noun, a `placeNouns` noun ending the phrase (power, quadrant, interval, term, …), a unit, a number or a letter term | "…, also the λ is in the denominator", "the θ is in the second quadrant", "Is θ in degrees? tan x = 1." | "Solve 2x + 3 = 7, also the lambda is in the cloud.", "…, the omega is in my bag" |
| P2 one meaning | for a converted letter, a colon after the name is no mention, and an article before an EVERYDAY letter is lifted in a maths position; `promote` runs a second pass when the first promoted letters that were not yet "converted" | "Solve for λ: 3λ - 6 = 0.", "Find λ: λ² = 9.", "Solve for α: 2α = 6." | "Lambda function: it returns x + 1.", "Note: the alpha team meets at 5, and 2α = 6." (V3 compound still names it) |
| P3 comparison | a multi-word relation ("the same as", "such that", "given that") that ends its run, followed only by keywords/weak items and then an ordinary word (not "pie", a name or a number), is English — no broken equation | "Is the λ in this equation for x = 5 the same as before?", "Find the value of μ such that the vectors are perpendicular." | "Is the lambda in this region the same as before?" (no maths) |
| P4 definition | a definition "⟨name⟩ [here/now/basically] is the [adj] ⟨noun⟩" with a definition noun followed by a tail (of/for/between/…, a connective or the end) counts as `definesMaths`; with evidence near it lifts the article | "Okay so the β here is the coefficient, y = 3 + βx." | "…the beta here is the new version, y = 3x + 2", "the alpha here is the best one" |
| P5 notation | whisper's bars and brackets are read through ("|x", "2|", "1)²"); arc/hyperbolic/inverse functions ("arctan(3/4)", "tan^-1(…)", "sin⁻¹(…)") are letter terms; a relation-free expression is evidence after expand/simplify/factorise/… or with a powered bracket; glued names take ")^2", ")²", "^2", "/N", "/x" and a digit prefix ("3pi/2"); "pi/N" is its own evidence; bare **delta** promotes only as a term of a written window that has a letter of its own (`windowOnlyNames`); a window holding a name needs an own term (number, letter, function, ≤ 2-letter product) | "Expand (x + λ)^2.", "θ = arctan(3/4).", "|x - 2| < δ", "x = π/4", "The discriminant δ = b² - 4ac." | "Lambda = arn of the function." (was a v3 bleed), "We tag releases alpha/1 and beta/1.", "Delta = 0.5 …" (engine-only) |
| P6 quantity | a value with a unit THIS letter stands for (`quantityUnits`: angle letters θ φ α β γ with degrees/°/rad; λ with nm/μm/m/cm; ω with rad/s; ρ with kg/m³, Ωm; τ with N m), also through "we got/measured" and "of water"; a change Δx with any number; a value statement beside strong vocabulary ("reject H0") | "θ is 30 degrees.", "the λ is 600 nm", "The θ we got was 0.93 rad.", "Our α is 0.05, so we reject H0.", "The μ of the distribution is 50 …" (stats nouns are maths nouns now) | "The beta is 30% off.", "The omega is 40 mm.", "Lambda 2 is 600 MB.", "The lambda is 30 seconds.", "Beta is 30 degrees warmer today." |
| P7 vocabulary | `strongTerms` (eigenvalue, perpendicular, "both sides by", "double angle", "standard deviation", "null hypothesis", "angular velocity", "coefficient of friction", "gamma factor", …) are evidence for the names of their own SENTENCE (an everyday letter: own stretch; a name alone between commas — a list — never); a definition with a strong noun anchors; "multiply/divide ⟨maths object⟩ by ⟨name⟩" anchors; "the γ factor" is a maths compound | "λ is an eigenvalue of A.", "Multiply both sides by λ.", "Divide by λ.", "Is it θ or 2θ in the double angle formula?", "The γ factor is 1.5.", "Then the Δx is 0.1." | "Multiply your savings by beta.", "The alpha factor is huge in this game.", "The gamma factor of my monitor is 2.2.", "Lambda is integral to our stack now." |

Deliberately NOT strong terms (each measured as a bleed on a held-out everyday set): integrate/differentiate
("integrate beta into the pipeline"), integral ("λ is integral to our stack"), derivative(s) (finance, "a
derivative of the old design"), orthogonal, variance, hypothesis, simultaneous, h1 (HTML), "of friction" ("a lot
of friction"). Not strong definition nouns: constant, root, unknown ("Lambda is the constant we use for
retries") — they still count next to evidence.

### 11.2 Results (probe `.build/math-context/probe-r3`; references `probe-v3-installed`, `probe-baseline`)

| Measure | probe-v3-installed | round 3 |
|---|---|---|
| `round3.tsv` | 110/259 (P 30/162, S 80/97) | **259/259** (P 162/162, S 97/97) |
| held-out rows written after the rules (scratch, not committed) | promote 9/40 | promote 40/40; 99 everyday lines: 0 changed |
| `wordings.tsv` (one row relabelled, below) | 572/597 (P 431/456, S 141/141) | **576/597** (P 435/456, S 141/141) |
| `context.tsv` | 137/137 | 137/137 |
| everyday / everyday-adversarial / everyday-whisper / everyday-fresh vs baseline | 0 / 0 / 0 / 0 | **0 / 0 / 0 / 0** |
| `verify2-bleed.txt` lines differing from baseline | 44 | 43 (one v3 bleed fixed: "… the omega is in the shop") |
| maths corpora vs v3: losses / gains | — | **0 losses**; gains: math 8, math-fresh 19, verify2-recall 15; math-adversarial, real, real-2026-10-04, prose 0 |
| STRESS A/B vs baseline | 14 / 15 | 14 / 15 |
| 10,000 lines, 5 runs (median) | 0.719 s | 0.742 s (+3.2 %) |

`wordings.tsv` relabel: the single-row family "fix-round must-stay (S)" held "Theta is 45 degrees." → stays.
Round 3's P6 requires the opposite ("Theta is 30 degrees." → θ), so the row is now P (`θ is 45 degrees.`) with
a comment. On the original labels: S 142 → 141 because of that row only.

### 11.3 Still not covered / risks

- A definition or quantity promotes the name in its own stretch even when the same letter sits in a broken
  equation elsewhere: "So θ is the angle, and sine theta equals opposite over hypotenuse." (math.txt) — the
  second θ stays words because its stretch is a broken spoken equation. Same shape as an anchor in v3.
- Strong terms work at SENTENCE scope for the non-everyday letters: "Eigenvalues are hard, and lambda …"
  promotes a bare lambda unless a veto, a status word or a place stops it (stress: 2 of 510 everyday-whisper
  lines with such a prefix differ from v3, both toward fewer letters).
- "the λ is 2 m" promotes (λ with metres); "Lambda is 3 m from the door" stays only because "from" is no
  connective.
- 21 P rows of `wordings.tsv` still miss: the engine-format spacing rows ("ω A", "I ω", "mc ΔT", "-N Δφ",
  "sin 2θ/g", "2πrad"), "3/10 pie" without evidence, "the same as" converted to "=" in "Is λ the same as t",
  indexed families with no evidence, and the determiner rows §10.7 traded away.
- Windows mirror: not ported (now also §11).

## 12. Round 3b (2026-10-05, workflow #3 fix stage) — the round-3 verify findings

**Why.** The adversarial verify of round 3 (`27e5760`) reported 12 bleed families and 12 recall families
(inputs saved as `.build/math-context/verify3-bleed.txt` / `verify3-recall.txt`, gitignored). Two earlier fix
attempts were interrupted (the Mac slept); their edits were taken from `wip/math-context-round3b-partial-2`,
re-verified, and extended. Code: `MathContext.swift` (word lists marked "round 3b") and `MathSpeech.Emitter`
(`quantityEnds`, `restHasMaths`, `mathsTail`, `tailEnds`, `everydayValue`, `conditionHasMaths`, `solvedFor`,
`calculusVerdict`, `everydayLetDefinition`, `rangeStatement`, `personal`, `actsAsPerson`, `predicatesThing`,
`inInterval`, and the head-noun rewrite of `located`). Commits `832464a` … (branch `feat/math-context`).

Terms: *everyday definition noun* = a definition noun that is also ordinary English (angle, slope, gradient,
mean, multiplier, coefficient, parameter, exponent, variance, density, frequency); *maths tail* = a preposition
followed, within four words, by a letter, a number, a Greek name or a maths noun that ends its phrase ("between
the two vectors", "at B", "of the distribution"); *scientific unit* = a unit only science writes (nm, μm, rad,
rad/s, kg/m³, N m).

### 12.1 Bleeds closed

| Finding | Rule | Stays now |
|---|---|---|
| definitions | an everyday definition noun anchors only with a maths tail; in "Let λ be the …" it may also end the sentence | "Theta is the slope at the ski resort.", "Lambda is the parameter in the URL.", "Let θ be the angle of the story." |
| temperatures, walks | a quantity must end the sentence (after "here/now/then", "for ⟨≤3 words⟩", or a tag "…, right?") or go on in maths after a connective; a scientific unit stands before any connective ("λ is 700 nm, so it's red.") | "Beta is 38 degrees, he has a fever.", "Lambda is 500 m, so we can walk.", "Tau is 5 nm, lol." (τ's "Nm" is case-sensitive) |
| strong terms across clauses | strong vocabulary counts in the name's own STRETCH (sentence scope only for a name in a maths position, a coefficient "2θ", or a letter converted elsewhere); a term that modifies an everyday noun ("eigenvalue quiz", `termModifiedNouns`) is none; a name that acts as a person ("went home", "θ and I", "has the …", `personVerbs`) takes none; "both sides by" needs an operand | "The quadratic was easy, so theta and I went to lunch.", "Theta went home after the eigenvalue quiz.", "Both sides by now want omega gone." |
| statistics nouns | distribution/population/sample are maths only when the name gets a value through them ("the μ of the distribution is 50") | "The alpha of the population is the leader." |
| "divide it by ω" | the operand of a maths verb must end the sentence or be followed by maths | "Divide it by omega, the new tier." |
| γ factor | a maths compound only with a number (never through an of/in phrase) or with evidence near | "The gamma factor is huge in this game.", "The gamma factor in the game is 2.2." |
| places | the place's noun phrase is judged by its HEAD: a maths word only modifying it ("graph database", "power bank", "sample folder") is everyday; a number after an everyday noun is a label ("room 5", "gate 12"); a number alone is a time ("in 2027"); idioms without an article ("in power", "in question", "in series"); an of/for/from tail must be maths ("the circle of friends"); a relative clause makes an everyday-sounding place noun a thing ("the sum we paid") | "…, also the lambda is in room 5.", "…, the theta is in the distribution list." |
| one meaning vs everyday values | an everyday unit (price, %, time, size, score — `everydayUnits`) or a person stops that occurrence even when the letter is converted elsewhere | "x + β = 5, and the beta is 2 weeks away.", "2λ = 6. The lambda is 30 seconds on cold start." |
| headings | a colon after a sentence-initial name is a heading unless an equation follows it | "Find α: 2α = 6. Alpha: the team meets at 5." |
| pi/4 of | "pi/N of …" is a portion, no evidence | "I ate pi/4 of the pizza." |
| vocative | an everyday letter called at a sentence start, then an order or a question (`vocativeFollowers`) | "Beta, solve 2x + 3 = 7 first, then play." |
| everyday predicates | away from the evidence's stretch, "⟨name(s)⟩ is/are the ⟨noun⟩" with a noun no maths sentence uses (`MathContext.mathsish`) is a thing | "Solve 2x + 3 = 7, then omega is the restaurant we go to.", "…, then lambda, omega and theta are the groups." |

### 12.2 Recall added

- Maths places v3 converted are back: row, column, form, limit, root, function, side, answer, range, solution,
  quadratic, coefficient, product, quotient, result ("…, also the λ is in the second row").
- Whisper notation: a name under a slash ("c/λ", "hc/λ", "2π/ω"), inside bars ("|λ| < 1"), in a bracket product
  or quotient ("(x - α)(x - β)", "(λ² - 1)/(λ - 1)"), in an exponent ("e^(-λt)"), in an interval ("[0, 2π]"),
  "2pi/T", and "X ~ N(μ, 4)" ("~" is a written relation). Glued names in the glued text are converted too.
- One meaning per dictation, PROMOTE direction: a converted (non-everyday) letter converts after an article
  wherever its sentence holds evidence ("So the ω, it's 2π/T, so ω = 2π/4."); vetoes are per occurrence — a
  term of a written equation is the letter whatever stands before it ("The α is wrong, α = 30°.", "I said
  θ = 35°."); sentence openers before a coefficient ("Because 2λ = -4.").
- Anchors: "Find λ such that / given that ⟨maths condition⟩" (`conditionTerms`); "with respect to λ" after a
  calculus word, ending the sentence or with a value; "Let θ be the angle at B."; ranges "θ goes from 0 to 2π"
  (a bound only maths writes); "for λ I got 3 and for μ I got -1" (the chain must end the sentence); "Plug λ
  back into / substitute θ into the … equation"; "The mean μ is 12."; "At the 5% level"; "reject the null";
  glued units ("600nm", "5rad/s"); "Is λ an eigenvalue of A?" ("an" may follow a name).
- Strong terms added: characteristic equation/polynomial, reject the null, line of best fit, divide/multiply
  both sides, two equations, add/subtract the equations; definition nouns: density, frequency, resistivity,
  permittivity, wavelengths.

### 12.3 Engine-wide changes (lines with no Greek name can change)

- "the one" / "this one" / "which one" is a pronoun, not the number 1 ("Is x the same as the one in part a?"
  used to become "Is x = 1 in part a?").
- "is the same as" never chains onto an equation the parser already holds ("r = a + λb is the same as t" keeps
  the words); "such that"/"given that" is the bar `∣` only when the condition ends the run ("Find k such that
  x = 2 is a root." keeps the words).
- A powered single letter multiplies by juxtaposition (spec §1.3): `ω²r`, `πr²h`, `a = -ω²x`; Whisper's "2pi f"
  → `2πf`. Labels relabelled for this: three `wordings.tsv` rows ("ω² x" → "ω²x") and one `context.tsv` row
  ("λ ∣ 5 = k" → "λ such that 5 = k").
- All four everyday corpora stay byte-identical to the baseline probe.

### 12.4 Results (probe `.build/math-context/probe-r3b`)

| Measure | probe-v3-installed | round 3 (`probe-r3`) | round 3b |
|---|---|---|---|
| verify findings (175 inputs: 76 bleed, 99 recall) | — | — | **175/175** |
| `verify3-bleed.txt` lines differing from baseline | 51 | 126 | 13 (below) |
| `verify3-recall.txt` exact | 104/311 | 233/311 | **311/311** |
| held-out sets written after the rules (scratch) | — | — | promote 158/158; 246 everyday lines: 8 changed (1 correct "Find α: 2α = 6. Alpha: …"; 7 are §12.5 shapes, 3 of them already in v3) |
| `round3.tsv` (now 484 rows: + family R3b, 213 P / 12 S) | 148/484 | — | **484/484** |
| `wordings.tsv` | 569/597 (new labels) | 576/597 | **576/597** (P 435/456, S 141/141) |
| `context.tsv` | — | 137/137 | 137/137 (one row relabelled) |
| everyday / -adversarial / -whisper (now 816 lines) / -fresh vs baseline | 0 / 0 / 49 / 0 | — | **0 / 0 / 0 / 0** |
| `verify2-bleed.txt` differing from baseline | 44 | 43 | 42 |
| maths corpora vs v3 | — | 0 losses | **0 losses**; math 7 gains + 6 spacing, math-fresh 19 + 1, verify2-recall 15 + 5 |
| idempotence (labelled + verify inputs, second pass) | — | 8 of 1,736 change | **0 of 1,961** |
| logic tests | — | 1662 total | **2539/2539** total (logic section 2059) |
| 10,000 lines, 10 runs (median) | 0.770 s | 0.790 s | 0.799 s (+3.8 %) |

The 13 `verify3-bleed` lines that still differ: 4 are correct conversions the bleed probe also contained ("θ =
30°, but theta waves …", "Find α: 2α = 6. Alpha: …", "Solve for lambda: 3λ - 6 = 0. Lambda Legal …", "x = π/4 is
the answer."); the rest are accepted ambiguities: "in the circle", "in this term", "in the system", "in the third
row" (maths places — the recall findings ask for "in the second row"), "Find the value of ω in the menu/deal"
(the strongest anchor), "The φ is 3 rads.", "The λ is 2 m …" (their own units), "β = 2x the users of α".

### 12.5 Still not covered / risks

- A Greek name with its own unit and the sentence ending converts even when it is a person or a place: "Phi is
  39 degrees.", "Gamma is 38 degrees, right?", "Theta is 90 degrees, right?" (P6 asked for "Theta is 30 degrees.").
- "Gamma factor is 1.8." converts (a Lorentz factor and a display gamma read the same).
- Whisper's "Beta = 2x faster" / "Alpha = 3x the sales of beta" (v3 already did this).
- Strong-term modifiers are a list (`termModifiedNouns`); an unlisted one ("the eigenvalue meetup") still counts.
- The `wordings.tsv` misses of §11.3 are unchanged (spacing "ω A", "I ω", "mc ΔT"; determiner rows; "pie").
- Windows mirror: not ported (§10–§12).
