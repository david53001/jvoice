# JVoice Audit — Domain 02: UI/UX & Accessibility

**Scope:** `Sources/JVoice/UI/{HUDView,HUDWindow,HUDLayout,MenuBarController,SettingsView,SettingsWindow}.swift`, `UI/Components/PanelPressableButtonStyle.swift`, `Models/{HUDState,AppMode,SettingsState,WhisperModelOption,TranscriptionLanguage}.swift`; `Tests/JVoiceTests/MenuBarIconTests.swift`. Read-only. `swift build` = clean.

## Summary

The focus-critical machinery is correct: the HUD is a `.nonactivatingPanel` with `canBecomeKey`/`canBecomeMain` overridden to `false` and is shown via `orderFrontRegardless()` (never `makeKey`/`NSApp.activate`), so it cannot steal focus from the paste target — the single most important UX invariant holds. The Settings window correctly *does* activate (it's the one window that should take focus). Beyond that, the findings cluster around two real defects and several polish/accessibility gaps: (1) **detailed error messages built by the coordinator are silently discarded** — the error HUD always reads the generic "Something Went Wrong" headline instead of the specific message the coordinator constructed (e.g. "No target app…", "Pasteboard is busy…"); (2) **empty-result and benign outcomes are rendered as scary orange-triangle errors** ("No speech detected." with an `exclamationmark.triangle`). Accessibility gaps: the `RecordingPill` (the only interactive HUD, with the Stop button) has no container accessibility label, the menu-bar status item exposes its state only via `accessibilityDescription` (no live announcement and no VoiceOver-grade label distinguishing idle/recording/transcribing in a discoverable way), and there are no accessibility identifiers anywhere (UI test hostility, not an end-user defect). The pills hardcode a near-black fill regardless of color scheme — acceptable as an intentional always-dark HUD, but the Settings window forces `.dark` while drawing a `.titled` system title bar that stays light, producing a two-tone window. Most behavioral items can't be executed on this CLT-only machine and are marked T2.

| Severity | T1 | T2 | Total |
|----------|----|----|-------|
| Critical | 0  | 0  | 0     |
| High     | 1  | 1  | 2     |
| Medium   | 4  | 3  | 7     |
| Low      | 4  | 1  | 5     |
| **Total**| **9** | **5** | **14** |

---

### [UI-01] Detailed error messages are discarded — HUD always shows generic "Something Went Wrong"
- **Severity:** High
- **Tier:** T1 (safe, locally build-verifiable)
- **Location:** `Sources/JVoice/UI/HUDView.swift:297,313` (StatusPill) vs `Sources/JVoice/Models/HUDState.swift:50-65` (`headline`) / `:67-82` (`subtitle`) / `:145-152` (`payload`); error producers in `Sources/JVoice/VoiceCoordinator.swift:356-365,421,442,454,490,518,522,537`.
- **What:** The coordinator builds specific, actionable error strings — `.error("No target app — focus an app that accepts text before recording.")`, `.error("Pasteboard is busy — try again.")`, `.error("Couldn't start recorder: \(msg)")`, `.error(error.localizedDescription)`, etc. `StatusPill` then renders **`state.headline`** (HUDView.swift:297 and again as the accessibility label at :313). For `.error`, `headline` is the hardcoded constant `"Something Went Wrong"` (HUDState.swift:63). The carefully constructed message lives in `state.payload` / `state.subtitle` and is never shown anywhere in the UI.
- **Evidence:** `HUDState.error` carries an associated `String`, and `subtitle` (HUDState.swift:79-81) explicitly returns that message for the error case — but `StatusPill` only reads `headline`. The HUD is a single-line pill (`.lineLimit(1)`), so there is no second line for the subtitle even if it were wired.
- **Impact:** Every distinct failure (no target app, mic permission, recorder setup failure, pasteboard busy, transcription throw) looks identical to the user: a generic "Something Went Wrong". The diagnostic effort in the coordinator is wasted and users can't self-correct (e.g. "focus a text field first").
- **Fix:** Show the message for errors. Minimal, in `StatusPill.body`, replace the single `Text(state.headline)` with the payload when present:
  ```swift
  Text(state.payload ?? state.headline)   // error carries the specific message
      ...
      .lineLimit(2)                        // allow the longer message to wrap
  ```
  and set `.accessibilityLabel(state.payload ?? state.headline)`. (`.done` payload is the full transcript, which you do NOT want to dump in the pill — so gate on the error case: `if case .error(let m) = state, !m.isEmpty { m } else { state.headline }`.) Keep the pill min-width but allow height to grow.
- **Verification:** `swift build`. Behaviorally: trigger each error path (no focused text field; deny mic) and confirm the pill text differs. Add a logic assert that `HUDState.error("X").payload == "X"` (already true) and a view-level snapshot if a test target ever runs UI.

---

### [UI-02] Benign empty result rendered as a scary error
- **Severity:** High
- **Tier:** T2 (needs running app / behavioral — UX judgment)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:490` (`updateHUD(.error("No speech detected."))`); rendering in `Sources/JVoice/UI/HUDView.swift:264-314` (StatusPill `.error` → orange + `exclamationmark.triangle.fill` via HUDState.swift:97).
- **What:** When transcription yields empty text (silence, a too-quiet clip, an accidental hotkey tap), the user sees the full error treatment: orange accent and `exclamationmark.triangle.fill`. A user who briefly tapped the hotkey or paused gets an alarming "Something Went Wrong"-class visual (compounded by UI-01, since the actual text "No speech detected." is also discarded → they literally see the generic error).
- **Evidence:** HUDState has no neutral terminal "nothing to paste" state; the only non-recording terminal states are `.done` (green check) and `.error` (orange triangle). Empty result is forced into `.error`.
- **Impact:** Normal, expected outcomes (silence) read as failures. Combined with UI-01 this is the most likely error a casual user hits, and it's the least informative.
- **Fix:** Either (a) treat empty as a quiet `.done` with a "Nothing to paste" headline (needs a small headline tweak / a dedicated state), or (b) at minimum fix UI-01 so the user reads the literal "No speech detected." Prefer a neutral icon (e.g. `mic.slash`/`text.badge.xmark`) rather than the danger triangle. This is a UX-policy decision — flag for David, don't unilaterally redesign per simplicity-first.
- **Verification:** Record silence; confirm the HUD no longer shows the danger-triangle error styling. Requires running app.

---

### [UI-03] `RecordingPill` (the only interactive HUD) has no container accessibility label
- **Severity:** Medium
- **Tier:** T1
- **Location:** `Sources/JVoice/UI/HUDView.swift:139-174` (RecordingPill).
- **What:** Every other pill calls `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` (PreparingModelPill :222-223, TranscribingPill :257-258, StatusPill :312-313). `RecordingPill` has neither. It contains decorative animation (OrbitalRing), two `Text` labels ("Recording"/"Listening…"), and the interactive `StopButton`.
- **Evidence:** Direct comparison of the four pill structs — RecordingPill is the only one missing the accessibility modifiers.
- **Impact:** VoiceOver reads the raw children inconsistently with the other states, and the decorative ring/aura may surface as unlabeled elements. The one HUD with a real control (Stop) is the one with the least-considered a11y. (The Stop button itself does have `.accessibilityLabel("Stop recording")` at :133, which is correct — but it should remain individually focusable, so do NOT `.ignore` children here.)
- **Fix:** Group the decorative + text content and keep the button focusable. E.g. wrap the `OrbitalRing` + `VStack` text in an element labeled "Recording, listening" and leave `StopButton` as a sibling focusable element. Simplest: add `.accessibilityElement(children: .contain)` on the HStack and `.accessibilityLabel("Recording")` on the OrbitalRing+text group; mark the OrbitalRing `.accessibilityHidden(true)` (it's pure decoration).
- **Verification:** `swift build`; VoiceOver pass on a running app (T2 to fully confirm, but the modifier addition is T1-safe).

---

### [UI-04] Settings window forces dark scheme but keeps a system (light) title bar → two-tone window
- **Severity:** Medium
- **Tier:** T2 (visual; needs running app to confirm severity)
- **Location:** `Sources/JVoice/UI/SettingsView.swift:395` (`.preferredColorScheme(.dark)`), `:396` (`.frame(width: 320, height: 520)`); `Sources/JVoice/UI/SettingsWindow.swift:8-12` (`contentRect 640×480`, styleMask `[.titled, .closable, .fullSizeContentView]`).
- **What:** The content view forces `.dark` and is a near-black palette, but the `NSWindow` is `.titled` without forcing the window's `appearance`. On a Mac in Light mode the title bar / traffic-light strip renders light while the content is black. Also `.fullSizeContentView` is set but the content does not extend under the title bar (no `titlebarAppearsTransparent`/`isMovableByWindowBackground` and the SwiftUI root has its own header) so the flag is inert.
- **Evidence:** `SettingsWindow` never sets `self.appearance = NSAppearance(named: .darkAqua)`; only the SwiftUI subtree is dark. `MenuBarIconTests` even comments that a forced-darkAqua hack "must never come back" (for the *icon*), but the Settings window legitimately needs a consistent dark chrome.
- **Impact:** In Light mode the Settings window looks half-broken (light title bar on a black body). Cosmetic but visible on every open for light-mode users.
- **Fix:** Set `self.appearance = NSAppearance(named: .darkAqua)` on the `SettingsWindow` (window-level, not the global app/icon), matching the forced-dark content. Drop `.fullSizeContentView` if unused, or actually make the header full-bleed.
- **Verification:** Open Settings in Light mode; title bar should be dark. T2 (visual).

---

### [UI-05] Settings window content frame (320×520) mismatches window contentRect (640×480)
- **Severity:** Medium
- **Tier:** T1
- **Location:** `Sources/JVoice/UI/SettingsWindow.swift:8` (`640×480`) vs `Sources/JVoice/UI/SettingsView.swift:396` (`.frame(width: 320, height: 520)`).
- **What:** The window is created at 640×480, then hosts a SwiftUI view hard-framed to 320×520. The 520 content height exceeds the 480 window height, and the 320 width is half the 640 window.
- **Evidence:** `NSHostingView` typically resizes the window to the hosted view's fitting size for a fixed-frame root, but the literal mismatch means the initial `contentRect` is throwaway and the final size depends on hosting-view auto-resize behavior. Either the window shows 320×520 (contentRect ignored) or 640×480 with the content pinned top-left and 40pt clipped vertically — both are bugs-in-waiting.
- **Impact:** At best the `640×480` is dead/misleading; at worst the content is clipped or letterboxed. The 520pt content in a 480pt window guarantees either a scroll/clip or a resize surprise.
- **Fix:** Make the window's `contentRect` match the intended content (e.g. `320×520`), or remove the hard `.frame` on the view and let the window own the size. Pick one source of truth for the size.
- **Verification:** `swift build`; open Settings, confirm no clipping and the size matches intent (T2 to confirm pixels, but the literal mismatch is a T1 fix).

---

### [UI-06] Menu-bar status item drops to idle icon while the HUD still shows done/error
- **Severity:** Medium
- **Tier:** T2 (behavioral/timing)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:294-301` (`.idle, .done, .error` → `updateActivity(.idle)`), `:535,538,491,455,308` (`scheduleHUDReset` keeps the HUD up 1s, errors 3s).
- **What:** On `.done`/`.error` the menu-bar activity is set to `.idle` immediately (the "J" template icon), but the HUD pill stays visible for 1s (`.done`/empty) or 3s (`showError`). So during the terminal window the menu bar already says "idle" while the HUD says "Pasted"/error.
- **Evidence:** `updateHUD` maps `.done`/`.error` straight to `.idle` menu activity (no transcribing/done state for the bar). The HUD dismiss is deferred via `scheduleHUDReset`.
- **Impact:** Minor inconsistency; the menu-bar narrative (the documented "progress stays visible even when the pill is off-screen") is briefly out of sync at the very moment a user glances at the bar to confirm success. The bar has no "done" affordance at all, so success is only ever shown in the (possibly off-screen / fullscreen-occluded) pill.
- **Fix:** Acceptable as-is for simplicity, but if tightening: the `MenuBarController.Activity` enum has no terminal state — consider not regressing to idle until the HUD resets, or accept the current behavior and document it. Low-priority; flag rather than change.
- **Verification:** Dictate, watch the menu bar vs HUD timing. T2.

---

### [UI-07] HUD positions only on `NSScreen.main`; ignores active display / cursor / fullscreen apps
- **Severity:** Medium
- **Tier:** T2 (multi-display behavior; can't reproduce on CLT-only machine)
- **Location:** `Sources/JVoice/UI/HUDWindow.swift:71-77` (`positionAtBottomCenter` uses `NSScreen.main`).
- **What:** The pill is always placed at the bottom-center of `NSScreen.main` (the screen with the key window / menu bar). On a multi-monitor setup where the user is typing into an app on a *secondary* display, the HUD appears on the primary screen — away from where the user is looking and where the paste lands.
- **Evidence:** `guard let screen = NSScreen.main` with no consideration of the frontmost app's screen or the screen under the mouse. `collectionBehavior` includes `.canJoinAllSpaces`/`.fullScreenAuxiliary` (good for spaces/fullscreen), but positioning is single-screen.
- **Impact:** On multi-display Macs the recording/transcribing feedback can appear on the wrong monitor. For a dictation tool used "anywhere", this is a real (if non-fatal) discoverability miss.
- **Fix:** Position relative to the screen containing the frontmost app's key window, or the screen under the mouse: `NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main`. Keep the bottom-center math.
- **Verification:** Two displays, dictate into an app on the secondary; HUD should follow. T2 (needs hardware).

---

### [UI-08] No accessibility identifiers anywhere; menu-bar state not announced to VoiceOver
- **Severity:** Medium
- **Tier:** T1 (adding labels/IDs is build-safe)
- **Location:** `Sources/JVoice/UI/MenuBarController.swift:92,98,101` (icon set with only `accessibilityDescription`); whole `UI/` tree (no `accessibilityIdentifier`).
- **What:** (a) The status item conveys state purely by tint color (red mic / cyan waveform / template J) plus the image's `accessibilityDescription`. There's no `NSAccessibility` *value*/*announcement* when state changes, and the button's `toolTip` stays the static "JVoice" (:33) regardless of activity, so a hovering/VoiceOver user can't tell recording from idle. (b) No `.accessibilityIdentifier` on any control, so future UI tests have nothing to target.
- **Evidence:** `updateStatusButton` swaps `button.image` + `contentTintColor` but never updates `button.toolTip` or posts an accessibility notification. Color-only state differentiation fails for color-blind users and VoiceOver.
- **Impact:** Color-blind users can't distinguish recording (red) from transcribing (cyan); both differ from idle mainly by hue. VoiceOver users get no state feedback from the bar.
- **Fix:** Update `button.toolTip` per state ("JVoice — Recording" / "— Transcribing" / "JVoice — Idle"), which also fixes the color-only signal for sighted hover. The image `accessibilityDescription` is already state-specific (good); optionally post `NSAccessibility.post(element: button, notification: .announcementRequested ...)` on transitions. IDs are optional polish.
- **Verification:** `swift build`; hover the menu bar in each state to confirm tooltip changes. VoiceOver confirm = T2.

---

### [UI-09] Custom-word add allows pure-punctuation / huge / case-dup entries; no length cap or normalization
- **Severity:** Low
- **Tier:** T1
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:572-576` (`addCustomWord`); UI `Sources/JVoice/UI/SettingsView.swift:299-318,399-404` (`submitWord`).
- **What:** `addCustomWord` only trims whitespace and rejects empty / exact-duplicate. It accepts: a single comma or symbol (`","`, `"!!!"`), arbitrarily long input (the user could paste a paragraph — the `TextField` has no `maxLength`), and case/whitespace-variant duplicates ("VS Code" vs "vs  code" vs "VS Code" with trailing space differences collapse only on exact match). The placeholder hints "VS Code" (multi-word ok) but nothing validates a sane vocabulary entry. Commas are NOT split — a user typing "React, Swift" creates one bogus entry "React, Swift" (the prompt builder/PhoneticMatcher then sees a 2-word "word").
- **Evidence:** Guard is `!trimmed.isEmpty, !customWords.contains(trimmed)`. No comma-splitting despite README/launch copy and the comma-friendly `--vocab "A,B"` CLI convention; no max length; case-sensitive dedupe.
- **Impact:** Garbage entries pollute the decoder `promptTokens` (the core accuracy lever per CLAUDE.md), risking exactly the regurgitation/hallucination failure mode the project fights. A pasted blob could bloat the prompt. The list UI (`ScrollView` maxHeight 88) will scroll fine, so it's a data-quality not layout issue.
- **Fix:** In `submitWord`/`addCustomWord`: split on commas, trim each, drop entries with no alphanumerics, cap length (e.g. ≤40 chars), and de-dupe case-insensitively. Small and surgical:
  ```swift
  for piece in word.split(separator: ",") {
      let t = piece.trimmingCharacters(in: .whitespacesAndNewlines)
      guard t.count <= 40, t.rangeOfCharacter(from: .alphanumerics) != nil,
            !customWords.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { continue }
      customWords.append(t)
  }
  ```
  Confirm with the owner whether comma-splitting is desired (it matches the CLI convention) before changing behavior.
- **Verification:** `./scripts/run-logic-tests.sh` if a VocabularyPrompt assertion is added; `swift build`. Add unit coverage for comma/dup/empty/oversize.

---

### [UI-10] HUD view is fully rebuilt on every state update, restarting animations / the Preparing timer
- **Severity:** Low
- **Tier:** T2 (animation behavior; can't observe on CLT-only machine)
- **Location:** `Sources/JVoice/UI/HUDWindow.swift:49-61` (`update` sets `hostingController.rootView = HUDView(state:...)` each call); `Sources/JVoice/UI/HUDView.swift:48-59` (`PulseModifier` `@State scale`), `:189` (`PreparingModelPill @State startDate = Date()`), `:206` (`TimelineView(.periodic(from: startDate...))`).
- **What:** Each `updateHUD` replaces the entire `rootView`. Because the top-level `HUDView` switches on `state` and returns *different* concrete pill types per state, transitioning recording→preparing→transcribing destroys/recreates the subtree, so `PulseModifier.scale` and the OrbitalRing's `TimelineView` phase reset on every transition (the spinner can visibly "jump"). The Preparing timer's `startDate` correctly resets to "now" each rebuild — which is the *desired* behavior here (it should count this preparation), so that part is fine; but if `update(.preparingModel)` were ever called twice the counter would reset to 0:00 mid-wait.
- **Evidence:** No `.id()`/identity preservation across pills; distinct structs per case means SwiftUI treats them as different views. Animations are `@State` local to each recreated struct.
- **Impact:** Minor visual hitch on state changes (spinner reset, pulse restart). The Preparing-timer reset-on-double-call could under-report the wait, undermining the "prove the app is alive" intent documented at HUDView.swift:178-183. Low because state transitions are infrequent and `.preparingModel` is set once (VoiceCoordinator.swift:464).
- **Fix:** Acceptable for simplicity. If polishing: hoist `startDate` to the coordinator (pass into the pill) so it survives rebuilds, and/or give the OrbitalRing a stable `.id` so its `TimelineView` isn't torn down between busy states. Don't gold-plate unless the hitch is observed.
- **Verification:** Observe transitions on a running app. T2.

---

### [UI-11] HUD pill hardcodes near-black fill — intentional but bypasses color-scheme semantics
- **Severity:** Low
- **Tier:** T1 (documentation/intent confirmation; no behavioral change recommended)
- **Location:** `Sources/JVoice/UI/HUDView.swift:25-44` (`pillBackground` fills `Color(red: 0.027, green: 0.027, blue: 0.055)`); all accent colors are literal RGB triples (`:142-143,185-186,230-231,267-281`).
- **What:** The HUD is always dark regardless of the system appearance. Every color is a hardcoded sRGB literal, not a semantic/asset color. This is consistent with the design tokens (CLAUDE.md says DESIGN-TOKENS.md is extracted from source) and a deliberate always-dark glassy HUD.
- **Evidence:** No `Color(.windowBackgroundColor)`/semantic usage; pure literals. Text colors (e.g. RecordingPill `textColor` 0.82/0.91/1.0 on near-black) have strong contrast, so WCAG contrast is fine *on the dark pill*.
- **Impact:** None functionally — but it means the HUD ignores Increase Contrast / light mode by design. Worth recording as intentional so a future "support light mode" request doesn't treat it as a bug. The only risk: the `.done` green text (0.694/0.988/0.718) on the dark fill is bright (fine), but accent-only differentiation (green=done, orange=error) is color-only — paired with the distinct SF Symbols (`checkmark.circle.fill` vs `exclamationmark.triangle.fill`) so it's not color-alone. OK.
- **Fix:** No change recommended. If light-HUD support is ever requested, route through DESIGN-TOKENS.md first (per CLAUDE.md). Confirm intent with owner.
- **Verification:** N/A (intent confirmation).

---

### [UI-12] Long `.done` transcript / long headline truncation in the fixed-width pill
- **Severity:** Low
- **Tier:** T1
- **Location:** `Sources/JVoice/UI/HUDView.swift:297-302` (`StatusPill` `Text(state.headline)` with `.lineLimit(1)`, min width via HUDLayout `:308`); `HUDLayout.swift:4` (`hudPillSize 220×50`).
- **What:** `StatusPill` shows only `state.headline` ("Pasted"/"Something Went Wrong"), so a long *transcript* never reaches the pill (good — it's not dumped). But once UI-01 is fixed to show error payloads, long error strings (e.g. "Couldn't start recorder: \(msg)") will hit `.lineLimit(1)` at min-width 220 and truncate with an ellipsis.
- **Evidence:** Pill min size is fixed; `sizeToFit` (HUDWindow.swift:63-69) grows width to the SwiftUI fitting size, but `.lineLimit(1)` means a long single-line string just elongates the pill — potentially wider than the screen for a very long message — or, if a max width were added, truncates.
- **Impact:** Pre-UI-01: none (headlines are short). Post-UI-01: long error text could either over-stretch the pill or truncate. Listed so the UI-01 fix accounts for it.
- **Fix:** When implementing UI-01, set `.lineLimit(2)` + `.fixedSize(horizontal: false, vertical: true)` and cap the pill width (e.g. `.frame(maxWidth: 360)`) so long messages wrap instead of stretching off-screen.
- **Verification:** `swift build`; render a 120-char error after UI-01. T1.

---

### [UI-13] `ignoresMouseEvents` toggled only inside `update(state:)` — initial state leaves it click-through, and recording pill blocks clicks under it
- **Severity:** Low
- **Tier:** T2 (behavioral)
- **Location:** `Sources/JVoice/UI/HUDWindow.swift:39` (`ignoresMouseEvents = true` at init), `:52` (`ignoresMouseEvents = (state != .recording)`).
- **What:** The panel starts click-through (`true`), and during `.recording` becomes click-*receiving* (`false`) so the Stop button works. While recording, the whole 220×50 pill (plus its 32pt padding region within the window) intercepts clicks at bottom-center of the screen — clicks that would otherwise reach the app behind it are swallowed even outside the visible Stop button, because the window (not just the button) takes events. The pill is bottom-center where dock/app UI often sits.
- **Evidence:** `ignoresMouseEvents` is a whole-window property; there's no per-subview hit-testing carve-out, so the transparent padding around the pill also eats clicks during recording.
- **Impact:** Minor: during recording, a click near the bottom-center (e.g. on a centered toolbar / the app behind) can be absorbed by the HUD window. Edge case, short-lived (only while recording).
- **Fix:** Acceptable. If tightening, shrink the window to the pill's actual bounds (drop the 32pt SwiftUI `.padding` and use a smaller window) so only the visible pill area intercepts, or override `hitTest` to pass through outside the pill rect. Don't over-engineer.
- **Verification:** While recording, click just outside the visible pill onto the app behind. T2.

---

### [UI-14] `MenuBarIconTests` only covers the idle template icon; recording/transcribing icon states untested
- **Severity:** Low
- **Tier:** T1
- **Location:** `Tests/JVoiceTests/MenuBarIconTests.swift:1-32`; states in `Sources/JVoice/UI/MenuBarController.swift:90-104`.
- **What:** Tests assert only `makeStatusIcon()` (idle "J") is a non-empty template image. There's no coverage that `updateActivity(.recording)`/`.transcribing` actually swap the SF Symbol + tint, or that the `updateActivity` early-return (`guard activity != self.activity`) doesn't skip a needed redraw after `installStatusItem`.
- **Evidence:** Only two `@Test`s, both about the static idle glyph. `updateStatusButton` logic (system-symbol availability, tint) is untested.
- **Impact:** A regression in the recording/transcribing icon (e.g. a typo'd symbol name returning nil image) would ship silently — these run in CI (`swift test` is 0 locally per CLAUDE.md).
- **Fix:** Add a `@MainActor` test that installs the status item, calls `updateActivity(.recording)`/`.transcribing`/`.idle`, and asserts `statusItem.button.image != nil` and `contentTintColor` matches expectation per state. Build-safe; runs in CI.
- **Verification:** `swift build`; assertions execute in CI (macos-15). The CLAUDE.md note that CI requires ≥90 swift-testing cases means additions are welcome.

---

## Cross-cutting notes (not numbered findings)

- **Focus invariant is correct.** HUDWindow: `.nonactivatingPanel` + `canBecomeKey=false` + `canBecomeMain=false` + `orderFrontRegardless()` (never `makeKey`/`NSApp.activate`). This is the right pattern and the paste-into-target contract holds. SettingsWindow correctly activates (it *should* take focus). No focus-stealing defect found — the most important risk in this domain is clean.
- **HUDState coverage is complete.** All six cases (`idle/recording/preparingModel/transcribing/done/error`) are rendered (`HUDView.swift:8-20`), `idle`→`EmptyView` + `orderOut`. No unrendered/stuck state. `Codable`/`Equatable` round-trips look correct (HUDState.swift:154-193). The decode-fallback discipline on the Model enums (AppMode/WhisperModelOption/TranscriptionLanguage all decode unknown raw → safe default; SettingsState normalizes schema forward and rejects newer-than-current) is solid and worth keeping.
- **`HUDLayout.minimumSize` is a no-op switch** (all cases return the same `hudPillSize`, HUDLayout.swift:7-11) — harmless, slightly redundant; not worth changing under surgical rules.
- **Two parallel enum families** exist: UI-layer `ToneMode`/`WhisperModelChoice` (VoiceCoordinator.swift:6-60) mirror model-layer `AppMode`/`WhisperModelOption` with bridge inits. Intentional separation (UI display vs persisted model) but a known duplication-maintenance cost; out of this audit's defect scope.
