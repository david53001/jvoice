# Services/AIPolish — the opt-in Claude polish step

AI Polish sends the already-cleaned transcript to Anthropic's Claude API (`claude-haiku-5-5`,
thinking disabled) to fix punctuation, run-ons and misheard words — using the topic and the user's
previous dictations to pick the meant word ("versails" → Vercel when deploying, Versailles in a
history lesson). Spec: `docs/ai-polish/PROTOTYPE-PLAN.md`; state and next steps:
`docs/ai-polish/PROGRESS.md`.

It is the ONE exception to "zero network calls at runtime", so three rules hold everywhere here:
- **Off by default, bring your own key.** No key ships in the app or the repo. The user's key lives
  only in the Keychain (`APIKeyStore`); never in UserDefaults, `SettingsState`, history, files, the
  clipboard or a log line. Tests use a fake transport and a placeholder key.
- **Never lose a dictation.** ANY failure — no key, offline, HTTP ≠ 200, the 3 s deadline, a stop
  reason other than `end_turn`, empty/over-long/chatty output, the context echoed back — returns
  the local text unchanged.
- **Log the reason only:** `AIPolish ok|fallback(<reason>) <ms>ms context=<n>` (category `latency`).

## Files
- `AIPolishRequest.swift` — **pure Foundation.** System prompt (tone + custom-words lines), the
  `<previous>…</previous>\n<transcript>…</transcript>` user turn, `max_tokens`, the JSON body (no
  sampling params, no prefill), the `URLRequest` (3 headers), the reply decoder and `validate` (all
  fallback rules). Also `AIPolishContext`: the IN-MEMORY ring of the last 3 pasted results —
  same target app, last 10 min, ≤ 1,500 chars, oldest first; cleared when AI Polish is turned off.
- `AIPolishClient.swift` — `AIPolishTransport` (the seam tests fake), `EphemeralTransport`
  (`URLSessionConfiguration.ephemeral`, every cache/cookie/credential store off), `AIPolishResult`,
  and `withDeadline`: a continuation race, NOT a task group — a group waits for every child, so a
  transport that ignored cancellation would hold the paste hostage. The deadline covers the key read too.
- `APIKeyStore.swift` — Keychain generic password (`com.jvoice.app.anthropic` / `api-key`,
  `WhenUnlockedThisDeviceOnly`, not synchronizable). The masked hint ("••••abcd") is stored as the
  item's `kSecAttrComment`, so Settings shows "Key saved" by reading attributes only; the secret is
  read for a dictation, Test Key, or the eye button.
- `AIPolish.swift` — the façade the coordinator calls (`AppTimings.aiPolishTimeout`, real
  transport, Keychain) + `checkKey` (Settings → Test Key: a 1-token request).
- `PolishEvalRunner.swift` — `PolishEvalCase` + pure `PolishEval` grading, and the hidden
  `--polish-eval` CLI: runs `scripts/ai-polish-eval/cases.json` against the REAL API through the
  same builder/parser/client (30 s per-call deadline so real latency is measured), writes
  `docs/ai-polish/eval-results/<date>-<model>-<thinking>.md`. Needs a real key: David's Mac only.

## Where it plugs in
`VoiceCoordinator.finishTranscription`, after `MathSpeech.convert` and the empty check, before the
copy/paste branch; the HUD stays on `.transcribing`. `finalText` replaces `processed` in the paste,
the copy-only path, the HUD, history, stats and the undo record. Settings: the "AI Polish" card
after Processing (`SettingsView.aiPolishSection`): masked field + eye button (reveal resets when
Settings closes), Save / Test Key / Remove Key, toggle disabled until a key is saved.
`SettingsState.aiPolish` is a NEW key with the schema left at v4 (like `appearance`) so older
builds keep reading the blob.

## How to verify changes here
- `./scripts/run-logic-tests.sh` — the "AI Polish" section compiles `AIPolishRequest` +
  `AIPolishClient` with a fake transport (request shape, every fallback, the deadline, the ring).
- `Tests/JVoiceTests/AIPolishTests.swift` (CI) — the same plus Test Key mapping and eval grading.
- Prompt changes: David re-runs the eval and commits the results file; never tune on the hold-out
  cases' exact words.
