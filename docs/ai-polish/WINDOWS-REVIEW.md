# AI Polish on Windows — independent review

Reviewed 2026-10-17 by one independent reviewer. Branch `feat/ai-polish-windows` at **`e9effd6`**,
diffed against `origin/main` (`git diff origin/main...HEAD`, 60 files, +7,522/−29). The code is the
same as the CI-tested commit `6105855`: the two commits after it change docs only.

## What was checked

- **Spec and logs:** `docs/ai-polish/WINDOWS-HANDOFF.md` (§2.1, 4, 5, 8), `WINDOWS-PROGRESS.md`, and the
  macOS review `REVIEW.md` for comparison.
- **macOS reference:** `origin/feat/ai-polish`. `AIPolishRequest.swift`, `AIPolishClient.swift`,
  `AIPolish.swift` and `AIPolishUsageStore.swift` were compared line by line with the C# port, along
  with the AI Polish parts of the Mac `VoiceCoordinator.swift` and `PolishEvalRunner.swift`.
- **Windows code:**
  - all of `windows/JVoice.Core/AIPolish/*` and `windows/JVoice.App/AIPolish/*`;
  - `VoiceCoordinator.AIPolish.cs`, plus the hooks in `VoiceCoordinator.cs` and the full `FinishTranscriptionAsync`;
  - `HudView.xaml(.cs)`, `SettingsView.xaml(.cs)` and `JVoicePalette.xaml`;
  - `App.xaml.cs`, `UiPreviewRunner.cs`, `windows.yml`, `PRIVACY.md`, the briefs and both test files.
- **Run locally on Linux:** the pure-logic scratch project (`AIPolishTests` + the Settings, HUD and
  coordinator-decision tests against the real `JVoice.Core`) **passed 219/219**. That includes
  `SystemPrompt_IsByteIdenticalToTheShippedTemplateFile` for all four tones. A small .NET program
  confirmed the top-up parsing bug in fix 1.
- **Facts taken from CI, not re-run here:** run 43 on `6105855` built the solution, passed
  **2052/2052** xUnit tests on windows-latest (70 of them new, including the real DPAPI round trip),
  and logged all 24 `--ui-preview` shots as "ok". **Nobody has looked at those PNGs yet**, including
  this reviewer (the artifact host can't be reached from here). So the score for the visual side is
  provisional.
- **No Windows eval data exists** (it needs David's key). Accuracy and speed are judged from the code
  alone; the eval numbers are **pending**.

## Scores

| # | Dimension | Score | One-line reason |
|---|---|---|---|
| 1 | Accuracy | **8/10** (provisional) | A faithful port. The prompt is byte-identical (test-locked, CRLF-safe), and every `validate` rule and constant matches the Mac in order. It should reproduce the Mac's 96.0 % hidden-test score. **Pending: no Windows eval data** |
| 2 | Speed | **8/10** (provisional) | The 3.0 s deadline covers the key read, HTTP, cancellation and a transport that ignores cancellation (all tested). The dictation path costs nothing extra when AI Polish is off. Cold-start latency (first TLS handshake, proxy auto-detect) is not measured. **Pending: no Windows eval data** (Mac p50 ≈ 780 ms) |
| 3 | Usefulness | **7/10** | The context ring, tone re-format, ≥ 3-word gate and refining pill are all correct ports. It inherits the Mac's weak spots (context-from-previous, no "paste the original" escape). The visual look is unverified |
| 4 | Never lose a dictation | **9/10** | Every failure path traced returns the local text, and `PolishAsync` can't throw. The used-up pill stays pending when the paste fails |
| 5 | API-key security | **9/10** | DPAPI with CurrentUser scope and app entropy, stored in Local AppData, written via a temp file. The HTTP client has no cookies, no credentials and no redirects. No key in git history. Two comments slightly overstate what the protection does |
| 6 | Balance + usage | **7/10** | The store logic is correct and thread-safe, and late replies are billed. But **the Amount box parses "2,50" as $250 on an English Windows and "4.99" as $499 on a Romanian/German one**. Late billing is also cancelled by the next hotkey press |
| 7 | Code fit | **8/10** | Clean Core/App split. It reuses the existing styles, HUD loop and preview harness. 70 meaningful tests. Small doc drift and one wrong threading comment. The coordinator glue has no test |
| | **Overall** | **8/10** (provisional) | A careful, faithful port that closes four of the Mac review's open items. Fix 1 is a real bug. The score becomes firm once the eval has run and someone has looked at the PNGs |

---

## 1. Accuracy — 8/10 (pending — no Windows eval data)

**The prompt.** `AIPolishRequest.PromptSource` (`windows/JVoice.Core/AIPolish/AIPolishRequest.cs:99-114`)
is a raw string, passed through `ReplaceLineEndings("\n")` at `:97`.
`SystemPrompt_IsByteIdenticalToTheShippedTemplateFile` (`AIPolishTests.cs:120`) compares it with
`prompts/minimal-edit.txt` for every tone. It passed both on CI (Windows checkout, CRLF) and here
(LF). The `.txt` on this branch is unchanged from `origin/feat/ai-polish`, and the Mac test locks the
Swift prompt to the same file. So Windows, the Mac and the file all send the same prompt.
`ToneLabel`, `ToneRule` and `CustomWordList` (`:126-148`) match the Mac's strings, including the
"none" case.

**The request.** These match the Mac:
- `MaxTokens` (`:196-201`): `(chars+2)/3`, clamped to 256…4096, +2048 with thinking. Characters are user-perceived (grapheme clusters), like Swift.
- The body (`:203-232`): model, `max_tokens`, `system`, one user message and `thinking: disabled`, with no `temperature`/`top_p`/`top_k` and no prefill.
- `UserContent` (`:163-172`).
- The headers (`:235-240`).

Two differences that can't change the score:
- `System.Text.Json` escapes non-ASCII characters and `<`/`>` as `\uXXXX`. The server decodes them to the same string.
- `UserContent` trims only space and tab (`:166`). Swift's `.whitespaces` also trims Unicode Zs spaces such as NBSP.

**The decoder and `Validate`.** `Decode` (`:249-280`) gives up on a non-object content block (Swift's
`as? [[String: Any]]` does the same), joins only `text` blocks, and needs integer usage values.
`Outcome` (`:282-289`) checks HTTP status, then malformed JSON, then `end_turn`. `Validate`
(`:384-435`) applies every Mac rule in the Mac's order:

1. unwrap the tags or quotes;
2. empty;
3. longer than 2×+40;
4. chatty openers, using the same 14 phrases and the same whole-word rule in `Opens`;
5. leaked tags or a ≥ 20-character previous line;
6. shorter than 60 % of a transcript of ≥ 15 characters;
7. under 60 % of the content words kept (≥ 3 words, number words excluded, same 36-word list);
8. more than `max(2, (int)(0.2 × tokens))` added tokens, or any new token after the last "?".

The tokeniser (`IsAlphanumeric`, `:341-348`) is Swift's `CharacterSet.alphanumerics` (L*, M*, N*),
splitting on runes, with apostrophes dropped. Lengths use `StringInfo` the way Swift's `.count`
does. Tests `AnswersToShortQuestions_FallBack` (`AIPolishTests.cs:414`) and
`AShortAnswerOrASummary_LosesTheUsersWordsAndFallsBack` (`:383`) lock the spec's three canonical
cases: "what is pi", "What is twelve times eight? 96", and "deploy it to versails" → "Deploy it to
Vercel.". **Nothing here would make Windows score differently from the Mac.** The only remaining
gaps are Unicode case-folding corners (`ToLowerInvariant` vs Swift's `lowercased()`, e.g. "İ").

**The eval harness** (`PolishEval.cs`):
- It refuses unknown, duplicate and leading arguments (`:113-139`).
- It runs through the app's own `AIPolishClient`, `Validate` and `TextProcessor.Format`, and grades what the app would paste, including the deadline (`:186-208`).
- Its report format matches the Mac's.
- `cp-django` was fixed. `cases-realistic.json` was added (24 cased and punctuated cases, 10 short questions) and kept separate from the train and test sets. Both were Mac review items.

## 2. Speed — 8/10 (pending — no Windows eval data)

**The deadline holds on every path** (`AIPolishClient.cs:62-111`):
- The key read (file + DPAPI) runs inside `Task.Run` (`:76`), so it is covered by the deadline. Tested by `TheDeadline_AlsoCoversABlockingKeyRead` (`AIPolishTests.cs:237`).
- `Task.WhenAny(attempt, timer, cancelled)` (`:80`) returns at the deadline even when the transport ignores its token. Tested by `TheDeadlineWins_EvenOverATransportThatNeverAnswers` (`:227`), whose `Stall` ignores cancellation.
- A cancelled dictation returns at once. Tested by `CancellingTheDictation_EndsThePolishAtOnce` (`:263`).
- `HttpClient.Timeout` is infinite and `ConnectTimeout` is 10 s (`AIPolishServices.cs:34-36`). Both are fine, because the race, not the client, is what returns.

**Nothing slow when AI Polish is off.** `PolishAsync` returns on `!_aiPolish` before any `await`
(`VoiceCoordinator.AIPolish.cs:184`). The foreground-exe probe only runs when app-aware modes or AI
Polish is on (`VoiceCoordinator.cs:1320`). At startup there is one small JSON read
(`VoiceCoordinator.cs:147-149`), and `PlatformPaths.ApiKeyFile` creates `%LOCALAPPDATA%\JVoice` (it
already exists for models).

**Not measured:**
- The first polish after launch or after an idle minute. `SocketsHttpHandler`'s default
  `PooledConnectionIdleTimeout` is 1 minute, so each new dictation after that pays DNS + TLS again.
- On Windows, the system proxy's auto-detect (WPAD) can delay the **first** request after launch by
  seconds on some networks.

Either can push a cold first dictation past 3 s. That doesn't lose text (it falls back, and the
reply is still billed), but the polish is wasted. The eval warms the connection after the first case,
so it won't show this.

## 3. Usefulness — 7/10

- **Context ring** (`AIPolishContext.cs`): capacity 3, a 10-minute window, a 1,500-character cap
  counted in graphemes, newest first and then reversed, and the tail of a single over-budget entry
  kept. It is an exact port, keyed case-insensitively by exe name (`:284`) — a sensible Windows
  choice. It is filled only after a paste or copy, and only while AI Polish is on
  (`VoiceCoordinator.AIPolish.cs:224-227`, `VoiceCoordinator.cs:1415`). It is cleared on
  switch-off, on Remove Key, on Restore Defaults, and when a vanished key is found
  (`VoiceCoordinator.AIPolish.cs:47, 103`; `VoiceCoordinator.cs:843-844`). With no exe, it gives no
  context (`:281`). Tests: `Context_KeepsTheSameAppFromTheLastTenMinutesOldestFirst`,
  `Context_IsCappedInLengthDroppingTheOldestFirst`.
- **Tone re-format:** `TextProcessor.Format(polish.Text, tone)` is applied, and a reply that
  formats to empty keeps the local text (`VoiceCoordinator.AIPolish.cs:210-211`). This is the Mac
  review's fix 8, done from the start. Windows `Format` never lowercases (Very Casual lowercases in
  `Process`, before the corrections), so the reply keeps its proper nouns.
- **Gates:** the ≥ 3-word gate (`AIPolishClient.cs:161-162`, `ShortDictations_AreNotSent`) runs
  after the balance check, the same order as the Mac (`VoiceCoordinator.AIPolish.cs:187-197`). The
  log lines `skipped(balance)` and `skipped(short)` match.
- **HUD:** the `RefiningPanel` (`HudView.xaml:97-122`) works like this:
  - "AI refining" in white, with a #D97757 gradient band moved by the existing per-frame loop
    (`HudView.xaml.cs:332-338`, 1.6 s), and a DropShadow glow;
  - the same 240 minimum width as the transcribing row (`MinWidthFor`, `:275-278`), so going from
    transcribing to refining doesn't resize the pill;
  - it holds still when Windows animations are off (`:144`);
  - the tray icon reads "transcribing" (`CoordinatorDecisions.cs:54`).

  Whether it *looks* right is **unverified**: `hud-refining.png` rendered "ok" on CI, but nobody
  has looked at it.
- **Limits inherited from the Mac:**
  - context-from-previous was the Mac's weakest category (66.7 % on the hidden test);
  - there is no "paste the original instead" escape;
  - the local correction packs (DeveloperTerms, BiblicalTerms, user corrections) are not re-applied
    to the reply. A reply that undoes one of them (e.g. lowercases "God") ships. That risk is low,
    since the prompt asks for names to be capitalised.

## 4. Never lose a dictation — 9/10

Every path was traced from `FinishTranscriptionAsync` (`VoiceCoordinator.cs:1340-1419`). Each one
pastes `processed`, the local text after the cleanup, maths and the empty check:

| Path | Where | Result |
|---|---|---|
| AI Polish off / balance $0 / < 3 words | `VoiceCoordinator.AIPolish.cs:184-197` | local text, no request |
| no key / unreadable DPAPI blob | `AIPolishClient.cs:117-120`; `ApiKeyStore.Read` catches everything (`ApiKeyStore.cs:39-53`) | `fallback(no-key)` |
| offline / DNS / TLS / any transport exception | `AIPolishClient.cs:144-147` | `fallback(network)` |
| transport timeout / token timeout | `:136-143` | `fallback(timeout)` |
| 3.0 s deadline | `:87-98` | `fallback(timeout)`; reply billed later, text never used |
| bad key (401) / balance too low at Anthropic (400) / 429 / 5xx / a redirect (auto-redirect is off) | `AIPolishRequest.cs:284` | `fallback(http<n>)` |
| refusal / `max_tokens` / other stop | `:286-287` | `fallback(stop:…)` |
| odd reply (non-JSON proxy page, too long or short, chatty, answer, leaked context) | `:285`, `Validate` | `fallback(<reason>)` |
| punctuation-only reply | `VoiceCoordinator.AIPolish.cs:210` | local text |
| any exception in `PolishAsync` (incl. a fault in `Body`) | the catch-all at `:216-220`, logs the type only | local text |
| paste refused / clipboard locked | `VoiceCoordinator.cs:1375-1394` | the text being pasted (polished or local) goes to the clipboard and Recent Transcripts; the used-up flag stays pending |
| copy-only | `:1347-1360` | same text staged, or kept in history |
| cancellation (quit) | `:1345` | not pasted — the same as before AI Polish; only quitting cancels, because a hotkey press during refining is ignored (`_isTranscribing`, `:1076-1091`) |

Tests: `HttpErrors_FallBack`, `NetworkErrors_FallBack`, `MalformedJson_FallsBack`,
`NonEndTurnStops_FallBack`, `EmptyText_FallsBack`, `OverLongOutput_FallsBack`,
`ChattyOutput_FallsBack`, `EchoingThePreviousDictation_FallsBack`, `NoKey_MeansNoRequest`,
`AnswersToShortQuestions_FallBack`.

**Threading.** `FinishTranscriptionAsync` starts on the UI thread and has no `ConfigureAwait(false)`,
so `PolishAsync` resumes on the dispatcher. `_aiPolish`, the context ring and the HUD are only
touched there, or through `_dispatcher.InvokeAsync`. The late-billing callback runs on a pool thread
but only uses the locked `AIPolishUsageStore`, a `volatile` flag, and `_dispatcher.InvokeAsync`
(`VoiceCoordinator.AIPolish.cs:166-172`). **No race was found that could paste the wrong text.** One
point off: the coordinator glue (gating, pending pill, ring append) has no test (see fix 9).

## 5. API-key security — 9/10

**Storage.** DPAPI with `DataProtectionScope.CurrentUser` and the entropy
`"JVoice.AIPolish.AnthropicApiKey.v1"` (`AIPolishServices.cs:59-69`, `ApiKeyStore.cs:21`). The file
is in `%LOCALAPPDATA%\JVoice\anthropic-api-key.bin`, Local and not Roaming
(`PlatformPaths.cs:47-63`). Under a preview profile it sits in the throwaway folder, so the CI
renders never touch a real key. Writing goes temp file → `File.Move(overwrite)`, and the temp file
only ever holds the ciphertext (`ApiKeyStore.cs:57-77`). A blob that won't decrypt reads as "no
key". Cleartext byte arrays are zeroed. `AIPolishDpapiTests` checks, on real DPAPI:
- the round trip;
- that the key is not on disk in UTF-8 or UTF-16;
- that it can't be unprotected without the entropy;
- that the wrong entropy reads as null.

**The key never leaks into:**
- `SettingsState` (only the `aiPolish` bool, `SettingsStateJson.cs:84`);
- the usage file (numbers only);
- logs (`AIPolish <label> <ms>ms context=<n> changed=<bool>`; the catch-all logs only the exception type, `VoiceCoordinator.AIPolish.cs:213, 218`; `LogLabel` folds unknown stop reasons into `stop:other`; `TheLogLabel_NeverCarriesTextOrTheKey`);
- `PolishHttpRequest.ToString()` (overridden so it hides the headers, `AIPolishClient.cs:13`);
- the clipboard or history;
- the eval output (the key comes from the environment or DPAPI and is never printed, `PolishEvalCli.cs:127-133`).

The Test Key error text is shown in Settings only.

**The HTTP client** (`AIPolishServices.cs:25-36`): one shared `SocketsHttpHandler` with
`UseCookies=false`, `AllowAutoRedirect=false` (a redirect would re-send `x-api-key` — a good
Windows-specific call), `Credentials=null`, `DefaultProxyCredentials=null`, `PreAuthenticate=false`.
`HttpClient` has no cache.

**The UI.** The field is a masked `PasswordBox` by default. The eye swaps it for a `TextBox`, and a
saved key is loaded only when the field is empty (`SettingsView.xaml.cs:316-329`). The reveal resets
on `IsVisibleChanged → false` (`:27`), and a revealed *saved* key is cleared from the field (`:331-341`).
Save clears the field (`:350-362`). The hint is computed from the stored key.

**Git history.** `git log -p origin/main..HEAD | grep sk-ant` finds only:
- the placeholder `sk-ant-…` in the field's watermark;
- the render-only placeholder `"sk-ant-example-not-a-real-key-0000"` (`App.xaml.cs`);
- copies of the Mac docs.

A pattern for real Anthropic keys (`sk-ant-(api|admin)NN-…`) across **all** branches finds **0**.
Tests use `test-key-not-real-0000`.

**Minor points (no score impact beyond the −1):**
- The entropy is in public source, so the comment "another program running as the same user can't
  decrypt the blob … without also knowing this" (`ApiKeyStore.cs:19-20`) overstates it. Any program
  running as the user can decrypt it. The same goes for PRIVACY's "a copy of the file can't decrypt
  it" (`PRIVACY.md:104`): true only *on another account or machine*. Neither is a hole — DPAPI
  CurrentUser is the right choice — but the wording should be exact.
- `SavedHint()` decrypts the whole key on the UI thread every time Settings opens
  (`VoiceCoordinator.AIPolish.cs:102`). It is cheap and shows no prompt, but storing the four-character hint
  next to the blob would keep the secret out of memory except for a dictation, Test Key or the eye.
  This is what the Mac does.
- A revealed key that the user edited stays in the `TextBox`/`PasswordBox` (and the `TextBox` undo
  buffer) while Settings stays open.
- The render placeholder starts with `sk-ant-`. A `test-key-not-real-…`-style placeholder would keep
  key-shaped strings out of the repo and the PNGs entirely.

## 6. Balance + usage — 7/10

**Correct, and matching the Mac** (`AIPolishUsageStore.cs`):
- Starts at $0.
- `AddBalance` refuses ≤ 0, NaN and anything over $1000, and remembers the last top-up.
- `RemoveBalance` refuses ≤ 0 or NaN, never goes below $0, and leaves the totals alone.
- `Record` subtracts, clamps at $0, and returns true only on the reply that takes the balance from above $0 to $0.
- "This month" resets on the first polish of a new local month.
- No Reset.
- Prices are $0.10 / $0.50 for Haiku 5.5 and $2 / $10 for Sonnet 5.5.
- `Dollars` shows four decimals under one cent.
- Everything is under one lock, so a late pool-thread `Record` is safe.
- A corrupt file reads as $0.

Tests: `Balance_StartsAtZeroAndTopUpsAddUp`, `EveryBilledReply_ComesOffTheBalance`,
`TheReplyThatEmptiesTheBalance_IsReportedOnceAndClampsAtZero`, `ANewMonth_StartsAtZeroButAllTimeKeepsCounting`,
`Usage_AddsUpThisMonthAndAllTime_AndSurvivesARestart`, `ACorruptUsageFile_ReadsAsZero`,
`UnknownModels_AreNotCounted_AndRemoveTakesBalanceBack`.

**Two Mac review items closed:**
- **Used-up pill.** `_polishUsedUpPending` is set by `Record` and cleared only when shown after a
  successful paste or copy (`VoiceCoordinator.AIPolish.cs:166-172, 231-245`), so a failed paste
  keeps it for next time. The pill is ONE `ShowError` after the normal 1 s "Pasted". Later
  dictations at $0 skip silently.
- **Late-reply billing.** `AttemptAsync` is left running up to 30 s after the deadline, and its usage
  goes to `onLateUsage` → `RecordPolishUsage` (`AIPolishClient.cs:87-98`). Tested by
  `AReplyAfterTheDeadline_IsStillBilledButNeverPasted`.

**Bugs and gaps:**
1. **Top-up amount parsing is 100× wrong for the "other" decimal mark** — a correctness bug.
   `TopUpAmount` (`SettingsView.xaml.cs:387-393`) first tries `CurrentCulture` with
   `NumberStyles.Number`, which allows thousands separators. Checked with .NET:
   - en-US: `"2,50"` → **250**, `"4,99"` → **499**;
   - ro-RO / de-DE: `"2.50"` → **250**, `"4.99"` → **499**, `"1,000"` → 1.

   The code comment promises "either decimal mark". On a European-locale PC, David's own test step
   ("Amount `4.99` → Remove") removes $499, which still ends at $0, so the test would pass by
   accident. And "2.50" → Add raises the spending limit to $250 with no warning beyond the balance
   text.
2. **Late billing is cancelled by the next dictation.** The attempt's token is linked to the
   dictation's `ct` (`AIPolishClient.cs:71`). The coordinator cancels the previous
   `_transcriptionCts` on the **next press** (`VoiceCoordinator.cs:1098`) and on the next stop
   (`:1230`). So a timed-out request is aborted (and goes unbilled locally) whenever the user starts
   another dictation within ~30 s — though Anthropic has usually billed it by then. The cost is tiny
   (≈ $0.0001), but the soft limit stays soft in exactly the case it was meant to fix.
   `WINDOWS-PROGRESS.md` decision 5 doesn't mention it.
3. **A stale used-up pill.** If the balance runs out and the user tops up before the next
   successful paste, that paste still shows "AI Polish balance used up". `TryShowPolishUsedUpAfterPaste`
   doesn't re-check the balance (`VoiceCoordinator.AIPolish.cs:231-235`).
4. Test Key calls aren't counted. They are max 1 token, the same as the Mac, and not worth fixing.

The red "on but never topped up" warning (Mac review fix 3) was not adopted. That is consistent
with the spec (§2.1: the switch reads off at $0 and the caption says "Add a balance to turn this
on."), so no deduction.

## 7. Code fit — 8/10

**Strengths:**
- The split follows the area-brief convention exactly: pure logic in `JVoice.Core/AIPolish/`; HTTP,
  DPAPI and the CLI in `JVoice.App/AIPolish/`; the coordinator half in a `partial` file. Each area
  has its own `CLAUDE.md`, and the index briefs are updated.
- `aiPolish` was added without a schema bump, the same way as `appearance`, with test
  `AiPolish_IsOffByDefault_AndRoundTrips`.
- `HudStateKind.Refining` is threaded through `IsBusy`, the tray mapping, `HudStateTests` and
  `CoordinatorDecisionsTests`.
- The Settings card reuses `SettingsCard`, `MonoSwitch`, `Note`/`RowTitle`, `SubtleButton`,
  `FractionToWidth` and palette tokens. The one new style, `InputPasswordBox`, mirrors `InputBox`.
  No hard-coded colours outside the HUD, where hard-coded colours were already the norm.
- The CI preview step and the `--settings-render aipolish-*` and `--hud-render refining` modes are
  neat additions. The step also fixed a latent issue: `light`/`dark` used to be picked up as an
  Updates-card state.
- The tests are meaningful. They use a fake transport that records requests, a stall that ignores
  cancellation, a real file round trip in a temp folder, and real DPAPI on Windows.

**Issues:**
- **A wrong threading comment.** `PolishAsync` says "Runs off the UI thread" (`VoiceCoordinator.AIPolish.cs:178`).
  It actually resumes on the dispatcher, because `FinishTranscriptionAsync` starts on the UI thread
  and has no `ConfigureAwait(false)`. The code is safe either way, but the comment will mislead the
  next person who touches it.
- **The coordinator glue has no test.** Nothing tests the gating order, the pending pill, the ring
  append, or that the polished text replaces the local text in paste, copy-only and history.
  Neither did the Mac, which its review flagged.
- **A Settings render can read the real key.** `--settings-render` run *without* a state token and
  outside a preview profile calls `RefreshAiPolishStatus()` (`App.xaml.cs`), which reads the real
  key's hint into the PNG. If a vanished key is found, it can even `PersistSettings()`. `--ui-preview`
  and CI are not affected (throwaway profile).
- **Stale test counts.** The briefs still say "1933 tests" (`windows/CLAUDE.md:17,23`,
  `JVoice.Core/CLAUDE.md:28`, `JVoice.App/CLAUDE.md:41`, `JVoice.Tests/CLAUDE.md:3`); CI runs 2052.
  This was already stale before the branch, but the branch touched those files.
- **Small cleanups:**
  - fully-qualified `System.Text.Json.Nodes` in `AIPolishKeyCheck` (`AIPolishClient.cs:188-198`);
  - the `cancelled.ContinueWith(OnlyOnFaulted)` "observe" line (`:106`) is dead, because a
    cancelled `Task.Delay` is Canceled, not Faulted.

**Docs:**
- `PRIVACY.md` is accurate and clear about what is sent and where the key lives (except the
  wording in §5).
- HANDOFF §7 #70 and the README are fine.
- The visual check called for by handoff §7 ("you opened and checked every relevant PNG") is still
  open; the progress log says so honestly.

---

## Ranked fixes (most gain first)

1. **[correctness bug] Parse the top-up amount without thousands separators.** In
   `windows/JVoice.App/UI/SettingsView.xaml.cs` `TopUpAmount` (`:387-393`):
   - replace both `TryParse` calls with one invariant parse after normalising the decimal mark:
     `text.Replace(',', '.')` with `NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite` and `CultureInfo.InvariantCulture`;
   - reject text that still has more than one `.`;
   - move the parse into a pure `JVoice.Core` helper (e.g. `AIPolishUsageStore.ParseAmount`) and lock it with tests: "5", "$5", "2.50", "2,50", "4.99" and "4,99" give 5, 5, 2.5, 2.5, 4.99 and 4.99; "1,000.00" is null or refused, never 1 or 1000 by accident.
2. **[correctness bug] Don't let the next dictation cancel a late reply.** In
   `windows/JVoice.Core/AIPolish/AIPolishClient.cs:71-104`:
   - make `attemptCts` a plain CTS (not linked);
   - forward the caller's `ct` with `using var reg = ct.Register(attemptCts.Cancel)` only until the race is decided;
   - when the deadline wins, dispose `reg` before leaving, so later cancellation of that dictation's token no longer reaches the background request (the `CancelAfter(deadline + 30 s)` cap still ends it);
   - add a test: deadline wins, then `cts.Cancel()`, then the late usage still arrives;
   - note the rule in `WINDOWS-PROGRESS.md` decision 5.
3. **[verification] Look at the 24 CI PNGs.** David downloads `windows-ui-preview` from run 43 (or
   runs `--ui-preview`) and commits `settings-aipolish-*.png` and `hud-refining.png` to
   `docs/ai-polish/windows-ui/`. Check:
   - the card at 960 wide in both themes;
   - that the footer is still reachable at 1600×1080 (`SettingsWindow` clamps `MaxHeight`, `SettingsWindow.cs:23`);
   - that the orange band reads in the static pose.

   Until then, Usefulness and Code fit can't be firm.
4. **[verification] Run the eval on Windows** (WINDOWS-PROGRESS step 4): train once, the hidden
   test set ×3, realistic once. Expect test ≈ 96 % and p50 ≈ 0.8 s. Any gap points at a porting bug
   in `AIPolishRequest`/`Validate`, which this review found none of.
5. **[polish / speed] Measure, then cut, cold-call latency.**
   - In `PolishEval.RunAsync`, add a `--cold` flag that builds a new `HttpPolishTransport` (new handler) per case, and report its p95.
   - In `windows/JVoice.App/AIPolish/AIPolishServices.cs`, set `PooledConnectionIdleTimeout` to match `PooledConnectionLifetime` (5 min) so dictations a few minutes apart reuse the TLS connection.
   - If the cold p95 is above 1.5 s, consider `UseProxy=false` only when the system proxy is auto-detect-only. Measure first; that changes behaviour behind corporate proxies.
6. **[polish] Re-check the balance before the used-up pill.** In `VoiceCoordinator.AIPolish.cs`
   `TryShowPolishUsedUpAfterPaste` (`:231`): if `_polishUsage.Balance > 0`, clear the flag and
   return false. A user who already topped up then never sees a stale "used up".
7. **[polish / security] Store the hint, not just the blob.** In `ApiKeyStore.Save`, also write
   `anthropic-api-key.hint` (the last four characters only), and have `SavedHint()` read that. Then
   opening Settings (`RefreshAiPolishStatus`) no longer decrypts the key on the UI thread.
   `Read()` stays the only decrypt path.
8. **[docs] Make the security wording exact.**
   - `ApiKeyStore.cs:19-20`: the entropy keeps out casual, not targeted, same-user readers, because
     it is public.
   - `PRIVACY.md:104`: "can't be decrypted by another Windows account or on another PC".
   - `VoiceCoordinator.AIPolish.cs:178`: "runs on the UI thread between awaits; the HTTP call and
     key read run on the pool".
   - Update the "1933 tests" counts in the five briefs to 2052.
9. **[test gap] Pull the coordinator's polish decisions into a pure helper.** For example, a
   `CoordinatorDecisions.PolishPlan(enabled, balance, text)` returning
   off / skipped(balance) / skipped(short) / send, plus a `ShouldShowUsedUp(pending, balance, pasted)`.
   Unit-test both, so the gating order and the pending-pill rule are locked like the rest of the brain.
10. **[polish] Keep renders and key-shaped strings apart.**
    - In `App.xaml.cs` `RenderSettingsToFile`, only call `RefreshAiPolishStatus()` when
      `JVOICE_PROFILE_DIR` is set; otherwise enter the `aipolish-nokey` preview, so a render never
      reads the real key or writes settings.
    - Change the render placeholder to `test-key-not-real-0000`.
