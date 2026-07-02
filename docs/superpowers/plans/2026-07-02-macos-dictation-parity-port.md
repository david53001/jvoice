# macOS dictation-parity port — handoff prompt

Paste the fenced block below into a **fresh Claude Code session on the Mac** (the machine that
can build the Swift app). It brings the macOS JVoice app up to parity with the six Tier-A
"brain" features that currently only exist in the Windows port.

Context for David (not part of the prompt): these six features live on the Windows line
(`origin/windows-port` == `feat/dictation-modes`, tip `a1da436`). The macOS app is on `origin/main`
and has **none** of them. Swift/AppKit/WhisperKit can't build on the Windows box, so the plan was
written there but must be *executed* on the Mac. The prompt tells the agent to read the Windows
reference implementations straight out of git — no `windows/` folder exists on `main`.

---

```text
You are working UNATTENDED and AUTONOMOUSLY on the macOS JVoice app. Do NOT ask questions
mid-task — when something is ambiguous, pick the most reasonable interpretation given the goal
and the existing code, log the assumption inline + in your final summary, and keep going. The
ONLY reasons to stop: an irreversible/destructive action, spending money, or being truly blocked
with no path forward on any interpretation. Never push, never open a PR, never add a remote —
David does all outward-facing git himself. Commit locally on a feature branch as you go.

=== READ FIRST (load these before touching code) ===
Repo root: the JVoice repo (macOS app). Run `git fetch origin` first so `origin/windows-port` is
available locally. You will build ON macOS.

1. `CLAUDE.md` (repo root) in full — project rules, $0 budget, "never modify ../MacOSUtils",
   build/test commands.
2. `docs/HANDOFF.md` in full — macOS session state and conventions.
3. These macOS source files (your edit targets), in full:
   - Sources/JVoice/Models/SettingsState.swift
   - Sources/JVoice/Models/AppMode.swift
   - Sources/JVoice/Services/Transcription/TextProcessor.swift
   - Sources/JVoice/Services/Transcription/TranscriptionManager.swift
   - Sources/JVoice/Services/Orchestration/PasteManager.swift
   - Sources/JVoice/Services/Orchestration/StatsStore.swift
   - Sources/JVoice/Services/Orchestration/HotKeyManager.swift
   - Sources/JVoice/UI/SettingsView.swift
   - Sources/JVoice/VoiceCoordinator.swift
   - scripts/run-logic-tests.sh
4. The Windows reference implementations to port FROM — read via git (no `windows/` dir on main):
   - git show origin/windows-port:windows/JVoice.Core/Text/DeveloperTerms.cs
   - git show origin/windows-port:windows/JVoice.Core/Policy/AppModeResolver.cs
   - git show origin/windows-port:windows/JVoice.Core/Models/ToneStyle.cs
   - git show origin/windows-port:windows/JVoice.Core/Policy/StatsMath.cs
   - git show origin/windows-port:windows/JVoice.App/Platform/System/Paster.cs
   - git show origin/windows-port:windows/JVoice.App/Platform/System/ForegroundApp.cs
   - git show origin/windows-port:windows/JVoice.App/VoiceCoordinator.cs   (wiring reference only)

=== GOAL + DEFINITION OF DONE ===
Add six features to the macOS app so it matches the Windows port's dictation feature set:
(1) developer-terms correction pack, (2) dictate-to-translate, (3) app-aware modes + a new `Code`
tone, (4) clipboard-only paste, (5) a time-saved stat, (6) an opt-in undo-last-paste hotkey.
DONE means, on a Mac: `swift build` passes with 0 errors; `./scripts/run-logic-tests.sh` passes
(you extended it with the new pure sources + assertions); the swift-testing suite in
Tests/JVoiceTests compiles and your new @Test cases are added; and each feature has a Settings
control. Real @Test execution happens in CI (macos-15 + Xcode 16) — locally the suite compiles
but runs 0 cases (that is expected on a CLT-only setup; run-logic-tests.sh is the real local gate).
All work committed locally on a branch, nothing pushed.

=== STEPS (ordered by priority; each says its expected result) ===

STEP 0 — Branch. `git checkout main && git pull`, then `git checkout -b feat/dictation-parity`.
Expected: on a fresh branch off current main.

STEP 1 — SettingsState schema v2 -> v3 (foundation for several features).
In Sources/JVoice/Models/SettingsState.swift: bump `currentSchemaVersion` 2 -> 3. Add fields with
these exact defaults (match Windows): `developerTerms: Bool = true`, `translateToEnglish: Bool = false`,
`copyToClipboardOnly: Bool = false`, `appAwareModes: Bool = false`, `appModeRules: [AppModeRule] = []`.
Add each to the memberwise `init`, `CodingKeys`, `init(from:)` (as `decodeIfPresent(...) ?? default`),
and `encode(to:)`. Create a new `AppModeRule: Codable, Equatable` model `{ appMatch: String; mode: AppMode }`
(mirror windows/JVoice.Core/Models/AppModeRule.cs). Add `case code` to `AppMode` + its `displayName`
("Code"), but do NOT add it to `AppMode.toggled` (Windows keeps Code out of the manual cycle).
TEST: add a v2->v3 migration case to Tests/JVoiceTests/SettingsStateMigrationTests.swift proving an
old v2 blob (no new keys) decodes with all new fields at default (developerTerms == true, etc.).
Expected: existing migration tests still pass; old blobs load cleanly.

STEP 2 — Developer-terms pack (highest value; pure).
Create Sources/JVoice/Services/Transcription/DeveloperTerms.swift mirroring
windows/JVoice.Core/Text/DeveloperTerms.cs: `static let map: [String: String]` (port ALL ~165
entries verbatim, keys lower-cased) + `static func augment(_ base: [String: String]) -> [String: String]`
that lays the pack UNDERNEATH base (base wins). CRITICAL: also port the exclusion list from the
C# doc-comments/test (ambiguous English words that must NOT be keys: cursor, bolt, continue, render,
railway, remix, warp, astro, svelte, bun, pinecone, chroma, cohere, perplexity, grok, drizzle,
lovable, llama; keep the homophones that ARE included: jason->JSON, groq->Groq, gemini->Gemini,
mistral->Mistral). Wire it in VoiceCoordinator.finishTranscription: change the `userDict` line to
`let extra = developerTerms ? DeveloperTerms.augment(userDict) : userDict` and pass
`extraDictionary: extra` into `TextProcessor.process`. This reuses the existing
`TextProcessor.applyCorrections` mechanism unchanged (word-boundary, case-insensitive, longest-first;
built-in correctionDictionary still wins). Add `@Published var developerTerms: Bool` to
VoiceCoordinator (didSet -> persistSettings), mirror in init/persistSettings/resetSettings. Add a
Settings toggle "Developer Terms" (subtitle "Fix coding terms: Node.js, GitHub, TypeScript, JSON, C#…")
copying the existing "Remove Filler Words" Toggle(...).toggleStyle(.switch) pattern in
SettingsView.processingSection.
TEST (TDD — write first): new Tests/JVoiceTests/DeveloperTermsTests.swift asserting a sample of
mappings ("node js"->"Node.js", "jason"->"JSON") AND that the exclusion words are absent from `map`;
add DeveloperTerms.swift to the swiftc list + assertions in scripts/run-logic-tests.sh.
Expected: `./scripts/run-logic-tests.sh` passes with the new dev-terms assertions.

STEP 3 — Time-saved stat (trivial; pure).
In Sources/JVoice/Services/Orchestration/StatsStore.swift add a computed
`var estimatedMinutesSaved: Double` implementing windows/JVoice.Core/Policy/StatsMath.cs
EstimatedMinutesSaved: `if totalWords <= 0 { return 0 }; let typing = Double(totalWords)/40.0; let
spoken = totalSeconds > 0 ? totalSeconds/60 : 0; return max(0, typing - spoken)` (40 == the WPM
baseline; expose totalSeconds or compute inside StatsStore). Add `@Published private(set) var
minutesSaved: Double` to VoiceCoordinator, set it next to `totalWordsSpoken/averageWPM` after
`statsStore.record(...)` and in init/resetSettings, with a display like Windows ("—" if <1, "{n} min",
"{n/60} h"). In SettingsView.statsSection make the card 3-up: add a third `stat(...)` cell + a 0.5pt
divider Rectangle for "time saved" (reuse the existing `stat` helper).
TEST: add estimatedMinutesSaved cases to StatsStoreTests (floors at 0, 40-wpm math). No SettingsState
change (derived stat).
Expected: stats card shows three cells; math test passes.

STEP 4 — `Code` tone formatting.
In TextProcessor.format add `case .code: return trimmed` (minimal: whitespace-trim only, no
punctuation/caps changes — verbatim from windows ToneStyle.Code => trimmed). Confirm the
`mode == .veryCasual ? lowercased` branch in `process(...)` already skips .code (it does). Decide
ToneMode handling: keep the manual segmented picker 3-way (casual/formal/veryCasual) and expose Code
ONLY as a per-app override (matches Windows) — so `.code` reaches `finishTranscription` via the
resolver in STEP 5, not the picker. Log this decision.
TEST: extend TextProcessorTests: `.code` preserves casing/symbols/punctuation as spoken.
Expected: run-logic-tests.sh passes with the new .code assertion.

STEP 5 — App-aware modes (depends on STEP 4).
Create a PURE Sources/JVoice/Services/Transcription/AppModeResolver.swift mirroring
windows/JVoice.Core/Policy/AppModeResolver.cs: `static func resolve(bundleId: String?, userRules:
[AppModeRule], enabled: Bool) -> AppMode?` — returns nil if !enabled/nil id; user rules first
(case-insensitive substring of `rule.appMatch`, in order); then a built-in code-app list by match
-> .code; else nil. ADAPT the Windows exe-name list to macOS BUNDLE IDs (this is the one
non-verbatim part — log it): e.g. com.microsoft.VSCode, com.apple.Terminal, com.googlecode.iterm2,
com.todesktop.230313mzl4w4u92 (Cursor), com.jetbrains.* (IntelliJ/PyCharm/CLion/GoLand/WebStorm/Rider),
com.sublimetext.*, dev.warp.Warp-Stable, org.alacritty, com.github.wez.wezterm, com.apple.dt.Xcode,
etc. In VoiceCoordinator.stopRecordingAndTranscribe capture the target's bundle id
(`NSWorkspace.shared.frontmostApplication?.bundleIdentifier` or
`NSRunningApplication(processIdentifier: resolvedTargetPID)?.bundleIdentifier`); in finishTranscription
compute `let effectiveMode = appAwareModes ? (AppModeResolver.resolve(bundleId:, userRules: appModeRules,
enabled: true) ?? toneMode.appMode) : toneMode.appMode` and pass `mode: effectiveMode` into
TextProcessor.process (replacing `mode: toneMode.appMode`). Add `@Published var appAwareModes` +
`appModeRules` to VoiceCoordinator (persist on change). Add an "App Modes" Settings card: master
toggle "Auto-switch by App" + a rule list with add/remove and a click-to-cycle mode chip (match
Windows §32; a simple ComboBox is acceptable if the chip is heavy — log the choice).
TEST: new Tests/JVoiceTests/AppModeResolverTests.swift (user-rule precedence, built-in match, nil when
disabled); add AppModeResolver.swift to run-logic-tests.sh.
Expected: run-logic-tests.sh passes; dictating into VS Code/Terminal yields Code-mode formatting.

STEP 6 — Dictate-to-translate (engine).
In TranscriptionManager.swift add a trailing `translate: Bool = false` to the
WhisperKitTranscriptionEngine init and thread it into decodeFile/decodeSamples as
`decodeOptions.task = .translate` (WhisperKit 1.0.0 `DecodingOptions.task: DecodingTask` with
`.transcribe`/`.translate`). VERIFY that exact symbol on the Mac at build time (WhisperKit source
wasn't available where this plan was written); if renamed, find the equivalent and log it. Keep
`decodeOptions.language = language.whisperCode` as the SOURCE hint (whisper only translates to English).
Add `translate:` to both engine factories (VoiceCoordinator.makeTranscriptionEngine and
TranscriptionManager.makeDefaultEngine). Add `@Published var translateToEnglish: Bool` with the SAME
didSet pattern as `transcriptionLanguage` (rebuild engine via updateEngine + persistSettings). Add a
Settings toggle "Translate to English" (subtitle "Speak the language above, paste English").
Expected: with a Romanian model + toggle on, spoken Romanian pastes as English.

STEP 7 — Clipboard-only paste.
In PasteManager.swift add `func copyOnly(_ text: String)` doing a PLAIN
`NSPasteboard.general.setString(text, forType: .string)` (NOT stage() — the user wants it visible in
clipboard history, whereas stage() adds Transient/Concealed markers). In VoiceCoordinator.finishTranscription,
when `copyToClipboardOnly` is on, SKIP the targetApp.activate()+sleep+pasteManager.paste(...) block and
call copyOnly instead, treating it as success (keep the downstream stats/history/HUD .done block).
Note the genuine bonus: clipboard-only needs no Accessibility trust (no Cmd+V) — log it. Add
`@Published var copyToClipboardOnly` + a Settings toggle "Copy to Clipboard" (subtitle "Copy the text
instead of auto-pasting it").
Expected: with the toggle on, a dictation lands on the clipboard and never synthesizes Cmd+V.

STEP 8 — Undo-last-paste hotkey (opt-in second shortcut).
In HotKeyManager.swift add `static let undoLastPaste = Self("undoLastPaste")` with NO `default:`
(unset == disabled; a registered global chord is swallowed system-wide, so no default — matches
Windows). In VoiceCoordinator add a second HotKeyManager(shortcutName: .undoLastPaste) { undoLastPaste() }
and .register() it in start(). Add PasteManager.sendUndo() mirroring synthesizeCommandVPaste but with
`CGKeyCode(kVK_ANSI_Z)` + `.maskCommand` (Carbon.HIToolbox already imported), gated on
accessibilityTrusted(), sent to the frontmost app PID. Make undoLastPaste() ONE-SHOT: track
`lastPastedText`/`lastPastedPID` set in the paste path (STEP 7 leaves them unset for clipboard-only),
only fire if the frontmost app is still that PID, then clear them. Add a
KeyboardShortcuts.Recorder("Undo Last Paste:", name: .undoLastPaste) card (caption "Optional — sends
the app's Undo (Cmd+Z) to reverse the last paste"). No SettingsState field (KeyboardShortcuts persists it).
Expected: after recording a chord and dictating, pressing it once sends Cmd+Z to the app you pasted into.

=== RULES ===
- Branch off main; commit locally per feature ("feat(mac): developer-terms pack", etc.). NEVER push,
  NEVER open a PR, NEVER add a remote. NEVER `git add -A` blindly — stage the files you changed.
- Do NOT modify anything under `windows/`, `../MacOSUtils`, or `Package.swift`/`Package.resolved`
  unless a step requires it. The `windows/` tree is read-only reference (via git show).
- Do NOT change the default Whisper model — macOS stays `.tiny`. (Windows' default -> Large is a
  DELIBERATE divergence; do not port it. Same for game-detection, run-elevated, the HUD redesign,
  and engine flash-attention — all out of scope.)
- TDD for every pure-logic piece (DeveloperTerms, AppModeResolver, StatsStore math, TextProcessor
  `.code`, SettingsState migration): write the failing @Test / run-logic-tests.sh assertion first,
  then implement. No faking, no skipped tests, no weakened assertions.
- Match existing code: reuse `TextProcessor.applyCorrections`, the `stat(...)` cell, the
  `processingSection` Toggle style, and the `transcriptionLanguage` didSet-rebuild pattern verbatim.
- Build gate: `swift build` (0 errors) AND `./scripts/run-logic-tests.sh` (green) before each commit.
  The swift-testing suite compiles locally but executes 0 cases on a CLT-only setup — that is normal;
  CI (macos-15 + Xcode 16) runs the real cases. Do not claim tests "pass" from a 0-executed local run;
  say "compiles locally; run-logic-tests.sh green; CI runs the @Tests".
- If `swift build` fails on a WhisperKit symbol (STEP 6), that's the expected verification point —
  find the real symbol in the resolved WhisperKit 1.0.0 and adjust; don't stub it out.

=== WHEN DONE ===
- Append a session entry to `docs/HANDOFF.md`: the six features, files added/changed, test counts,
  and every logged assumption (bundle-ID list, DecodingOptions.task symbol, ToneMode/Code exposure,
  App Modes chip-vs-combobox, clipboard-only-needs-no-AX).
- Report back a short summary: what changed per feature, `swift build` + run-logic-tests.sh results
  (paste the real output lines), what still needs David's eyes (esp. STEP 6 symbol + the bundle-ID
  list completeness), and confirm nothing was pushed.
```
