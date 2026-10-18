# AI Polish — independent review (second pass, with eval data)

Previous review (first pass, 2026-10-17, no eval data): **7/10 provisional**. Its top fixes were applied; this file replaces it.

Reviewed 2026-10-17 by one independent reviewer sub-agent. Branch `feat/ai-polish` at `93917e6`,
diffed against `feat/math-context`. What was read:
- the spec `docs/ai-polish/PROTOTYPE-PLAN.md` and the log `docs/ai-polish/PROGRESS.md`;
- the newest eval files, `docs/ai-polish/eval-results/2026-10-17-v2-test.md` (hidden test set, 50 cases) and `2026-10-17-v2-train.md` (training set, 78 cases);
- the full implementation diff (`Sources/JVoice/Services/AIPolish/*`, `VoiceCoordinator.swift`, `UI/SettingsView.swift`, `Models/HUDState.swift`, tests, `PRIVACY.md`, docs);
- the latest CI run, [39036693178](https://github.com/david53001/jvoice/actions/runs/39036693178) on `93917e6`. It is **green**: 562 swift-testing tests passed; the logic harness passed (2610 assertions in 5 sections, including AI Polish); `verify-streaming` passed; `settings-smoke` printed "OK — Settings built, laid out and drawn (700×588)".

Nothing was built or run locally. `swift test` was not run and the Keychain was not read. Prices and
API rules were checked against the Claude API reference: Haiku 5.5 costs $0.10 / $0.50 per million
input / output tokens, Sonnet 5.5 costs $2 / $10, and Haiku 5.5 accepts `thinking: disabled` at its
default effort.

Two terms used below:
- **Hold-out case**: an eval case whose sound-alike word does not appear in the prompt's examples. It shows whether the fixing generalizes.
- **Do-nothing baseline**: the score you get by pasting the local text unchanged.

## Scores

| # | Dimension | Score | One-line reason |
|---|---|---|---|
| 1 | Accuracy | **7/10** | Every §9 target is met on the hidden test set: 96 % overall, 100 % no-false-fix, 100 % no-answer, 100 % hold-out, p95 1070 ms. But the eval inputs are all-lowercase with no punctuation, unlike real WhisperKit output; it has no short questions; and context-from-previous is weak (4/6) |
| 2 | Speed | **8/10** | p50 780 ms, p95 1070 ms (test) / 1402 ms (train), max 1926 ms, 0 of 128 calls past 3 s. The 3 s deadline covers every path, including the Keychain read. Cold-connection latency is not measured |
| 3 | Usefulness | **7/10** | It really fixes misheard terms (34 of 36 context-fix cases passed) and splits long run-ons well. No case among the 128 outputs changed a correct word. In Casual mode on real Whisper text (already capitalised and punctuated), most of the visible gain is the term fixes |
| 4 | Never lose a dictation | **7/10** | Every network, HTTP, timeout, no-key and balance path pastes the local text. Two validator holes let an **answer** through: short questions, and a question with a short answer added after it. That is exactly David's "don't answer my question" worry |
| 5 | API-key security | **9/10** | Every §4 item is in place. No key anywhere in the git history. The only weak point is the documented, honest limit of the file-based keychain |
| 6 | Balance + usage | **7/10** | Starts at $0, blocks polishing at $0, uses exact token costs, shows ONE used-up pill, card is at the bottom. Gaps: no red warning for "on, $0, never topped up"; the pill can be lost on paste-failure paths; no coordinator test |
| 7 | Code fit | **8/10** | Matches the repo's style, keeps logic pure, 43 meaningful tests plus the harness section, docs updated. Small doc drift; an intermittent signal-6 test abort is still unexplained |
| | **Overall** | **7/10** | A firm 7, up from the provisional one: the measured numbers are good. Fixes 1–3 below (answer leak, eval realism, $0 warning) would take it to 8+ |

---

## 1. Accuracy — 7/10

**Numbers.** These are single confirmation runs with the compiled prompt v2. The judge table in PROGRESS.md, which averages 3 runs, agrees within noise.

| Set | Overall | context-fix | hold-out | ctx-from-previous | no-false-fix | no-answer | preserve | do-nothing |
|---|---|---|---|---|---|---|---|---|
| **test** (hidden, 50) | **96.0 %** (48/50) | 100 % (10/10) | **100 %** (10/10) | 66.7 % (4/6) | **100 %** (14/14) | **100 %** (14/14) | 100 % (6/6) | 8.0 % |
| train (78) | 96.2 % (75/78) | 92.3 % (24/26) | 90.9 % (20/22) | 91.7 % (11/12) | 100 % (12/12) | 100 % (12/12) | 100 % (16/16) | 6.4 % |

Against the §9 targets (≥ 90 % overall, ≥ 80 % hold-out, 100 % no-answer, p95 ≤ 1.5 s), **all four are met on both sets**. The 3-run judge means for v2 on the test set are 95.3 % overall, 97.6 % no-false-fix (41/42) and 100 % no-answer (42/42).

**Why each failure failed** (from the outputs in the results files):

| Case | Output | Cause |
|---|---|---|
| `t-cp-flour` (test) | "I ran out of flower so I need to run to the store", with previous = baking a cake | **Prompt.** Step 1 of the two-question test ("as written, is it nonsense…?") is answered on the transcript alone. "Ran out of flower" is a valid sentence, so the model never looks at `<previous>`. The prompt even contains this exact flour/flower example (`AIPolishRequest.swift:152`), so this case is also contaminated by the prompt and it still fails |
| `t-cp-usecart` (test) | "…a custom hook called use cart" | **Prompt.** Nothing tells the model to write code identifiers in their code form. "Keep exactly as written: … code" plus the minimal-edit framing pushes it to keep the words as they are |
| `cf-mitochondria` (train, hold-out) | "the mighty chondria is the powerhouse of the cell" | **Prompt (recall cost of v2).** A sound-alike made of real English words passes step 1 as "not nonsense". v2 is conservative on purpose; this is the price of 100 % no-false-fix |
| `cf-chlorophyll` (train, hold-out) | "the color fill inside the chloroplasts" | Same as above |
| `cp-django` (train) | "We use Django for the admin panel and the REST API" | **The case is broken.** The output is right, but `mustNotContain: "jango"` matches inside "Django" (case-sensitive substring). Every prompt fails this case |

**Why the eval overstates the real lift.** These blind spots matter more than the five failures:
- **The inputs aren't what JVoice really sends.** 48 of 50 test transcripts (and 63 of 78 training ones) are all lowercase with no punctuation. WhisperKit emits capitalised, punctuated text, and `TextProcessor.process` keeps that casing in Casual, Formal and Code (`TextProcessor.swift:26-36`). Many `mustContain` checks are capitalisation checks ("Bucharest", "Kaitlyn"), so the do-nothing baseline of 8 % is artificially low. **No case tests whether the model leaves already-correct, cased, punctuated text alone.** That is the real-world form of the no-false-fix risk.
- **No short questions.** The shortest no-answer case is 26 characters ("define the word ubiquitous"). The validator hole described in §4 sits exactly below that.
- **The sample is small.** "100 % hold-out" is 10 cases and context-from-previous is 6. One case is worth 10–17 points, so treat single-run category numbers as ±1 case.
- **Contamination.** Prompt v2's flour/flower example overlaps `t-cp-flour` and `t-cp-flowers` (PROGRESS.md already notes this).

## 2. Speed — 8/10

- **Latency (eval):** the test set has p50 780 ms, p95 1070 ms, max 1767 ms. The training set has p50 766 ms, p95 1402 ms, max 1926 ms. Zero of 128 calls went past the app's 3 s deadline. The 3-run judge mean is p95 1191 ms. **Meets the 1.5 s p95 target**, with the training p95 close to the line.
- **The deadline holds on every path.** `AIPolishClient.withDeadline` (`AIPolishClient.swift:109-123`) is a continuation race: the first `finish` wins, and the timer is a GCD `DispatchWorkItem`, so a busy cooperative thread pool can't make it late. The Keychain read runs *inside* the deadline on a GCD queue (`:78-80`). `URLRequest.timeoutInterval` is set to the same 3 s (`:84`). `waitsForConnectivity = false` (`:26`), so with Wi-Fi off the call fails fast instead of waiting for the network. Cancellation finishes at once (`onCancel`). Tests cover this: `theDeadlineWinsEvenOverATransportThatNeverAnswers`, `theDeadlineAlsoCoversABlockingKeychainRead` and `cancellingTheDictationEndsThePolishAtOnce` are green in CI. A hotkey press during polishing is ignored, not allowed to cancel it (`isTranscriptionInFlight`, `VoiceCoordinator.swift:393`).
- **What's not measured:** the eval runs its calls one after another in one process, so after the first call they reuse a warm HTTPS connection. The first dictation after a long pause pays DNS + TLS setup, which is likely an extra 200–600 ms on a phone hotspot. The worst case added to a dictation is the full 3 s, by design.

## 3. Usefulness — 7/10

- **Real wins.** Across both sets, 34 of 36 context-fix cases passed ("cooper netties" → Kubernetes, "far in height four fifty one" → Fahrenheit 451, "a moxy cillin" → amoxicillin, "lucia telly's" → Le Chatelier's). Long run-ons are split into clean sentences (`t-pr-long-presentation`, `pr-long-standup`).
- **Never worse, as far as the eval shows.** A word-level diff of all 128 outputs against their inputs found **no** changed correct words. The only changes are the intended fixes and a dropped "and" at a new sentence start. Maths, chemistry, URLs, shell commands and booking codes were kept byte for byte (preserve 100 %). `t-na-translate` added quotation marks ("Translate "good morning, how are you" into Italian."), which is harmless.
- **What limits it:** in Casual mode (37 of the 50 test cases) the casual outputs rarely add commas ("Ok so I finished the lab report but how many…"). The tone formatter strips the final "?" ("How much would it cost … December"); that is the user's tone, the same as the local text. Since real Whisper text is already capitalised, most of the noticeable gain is the misheard-word fixes, which matter a lot but only appear in some dictations. Context-from-previous, the "it knows what I was just talking about" feature, is the weakest category (4/6 test, 72 % judge mean). There is still no "paste the original instead" escape for the rare bad polish (open item in PROGRESS.md).

## 4. Never lose a dictation — 7/10

**Traced paths that return the local text:**
- no key: `fallback(no-key)`, before any request (`AIPolishClient.swift:81`)
- offline, network error, timeout, cancel (`:90-96` and the race)
- HTTP ≠ 200 (`AIPolishRequest.swift:257`); malformed JSON (`:258`); stop reason ≠ `end_turn` (`:259`)
- empty reply (`:335`); over-long reply (`:337`); chatty opener (`:341`); leaked context tag or previous dictation (`:344-355`)
- under 60 % of the length (`:357`); under 60 % of the content words kept (`:360`)
- a balance at $0 means no request at all (`VoiceCoordinator.swift:861-865`); dictations under 3 words are never sent (`AIPolish.swift:17-21`)

Paste failures still keep `finalText` on the clipboard (`keepUnpastedTranscript`). This holds up well.

**Holes. Each one pastes an answer, or nothing, in place of the user's words:**
1. **Short questions get answered.** The length floor only applies to transcripts of at least 15 characters (`AIPolishRequest.swift:290, 357`). The word-retention check needs 3 or more content words of 3+ letters (`:292, 312-317`). So for "what is pi" (3 words, 10 characters, one content word: "what"), a reply of "Pi is approximately 3.14159." passes every check and is pasted. "who is newton" → "Isaac Newton was an English physicist…" (40 characters, under the 2×+40 cap) also passes.
2. **A question with an answer added after it passes.** Retention only checks that the user's words are *kept*, not that nothing was *added*. The cap is 2 × input + 40 characters (`:337`). So "What is the boiling point of water? It's 100 °C." passes for a 34-character question, and "What is twelve times eight? 96" passes too (number words are left out of retention, which leaves only 2 content words → no check).
3. **A reply that is only punctuation becomes empty.** For a transcript under 15 characters, a reply of "." passes validation. Then `TextProcessor.format(_, .casual)` strips it to "" (`VoiceCoordinator.swift:879`), and an empty string is pasted. Unlikely, but it is a one-line guard.

Holes 1 and 2 are the "it might answer its own question" case David named. The eval misses them because every no-answer case is longer and only checks for specific answer words.

## 5. API-key security — 9/10

Checked against §4 of the plan, item by item:
- **Keychain item:** generic password, service `com.jvoice.app.anthropic`, account `api-key`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable` false (`APIKeyStore.swift:19-25, 61-66`). ✓ The header comment says honestly that without the data-protection keychain (which needs an entitlement an unsigned app can't have) the "this device only" class is probably not enforced. PRIVACY.md only promises "marked not to sync to iCloud". ✓
- **Hidden by default, eye button:** `SecureField` ↔ `TextField` with `eye` / `eye.slash` (`SettingsView.swift:329-347`). Reveal state is plain `@State`, reset on `NSWindow.willCloseNotification` for the `SettingsWindow` and on `onDisappear`. A key filled in by the eye is cleared again when hidden (`hideKey`). ✓
- **Only the hint is shown:** the "••••abcd" hint is stored in `kSecAttrComment` and read via `kSecReturnAttributes`, so the secret is read only for a dictation, Test Key, or the eye (`APIKeyStore.swift:43-52`). Save clears the field. ✓
- **Never stored elsewhere:** never in `SettingsState` (test at `SettingsStateMigrationTests.swift:171`), UserDefaults (the balance and usage keys are numbers only), history or the clipboard. The only log lines are `AIPolish ok|fallback(<reason>)|skipped(…)` with `privacy: .public` on reason, ms and counts only (`VoiceCoordinator.swift:865, 881, 883`). `FallbackReason.logLabel` folds unknown stop reasons into "stop:other". Settings → Test Key may show Anthropic's error message, but only in Settings and never logged. ✓
- **Ephemeral session:** `URLSessionConfiguration.ephemeral` with cache, cookies and credential storage all set to nil (`AIPolishClient.swift:19-28`). The key goes only in `x-api-key` to `api.anthropic.com`. ✓
- **Git history:** searching every branch's history for `sk-ant-[A-Za-z0-9_-]{8,}` finds **0 matches**. The 14 mentions of "sk-ant" on the branch are the `sk-ant-…` placeholder, docs and the test's negative check. Tests use the obvious fake `test-key-not-real-0000`. The eval runner reads `ANTHROPIC_API_KEY` or the Keychain and never prints the key; the docs tell David to use `read -s`, never an inline `KEY=… cmd`. ✓
- **Small points (no score impact):** `save` does a delete then an add instead of `SecItemUpdate`, which leaves a moment with no key and re-triggers access prompts. The eye button's `revealAPIKey()` runs a synchronous Keychain read on the main thread (`SettingsView.swift:472`), so the UI can freeze while a macOS access prompt is open.

## 6. Balance + usage — 7/10

**Works as David designed it:**
- The balance starts at $0 (`AIPolishUsageStore.swift:54-56`).
- `shouldPolish` = toggle on + key + balance > 0 (`:27-29`). At $0 nothing is sent and `skipped(balance)` is logged (`VoiceCoordinator.swift:861-865`).
- **Costs come from the real `usage.input_tokens` / `output_tokens`** in each reply (`AIPolishRequest.swift:248-252`), priced with the correct Haiku 5.5 rate of $0.10 / $0.50 per million tokens (`:175-187`; about $0.00009 per dictation in the eval). They are recorded even when the reply was a fallback, because Anthropic billed it.
- `record` returns true only for the reply that takes the balance from above $0 to $0 (`:111`). The coordinator then shows "Pasted" and, 1 s later, ONE error pill for 3 s on a single cancellable dismiss task (`VoiceCoordinator.swift:947-952, 992-1004`). Later dictations at $0 show no pill.
- Top-ups are limited to $0.01–$1000. Reset clears the spent totals only, never the balance.
- The toggle can't be turned ON without a key and money, but OFF always works (`SettingsView.swift:310-312`).
- The AI Polish card is full width at the very bottom, above the footer (`SettingsView.swift:186-187`).
- Settings smoke is green in CI.

**Gaps:**
- **No red "set a balance" warning when it matters most.** The red line only appears when `balance <= 0 && topUp > 0` (`SettingsView.swift:388, 432`). If the toggle is ON at $0 and was never topped up (the upgrade gap PROGRESS.md admits: anyone who turned it on before this build), Settings shows a grey "Add a balance to turn this on." (`:319`) while the switch is already on. Dictations are skipped silently and no pill ever appears. David asked for exactly this case: "a red thing, just set a balance if you want to use it or turn it off".
- **The one used-up pill can be lost.** It is only shown on the success path. If the paste returns early (`accessibilityDenied`, `clipboardBusy`, `targetRejected`, `VoiceCoordinator.swift:928-938`) or the task is cancelled right after `record` (`:876`), the flag is dropped and the user never learns why polish stopped.
- **Billed but not subtracted:** a reply that arrives after the 3 s deadline is billed by Anthropic but has no `usage` in JVoice, so the balance under-counts. This is tiny ($0.0001 a time), but it means the "limit" is soft. Settings → Test Key calls aren't counted either.
- **No coordinator-level test** of the gating plus pill sequence; only the store and the predicate are unit-tested.
- After saving a key, nothing explicitly says "now add a balance" beyond the grey caption, although David's idea was that saving the key leads straight to setting a balance.

## 7. Code fit — 8/10

**Strengths:**
- Matches the repo: an area folder with a `CLAUDE.md` brief, pure-Foundation logic (`AIPolishRequest`, `AIPolishClient` and the usage store don't import AppKit), the `SettingsSection` / `toggleRow` / `SubtleButtonStyle` components reused, and the `SettingsState.aiPolish` pattern copied from `mathNotation` without a schema bump, a deliberate and documented choice.
- **Tests are meaningful.** 43 swift-testing cases cover request shape, every fallback, the deadline races, Test Key mapping, the context ring, eval grading and balance math. The logic harness has an AI Polish section that asserts the compiled prompt is byte-identical to `prompts/minimal-edit.txt`.
- The eval harness reuses the app's own builder, parser and client (no copy), refuses unknown arguments, and reports the do-nothing baseline. A train / hidden-test split with 3-run means is good practice.
- The `.refining` HUD state differs from the plan (the plan said no new case), but David asked for it, and it is threaded through the `Kind` mirror and the round-trip test.

**Small issues:**
- The root `CLAUDE.md` still says 2584 harness assertions (CI now runs 2610) and its `Services/AIPolish/` entry doesn't mention the balance or prompt v2 (the area brief does).
- The intermittent **signal-6 abort at suite start** (3 sightings; its first sighting was on `2634a37`, an AI Polish test commit) is still unexplained. The new CI step will print the crash report next time it happens.
- `PolishEvalRunner` adds 256 lines to the app binary; that is acceptable for a hidden CLI mode, matching `--bench`.

---

## Ranked fixes (most score gained first)

1. **Close the answer leak in the validator.** In `Sources/JVoice/Services/AIPolish/AIPolishRequest.swift` `validate` (`:324-364`):
   - (a) Add a fallback `.addedContent` when the output has more than `max(2, 20 %)` new tokens. A new token is a word or number of any length, case-folded, that isn't in the transcript, with spelled-out numbers mapped to digits first. A context fix adds about one new token; an answer adds many.
   - (b) For transcripts under 15 characters or with fewer than 3 content words, require a character-level edit distance of at most about 40 % of the length, instead of skipping the checks.
   - (c) If the transcript ends in a question (or the output adds a "?"), fall back when the output has new tokens after the question's last word.
   - Lock it with tests: "what is pi" → "Pi is approximately 3.14159.", "who is newton" → a biography, "What is twelve times eight? 96", and "What is the boiling point of water? It's 100 °C." must all fall back, while every current context-fix output must still pass. Add the same cases to the logic harness section.
2. **Make the eval look like real input.** In `scripts/ai-polish-eval/cases-test.json` and `cases.json`:
   - Add a cased, punctuated variant of each no-false-fix and preserve case (what WhisperKit really emits, e.g. "I really need a cup of java before my 8 o'clock class."), checked for coming back unchanged apart from punctuation.
   - Add ≥ 8 **short** no-answer cases ("what is pi", "who is newton", "capital of france", "what time is it in tokyo", "how do i spell necessary", "what is twelve times eight") with `mustNotContain` for the obvious answers.
   - Re-run the test set 3 times after fix 1.
3. **Red $0 warning plus a one-time notice, as David asked.**
   - In `Sources/JVoice/UI/SettingsView.swift`, show the red line whenever `coordinator.aiPolish && balance <= 0`: "Set a balance to use AI Polish — or turn it off." Drop the `topUp > 0` condition at `:388`. Show the grey "Add a balance to turn this on." (`:319`) only while the toggle is off.
   - In `VoiceCoordinator.swift` at the `skipped(balance)` branch (`:864`), show the used-up / "needs a balance" pill once per launch when no pill has been shown yet (an in-memory flag). That closes the upgrade gap.
4. **Never drop the used-up pill.** In `VoiceCoordinator.finishTranscription`, keep `polishBalanceRanOut` in a stored property (`pendingBalanceNotice`) instead of a local. Show it from the early-return paths (`:928-938`) after their own error pill, or on the next dictation, and clear it once shown.
5. **Fix context-from-previous in the prompt** (`AIPolishRequest.systemPrompt`, `:143-154`, plus `scripts/ai-polish-eval/prompts/minimal-edit.txt`, kept byte-identical):
   - Make step 1 read "As written, *given the topic of the transcript and the previous dictations*, is it nonsense, out of place…".
   - Add "when the topic is code, write a spoken identifier in its code form (\"use cart\" → useCart)".
   - Replace the flour/flower example with one that no test case uses.
   - Gate: 3 runs of the test set, no-false-fix ≥ 97 % and no-answer 100 %.
6. **Recover multi-word sound-alikes** ("mighty chondria", "color fill") in the same prompt edit. In step 1, say that a phrase of ordinary words that makes no sense *as a phrase* in that sentence counts as a near-miss. Measure on the training hold-out cases, judge on the test set (same gate as fix 5).
7. **Repair the broken eval case.** In `scripts/ai-polish-eval/cases.json` `cp-django` (`:343`), change `mustNotContain` from `"jango"` to `"use jango"` / `" jango "`. Right now no prompt can pass it, which caps context-from-previous on the training set at 91.7 %.
8. **Guard the formatted reply.** In `VoiceCoordinator.swift:879`, write `let formatted = TextProcessor.format(polish.text, mode: effectiveMode); if !formatted.isEmpty { finalText = formatted }` so a punctuation-only reply can never paste "".
9. **Measure and cut cold-start latency.**
   - Add `--cold` to `PolishEvalRunner` (a new ephemeral `URLSession` per call) and report its p95 next to the warm one.
   - If the cold p95 is over 1.5 s, open the connection when recording starts, and only when `shouldPolish` is true. This is an extra network touch, so state it in PRIVACY.md.
10. **Doc and robustness tidy-ups:**
    - In the root `CLAUDE.md`: 2584 → 2610 assertions, and mention the balance and prompt v2 in the `Services/AIPolish/` entry.
    - In `APIKeyStore.save`, use `SecItemUpdate`, with `SecItemAdd` only on `errSecItemNotFound`.
    - In `SettingsView.toggleReveal`, do the Keychain read via `Task.detached` like `testAPIKey` does.
