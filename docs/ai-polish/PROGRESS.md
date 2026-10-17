# AI Polish — progress log

Spec: `docs/ai-polish/PROTOTYPE-PLAN.md`. Branch: `feat/ai-polish` (pushed to `origin` for CI only —
never merged, tagged or released). "State" is always current; "Log" is newest first.

## State

| Step (plan §10 order) | Status |
|---|---|
| SettingsState `aiPolish` flag (default off, no schema bump) | done |
| `AIPolishRequest` (prompt, body, parser, fallback rules) + `AIPolishContext` ring | done |
| `AIPolishClient` (transport protocol, ephemeral URLSession, hard deadline) | done |
| `APIKeyStore` (Keychain) | done |
| `AIPolish` façade + Test Key | done |
| VoiceCoordinator hook + context buffer + log line | done |
| Settings UI section | done |
| swift-testing `AIPolishTests` + SettingsState tests | done |
| Logic harness section (`scripts/run-logic-tests.sh`, 5th section) | done |
| Eval harness (`--polish-eval`) + 78 cases (22 hold-out) | done |
| Docs (PRIVACY.md, root CLAUDE.md, `Services/AIPolish/CLAUDE.md`) | done |
| CI green on `feat/ai-polish` | done — latest code commit green in run 103 |
| David runs the eval | done 2026-10-17 on the Mac (results below + `eval-results/`) |
| Default model chosen by the §6b rule | done — **Haiku 5.5, thinking off** (unchanged `Options.standard`) |
| Usage stat in Settings + "AI refining" HUD pill + shorter caption (David, 2026-10-17) | done, installed on David's Mac |
| Top-up **balance** replaces the monthly budget (David, 2026-10-17): $0 default, Settings "Top up $ [5] Add", each billed reply subtracts, at $0 polish is skipped (`skipped(balance)`), ONE "balance used up" pill; AI Polish card moved full-width to the bottom of Settings | done, installed on David's Mac, committed + pushed — release build + logic harness + `--settings-smoke` green |
| **Prompt tuning** (no-false-fix, no-answer, preserve) | done — **prompt v2 "minimal-edit"** compiled into `AIPolishRequest.systemPrompt`, installed; see "Prompt v2" below |
| Hidden test set `scripts/ai-polish-eval/cases-test.json` (50 cases) + `--prompt-file` candidates in `scripts/ai-polish-eval/prompts/` | done |
| Final review (`docs/ai-polish/REVIEW.md`) | done without eval data: **7/10 provisional**; top fixes applied (table at the end of REVIEW.md); re-run after the eval |

**Eval results (2026-10-17, David's Mac, installed app reading the Keychain key).** Targets (plan
§9): ≥ 90 % overall, ≥ 80 % on the hold-out `context-fix` cases, 100 % on `no-answer`, p95 ≤ 1.5 s.

| Config | Overall | Hold-out | no-answer | no-false-fix | preserve | p95 | Cost/dictation |
|---|---|---|---|---|---|---|---|
| (a) Haiku, thinking off — run 1 | 84.6 % | 95.5 % | 91.7 % | 66.7 % | 75.0 % | 1149 ms | $0.000069 |
| (a) run 2 | 85.9 % | 95.5 % | 91.7 % | 83.3 % | 68.8 % | 1358 ms | $0.000069 |
| (a) run 3 (`…-haiku-5-5-off-run3.md`) | 92.3 % | 95.5 % | 100 % | 91.7 % | 81.2 % | 1307 ms | $0.000069 |
| (b) Haiku, adaptive + effort low | 70.5 % | 81.8 % | 83.3 % | 41.7 % | 43.8 % | 1432 ms | $0.000069 |
| (c) Sonnet 5.5, effort low | 78.2 % | 90.9 % | 75.0 % | 91.7 % | 68.8 % | **4480 ms** (16/78 past 3 s) | $0.0014 |

- **Decision (§6b rule):** (a) Haiku, thinking off — most accurate AND the only configs under the
  1.5 s p95; (c) fails the latency rule outright, (b) is worse on every category. `Options.standard`
  unchanged.
- **Run-to-run noise is large:** the same config (a) scored 84.6 / 85.9 / 92.3 % (runs 1–2 were meant
  to be (b)/(c) but zsh passed `"--thinking low"` as one unsplit word, which the runner silently
  ignored — it now refuses unknown arguments). Compare prompt changes on ≥ 3 runs each, not one.
- **Against the targets (a, mean of 3):** hold-out ✓ (95.5 %), p95 ✓; overall ✗ (87.6 %), no-answer ✗
  (94 % mean — it sometimes answers instead of cleaning), no-false-fix is the weakest (81 % mean —
  it "corrects" words that were right), preserve ~75 %. Those three categories are what prompt tuning
  should target (never on the hold-out cases' exact words).

## Prompt v2 (2026-10-17)

**How it was chosen.** Four candidate prompts were written as `--prompt-file` templates in
`scripts/ai-polish-eval/prompts/` (`baseline.txt` = the v1 app prompt, `minimal-edit.txt`,
`question-firewall.txt`, `compact-fewshot.txt`, and `merged.txt` = parts of the top two). They were
tuned on the training set `scripts/ai-polish-eval/cases.json` (78 cases) and judged on a separate
**hidden test set** `scripts/ai-polish-eval/cases-test.json` (50 cases, never used for tuning), each
run 3 times, all candidates at the same time per round so they saw the same network. Template
placeholders: `{{TONE}}`, `{{TONE_RULE}}`, `{{CUSTOM_WORDS}}` (filled exactly like the app does).
Run a candidate: `/Applications/JVoice.app/Contents/MacOS/JVoice --polish-eval <cases.json>
--prompt-file <template.txt> --out <file.md>` (~1.5–2 min, ~$0.005 per 78 cases; the installed app
reads the key from the Keychain).

**Decision rule** (David's priorities): (1) never change words that were already correct, (2) never
answer a dictated question/request, (3) keep the context fixes, (4) stay fast. Gates: mean p95
≤ 1500 ms and hold-out ≥ baseline − 5; among those, the highest mean of no-false-fix + no-answer.

Judge table — means of 3 runs on the TEST set (train = 1 run; baseline train = the 3-run mean above):

| Prompt | Test overall | no-false-fix | no-answer | Hold-out | p50 | p95 | Cost/dictation | Train overall |
|---|---|---|---|---|---|---|---|---|
| baseline (v1) | 92.0 % | 88.1 % | 90.5 % | 96.7 % | 759 ms | 1060 ms | $0.000068 | 87.6 % |
| **minimal-edit (v2, chosen)** | 95.3 % | **97.6 %** | **100 %** | 100 % | 816 ms | 1191 ms | $0.000091 | 92.3 % |
| question-firewall | 96.7 % | 90.5 % | 100 % | 100 % | 837 ms | 1294 ms | $0.000092 | 94.9 % |
| compact-fewshot | 96.7 % | 92.9 % | 100 % | 96.7 % | 884 ms | 1203 ms | $0.000063 | 96.2 % |
| merged | 94.7 % | 92.9 % | 97.6 % | 96.7 % | 920 ms | 1461 ms | $0.000083 | 93.6 % |

- **Decision: minimal-edit**, now `AIPolishRequest.systemPrompt` (byte-identical to
  `prompts/minimal-edit.txt` rendered — `scripts/run-logic-tests.sh` asserts it for every tone, so
  edit both together). It scores 98.8 on no-false-fix + no-answer (next best 96.4): 41/42
  no-false-fix case runs (one added "the" to t-nf-flask), 42/42 no-answer. compact-fewshot and
  question-firewall capitalised java (the coffee) to "Java" every run; baseline answered or ignored
  a request in 4/42 runs and changed correct words (flask, slack, could-care-less).
- **Cost of the win:** +57 ms p50, +131 ms p95, +$0.000023 per dictation (the prompt is longer:
  347 vs 227 words).
- **Weak spot — context-from-previous:** 72.2 % on test (baseline 88.9 %, compact-fewshot 94.4 %).
  It keeps "use cart" instead of `useCart` (3/3 runs) and "flower" while baking (2/3). If that
  matters as much as the safety goals, compact-fewshot is the runner-up (shortest, cheapest, only
  consistent miss java→Java).
- **Test-set caveats:** compact-fewshot's "graph q l"→GraphQL example nearly matches hold-out case
  t-cf-graphql; minimal-edit's flour/flower example overlaps t-cp-flour / t-cp-flowers. Every
  mustContain/mustNotContain check is a case-sensitive substring. `cp-django` in `cases.json` fails
  for every prompt ("Django" contains the forbidden "jango"), capping training context-from-previous
  at 91.7 %.

**Confirmation run with the compiled prompt** (installed app, no `--prompt-file`, 1 run each):

| Set | Overall | context-fix | ctx-from-previous | no-answer | no-false-fix | preserve | Hold-out | p50 | p95 | Cost/dictation |
|---|---|---|---|---|---|---|---|---|---|---|
| train `cases.json` (`eval-results/2026-10-17-v2-train.md`) | 96.2 % | 92.3 % | 91.7 % | 100 % | 100 % | 100 % | 90.9 % | 766 ms | 1402 ms | $0.000093 |
| test `cases-test.json` (`eval-results/2026-10-17-v2-test.md`) | 96.0 % | 100 % | 66.7 % | 100 % | 100 % | 100 % | 100 % | 780 ms | 1070 ms | $0.000091 |

Matches the judge within noise. Fails: train — cf-mitochondria ("mighty chondria"), cf-chlorophyll
("color fill"), cp-django (the impossible case); test — t-cp-flour, t-cp-usecart (the known weak spot).

## Top-up balance (2026-10-17, David's design)

The display-only monthly budget is gone. AI Polish draws from a local prepaid **balance** (a
spending limit JVoice keeps — not money held anywhere; Anthropic still bills the user's own key):
- Starts at $0. Settings → AI Polish (full-width card at the bottom): "Balance: $x left", a bar
  (balance ÷ last top-up), "Top up $ [5] Add" (refuses ≤ 0, non-numbers, > $1000), a red "Balance
  used up — add more to keep polishing." line, then This month / All time + Reset (Reset clears
  the spent totals only, never the balance).
- The toggle can be turned ON only with a key AND a balance > $0; turning it OFF always works.
- Each billed reply's cost (from Anthropic's `usage` tokens) is subtracted (clamped at $0). At $0
  nothing is sent (`AIPolish skipped(balance)` in the log) and the local text pastes.
- The ONE reply that empties the balance: "Pasted" first, then after 1 s one orange error pill
  "AI Polish balance used up — add more in Settings" for 3 s. No more pills while it stays at $0.
- Stored in UserDefaults `jvoice.app.aiPolish.balance` / `.lastTopUp` (numbers only).
- Known gap: someone who already had the toggle ON before this build starts at $0, so polish stops
  silently (no "used up" pill, since no reply emptied it) until they open Settings and top up.

**Next steps:** David dogfoods v2 + the balance on his Mac (top up, dictate a question, a
deploy-to-"versails" pair, run the balance down with a tiny top-up to see the one "used up" pill). Optional: improve context-from-previous
(identifier casing like `useCart`, flour/flower) without losing no-false-fix — compare on ≥ 3 runs of
`cases-test.json`. Open items from the review, not done yet: pre-connect to `api.anthropic.com`
when recording starts + a `--cold` eval option; a "paste original (unpolished)" action;
`SecItemUpdate` instead of delete+add; tone-check fields in the eval; whether Code tone should skip
polish entirely (David's call).

## CI

| Run | Commit | Result |
|---|---|---|
| [97](https://github.com/david53001/jvoice/actions/runs/39025718923) | `d0d5061` first implementation | green (build, swift-testing suite, logic scripts) |
| [98](https://github.com/david53001/jvoice/actions/runs/39026141872) | `e1a7b9b` eval harness, logic section, docs, CI smoke step | green — swift-testing 545/545 executed, logic scripts incl. the AI Polish section, new `--settings-smoke` step: "OK — Settings built, laid out and drawn (700×588)" |

| [99](https://github.com/david53001/jvoice/actions/runs/39026550700) | `c8b562c` docs only | red — `PasteManagerTests.failedPasteRestoresOriginalClipboard` (pre-existing: it uses the shared `NSPasteboard.general` with a fixed 600 ms wait under the parallel suite; the identical code was green in run 98). AI Polish's own stall fakes were changed to wait on a timer instead of blocking a test thread, so they can't add to such timing flakes |
| [100](https://github.com/david53001/jvoice/actions/runs/39027435380) | `2634a37` review fixes | red twice: attempt 1 the test process aborted (signal 6, no test named — not reproduced); attempt 2 a REAL finding — `theDeadlineAlsoCoversABlockingKeychainRead` took 1.8 s instead of ~0.2 s, because the deadline timer was a `Task.sleep` and the blocking key read ran on a cooperative thread, so a busy pool made the timer late. Fixed next commit: GCD timer + the Keychain read on a GCD queue |
| [101](https://github.com/david53001/jvoice/actions/runs/39028075439) | `bd8fe0d` deadline on GCD | the AI Polish deadline test now passes; red only on `PasteManagerTests.failedPasteRestoresOriginalClipboard` again. Root cause (pre-existing test-isolation bug): it was the one async test on the shared `NSPasteboard.general`, so another test's write during its 600 ms wait made PasteManager rightly skip the restore as a user copy. Fixed next commit: isolated named pasteboard + injected AX trust, like its neighbours |
| [102](https://github.com/david53001/jvoice/actions/runs/39028393044) | `1439125` isolated pasteboard | swift-testing suite green (551 tests); logic harness green (2584 assertions, 5 sections incl. AI Polish); red only on the known `verify-streaming.sh` scenario 12 flake. `257fdea` makes that check wait (bounded, ≤ 2 s) for the cut instead of a fixed 120 ms sleep |
| [103](https://github.com/david53001/jvoice/actions/runs/39028801562) | `3a82a0d` streaming-flake fix + docs | **green** — build, swift-testing suite, logic scripts (incl. AI Polish section), verify-streaming, Settings smoke |
| [run 39034432426](https://github.com/david53001/jvoice/actions/runs/39034432426) | `898ce77` prompt v2 + top-up balance | attempt 1 red: the swift-testing process aborted (signal 6) 0.23 s in with no test named — the same unexplained abort as run 100 attempt 1; attempt 2 (re-run, no change) **green**. If it recurs, look for an uncaught exception/abort in a test that runs at suite start |
| [run 39035152148](https://github.com/david53001/jvoice/actions/runs/39035152148) | `d63c585` docs only | red — the same signal-6 abort at suite start (3rd sighting, so it is a real intermittent bug, not a one-off; pre-dates prompt v2 — first seen on `2634a37`) |
| [run 39035509423](https://github.com/david53001/jvoice/actions/runs/39035509423) | `441e4a2` CI prints the test process's crash report on failure | **green on 3 attempts in a row**. The new failure-only step "Print test-process crash reports" prints the faulting thread + abort message from `~/Library/Logs/DiagnosticReports/*.ips`; the next time the abort happens, read that step's output to find the culprit |

Note: the base branch `feat/math-context` is red at its head ([run 95](https://github.com/david53001/jvoice/actions/runs/37328496182))
on a timing-sensitive `verify-streaming.sh` assertion ("the chunk cut reused the speculative decode",
scenario 12, fixed 120 ms sleeps); the plan-only commit on this branch hit the same one. It is not
AI Polish code; it passed on run 97. If it shows up again, it is that flake, not this feature.

## What was built

- `Sources/JVoice/Services/AIPolish/` — `AIPolishRequest` (pure), `AIPolishClient`, `APIKeyStore`,
  `AIPolish`, `PolishEvalRunner`, area brief `CLAUDE.md`.
- `VoiceCoordinator.finishTranscription`: polish after MathSpeech + the empty check; `finalText`
  used for paste / copy-only / HUD / history / stats / undo; context ring appended after a
  successful paste or copy, cleared when AI Polish is turned off; log line
  `AIPolish ok|fallback(<reason>) <ms>ms context=<n>`. Key helpers: `refreshAPIKeyStatus`,
  `saveAPIKey`, `removeAPIKey` (also turns AI Polish off), `revealAPIKey`, `testAPIKey`.
- `SettingsState.aiPolish` (default false), `AppTimings.aiPolishTimeout = 3.0`.
- Settings → "AI Polish" card after Processing.
- `JVoice --polish-eval` + `scripts/ai-polish-eval/cases.json` (78 cases: context-fix 26 of which
  22 hold-out, context-from-previous 12, no-false-fix 12, no-answer 12, preserve 16 incl. 3 long
  dictations). Doing nothing scores 5/78, so a run's accuracy is real lift.
- Tests: `Tests/JVoiceTests/AIPolishTests.swift`, 2 new cases in `SettingsStateMigrationTests`,
  "AI Polish" section in `scripts/run-logic-tests.sh`. CI also runs `--settings-smoke` now.

### Decisions / deviations from the plan (all small)

1. **No schema bump** for `aiPolish`: a new key with the schema left at v4, like `appearance`, so
   David's daily `feat/math-context` build keeps reading the settings blob (a v5 blob would be
   refused by it and reset his settings).
2. **The deadline is a continuation race, not a task group**, and it covers the Keychain read too:
   a task group waits for every child, so a transport (or a Keychain permission prompt) that
   ignored cancellation could hold the paste past 3 s. Its timer is a GCD timer and the
   synchronous Keychain read runs on a GCD queue, so a busy Swift cooperative pool can't delay it
   (CI run 100 caught exactly that with a `Task.sleep` timer).
3. **The key hint "••••abcd" is the Keychain item's `kSecAttrComment`**, so Settings can say "Key
   saved" by reading attributes only — the secret is read only for a dictation, Test Key or the eye.
4. **`--thinking low` adds 2048 to `max_tokens`** (thinking spends tokens inside the budget; without
   headroom configs (b)/(c) would end in `max_tokens` → fallback and look worse than they are).
   `low` sends `thinking: adaptive` + `output_config.effort: low` for both models; on Sonnet 5.5
   adaptive is what omitting `thinking` means, so it is config (c). The runner refuses Sonnet with
   `--thinking off` (Sonnet 5.5 rejects disabled thinking with a 400).
5. **Extra fallbacks beyond the plan's list:** output still wrapped in `<transcript>` tags is
   unwrapped; output containing a `<previous>`/`<transcript>` tag, or repeating a ≥ 20-char
   previous dictation that isn't in the transcript, falls back (`leaked-context`). Chatty openers
   only count when the transcript itself doesn't contain that phrase ("Sure, I'll be there" is kept).
6. **Context needs a known target app**: with no bundle id, no context is sent.
7. **Restore Default Settings turns AI Polish off but keeps the key** in the Keychain (Remove Key
   deletes it). Easy to change if David prefers the reset to delete it too.
8. **Eval latency** is measured with a 30 s per-call deadline (the app's is 3 s) so slow calls are
   measured, not cut; a call past 3 s is graded as the local text (what the app would paste). Each
   summary line shows accuracy (what the user gets), accuracy by a real polish, the do-nothing
   baseline and the fallback count.
10. **After the review:** a content-retention floor (`too-short` / `dropped-words` fallbacks), the
   tone's formatting re-applied to the reply, and dictations under 3 words not sent at all
   (none of these are in the plan; all keep the "never lose a dictation" rule).
9. `PRIVACY.md`'s effective date was not bumped (feature is unreleased) — bump it when it ships.

## David: run the eval (on the Mac — a cloud session never gets the key)

From the JVoice worktree on `feat/ai-polish`:

```
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build -c release
read -s "ANTHROPIC_API_KEY?Key: " && export ANTHROPIC_API_KEY   # zsh: hidden input, not in shell history
.build/release/JVoice --polish-eval scripts/ai-polish-eval/cases.json                                   # (a) Haiku, thinking off (default)
.build/release/JVoice --polish-eval scripts/ai-polish-eval/cases.json --thinking low                    # (b) Haiku, adaptive + effort low
.build/release/JVoice --polish-eval scripts/ai-polish-eval/cases.json --model claude-sonnet-5-5 --thinking low   # (c) Sonnet, effort low
unset ANTHROPIC_API_KEY
git add docs/ai-polish/eval-results && git commit -m "docs(ai-polish): eval results" && git push origin feat/ai-polish
```

(If the key is already saved in Settings → AI Polish, skip the `read -s`/`export` lines: the runner
falls back to the Keychain item — macOS may ask once to allow the access.) Never type the key inline
as `ANTHROPIC_API_KEY=sk-… cmd` (shell history). Each run is 64 calls: under 1 cent on Haiku,
roughly 10 cents on Sonnet. The results files contain only the case texts and outputs, never the key.
Default = the most accurate config whose p95 ≤ 1.5 s; ties → the cheaper one.

## David: manual test steps

1. `git fetch && git checkout feat/ai-polish` in a JVoice worktree on the Mac.
2. `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./scripts/dev-install.sh`
3. Settings → AI Polish: paste the key → Save → the field clears and shows "Key saved ••••last4";
   the eye button reveals the saved key and hides it again; close and reopen Settings → hidden.
   Test Key → "Key works."
4. Turn "Polish with Claude" on and dictate:
   - a long run-on sentence → punctuated;
   - "what's the capital of France" → pasted as the question, not answered;
   - something with maths ("lambda squared plus x") → symbols kept;
   - "we're moving the site to a new host" then "deploy it to versails" in the same app → "Vercel".
5. Wi-Fi off → dictation still pastes the local text within ~3 s.
6. Save a wrong key → dictation pastes the local text; Test Key says "Invalid key — Anthropic didn't
   accept it."
7. `/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jvoice.app"' | grep AIPolish`
   → `AIPolish ok …` / `AIPolish fallback(…) …` lines with no transcript text or key.
8. Remove Key → toggle turns off and greys out; "No key saved".

## Log

- 2026-10-17 — Prompt v2 ("minimal-edit") chosen on the hidden test set and compiled in; top-up
  balance replaced the monthly budget; both installed, committed and pushed (CI in the table above).
- 2026-10-17 — Final reviewer (one fresh sub-agent, plan §10) scored 7/10 provisional (no eval
  data). Applied its fixes 1–4 and parts of 6, 8, 9, 10; the rest are listed under "Next step".
- 2026-10-17 — Prototype implemented in one session: all code, tests, eval harness, cases, docs.
  No local Swift toolchain in the cloud container (download.swift.org blocked, no apt package), so
  CI on the macOS runner is the compiler. First push green (run 97).
