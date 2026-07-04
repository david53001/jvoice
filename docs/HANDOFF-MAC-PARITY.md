# HANDOFF — Bring the macOS app up to Windows parity

**Status:** ready to execute · **Owner of this run:** a fresh Claude Code session **on David's Mac** ·
**Branch:** `feat/mac-parity` (already pushed; this doc lives on it) · **Created:** 2026-07-04 (from the Windows machine)

> **⚠️ READ THE DIRECTION TWICE — it is the opposite of the usual rule.**
> For this one task **Windows is the source of truth** and the **macOS app is the target that must
> change to match it.** The Windows port under `windows/` has grown ~11 features and a redesigned UI
> that the macOS app (`Sources/JVoice/`) does **not** have yet. Your job on the Mac is to **port those
> Windows features and that UI onto the macOS Swift app** so the two products feel the same — **with one
> explicit exception: the animated HUD "pill" (the moving voice-activity bars). Leave the HUD alone.**
>
> This **inverts** the standing rule in `CLAUDE.md` ("Never modify the Windows port / the Swift app is
> read-only reference"). For *this* task the roles flip: **`windows/` is now read-only reference; you
> edit `Sources/`, `Tests/`, `Package.swift`, `Resources/`, `docs/`.** Do **not** edit anything under
> `windows/`.

---

## 1. Context & goal

JVoice is a menu-bar / tray voice-dictation app. Press a hotkey → record → on-device Whisper
transcription → tone-styled text pasted into the frontmost app. It exists as two native products in **one
mono-repo**:

- **macOS** (`Sources/JVoice/`, SwiftUI + WhisperKit) — the original. Clean, small, **feature-behind**.
- **Windows** (`windows/`, .NET 9 / WPF + Whisper.net) — a later port that **kept growing**. It now has
  many David-requested features and a full monochrome UI redesign the Mac never received.

David's instruction (verbatim intent): *"make the Mac match us [Windows] — the layout, the functions,
everything about the app, the whole UI — except the animated pill; keep that as-is for now."*

**GOAL:** Make the macOS app reach feature + UI parity with the Windows app, porting each Windows-only
feature into idiomatic Swift and restyling the macOS **Settings window and menu-bar** to mirror the
Windows monochrome design and card set — **without touching the HUD** (macOS keeps its existing colored
orbital-ring pills; Windows keeps its bars; the two HUDs stay different "for now").

**Why a Mac session:** the Swift app only builds/runs/renders on macOS (Xcode toolchain, WhisperKit
CoreML). You will have the **full Windows source in the same working tree** (`windows/`) to read as the
exact spec, plus the real Mac app to build and screenshot.

---

## 2. Read-first (load these before doing anything)

Load, in this order:

1. **This whole file.**
2. **`CLAUDE.md`** (repo root) — the project brief. Note especially the "Architecture", "Build & test",
   and the long "Windows port … §7" changelog (it explains every Windows feature you are about to port,
   with the reasoning). The §7 numbers referenced below (#18, #21, #26, #27, #28, #31, #32, #34, #35,
   #36) are entries in that changelog.
3. **`docs/HANDOFF-WINDOWS.md`** — the zero-context anchor for the Windows port; the same §7 entries in
   full detail. This is where the *why* of each Windows feature lives.
4. **`docs/HANDOFF.md`** — the macOS session ledger (its "Current status & next steps"). You will append
   your own summary here when done.
5. **The macOS UI + models you'll edit:** `Sources/JVoice/UI/SettingsView.swift`,
   `Sources/JVoice/UI/MenuBarController.swift`, `Sources/JVoice/Models/SettingsState.swift`,
   `Sources/JVoice/Models/AppMode.swift`, `Sources/JVoice/Models/WhisperModelOption.swift`,
   `Sources/JVoice/Services/TextProcessor.swift`, `Sources/JVoice/Services/SettingsStore.swift`,
   `Sources/JVoice/VoiceCoordinator.swift`.
6. **The Windows source-of-truth** for whichever feature you're porting (exact files in §5's table).

Do **not** read the macOS `HUDView.swift` / `HUDWindow.swift` / `HUDLayout.swift` expecting to change
them — they are **out of scope** (see §7).

---

## 3. Definition of done (checkable)

- [ ] `swift build` passes (macOS 14+, Swift 5.9) with zero errors.
- [ ] `./scripts/run-logic-tests.sh` passes, **extended** to cover every new pure-logic source you add
      (DeveloperTerms, UserCorrections, AppModeResolver, StatsMath, TranscriptHistory, ReleaseVersion,
      UpdateCheck, UpdateProgressCurve, GameDetectionPolicy, and the grown SettingsState migration).
- [ ] `swift test` compiles the suite; you have **ported the matching Windows xUnit tests** to
      swift-testing (see §5 "tests" column). Locally it executes 0 (CLI-tools-only machine); CI
      (`.github/workflows/test.yml`) runs them — so the ported tests must be real, not stubs.
- [ ] The macOS **Settings window** is restyled monochrome and shows the Windows card set in the Windows
      order (§6), including every new feature card.
- [ ] The macOS **menu bar** mirrors the Windows tray menu (§6.3), minus the Windows-only elevation items.
- [ ] Every ported feature is wired end-to-end in `VoiceCoordinator.swift` and verified by launching the
      app (§8), not just by tests.
- [ ] The **HUD is byte-for-byte unchanged** (`git diff` touches no `HUD*.swift`).
- [ ] Work is committed on `feat/mac-parity`. **Not pushed** (David pushes). `docs/HANDOFF.md` updated
      with a session summary (what changed, assumptions, needs-eyes, next steps).

---

## 4. Ground rules (guardrails)

- **Autonomy:** work unattended per `~/.claude/CLAUDE.md`. Do **not** stop to ask questions. When
  something is ambiguous, pick the most reasonable interpretation, **log the assumption inline + in the
  final summary**, and keep going. Only hard-stop for: destructive/irreversible actions, spending money,
  or being truly blocked.
- **Do NOT modify anything under `windows/`.** It is the read-only spec for this task.
- **Do NOT touch the HUD:** `Sources/JVoice/UI/HUDView.swift`, `HUDWindow.swift`, `HUDLayout.swift`, and
  the recording/transcribing/done pill visuals. macOS keeps its colored pills. (You *may* touch the
  menu-bar status-item icon states — that's not the HUD; see §6.3.)
- **Don't regress the shared "brain."** The macOS services (`TextProcessor`, `PhoneticMatcher`,
  `VocabularyPrompt`, `RepetitionGuard`, `RegurgitationRecovery`, `ChunkPlanner`, `WavTail`,
  `StreamingTranscriptionSession`) are the **originals** the Windows C# was ported *from*. Keep their
  behavior. You are **adding** new post-processing hooks (Developer Terms, User Corrections) and new
  features around them — not rewriting them.
- **TDD for the pure-logic ports.** For each Core port, write/port the tests first, watch them fail,
  then implement (per `superpowers:test-driven-development`). The Windows xUnit tests are your oracle —
  translate them faithfully to swift-testing; keep every constant verbatim.
- **Match the Swift codebase.** Read neighboring Swift before writing. The shared logic already exists in
  Swift form elsewhere — mirror its idioms, not the C#'s.
- **Git:** commit locally in logical groups on `feat/mac-parity`. **Never push, never open a PR, never
  add a remote.** Do not `git add windows/…`. Don't force-push.
- **Honesty:** never fake a pass. If a feature can't be finished (e.g. WhisperKit lacks an API), stop on
  *that feature*, document it in the summary, and move to the next — don't weaken a test to go green.

---

## 5. The feature port matrix (Windows → macOS)

Each row: **Windows source-of-truth** (read it for exact constants) → **macOS target** (create/edit) →
behavior + notes. "Tests" = the Windows xUnit file to translate to swift-testing under
`Tests/JVoiceTests/`. Do these **in the phase order of §9**, not table order.

| # | Feature | Windows source-of-truth (read-only) | macOS target (edit/create) | Notes / platform mapping |
|---|---------|--------------------------------------|-----------------------------|--------------------------|
| 1 | **Developer Terms** correction pack (opt-out, default ON) | `windows/JVoice.Core/Text/DeveloperTerms.cs`; tests `windows/JVoice.Tests/DeveloperTermsTests.cs` (72 cases incl. the exclusion audit) | new `Sources/JVoice/Services/DeveloperTerms.swift`; hook into `TextProcessor.swift` **post-processing** channel (like the built-in `correctionDictionary`, **NOT** the decoder prompt); gate by new setting `developerTerms` | Port the map **and** the `\bword\b` matcher **and** the excluded-words list verbatim (`cursor`, `bolt`, `continue`, `render`, `pinecone`, `perplexity`, `grok`, `svelte`, `llama`, … — see §7 #28/#34). Homophones kept: `jason`→JSON, `groq`→Groq, `gemini`→Gemini, `mistral`, `firebase`, `windsurf`. |
| 2 | **User Corrections** (user-editable find→replace list) | `windows/JVoice.Core/Text/UserCorrections.cs`, `windows/JVoice.Core/Models/CorrectionRule.cs`; tests `UserCorrectionsTests.cs` | new `Sources/JVoice/Services/UserCorrections.swift` + `Models/CorrectionRule.swift`; hook into `TextProcessor.swift`; persist in `SettingsState.corrections` | New user feature on Mac (distinct from the built-in `correctionDictionary`). Whole-phrase, case rules per the C#. |
| 3 | **App-aware modes** + **Code tone** | `windows/JVoice.Core/Policy/AppModeResolver.cs`, `windows/JVoice.Core/Models/ToneStyle.cs` (the `Code` case), `windows/JVoice.App/Platform/System/ForegroundApp.cs`; tests `AppModeResolverTests.cs` + Code cases in `TextProcessorTests.cs` | add `.code` to `Sources/JVoice/Models/AppMode.swift`; new `Sources/JVoice/Services/AppModeResolver.swift`; foreground-app read via **`NSWorkspace.shared.frontmostApplication`** (bundleIdentifier / localizedName) | User rules beat a built-in terminals/editors/IDEs→Code list. **Translate the built-in app list to macOS bundle IDs** (Terminal `com.apple.Terminal`, iTerm `com.googlecode.iterm2`, VS Code `com.microsoft.VSCode`, Xcode `com.apple.dt.Xcode`, JetBrains `com.jetbrains.*`, etc.). `Code` tone = minimal formatting; keep it out of the manual tone cycle (mirror `AppMode.toggled`). Same read-only access class as macOS already uses. |
| 4 | **Stats: time-saved** | `windows/JVoice.Core/Policy/StatsMath.cs` (`EstimatedMinutesSaved`, 40-wpm baseline); tests `StatsMathTests.cs` | new `Sources/JVoice/Services/StatsMath.swift` (or extend `StatsStore.swift`); Settings Stats card → **3-up** | Pure math. Display formatting mirrors Windows (`"—"` <1 min, `"N min"` <60, else `"N.N h"`). |
| 5 | **Recent Transcripts** history (last 30) | `windows/JVoice.Core/Models/TranscriptHistory.cs`, `TranscriptHistoryEntry.cs`; tests `TranscriptHistoryTests.cs` | new `Sources/JVoice/Services/TranscriptHistory.swift` + `Models/TranscriptHistoryEntry.swift`; persist JSON (macOS Application Support, mirror the existing `LastTranscriptStore` file pattern); append on each paste in `VoiceCoordinator.swift` | **Replaces** the macOS "Last Transcript" Fix/Revert card in Settings (see §6.2 + the Assumption in §10 about learn-from-fix). Card: last-30, hover-reveal Copy/Delete + Clear all. |
| 6 | **SettingsState schema growth** | `windows/JVoice.Core/Models/SettingsState.cs` (v4 — see the exact fields quoted in §5.1), `SettingsStateJson.cs` (per-field fallbacks); tests `SettingsStateTests.cs`, `SettingsStoreJsonTests.cs` | `Sources/JVoice/Models/SettingsState.swift` + `Services/SettingsStore.swift` | Add the new fields with safe defaults + forward-compat decoders (macOS `SettingsStore` already does versioned decode + corrupt-blob backup — extend that). **Bump the schema version.** See §5.1 for the field list. |
| 7 | **Model default → Large** + **"Keep on Large" advisory** | `windows/JVoice.Core/Models/SettingsState.cs` default `Model: WhisperModelOption.LargeTurbo`; advisory copy in `windows/JVoice.App/UI/SettingsView.xaml` (§7 #35) | `Sources/JVoice/Models/SettingsState.swift` default `.tiny`→`.largeTurbo`; `Sources/JVoice/UI/SettingsView.swift` Whisper Model card | Deliberate change: first run now downloads large-v3-turbo (~630 MB). Add the always-shown "**Keep this on Large.**" callout + an extra caution line shown only when a smaller model is selected. Keep in sync anywhere a model default is inferred. |
| 8 | **Translate to English** | `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs` (the `translate` flag / `WithTranslate()`); toggle in `SettingsView.xaml` | `Sources/JVoice/Services/TranscriptionManager.swift`; toggle `translateToEnglish` | **Verify WhisperKit supports the translate task** — set `DecodingOptions.task = .translate` (WhisperKit exposes `.transcribe`/`.translate`). If confirmed, wire the toggle (rebuild engine or pass per-decode). If WhisperKit truly can't, document the gap and skip (don't fake). |
| 9 | **Copy to Clipboard** (clipboard-only) | `windows/JVoice.App/Platform/System/Paster.cs` (`Stage`); toggle in `SettingsView.xaml` | `Sources/JVoice/Services/PasteManager.swift` (add a stage-to-clipboard path); toggle `copyToClipboardOnly` | When ON, put text on the pasteboard and **skip the synthesized ⌘V**. |
| 10 | **Undo Last Paste** (opt-in 2nd global hotkey) | `windows/JVoice.App/VoiceCoordinator.cs` undo path (sends Ctrl+Z); `HotkeyChord` UndoHotkey; tests `HotkeyChordTests.cs` | add a 2nd `KeyboardShortcuts.Name` (e.g. `.undoLastPaste`) in `Sources/JVoice/Services/HotKeyManager.swift`; send **⌘Z** to the last target app via `PasteManager` | Default: **none** (no default chord — a registered global chord is swallowed system-wide). One-shot; suppress while game-detection is active (see #11). UI: second recorder in the Keyboard Shortcut card. |
| 11 | **Game detection** (Off / Balanced / Aggressive) — pause the hotkey while a game is foreground | pure policy `windows/JVoice.Core/Policy/GameDetectionPolicy.cs` + `Models/GameDetectionMode.cs` (tests `GameDetectionPolicyTests.cs`); Windows signals `windows/JVoice.App/Platform/System/GameDetector.cs` | port the **pure policy** to `Sources/JVoice/Services/GameDetectionPolicy.swift` + `Models/GameDetectionMode.swift`; a **macOS-native** signal gatherer | **The one platform-bound feature.** Port the Off/Balanced/Aggressive policy + tests 1:1. The *signals* are Windows-specific (D3D fullscreen, GameConfigStore, exe path). On macOS build a best-effort detector from **read-only** signals only (frontmost app + `NSWorkspace`, display-is-fullscreen via `CGDisplay`/`NSScreen`, a known-games / Steam-path heuristic) — anti-cheat-safe, no memory reads. If a clean signal set isn't reachable, ship the **setting + policy + Balanced default** wired to whatever fullscreen signal you can get, and **document the gap** in the summary. |
| 12 | **In-app Updates** (check GitHub Releases, one-click update, eased progress) | pure `windows/JVoice.Core/Policy/ReleaseVersion.cs`, `UpdateCheck.cs`, `UpdateProgressCurve.cs` (tests `ReleaseVersionTests.cs`, `UpdateCheckTests.cs`, `UpdateProgressCurveTests.cs`); I/O `windows/JVoice.App/Update/UpdateService.cs`, `UpdateCoordinator.cs`, `UpdateConfig.cs` | new `Sources/JVoice/Services/ReleaseVersion.swift`, `UpdateCheck.swift`, `UpdateProgressCurve.swift`, `UpdateService.swift`, `UpdateCoordinator.swift`, `UpdateConfig.swift`; Settings **Updates** card + a menu-bar "Update Available…" item | macOS downloads the **DMG** (not an `.exe`). "Marketing" eased bar (no % text). **Note the mono-repo tag advantage:** macOS releases own the `v1.x` tag namespace, which `ReleaseVersion` *can* parse — so the macOS updater can actually function (unlike Windows' unparseable `windows-v1.0.0`, §7 #40). Privacy: the check is the only runtime network call besides the model download; sends no user data; default ON. |
| — | **Elevation / Run-as-Admin** (Windows tray items) | `windows/JVoice.App/VoiceCoordinator.cs` elevation paths | **SKIP — no macOS equivalent** | Windows UIPI has no macOS analog; the closest (Accessibility permission) is already handled by the Mac app. Omit these menu items. Documented, not a gap. |

### 5.1 Exact new SettingsState fields (from `windows/JVoice.Core/Models/SettingsState.cs`, schema v4)

Port these onto the macOS `SettingsState` (defaults shown; **use the same defaults**), plus forward-compat
decoding for each. Note the two intentional macOS-hotkey/threading differences flagged below.

```
GameMode            = GameDetectionMode.Balanced   // #11
DeveloperTerms      = true                          // #1
CopyToClipboardOnly = false                         // #9
UndoHotkey          = null (disabled)               // #10 — on macOS lives in KeyboardShortcuts, not SettingsState
TranslateToEnglish  = false                         // #8
AppAwareModes       = true                          // #3
AppModeRules        = []                            // #3 (built-in code apps are implicit, not persisted)
CheckForUpdates     = true                          // #12
Corrections         = []                            // #2 (macOS may already carry a corrections field; confirm)
Model default        Tiny → LargeTurbo              // #7
```

macOS deviations to honor (don't blindly copy the C#):
- **Hotkeys** (`Hotkey`, `UndoHotkey`): macOS uses the **KeyboardShortcuts** library, which persists chords
  in its **own** UserDefaults key — *not* inside `SettingsState`. So on macOS, the primary + undo chords
  stay in KeyboardShortcuts; `SettingsState` does **not** gain hotkey fields. (Windows folds them into
  `settings.json`; macOS should not.)
- **Default hotkey** stays **⌥Space** on macOS (Windows uses Ctrl+Shift+Space because Alt+Space is the
  system window menu). Don't change the macOS default chord.

---

## 6. UI parity spec (Settings + menu bar) — the monochrome redesign

**Source-of-truth files (read-only):** `windows/JVoice.App/UI/SettingsView.xaml` (card set + ordering +
labels + copy), `windows/JVoice.App/UI/Styles/JVoicePalette.xaml` (the monochrome palette — **every**
accent name resolves to white `#FFFFFF`; only a single gray differs), `windows/JVoice.App/UI/DarkSection.cs`
(card chrome), `windows/JVoice.App/UI/TrayIcon.cs` (tray menu).

### 6.1 Monochrome palette
Rework `SettingsPalette` in `Sources/JVoice/UI/SettingsView.swift` so **all section accent dots become
white** (monochrome), matching Windows §7 #18. Keep the existing `DarkSection` chrome (rounded card, 5px
dot, UPPERCASED bold header, divider). This removes the current colored dots (blue/purple/cyan/green/
orange). The dark card/background tones stay dark; only the *accents* go mono.

### 6.2 Settings card set + order (mirror the Windows 3-column masonry)
Windows renders **12 cards** in a 3-column masonry (it went multi-column because a single column is too
tall for a 1600×1080 screen — §7 #29/#33). On macOS, replicate the **same card set and ordering** using a
multi-column SwiftUI layout (e.g. an `HStack` of `VStack` columns, or `LazyVGrid`). Cards, in Windows
order:

- **Column 1:** `STATS` (3-up: total words · avg WPM · time saved) · `RECENT TRANSCRIPTS` (last-30, hover
  Copy/Delete, Clear all) · `WHISPER MODEL` (Tiny·Base·Small·Large segmented + guidance caption + **Keep
  on Large** advisory) · `VOICE STYLE` (Casual·Formal·Very Casual segmented; `Code` is **not** a manual
  option here).
- **Column 2:** `LANGUAGE` (English·Romanian + **Translate to English** toggle) · `PROCESSING` (Remove
  Filler Words · Developer Terms · Copy to Clipboard toggles) · `CUSTOM WORDS` (list + Add) · `GAMING`
  (Off·Balanced·Aggressive + caption).
- **Column 3:** `APP MODES` (Auto-switch by App toggle + per-app rules with a mode chip that cycles
  Casual→Formal→VeryCasual→Code) · `CORRECTIONS` (From→To rules) · `KEYBOARD SHORTCUT` (Toggle Recording
  recorder + caption; divider; Undo Last Paste recorder + Clear) · `UPDATES` (Automatic Updates toggle +
  version line + Check Now + status + Update Now + eased progress bar).
- **Footer (full width):** `Restore Default Settings` (destructive) · `Quit JVoice` (destructive).

Copy the exact labels/subtitles/empty-states/captions from `SettingsView.xaml` (e.g. Processing subtitles
"Strip um, uh, er, ah, hmm from output" / "Fix coding terms: Node.js, GitHub, TypeScript, JSON, C#…" /
"Copy the text instead of auto-pasting it"; Gaming caption; empty states "No transcripts yet." / "No
custom words added." / "No corrections added." / "No custom rules added.").

**Retire** the macOS-only "Last Transcript" (editable + Fix/Revert) card and its Stats 2-up layout — they
are replaced by `RECENT TRANSCRIPTS` and the 3-up Stats. (See §10 assumption on learn-from-fix.)

The header block stays: **"JVoice"** (17pt bold) + subtitle (Windows uses "Voice dictation controls").

### 6.3 Menu bar (mirror the Windows tray menu — `TrayIcon.cs`)
`Sources/JVoice/UI/MenuBarController.swift` menu, in order:
1. **"Update Available — Open Settings…"** (bold, **only** when an update is available) + separator.
2. **"Start Dictation"** / **"Stop Dictation"** (toggles by recording state).
3. — separator —
4. **"Settings…"**
5. **"Launch at Login"** (checkmark).
6. — separator —
7. **"Quit JVoice"**

**Omit** the Windows elevation items ("Restart as Administrator", "Run as Administrator at Login",
"Running as Administrator"). Keep the idle status-item **"J"** template icon. Make the recording /
transcribing status-item icons **monochrome** (template) to match the Windows monochrome tray, instead of
the current red-mic / cyan-waveform tints. *(This is the menu-bar status item — not the HUD; still in
scope.)*

---

## 7. Explicitly OUT of scope (do not touch)

- **The HUD / "the animated pill."** `Sources/JVoice/UI/HUDView.swift`, `HUDWindow.swift`,
  `HUDLayout.swift`, `UI/Components/PanelPressableButtonStyle.swift`, and all recording/preparing/
  transcribing/done/error **pill visuals**. macOS keeps its colored orbital-ring pills; Windows keeps its
  bars. David: *"except the pill; keep that the same for now."* Your `git diff` must not touch these files.
- **The shared brain internals** (TextProcessor's existing behavior, PhoneticMatcher, VocabularyPrompt,
  RepetitionGuard, RegurgitationRecovery, ChunkPlanner, WavTail, StreamingTranscriptionSession) — add
  hooks, don't rewrite.
- **Anything under `windows/`.**
- **Windows-only platform mechanics with no macOS analog:** elevation/UIPI (skip). Game-detection is
  *partly* in scope (port policy; best-effort macOS signals) — see #11.

---

## 8. Verification (do this, don't assume)

1. `swift build` → 0 errors.
2. `./scripts/run-logic-tests.sh` → passes, including your new logic sources (extend the script's compile
   list + add assertions mirroring the ported Windows tests).
3. `swift test` → compiles the suite (0 execute locally is expected on a CLI-tools-only Mac; CI runs
   them). Confirm your ported tests are wired under `Tests/JVoiceTests/`.
4. **Run the app** and confirm visually (this is required, not optional):
   - Launch: `swift run JVoice` (or build `.build/debug/JVoice`). It's a menu-bar app (no dock icon).
   - Open **Settings** from the menu bar. Confirm: monochrome dots; the full Windows card set in order;
     the new cards render; Stats is 3-up; Whisper Model shows the Keep-on-Large advisory; model default is
     Large.
   - Screenshot Settings (window capture) and save under `docs/` or attach to the summary.
   - Exercise at least: toggling Developer Terms, adding a Correction, adding an App-mode rule, toggling
     Translate, toggling Copy-to-Clipboard, and a dictation round that appends to Recent Transcripts.
   - Confirm the **HUD still looks exactly as before** (record once; the colored pill appears unchanged).
5. If any feature can't be verified on-device (e.g. Updates needs a live release), note it explicitly.

---

## 9. Suggested execution order (phased — do the highest-value, lowest-risk first)

1. **Phase 1 — pure-logic ports (TDD).** #1 DeveloperTerms, #2 UserCorrections, #4 StatsMath, #5
   TranscriptHistory, #3 AppModeResolver (+ `.code` tone), #11 GameDetectionPolicy (pure part), #12
   ReleaseVersion/UpdateCheck/UpdateProgressCurve, #6 SettingsState growth (+ migration tests), #7 model
   default. Port the matching Windows tests first, then implement. End Phase 1 with `run-logic-tests.sh`
   green. **Commit.**
2. **Phase 2 — service/platform wiring.** #9 clipboard-only, #8 translate (verify WhisperKit), #10 undo
   hotkey, #3 foreground-app via NSWorkspace, #11 macOS game signals (best-effort), #12 UpdateService/
   Coordinator, TranscriptHistory persistence, DeveloperTerms/UserCorrections hooks into TextProcessor.
   **Commit.**
3. **Phase 3 — UI restyle.** §6 monochrome Settings + the full card set + menu-bar parity. **Commit.**
4. **Phase 4 — VoiceCoordinator integration.** Wire every feature end-to-end (tone resolution per
   foreground app, translate, clipboard-only, undo, updates coordinator, stats time-saved, history
   append, corrections apply, model-default advisory). **Commit.**
5. **Phase 5 — verify + document.** §8 verification; update `docs/HANDOFF.md`; final summary. **Commit.**

Commit in logical groups as you go so partial progress is always saved.

---

## 10. Decisions & assumptions already made (don't re-litigate; log any new ones)

- **Direction:** Windows is the source of truth; the Mac changes to match. (David, this session.)
- **HUD excluded** ("except the animated pill"). macOS keeps its colored pills.
- **Recent Transcripts replaces the Mac's editable Last-Transcript/Fix-Revert card** (Q answered "mac
  matching us"; Windows has no Fix/Revert box). **Assumption to flag for David:** this drops the macOS
  *learn-from-fix* behavior (Fix auto-adding custom words), since Windows has no equivalent. If David
  wants to keep learn-from-fix, it can be preserved as a background behavior without the editable box —
  note it in the summary and leave the underlying `LastTranscriptStore`/`fixLastTranscript` code in place
  (just unwired from the UI) rather than deleting it, so it's easy to restore.
- **Settings look:** adopt the Windows **monochrome** palette (Q answered "mac matching us"). The colored
  accents go.
- **Model default → Large** on macOS too (matches Windows §7 #35), with the Keep-on-Large advisory.
  First-run downloads ~630 MB — acceptable per David's directive.
- **Elevation/Run-as-Admin:** no macOS equivalent → omitted (not a gap).
- **macOS keeps ⌥Space** as the default primary hotkey; hotkey chords stay in KeyboardShortcuts, not
  SettingsState.
- **Multi-column Settings:** replicate the Windows 3-column masonry rather than a single tall column
  (a single column of 12 cards is too tall — the same reason Windows went multi-column, §7 #29/#33).

If you must make a new judgment call, follow the same rule: pick the sensible option, **log it**, proceed.

---

## 11. When done

- Update **`docs/HANDOFF.md`** ("Current status & next steps") with a dated entry: what you ported, the
  per-feature status, assumptions, what needs David's eyes (esp. the learn-from-fix note, the game-detect
  macOS-signal gap if any, and WhisperKit translate confirmation), and next steps.
- Leave everything **committed on `feat/mac-parity`**, building green, tests wired. **Do not push.**
- Report back a short four-part summary: **What I did · Assumptions I made · Needs your eyes · Next steps.**
