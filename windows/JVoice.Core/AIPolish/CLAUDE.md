# Core / AIPolish — the opt-in Claude cleanup (pure half)

Port of the macOS AI Polish (branch `feat/ai-polish`, `Sources/JVoice/Services/AIPolish/`). After the
local cleanup + Math Notation, a dictation (≥ 3 words) goes to `claude-haiku-5-5` (thinking disabled)
to fix punctuation, run-ons and misheard words from context ("versails" → Vercel when deploying).
Spec + Windows decisions + David's steps: `../../../docs/ai-polish/WINDOWS-HANDOFF.md`,
`../../../docs/ai-polish/WINDOWS-PROGRESS.md`. HANDOFF-WINDOWS §7 #70.

It is the one opt-in exception to "zero network at runtime", so these rules hold everywhere:
- **Off by default, bring your own key.** No key in the repo, tests (placeholder
  `test-key-not-real-0000`), CI, logs or settings JSON.
- **Never lose a dictation.** Any failure — no key, offline, HTTP ≠ 200, the 3.0 s deadline, a stop
  reason ≠ `end_turn`, or any `Validate` rule — returns the local text unchanged.
- **Log the reason only** (`AIPolishResult.LogLabel`), never text or key.

## Files
- `AIPolishRequest.cs` — prompt v2 (`PromptTemplate`, byte-identical to
  `scripts/ai-polish-eval/prompts/minimal-edit.txt`; line endings normalised to `\n` because a Windows
  checkout gives CRLF — **change both together, on both platforms**), user turn, `MaxTokens`, body,
  headers, `Decode`, `Outcome`, **`Validate`** (every Mac rule + constant), pricing. Lengths are
  user-perceived characters like Swift `String.count`.
- `AIPolishClient.cs` — `IPolishTransport` seam, `AIPolishResult`, the deadline (`Task.WhenAny` against a
  timer — wins even if the transport ignores cancellation; the key read is inside it). Windows-only: a
  reply that misses the deadline is left to finish (≤ 30 s) and `onLateUsage` bills it. Also
  `AIPolishGate` (≥ 3 words, 3.0 s) and `AIPolishKeyCheck` (Settings → Test Key).
- `AIPolishContext.cs` — in-memory ring: last 3 pasted results, same exe (case-insensitive), 10 min,
  ≤ 1,500 chars, oldest first. Never persisted.
- `AIPolishUsageStore.cs` — balance (starts $0, top-up ≤ $1000, clamps at $0, `Record` returns true for
  the ONE reply that empties it) + this-month / all-time totals in a JSON file. No Reset.
- `ApiKeyStore.cs` — the key file with an injected protector (the app passes DPAPI, CurrentUser +
  `Entropy`); temp file + replace; unreadable ⇒ "no key".
- `PolishEval.cs` — eval cases, grading, `ParseArgs` (refuses unknown arguments), `RunAsync` (the same
  client/validator as the app) and the Markdown report. The CLI is `JVoice.App/AIPolish/PolishEvalCli.cs`.

## Verify
`dotnet test windows/JVoice.Tests` — `AIPolishTests`, `AIPolishDpapiTests`. Prompt changes: try a
template with `JVoice.exe --polish-eval <cases> --prompt-file <t.txt>` first (needs a real key — David's PC).
