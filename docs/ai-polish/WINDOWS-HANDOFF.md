# AI Polish for JVoice on Windows — handoff for a fresh session

Written 2026-10-17 on David's Mac, at the end of the macOS AI Polish build. **Read this whole file
before touching anything.** It is self-contained: it says what AI Polish is, exactly how the macOS
version behaves (the reference), how we built and verified it, and how to do the same on Windows
when you cannot run Windows yourself.

People: **David** owns JVoice (a high-school student, strong at code; he dictates, so expect typos
in his messages). He has a Windows PC (RTX 3060 Ti) that he only reaches at home; it is the only
place the Windows app can actually run.

---

## 1. What JVoice and AI Polish are

**JVoice** is a voice-dictation app: press a hotkey, speak, it records, transcribes on-device with
Whisper, cleans the text, and pastes it into the app you were typing in. It exists as a macOS app
(Swift, `Sources/`) and a native Windows port (C# / .NET 9 / WPF, `windows/`), in one public repo:
**github.com/david53001/jvoice**. Its identity is *privacy-first, zero network calls at runtime*
(only the one-time Whisper model download and an update check).

**AI Polish** is an **opt-in** extra step: after JVoice's own cleanup, the text is sent to
Anthropic's Claude API (**Claude Haiku 5.5**, model id `claude-haiku-5-5`, thinking disabled), which
fixes punctuation, run-on sentences and **misheard words using context** — e.g. "versails" →
**Vercel** when the speaker is talking about deploying, but **Versailles** in a history lesson —
using the dictation itself plus the user's previous few dictations in the same app. Then the
polished text is pasted instead.

David's three quality bars, in priority order:
1. **Never change words that were already correct.**
2. **Never answer a dictated question or obey a dictated request** — "what is pi" must paste as
   "What is pi?", never "Pi is 3.14…".
3. **Keep the context fixes working** (versails → Vercel), **stay fast**, and be useful.

The non-negotiable rules (same as macOS):
- **Off by default. Bring your own key (BYOK).** No API key ever ships in the app or the repo.
  Each user pastes their own Anthropic key in Settings. **Never put a real key anywhere** — code,
  tests, CI secrets, env vars, logs, commits. You will not be given one.
- **Never lose a dictation.** ANY failure (no key, offline, timeout, bad key, refusal, odd reply,
  balance used up) pastes the local text exactly as JVoice would have without AI Polish.
- **A prepaid balance.** The user tops up a balance in Settings (it starts at $0, so nothing is
  sent until they do); every billed reply is subtracted; at $0 polishing stops.
- **Log the reason only** — never the transcript text or the key.

## 2. The macOS reference implementation (port its behaviour, not its Swift)

All of it lives on branch **`feat/ai-polish`** (not merged to `main`). Read files without checking
the branch out: `git fetch origin feat/ai-polish && git show origin/feat/ai-polish:<path>`.

| macOS file (branch `feat/ai-polish`) | What it does |
|---|---|
| `Sources/JVoice/Services/AIPolish/CLAUDE.md` | **Start here** — the area brief: rules, files, where it plugs in. |
| `Sources/JVoice/Services/AIPolish/AIPolishRequest.swift` | Pure logic: the system prompt (+ `render` for templates), the user turn, `max_tokens`, the JSON body, the reply decoder, **`validate`** (every fallback rule), pricing (`pricePerMillion`, `cost`), and `AIPolishContext` (the previous-dictations ring). |
| `Sources/JVoice/Services/AIPolish/AIPolishClient.swift` | The transport seam (tests fake it), the ephemeral HTTP session, `AIPolishResult`, and **the hard deadline** (a race that never waits for a transport that ignores cancellation; the key read is inside the deadline). |
| `Sources/JVoice/Services/AIPolish/AIPolish.swift` | The façade the coordinator calls; `isWorthPolishing` (≥ 3 words); `checkKey` (Settings → Test Key: a 1-token request, mapped to plain-English messages). |
| `Sources/JVoice/Services/AIPolish/APIKeyStore.swift` | Where the key lives on macOS (an owner-only file — see §4 for why, and why Windows should do better). |
| `Sources/JVoice/Services/AIPolish/AIPolishUsageStore.swift` | Spent "this month" / "all time" totals, the **balance**, `addBalance` (cap $1000), `removeBalance`, `record` (subtracts, clamps at $0, returns "this reply used it up"), `shouldPolish`. |
| `Sources/JVoice/Services/AIPolish/PolishEvalRunner.swift` | The hidden `--polish-eval` CLI (the eval harness, §6). |
| `Sources/JVoice/VoiceCoordinator.swift` (`finishTranscription`, and the "AI Polish key" / balance functions) | Where polish plugs in: after the local cleanup + maths, before paste; HUD shows "AI refining"; usage recorded; the one "balance used up" pill. |
| `Sources/JVoice/Models/HUDState.swift`, `Sources/JVoice/UI/HUDView.swift` (`RefiningPill`) | The new `.refining` HUD state: "AI refining" with a Claude-orange glow sweeping through the letters. |
| `Sources/JVoice/UI/SettingsView.swift` (`aiPolishSection`, `aiPolishKeyColumn`, `polishBalanceColumn`) | The Settings section (full width, at the very bottom). |
| `Tests/JVoiceTests/AIPolishTests.swift`, AI Polish section of `scripts/run-logic-tests.sh` | Every rule locked by tests — translate these to xUnit. |
| `scripts/ai-polish-eval/cases.json` (78, training), `cases-test.json` (50, **hidden test set**), `prompts/*.txt` | The eval data + prompt templates (`minimal-edit.txt` = the shipped prompt v2; `baseline.txt` = v1). |
| `docs/ai-polish/PROTOTYPE-PLAN.md`, `PROGRESS.md`, `REVIEW.md`, `eval-results/` | The original spec, the full progress log + decisions, the independent review (7/10, ranked fixes), all eval runs. |

### 2.1 Behaviour to reproduce exactly (constants are copied from the Mac code — keep them)

- **When it runs:** only if the AI Polish switch is on AND a key is saved AND balance > $0 AND the
  local text has ≥ 3 words. Otherwise paste the local text (log `AIPolish skipped(short)` /
  `skipped(balance)`).
- **Where:** after the local cleanup (TextProcessor + correction packs + Math Notation), after the
  "empty → no speech" check, before paste / copy-only. The polished text replaces the local text
  everywhere downstream (paste, copy-only, HUD, history, stats, undo record).
- **Request:** `POST https://api.anthropic.com/v1/messages`, headers `x-api-key: <key>`,
  `anthropic-version: 2023-06-01`, `content-type: application/json`. Body: `model`
  `claude-haiku-5-5`, `max_tokens` = `min(4096, max(256, 3 × ceil(chars/3)))`, `thinking:
  {"type":"disabled"}`, `system` = the prompt, one user message `<previous>\n…\n</previous>\n<transcript>\n…\n</transcript>`
  (`<previous>` omitted when empty). **No** `temperature`/`top_p`/`top_k` (400 on this model), **no**
  assistant prefill (400). No cookies, no cache, no stored credentials on the HTTP client.
- **System prompt:** byte-identical to `scripts/ai-polish-eval/prompts/minimal-edit.txt` with
  `{{TONE}}`, `{{TONE_RULE}}`, `{{CUSTOM_WORDS}}` filled exactly like the Mac's `toneLabel`,
  `toneRule`, `customWordList` (custom words joined by ", ", or `none`). Lock it with a test that
  compares against the file for every tone (the Mac does this).
- **Deadline:** 3.0 s for the whole thing, including reading the key. On timeout: local text. The
  deadline must win even if the HTTP call ignores cancellation (use `Task.WhenAny` against a timer,
  not just a CancellationToken).
- **Reply handling:** concatenate the `text` content blocks; accept only `stop_reason == "end_turn"`;
  then **`validate`** — port every rule and threshold from `AIPolishRequest.validate` in order:
  unwrap `<transcript>` tags / surrounding quotes; empty → fallback; longer than `2 × input + 40`
  chars → `too-long`; chatty openers ("Sure", "Here is" … unless the transcript itself says them) →
  `chatty`; `<previous`/`<transcript` tags or a ≥ 20-char previous dictation echoed → `leaked-context`;
  shorter than 60 % of a ≥ 15-char transcript → `too-short`; under 60 % of the transcript's 3+-letter
  words kept (needs ≥ 3 such words; number words ignored) → `dropped-words`; **more than
  `max(2, 20 % of the transcript's tokens)` new tokens, or any new token after the last "?"** →
  `added-content` (this is what stops answers to short questions). Then re-apply the tone's own
  formatting to the reply (the Mac calls `TextProcessor.format(_, mode:)`); if that comes out empty,
  keep the local text.
- **Context ring:** in memory only, never saved. Last 3 **pasted** results, same target app (on
  Windows use the foreground exe name, `ForegroundApp.ExeName`), from the last 10 minutes, oldest
  first, ≤ 1,500 chars total; no app id → no context. Cleared when AI Polish is switched off.
- **Usage + balance:** price = $0.10 / $0.50 per million input / output tokens for
  `claude-haiku-5-5` ($2 / $10 for `claude-sonnet-5-5`, used only by the eval). Every reply that
  came back (used or not) is billed: add to month / all-time totals and subtract from the balance
  (clamp at $0). Calls with no reply (offline, timeout) aren't recorded. "This month" restarts on the
  first polish of a new calendar month. Add: refuse ≤ 0, NaN, or > $1000; remember the last top-up
  (the bar shows balance ÷ last top-up). Remove: refuse ≤ 0 / NaN, never below $0. There is **no
  Reset** for the spent totals (David removed it).
- **HUD:** while waiting on Claude the pill shows **"AI refining"** with a Claude-orange
  (`#D97757`) highlight sweeping through the letters (1.6 s period) and a soft orange glow — the same
  "Claude is working" look as David's terminal dashboard. It is the one coloured element allowed in
  the otherwise monochrome Windows UI (David asked for it). Same pill size as the transcribing pill.
  When a reply uses the balance up: after the paste, ONE pill "AI Polish balance used up — add more
  in Settings"; later dictations at $0 skip polish silently (no repeated pop-ups).
- **Settings → AI Polish** (full width, the **last** section, above the footer): left half — switch
  "Polish with Claude" with caption "Sends dictations to Claude to fix mistakes." (the switch reads
  **off** and is disabled while there is no key or the balance is $0; caption under it "Save your
  Anthropic API key below to turn this on." / "Add a balance to turn this on."), the key field
  **masked by default** with an **eye button** to reveal (reveal resets when Settings closes), Save
  (clears the field; then "Key saved ••••abcd"), Test Key, Remove Key. Right half — "Balance: $0.73
  left", a thin bar, "Amount $ [5] Add Remove", a red line "Balance used up — add more to keep
  polishing." when it ran out, then "This month: $x · n polishes" and "All time: $x · n polishes"
  (amounts under a cent show 4 decimals, e.g. "$0.0001").
- **Test Key:** a 1-token request; 200 → "Key works.", 401 → "Invalid key — Anthropic didn't accept
  it.", 429 → rate-limited message, network error → "Couldn't reach Anthropic…", other → Anthropic's
  own error message (shown in Settings only, never logged).
- **Log line** (the app's diagnostic log): `AIPolish ok|fallback(<reason>) <ms>ms context=<n>
  changed=<bool>` — reason only.

## 3. Where it goes on Windows (read these Windows docs first)

- `windows/CLAUDE.md` (area index) and each area's `CLAUDE.md`; `docs/HANDOFF-WINDOWS.md` is the
  zero-context anchor for the Windows port (§7 is a numbered change log — the last entry is #69; add
  yours as **#70**); root `CLAUDE.md` (hard rules + the Windows section).
- `windows/JVoice.App/VoiceCoordinator.cs` — the orchestrator (the Windows twin of the Mac's
  `finishTranscription`).
- `windows/JVoice.Core/` — the portable brain (`net9.0`, no Win32). **Put all pure AI Polish logic
  here** (prompt, request body, validate, context ring, pricing, usage/balance math, eval grading),
  so it is testable and compiles anywhere.
- `windows/JVoice.App/` — WPF shell (`net9.0-windows`): HTTP transport, key storage, the
  coordinator hook, HUD (`UI/HudView.xaml`, `UI/HudWindow.cs`), Settings (`UI/SettingsView.xaml`,
  a 960-wide three-column masonry since HANDOFF §7 #33 — put AI Polish **full width below the columns**).
- `windows/JVoice.Core/Models/SettingsState.cs` (+ `SettingsStateJson.cs`) — schema is **v6**. Add
  `AiPolish` (default false) the Windows way (per-field JSON fallback, bump to v7 if that's the
  convention — check how v5 → v6 was done in HANDOFF §7 #47).
- `windows/JVoice.App/Platform/Persistence/` — `PlatformPaths` (`%APPDATA%\JVoice`), settings/stats
  stores; usage + balance can be a small JSON file there.
- Hidden CLI modes already exist (`App.xaml.cs`, `Diagnostics/UiPreviewRunner.cs`):
  `--settings-render <png> [dark|light]`, `--hud-render <png> <state>`, and `--ui-preview <dir>`
  which renders **every** surface off-screen with a throwaway profile. Add the new states to them.

## 4. Windows-specific decisions (yours to make — record each in the progress log)

- **Key storage — do better than the Mac.** On macOS the key had to move from the Keychain to an
  owner-only file because the self-signed app made macOS ask for the user's password after every
  update (David's decision, 2026-10-17; trade-off documented in `PRIVACY.md`). Windows has no such
  problem: encrypt the key with **DPAPI** (the Windows Data Protection API, which encrypts data so only the
  same Windows user on the same machine can decrypt it: `System.Security.Cryptography.ProtectedData.Protect`,
  `DataProtectionScope.CurrentUser`, with an app-specific entropy) and store the blob in
  `%LOCALAPPDATA%\JVoice\anthropic-api-key.bin` (Local, not Roaming), or use Windows Credential
  Manager (`CredWrite`, generic credential, local persistence). Either way: **no prompts ever**,
  readable only by this Windows user, never in settings JSON, logs, history or the clipboard. Write
  via a temp file + replace. The masked hint is computed from the stored key.
- **HTTP:** one `HttpClient` with `UseCookies = false`, no cache, no proxy credentials; the deadline
  as in §2.1.
- **HUD look:** follow the current Windows pill (near-solid, sized like the Mac's — HANDOFF #67/#68);
  the refining pill shows the "AI refining" text with the orange sweep + glow. Respect reduced
  motion if the app already does.
- **Settings at small resolutions:** David runs a non-native 1600×1080 desktop; the window is
  clamped to the work area (HANDOFF #33) — make sure the new section doesn't push the footer
  off-screen (the outer ScrollViewer must still work).
- **Eval CLI on Windows:** `JVoice.exe --polish-eval <cases.json> [--model …] [--thinking off|low]
  [--prompt-file <template.txt>] [--out <file.md>]`, same output format as the Mac runner (per-case
  PASS/FAIL with in/out, per-category accuracy, "by a real polish", do-nothing baseline, fallbacks,
  p50/p95/max latency, tokens, cost). **Refuse unknown arguments** (a silently ignored flag once made
  three "different" runs the same config). Key from `ANTHROPIC_API_KEY`, else the saved key; never
  printed. It must reuse the same request builder / validator / client as the app, not a copy.

## 5. How we work (the system to replicate)

1. **A progress log.** Create `docs/ai-polish/WINDOWS-PROGRESS.md` (state table + log, newest
   first) and update it after **every** step: what's done, CI status, next step. Sessions end
   without warning; the next one resumes from it.
2. **Tests lock every rule.** Translate `Tests/JVoiceTests/AIPolishTests.swift` and the AI Polish
   section of `scripts/run-logic-tests.sh` to xUnit in `windows/JVoice.Tests/` (fake transport, a
   placeholder key like `test-key-not-real-0000`, no network). Include: the request shape and
   headers, the prompt byte-identical to `minimal-edit.txt` per tone, every `validate` fallback (incl.
   "what is pi" → "Pi is approximately 3.14159." and "What is twelve times eight? 96" both fall
   back, while "Deploy it to Vercel." for "deploy it to versails" passes), the deadline beating a
   stalled transport, the context ring, pricing, balance add/remove/clamp/used-up-once, month
   rollover, key storage round trip in a temp folder.
3. **CI is your compiler and test runner.** You are on Linux in the cloud: you cannot build or run
   WPF. `.github/workflows/windows.yml` runs on `windows-latest` for pushes to `feat/**` that touch
   `windows/**` (build Release + `dotnet test` + a "tests actually ran" check). Push, then
   `gh run list --branch <branch> --limit 1` and `gh run watch <id> --exit-status`. Logs are huge:
   `gh run view <id> --log-failed > ci.log` and grep for `error`, `Failed`, `[FAIL]`. If .NET 9 is
   installable in your container, you can at least `dotnet build windows/JVoice.Core` and run pure
   logic locally — the WPF projects need Windows (or `-p:EnableWindowsTargeting=true` to *compile*
   only).
4. **Look at the UI through CI.** This is how you "see" Windows: add a step to `windows.yml` (after
   the build) that runs `windows/JVoice.App/bin/Release/net9.0-windows/win-x64/JVoice.exe --ui-preview
   ${{ github.workspace }}/ui-preview` (find the exact exe path from the build output) and uploads
   the folder as an artifact (`actions/upload-artifact@v4`, name `windows-ui-preview`, `if: always()`).
   Then `gh run download <id> -n windows-ui-preview -D <dir>` and **open every PNG** (your file-read
   tool shows images) — check the AI Polish section in dark and light, the refining pill, spacing,
   clipping, contrast. Add preview shots for the AI Polish states: no key; key + $0 (switch off,
   "Add a balance…"); key + $3.20 of $5 with the bar; used up (red line); revealed vs masked field;
   and `hud-refining`. If WPF rendering fails on the CI runner, say so in the progress log and ask
   David to run `JVoice.exe --ui-preview <dir>` on his PC and commit the PNGs.
5. **The eval decides, not opinions.** Single runs are noisy (the same prompt scored 84.6 % and
   92.3 % on Mac). Never tune on `cases-test.json`'s words; compare configs on ≥ 3 runs; report
   latency next to accuracy. Ship the Mac's prompt v2 unchanged unless the Windows eval shows a
   Windows-specific reason — the model and prompt are platform-independent, so the Mac numbers
   should reproduce (Mac v2: train 96.2 %, hidden test 96.0 %; no-false-fix 100 %, no-answer 100 %,
   hold-out context fixes 100 %; p50 ≈ 780 ms, p95 ≈ 1.1–1.4 s; ≈ $0.00009 per dictation).
   Differences point at a porting bug in the request builder or validator.
6. **David runs everything that needs the key or the real app** (he is the only one with a Windows
   PC and a key). Give him exact, copy-pasteable PowerShell in the progress log. To pass the key
   without it landing in history:
   ```powershell
   $s = Read-Host "Key" -AsSecureString
   $env:ANTHROPIC_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
   .\JVoice.exe --polish-eval scripts\ai-polish-eval\cases-test.json --out docs\ai-polish\eval-results\windows-test-1.md
   Remove-Item Env:ANTHROPIC_API_KEY
   ```
   (or, once the key is saved in Settings, just run it without the env var).
7. **One independent reviewer at the end.** Spawn exactly ONE fresh sub-agent (no other sub-agents,
   no workflows unless David asks) with the macOS review brief (`docs/ai-polish/PROTOTYPE-PLAN.md`
   §10) adapted to Windows: score accuracy, speed, usefulness, never-lose-a-dictation, key security,
   balance + usage, code fit 1–10 with evidence (file:line, eval numbers, CI and screenshot
   artifacts), ranked fixes; write `docs/ai-polish/WINDOWS-REVIEW.md`. Then fix what it ranks
   highest.

## 6. Git and safety rules

- Start from **`origin/main`** (= `origin/windows-port`, commit `c0b97b6`, the shipped
  `windows-v1.1.0`). Create **`feat/ai-polish-windows`**. Bring over the shared, platform-free files
  from the Mac branch: `git checkout origin/feat/ai-polish -- scripts/ai-polish-eval docs/ai-polish`
  (eval data, prompts, the Mac docs for reference). Do **not** bring over `Sources/`, `Tests/`,
  `Package.swift` or the Mac `PRIVACY.md` changes — the macOS app is read-only for Windows work and
  its AI Polish branch is not merged.
- Push **only** `feat/ai-polish-windows`. Never push or merge to `main`/`windows-port`/any other
  branch, never tag, never create or edit a release, never rebuild the installers, never force-push.
  The repo is **public**: never commit a key, a `.env`, or David's personal data.
- Don't change Whisper / audio / the brain's existing behaviour — AI Polish is additive.
- Update `PRIVACY.md` (its Windows section and the "where your data lives" list: AI Polish is the
  one opt-in network call; what is sent; where the key is stored), `windows/README.md` if it lists
  features, and `docs/HANDOFF-WINDOWS.md` §7 #70.

## 7. Done = ready for David to try

- CI green on `feat/ai-polish-windows` (build + all xUnit tests incl. the new ones) and the
  `windows-ui-preview` artifact shows the AI Polish section and the refining pill looking right in
  dark and light (you opened and checked every relevant PNG).
- `WINDOWS-PROGRESS.md` has David's steps: pull the branch on the PC, build/publish and refresh the
  install exactly as `docs/HANDOFF-WINDOWS.md` describes (quit any running/elevated JVoice first),
  Settings → AI Polish: paste key → Save → masked hint, eye toggles, Test Key → "Key works.", add
  $5, switch on; dictate a run-on sentence, a question ("what is the capital of france" must stay a
  question), something with maths, and "we're moving the site to a new host" then "deploy it to
  versails" in the same app (→ Vercel); unplug the network → local text pastes within ~3 s; Remove
  $4.99 → used-up pill once; the eval commands (§5.6) on both case files, 3 runs of the test set.
- The reviewer's `WINDOWS-REVIEW.md` exists and its top fixes are done or listed.

## 8. Open items already known from the Mac review (fix on Windows from the start)

From `docs/ai-polish/REVIEW.md` (Mac, 7/10): context-from-previous is the weak category (hidden test
66.7 % — "flour" while baking, `useCart` in React code); multi-word sound-alikes ("mighty chondria" →
mitochondria) are sometimes missed; the training case `cp-django` can never pass (its
`mustNotContain` "jango" is inside "Django" — change it to `" jango "`); the eval inputs are mostly
lowercase without punctuation while real Whisper output is cased and punctuated (add realistic
variants + ≥ 8 short questions); the "used up" pill can be lost when the paste itself fails (keep it
pending and show it next time); a reply that arrives after the 3 s deadline was billed but isn't
subtracted from the balance. Prompt changes must stay byte-identical between
`prompts/minimal-edit.txt` and the code, on both platforms.
