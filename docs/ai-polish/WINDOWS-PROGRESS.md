# AI Polish on Windows — progress log

Branch **`feat/ai-polish-windows`** (from `origin/main` = `c0b97b6`, the shipped `windows-v1.1.0`).
Spec: `docs/ai-polish/WINDOWS-HANDOFF.md`. macOS reference: branch `feat/ai-polish` (read-only here).
Newest entries first. Updated after every step, so a new session can resume from this file alone.

## State

| Area | State |
|---|---|
| Core logic (`windows/JVoice.Core/AIPolish/`) | done |
| xUnit tests (`AIPolishTests`, `AIPolishDpapiTests`) | done — **CI run 43: 2052/2052 passed** on windows-latest (70 new incl. the real-DPAPI round trip) |
| App wiring (HTTP transport, DPAPI, coordinator, HUD, Settings, `--polish-eval`) | done — builds on CI (run 43, `6105855`) |
| CI UI preview artifact | done — run 43 rendered **all 24 shots `ok`** (incl. 6 AI Polish Settings states + `hud-refining`), artifact `windows-ui-preview` uploaded. **Not yet looked at:** this cloud container's proxy blocks the artifact host (`productionresultssa2.blob.core.windows.net`), so the PNGs have NOT been opened by Claude — David: see "Look at the UI" below |
| Docs (PRIVACY, HANDOFF §7 #70, briefs, windows/README) | done |
| Live dictation + eval with a real key | **David** (steps below) |
| Handoff §9 (resizable masonry Settings, AI Polish card, shared glow, second launch) | done — CI green on `f2c30bc`; every PNG opened and checked (step 5) |
| Independent review | done — `WINDOWS-REVIEW.md`, **8/10 (provisional: no Windows eval or screenshot check yet)**; fixes 1, 2, 5 (idle timeout), 6–10 done in step 4; 3 + 4 are David's (look at the PNGs, run the eval) |

## David: try it on your PC (PowerShell, from your jvoice clone)

**1. Get the branch, test, build, refresh the install** (quit JVoice first: it locks its files).
```powershell
cd $HOME\jvoice                      # wherever your clone is
git fetch origin feat/ai-polish-windows
git switch feat/ai-polish-windows     # first time: git switch -c feat/ai-polish-windows --track origin/feat/ai-polish-windows
git pull
dotnet test windows\JVoice.Tests\JVoice.Tests.csproj -c Release        # expect 2052/2052
Stop-ScheduledTask 'JVoice Elevated Autostart' -ErrorAction SilentlyContinue
Stop-Process -Name JVoice -ErrorAction SilentlyContinue
dotnet publish windows\JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=gpu -p:SelfContained=true `
  -p:PublishTrimmed=false -p:PublishReadyToRun=true -o windows\artifacts\gpu-folder
robocopy windows\artifacts\gpu-folder "$env:LOCALAPPDATA\Programs\JVoice" /MIR /XF uninstall.ps1 LICENSE.txt   # exit code < 8 = OK
Start-ScheduledTask 'JVoice Elevated Autostart'      # or: Start-Process "$env:LOCALAPPDATA\Programs\JVoice\JVoice.exe"
```

**2. Look at the UI** (Claude could not open the CI PNGs). Either download the `windows-ui-preview`
artifact from the latest "Windows" run of this branch on GitHub Actions, or render locally:
```powershell
$exe = "$env:LOCALAPPDATA\Programs\JVoice\JVoice.exe"
& $exe --ui-preview $env:TEMP\jvoice-ui | Out-Host; Invoke-Item $env:TEMP\jvoice-ui
```
Check `settings-aipolish-*.png` (nokey, zero, on, on-light, revealed, usedup) and `hud-refining.png`.
If anything looks off, copy the PNGs into `docs/ai-polish/windows-ui/` and commit them so the next
session can see them.

**3. In the app** — Settings → AI Polish:
- paste your key → **Save** → the field clears and the line reads "Key saved ••••abcd"; the eye shows /
  hides it (and it is hidden again after closing Settings); **Test Key** → "Key works.";
- Amount `5` → **Add** → "Balance: $5.00 left", full bar; switch **Polish with Claude** on.
- Dictate (watch for the orange "AI refining" pill): a run-on sentence; a question ("what is the
  capital of france" must paste as a question, never "Paris"); something with maths ("x squared plus 1
  equals 5"); then in the SAME app "we're moving the site to a new host" followed by "deploy it to
  versails" → should paste "Vercel".
- Pull the network cable / turn Wi-Fi off → dictate → the local text pastes within ~3 s.
- Amount `4.99` → **Remove**, dictate until the balance hits $0 → ONE "AI Polish balance used up — add
  more in Settings" pill after "Pasted"; later dictations paste unpolished with no pill; the red line
  shows in Settings.
- Log check (reason only, never text): `Select-String AIPolish "$env:APPDATA\JVoice\diagnostic.log" | Select-Object -Last 10`

**4. The eval** (from the repo root; ≈ $0.005 per run; the key never lands in history):
```powershell
$s = Read-Host "Anthropic key" -AsSecureString
$env:ANTHROPIC_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
$exe = "$env:LOCALAPPDATA\Programs\JVoice\JVoice.exe"
& $exe --polish-eval scripts\ai-polish-eval\cases.json --out docs\ai-polish\eval-results\windows-train-1.md | Out-Host
1..3 | ForEach-Object { & $exe --polish-eval scripts\ai-polish-eval\cases-test.json --out "docs\ai-polish\eval-results\windows-test-$_.md" | Out-Host }
& $exe --polish-eval scripts\ai-polish-eval\cases-realistic.json --out docs\ai-polish\eval-results\windows-realistic-1.md | Out-Host
Remove-Item Env:ANTHROPIC_API_KEY
git add docs\ai-polish\eval-results; git commit -m "AI Polish (Windows): eval results"; git push
```
(Once the key is saved in Settings you can skip the `$env:` lines.) Expect roughly the Mac's numbers
(test ≈ 96 %, p50 ≈ 0.8 s); a big gap points at a porting bug. Without `| Out-Host` PowerShell does not
wait for JVoice.exe (it is a windowed app) and prints nothing — the report file is still written.


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
   the balance. Its text is never used. The dictation's cancellation reaches the request only until
   the race is decided (the coordinator cancels the old token on the NEXT press — review fix 2).
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

### 2026-10-17 — step 5: handoff §9 (the Mac's evening changes)
- **1. Resizable Settings** (`UI/SettingsWindow.cs`): `SizeToContent.Manual`, `ResizeMode.CanResize`, min
  700 × 420 (Mac minimum; two ~316-DIP columns), no Max* caps — edge/corner drag and title-bar
  double-click / Maximize (fill + restore) are native Win32 and nothing blocks them. Opens at 1080 × the
  content's height at that width, capped to the work area − 16 (the §7 #33 "X never off-screen" guard is
  now a starting size, not a cap). Hide/show keeps the user's size and a maximized state (`ShowOrActivate`
  no longer forces `WindowState.Normal` — it used to un-maximize on every reopen).
- **2. Masonry** (`UI/MasonryPanel.cs` + pure `Core/Policy/MasonryLayout.cs`): content width picks 2 / 3 / 4
  columns at 560 / 900 / 1360 DIP (every column ≥ ~290 DIP, about today's card width); each card, in
  order, goes into the currently shortest column (tie → leftmost); WPF re-measures on every size change, so
  it reflows live while dragging. Content capped at 1440 and centred. Header + Stats full width on top,
  footer at the bottom. Order = the Mac's (Whisper Model, Recent Transcripts, Processing, Custom Words,
  Voice Style, Language, App Modes, Keyboard Shortcut, AI Polish, Tours & Tips, Appearance) with the
  Windows-only cards next to their neighbours: Corrections after Custom Words, Microphone after Language,
  Gaming after Keyboard Shortcut, Updates last. Cards lost their own bottom margin (the panel owns the
  12-DIP spacing).
- **3. AI Polish card** is a normal stacked card: switch + caption, key field + eye, Save · Test Key ·
  Remove Key (a WrapPanel so it never clips), status line "Key saved" / "No key saved" (or the last
  message), divider, balance + bar, Amount row, red used-up line, This month / All time. With a key
  saved, the empty field's placeholder is the hint "••••abcd" (`ApiKeyPlaceholder`), never the key.
- **4. One shared glow** (`UI/ClaudeGlowText.cs`, numbers in pure `Core/Policy/ClaudeGlow.cs`): a #D97757
  band swept through the letters + a breathing orange DropShadow. Full on the "AI refining" pill (1.6 s,
  0.2–0.7, blur 6) — the pill's own sweep code is gone; Subtle on the "AI POLISH" card title (3.2 s,
  0.12–0.35, blur 4, over Text.Secondary) via `SettingsCard.GlowHeader`. Animates only while visible
  (hidden pill / closed Settings cost nothing); still pose when Windows animations are off or off-screen.
- **5. Second launch** (`Platform/System/ShowSettingsSignal.cs`): before, launching `JVoice.exe` while it ran
  exited silently. Now the running copy listens on a per-session named event; a user launch that loses
  the single-instance race sets it and the running copy opens its real `SettingsWindow` (the same one the
  tray opens — never an empty window). The event's ACL is this user + SYSTEM with a Medium mandatory label,
  so a normal double-click also reaches an ELEVATED running copy. The `--autostart` step-aside and the
  elevated relaunch never signal (`CoordinatorDecisions.SecondLaunchOpensSettings`, tested).
- **6. Key folder**: the DPAPI blob lives in `%LOCALAPPDATA%\JVoice`, which inherits the user profile's
  owner-only ACL; JVoice never sets a wider ACL and never uses a shared location (renders use the
  throwaway profile).
- **7. Screenshots**: `--settings-render` takes `--size WxH|Wxfull`; `--ui-preview` adds settings-wide
  (1400 × full, both themes), settings-fill (maximized client area on 1920 × 1080, both themes; and on
  David's 1600 × 1080), settings-small (the 700 × 420 minimum's client area, both themes) and
  settings-small-full (2 columns at full height, both themes).
- **Seeing the PNGs from the cloud:** the artifact host is blocked here, so a new opt-in CI job
  `ui-snapshot` (only `feat/ai-polish-windows`, only when the commit message has `[ui-snapshot]`) commits 1x
  copies to `docs/ai-polish/windows-ui/ci/`; the session `git pull`s them. Normal CI runs stay read-only.
- **CI run on `f2c30bc`: green** (build, all tests, 33/33 previews `ok`). **Every PNG opened and checked:**
  - default 1080 (dark/light): 3 columns, no holes, nothing clipped; AI Polish card stacks cleanly with the
    orange title; footer reachable (the window scrolls when the work area is shorter);
  - wide 1400 (dark/light): 4 columns, shortest-column placement visible, no holes;
  - maximized 1920 and 1600: content capped at 1440 and centred, 4 columns, no holes;
  - minimum 700 × 420: 2 columns, scrollbar shown; at full height no holes or clipping (dark/light);
  - AI Polish states: no key (`sk-ant-…`, "No key saved"), $0 (hint `••••0000`, "Add a balance…"), on
    ($3.20 of $5 bar), on-light, revealed (placeholder key, eye-slash), used up (red line) — all correct;
    one tweak made: the `on` render now shows the empty field with the hint instead of a typed draft;
  - `hud-refining`: same size as the transcribing pill, orange band + glow mid-word; the other 8 pill
    states, Welcome (4) and tour tags (2) unchanged and clean; settings-update-available fine.
- Tests: `SettingsLayoutTests` (column thresholds, shortest-column placement + a 200-run random no-hole
  check, the glow values/pose, the second-launch rule). Local Core subset 255/255.

### 2026-10-17 — step 4: independent review + fixes
- ONE reviewer sub-agent (§5.7) wrote `docs/ai-polish/WINDOWS-REVIEW.md` on `e9effd6`: Accuracy 8 and
  Speed 8 (both provisional — no Windows eval yet), Usefulness 7, Never lose a dictation 9, Key security
  9, Balance + usage 7, Code fit 8; **overall 8/10 provisional**. It found no porting differences in the
  prompt/request/validator and no path that loses a dictation.
- Fixed from its ranked list:
  1. **Bug — top-up amount off by 100×:** "2,50" on an English PC read as $250 (thousands separator).
     Now `AIPolishUsageStore.ParseAmount`: either decimal mark, no thousands separators, same on every
     PC language; tested in en-US / ro-RO / de-DE.
  2. **Bug — the next dictation cancelled late billing:** the client's request token was linked to the
     dictation's token, which the coordinator cancels on the next press. Now forwarded only until the
     race is decided; test `ALateReply_IsStillBilled_EvenWhenTheNextDictationCancelsTheOldToken`.
  5. `PooledConnectionIdleTimeout` 5 min (TLS stays warm between dictations; the default is 1 min).
  6. A stale "used up" pill is never shown after a top-up (`AIPolishGate.ShouldShowUsedUp`).
  7. Hint file `anthropic-api-key.bin.hint` (last 4 chars): opening Settings no longer decrypts the key.
  8. Exact security wording (entropy is public: casual readers only; PRIVACY "another Windows account
     or another PC"); comment on which thread `PolishAsync` runs; stale "1933 tests" counts.
  9. Coordinator gating as pure `AIPolishGate.Plan` (off → skipped(balance) → skipped(short) → send), tested.
  10. Renders outside a throwaway profile stage "no key" (never decrypt the real key); placeholder is
      `test-key-not-real-0000`.
- CI run 39041792556 on `ac7ca5a`: build, all tests and `--ui-preview` (24/24 `ok`) green; artifact
  https://github.com/david53001/jvoice/actions/runs/39041792556/artifacts/12104062518 (not opened by Claude).
- **Next:** David runs steps 1–4 above; the next session reads his eval reports and the PNGs, and
  re-runs the review if anything moves.
- Not done (David): fix 3 (open the PNGs), fix 4 (the eval). Fix 5's `--cold` latency flag: skipped
  until the eval shows cold calls matter.

### 2026-10-17 — step 3: CI green + docs
- CI run 43 (`6105855`): build OK, **2052/2052 tests**, `--ui-preview` 24/24 shots `ok`, artifact
  uploaded. The artifact can't be downloaded from this cloud container (proxy blocks the blob host) —
  David opens it (step 2 above).
- Docs: `PRIVACY.md` (AI Polish = the opt-in third network call: what is sent, DPAPI key location,
  usage file), `docs/HANDOFF-WINDOWS.md` §7 #70 + persistence paths, `windows/README.md`, new briefs
  `JVoice.Core/AIPolish/CLAUDE.md` + `JVoice.App/AIPolish/CLAUDE.md`, index lines in the other briefs.

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
