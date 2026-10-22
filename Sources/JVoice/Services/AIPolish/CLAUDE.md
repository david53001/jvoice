# Services/AIPolish — the opt-in Claude polish step

AI Polish sends the already-cleaned transcript to Anthropic's Claude API (`claude-haiku-5-5`,
thinking disabled) to fix punctuation, run-ons and misheard words — using the topic and the user's
previous dictations to pick the meant word ("versails" → Vercel when deploying, Versailles in a
history lesson). Spec: `docs/ai-polish/PROTOTYPE-PLAN.md`; state and next steps:
`docs/ai-polish/PROGRESS.md`.

It is the only runtime network call that carries user data (the others: the one-time model download
and Sparkle's daily appcast check, which send none; `PRIVACY.md` lists all three), so these rules
hold everywhere here:
- **Off by default, bring your own key.** No key ships in the app or the repo. The user's key lives
  only in one owner-only file (`APIKeyStore`); never in UserDefaults, `SettingsState`, history, files, the
  clipboard or a log line. Tests use a fake transport and a placeholder key.
- **Never lose a dictation.** ANY failure — no key, offline, HTTP ≠ 200, the 3 s deadline, a stop
  reason other than `end_turn`, empty/over-long/chatty output, the context echoed back, or the
  user's words gone (< 60 % of the length, or < 60 % of its 3+-letter words kept — a short answer,
  a summary, a cut-off reply), or **any number changed** (`changed-numbers`: the digit numbers, in
  order, must match the local text's exactly — thousands commas aside; added 2026-10-20 after Claude
  dropped a leading "78.44" and turned "81.2 dollars" into "$81.20") — returns the local text unchanged.
- **The user's tone wins.** The prompt spells out each tone, and the coordinator re-applies
  `TextProcessor.format(_, mode:)` to the reply (Casual's missing final period, Formal's capital +
  period). Dictations under 3 words are not sent at all (`AIPolish.isWorthPolishing`).
- **Log the reason only:** `AIPolish ok|fallback(<reason>) <ms>ms context=<n> changed=<bool>`,
  `AIPolish skipped(short)` or `AIPolish skipped(balance)` (category `latency`).

## Files
- `AIPolishRequest.swift` — **pure Foundation.** System prompt — **v2 "minimal-edit"** since
  2026-10-17 (never answer a dictated question/request, keep correct words, two-question test before
  fixing a sound-alike; tone + custom-words lines), byte-identical to
  `scripts/ai-polish-eval/prompts/minimal-edit.txt` rendered (the logic harness asserts it — change
  both together); `render(_:mode:vocabulary:)` fills a `--prompt-file` template. Then the
  `<previous>…</previous>\n<transcript>…</transcript>` user turn, `max_tokens`, the JSON body (no
  sampling params, no prefill), the `URLRequest` (3 headers), the reply decoder and `validate` (all
  fallback rules). Also `AIPolishContext`: the IN-MEMORY ring of the last 3 pasted results —
  same target app, last 10 min, ≤ 1,500 chars, oldest first; cleared when AI Polish is turned off.
- `AIPolishClient.swift` — `AIPolishTransport` (the seam tests fake), `EphemeralTransport`
  (`URLSessionConfiguration.ephemeral`, every cache/cookie/credential store off), `AIPolishResult`,
  and `withDeadline`: a continuation race, NOT a task group — a group waits for every child, so a
  transport that ignored cancellation would hold the paste hostage. The deadline covers the key read too.
- `APIKeyStore.swift` — the key in ONE file, `~/Library/Application Support/JVoice/anthropic-api-key`:
  mode 0600 in a 0700 folder, written via a 0600 temp file + swap, excluded from Time Machine.
  NOT the Keychain (David, 2026-10-17): the self-signed app's login-keychain access list follows
  each build's code hash, so every update made macOS ask for the user's password; the
  data-protection keychain needs a paid-ID entitlement. Trade-off (documented in PRIVACY.md): other
  software running as the same user could read the file, like the `aws`/`anthropic` CLIs' keys.
  The hint ("••••abcd") is computed from the file.
- `AIPolish.swift` — the façade the coordinator calls (`AppTimings.aiPolishTimeout`, real
  transport, the saved key) + `checkKey` (Settings → Test Key: a 1-token request).
- `AIPolishUsageStore.swift` — what AI Polish has cost AND the prepaid **balance** it draws from
  (David's design, 2026-10-17; replaced the display-only monthly budget). Every reply Anthropic
  billed (used or a fallback) is priced from its `usage` tokens by `AIPolishRequest.cost`, added to
  "this month" (restarts each calendar month) and "all time" totals, and subtracted from the balance
  (clamped at $0; `record` returns true for the ONE reply that empties it). The balance starts at $0
  and is topped up in Settings (`addBalance`, ≤ `maxTopUp`; the last top-up amount is kept for the
  bar). `shouldPolish(enabled:hasKey:balance:)` = toggle on + key + balance > 0. Reset clears the
  spent totals only, never the balance. All in UserDefaults (`jvoice.app.aiPolish.*`, numbers only).
  It is a local spending limit, not money held anywhere — Anthropic bills the user's own account.
- `PolishEvalRunner.swift` — `PolishEvalCase` + pure `PolishEval` grading, and the hidden
  `--polish-eval` CLI: runs `scripts/ai-polish-eval/cases.json` against the REAL API through the
  same builder/parser/client (30 s per-call deadline so real latency is measured; a call past the
  app's 3 s is graded as the local text, the tone formatting is re-applied as in the app, and each
  line reports accuracy, accuracy by a real polish, the do-nothing baseline and fallbacks), writes
  `docs/ai-polish/eval-results/<date>-<model>-<thinking>.md`. Needs a real key: David's Mac only.

## Where it plugs in
`VoiceCoordinator.finishTranscription`, after `MathSpeech.convert` and the empty check, before the
copy/paste branch, only while `AIPolishUsageStore.shouldPolish` (balance > 0; at $0 it logs
`AIPolish skipped(balance)` and sends nothing). The reply that empties the balance shows ONE
`.error` pill after "Pasted" ("AI Polish balance used up — add more in Settings"); no pill after
that. Meanwhile the HUD shows `.refining` ("AI refining" with a Claude-orange glow sweeping
through the letters, `RefiningPill` in `UI/HUDView.swift`). `finalText` replaces `processed` in the paste,
the copy-only path, the HUD, history, stats and the undo record. Settings: the "AI Polish" card,
full width at the very bottom above the footer (`SettingsView.aiPolishSection`): left — toggle,
masked field + eye button (reveal resets when Settings closes), Save / Test Key / Remove Key; right
(240 pt) — "Balance: $x left", a bar (balance / last top-up), "Top up $ [5] Add", a red "Balance
used up" line, then This month / All time + Reset. The toggle can be turned ON only with a key AND
a balance > 0 (turning it OFF always works).
`SettingsState.aiPolish` is a NEW key with the schema left at v4 (like `appearance`) so older
builds keep reading the blob.

## How to verify changes here
- `./scripts/run-logic-tests.sh` — the "AI Polish" section compiles `AIPolishRequest` +
  `AIPolishClient` with a fake transport (request shape, every fallback, the deadline, the ring).
- `Tests/JVoiceTests/AIPolishTests.swift` (CI) — the same plus Test Key mapping and eval grading.
- Prompt changes: write the candidate as a template in `scripts/ai-polish-eval/prompts/`
  (placeholders `{{TONE}}`, `{{TONE_RULE}}`, `{{CUSTOM_WORDS}}`; `baseline.txt` = v1) and run it
  WITHOUT a rebuild: `/Applications/JVoice.app/Contents/MacOS/JVoice --polish-eval <cases.json>
  --prompt-file <template.txt> --out <file.md>` (it reads the saved key file — `ANTHROPIC_API_KEY` overrides it; ~2 min,
  ~$0.005). Tune on `scripts/ai-polish-eval/cases.json` (78 cases, training); decide on the HIDDEN
  `scripts/ai-polish-eval/cases-test.json` (50 cases — never tune on its words), ≥ 3 runs each
  (run-to-run noise is several points). Only then copy the winner into `systemPrompt`, reinstall,
  and confirm with a run without `--prompt-file`. The v2 decision + judge table: "Prompt v2" in
  `docs/ai-polish/PROGRESS.md`.
