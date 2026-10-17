# AI Polish on Windows — progress log

Branch **`feat/ai-polish-windows`** (from `origin/main` = `c0b97b6`, the shipped `windows-v1.1.0`).
Spec: `docs/ai-polish/WINDOWS-HANDOFF.md`. macOS reference: branch `feat/ai-polish` (read-only here).
Newest entries first. Updated after every step, so a new session can resume from this file alone.

## State

| Area | State |
|---|---|
| Core logic (`windows/JVoice.Core/AIPolish/`) | done — request, prompt v2, validate, client + deadline, context ring, usage/balance, key file, eval |
| xUnit tests (`AIPolishTests`, `AIPolishDpapiTests`) | written; Core-only subset 219/219 locally; CI run 1 failed to COMPILE the test project (missing `using System.Net.Http` under UseWPF) — fixed in step 2 |
| App wiring (HTTP transport, DPAPI, coordinator, HUD, Settings, `--polish-eval`) | written; whole solution compiles locally (`-p:EnableWindowsTargeting=true`); CI pending |
| CI UI preview artifact | step added to `windows.yml` (`windows-ui-preview`); first run pending |
| Docs (PRIVACY, HANDOFF §7 #70, briefs) | not started |
| Independent review | not started |

## Decisions (Windows-specific)

1. **Pure logic in `JVoice.Core/AIPolish/`** (new area): everything except HTTP, DPAPI and WPF, so it
   compiles and is tested anywhere. The file-backed stores take a path (tests use a temp folder).
2. **Settings key `aiPolish` without a schema bump** (stays v6), the same convention as `appearance`
   (and as the Mac did): older builds read the file and ignore it. Absent/wrong type ⇒ OFF.
3. **Prompt line endings are normalised to `\n` in code.** The repo has no `.gitattributes`, so a
   Windows checkout (git autocrlf) gives the `.cs` and the `.txt` CRLF; without normalising, the
   Windows request would differ from the Mac's. The test compares against the `.txt` with endings
   normalised.
4. **Lengths count user-perceived characters** (`StringInfo.LengthInTextElements`) like Swift's
   `String.count`; tokens/words split on letters+marks+numbers like `CharacterSet.alphanumerics`.
5. **Late replies are billed** (Mac review item): when the 3 s deadline wins, the request is NOT
   cancelled; it may finish in the background for up to 30 s and its usage is then subtracted from
   the balance. Its text is never used. Cancelling the dictation still cancels the request.
6. **Key storage: DPAPI** (`ProtectedData`, CurrentUser, app-specific entropy
   `JVoice.AIPolish.AnthropicApiKey.v1`) in `%LOCALAPPDATA%\JVoice\anthropic-api-key.bin`, written via
   temp file + replace. No prompts. Another Windows user, another machine, or a program calling
   `Unprotect` without the entropy can't read it. A blob that won't decrypt reads as "no key".
7. **Usage + balance in `%APPDATA%\JVoice\ai-polish-usage.json`** (numbers only).
8. **Context ring keyed by the paste window's exe name** (`ForegroundApp.ExeName`), case-insensitive.
9. **Eval data:** `cases.json` `cp-django` fixed (`mustNotContain` `" jango "`, Mac review); a new
   `cases-realistic.json` (24 cases: cased + punctuated like real Whisper output, 10 short questions)
   kept SEPARATE so train/test numbers stay comparable with the Mac's. `cases-test.json` untouched.
10. **Eval report default path** `docs/ai-polish/eval-results/<date>-windows-<model>-<thinking>.md`.

## Log

### 2026-10-17 — step 2: App wiring + CI UI preview
- Local build trick: the cloud container has .NET 10 SDK (apt, Microsoft repo); `dotnet build
  windows/JVoice.sln -c Release -p:EnableWindowsTargeting=true` compiles the WPF app and the test
  project (XAML included) on Linux — catches compile errors before CI. Tests still RUN only on CI.
- `JVoice.App/AIPolish/`: `HttpPolishTransport` (one `SocketsHttpHandler`: no cookies, no credentials,
  no redirects — a redirect would re-send `x-api-key` — infinite HttpClient timeout, the client's
  deadline rules), `DpapiKeyProtector` (+ `PlatformPaths.ApiKeyFile` / `AiPolishUsageFile`),
  `PolishEvalCli` (`--polish-eval`, routed first in `App.Main`).
- `VoiceCoordinator.AIPolish.cs` (partial): Settings state, key/balance actions, `PolishAsync` (runs
  after maths + the empty check, before paste/copy; the result replaces the local text everywhere),
  context ring append after each paste/copy, the ONE "used up" pill after "Pasted" — kept PENDING when
  that paste fails (Mac review item), late-reply billing, preview states for renders.
- HUD: `RefiningPanel` — "AI refining", white text with a #D97757 band swept by the render loop
  (1.6 s), soft orange glow, same 240 minimum width as the transcribing row; holds still when Windows
  animations are off (`SystemParameters.ClientAreaAnimation`).
- Settings: full-width "AI Polish" card (grid row 2, footer moved to row 3): switch + caption, masked
  PasswordBox / revealed TextBox + eye (reveal resets when the window hides), Save / Test Key / Remove
  Key; right 300 px: balance, bar, Amount $ [5] Add / Remove, red used-up line, This month / All time.
- Renders: `--settings-render <png> aipolish-nokey|aipolish-zero|aipolish-on|aipolish-revealed|aipolish-usedup [light|dark]`
  (staged in memory, placeholder key only), `--hud-render <png> refining`, `--hud-preview refining`;
  `--ui-preview` takes 7 new shots. CI renders them and uploads `windows-ui-preview`.

### 2026-10-17 — step 1: Core logic + tests
- Branch created from `origin/main`; brought over `scripts/ai-polish-eval/` and `docs/ai-polish/`
  from `origin/feat/ai-polish` (no `Sources/`, `Tests/`, `Package.swift`, Mac `PRIVACY.md`).
- `JVoice.Core/AIPolish/`: `AIPolishRequest` (prompt v2 byte-identical to `minimal-edit.txt`, body,
  headers, decoder, every `validate` rule and constant from the Mac), `AIPolishClient` (`IPolishTransport`
  seam, `Task.WhenAny` deadline that beats a transport ignoring cancellation, key read inside the
  deadline, late-reply billing), `AIPolishGate` (≥ 3 words, 3.0 s), `AIPolishKeyCheck` (Test Key),
  `AIPolishContext` (ring), `AIPolishUsageStore` (balance/usage JSON), `ApiKeyStore` (encrypted key
  file, injected protector), `PolishEval` (cases, grading, CLI args that refuse unknowns, the run + report).
- `HudStateKind.Refining` ("AI refining", busy) + tray mapping; `SettingsState.AiPolish`.
- Tests: `AIPolishTests` (the Mac suite translated + Windows additions) and `AIPolishDpapiTests`
  (real DPAPI round trip; Windows CI only). Local Linux run of the Core-only subset: 219/219.
- Next: push → CI; then the App side.
