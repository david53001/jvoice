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
| CI green on `feat/ai-polish` | done (runs 97, 98) |
| **David runs the eval** | **todo — commands below** |
| Default model chosen by the §6b rule | pending — no eval data |
| Final review (`docs/ai-polish/REVIEW.md`) | done without eval data: **7/10 provisional**; top fixes applied (table at the end of REVIEW.md); re-run after the eval |

**Accuracy / speed: pending — no eval data yet.** The cloud session has no API key (by design), so
nothing has been measured against the real API. Targets (plan §9): ≥ 90 % overall, ≥ 80 % on the
hold-out `context-fix` cases, 100 % on `no-answer`, p95 ≤ 1.5 s.

**Next step:** David runs the eval (below) and commits the results file(s); then the next session
picks the default config by the §6b rule, re-runs the final review (same brief, plan §10), and
tunes the prompt if needed. Open items from the review, not done yet: pre-connect to
`api.anthropic.com` when recording starts + a `--cold` eval option (if the eval shows cold-start
latency); a "paste original (unpolished)" action; `SecItemUpdate` instead of delete+add; tone-check
fields in the eval; whether Code tone should skip polish entirely (David's call).

## CI

| Run | Commit | Result |
|---|---|---|
| [97](https://github.com/david53001/jvoice/actions/runs/39025718923) | `d0d5061` first implementation | green (build, swift-testing suite, logic scripts) |
| [98](https://github.com/david53001/jvoice/actions/runs/39026141872) | `e1a7b9b` eval harness, logic section, docs, CI smoke step | green — swift-testing 545/545 executed, logic scripts incl. the AI Polish section, new `--settings-smoke` step: "OK — Settings built, laid out and drawn (700×588)" |

| [99](https://github.com/david53001/jvoice/actions/runs/39026550700) | `c8b562c` docs only | red — `PasteManagerTests.failedPasteRestoresOriginalClipboard` (pre-existing: it uses the shared `NSPasteboard.general` with a fixed 600 ms wait under the parallel suite; the identical code was green in run 98). AI Polish's own stall fakes were changed to wait on a timer instead of blocking a test thread, so they can't add to such timing flakes |
| [100](https://github.com/david53001/jvoice/actions/runs/39027435380) | `2634a37` review fixes | red twice: attempt 1 the test process aborted (signal 6, no test named — not reproduced); attempt 2 a REAL finding — `theDeadlineAlsoCoversABlockingKeychainRead` took 1.8 s instead of ~0.2 s, because the deadline timer was a `Task.sleep` and the blocking key read ran on a cooperative thread, so a busy pool made the timer late. Fixed next commit: GCD timer + the Keychain read on a GCD queue |
| [101](https://github.com/david53001/jvoice/actions/runs/39028075439) | `bd8fe0d` deadline on GCD | the AI Polish deadline test now passes; red only on `PasteManagerTests.failedPasteRestoresOriginalClipboard` again. Root cause (pre-existing test-isolation bug): it was the one async test on the shared `NSPasteboard.general`, so another test's write during its 600 ms wait made PasteManager rightly skip the restore as a user copy. Fixed next commit: isolated named pasteboard + injected AX trust, like its neighbours |

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

- 2026-10-17 — Final reviewer (one fresh sub-agent, plan §10) scored 7/10 provisional (no eval
  data). Applied its fixes 1–4 and parts of 6, 8, 9, 10; the rest are listed under "Next step".
- 2026-10-17 — Prototype implemented in one session: all code, tests, eval harness, cases, docs.
  No local Swift toolchain in the cloud container (download.swift.org blocked, no apt package), so
  CI on the macOS runner is the compiler. First push green (run 97).
