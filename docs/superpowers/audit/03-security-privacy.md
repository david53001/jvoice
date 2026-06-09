# JVoice — Security & Privacy Audit (read-only)

**Auditor:** senior application-security engineer (automated deep pass)
**Date:** 2026-06-09
**Scope:** `Sources/JVoice/**` (app code), `Resources/Info.plist`, `Package.swift`/`Package.resolved`, and the WhisperKit dependency's download path (`.build/checkouts/WhisperKit`).
**Method:** repo-wide grep for network/IO/logging/persistence APIs, full read of every privacy-relevant source file, dependency download-path inspection, `swift build` sanity check (passes), and on-machine checks of the temp-dir permission mode and ATS posture.

## Summary

JVoice's core privacy claim — "zero network calls at runtime (only the one-time Whisper model download), no telemetry, no accounts" — is **CONFIRMED** at the application-code level. There is no `URLSession`, `URLRequest`, socket, `NWConnection`, analytics, telemetry, or `http(s)` literal anywhere in `Sources/`. The only network-capable path in the whole binary is WhisperKit's one-time model snapshot from `https://huggingface.co` (HTTPS, TLS-validated, gated to first use of an un-downloaded model). Audio-file hygiene is genuinely good: temp WAVs are deleted on the success path (`defer`), on every recording-failure teardown, on quit-mid-recording, on no-target/too-short aborts, and via a launch-time orphan sweep; the per-user temp dir is mode `0700` (owner-only), so a lingering WAV is not world-readable. Clipboard paste snapshots and restores the prior clipboard. No transcript text, audio path, or PII reaches `os_log`/`NSLog`/unified logging.

The findings below are mostly Low/Info hardening items. The two that matter most for a "privacy-first" product are: (a) the **full transcript text is persisted indefinitely in plaintext UserDefaults** with no user-facing "clear" affordance and survives a settings reset (SEC-01), and (b) the **transcript transits the general pasteboard** during paste, which is unavoidable for the Cmd+V approach but is not marked concealed/transient, so clipboard-history managers and Universal Clipboard can capture it (SEC-02). Neither breaks the network claim, but both are at-rest / in-transit-on-device exposures worth tightening for the product's threat model.

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 0 | — |
| High     | 0 | — |
| Medium   | 2 | SEC-01, SEC-02 |
| Low      | 3 | SEC-03, SEC-04, SEC-05 |
| Info     | 4 | SEC-06, SEC-07, SEC-08, SEC-09 |

---

## Network claim verification

**Verdict: CONFIRMED — zero runtime network in app code; the only network egress is WhisperKit's one-time model download over HTTPS.**

Grep evidence (repo root, `Sources/` only):

```
$ grep -rnE "URLSession|URLRequest|NSURLConnection|dataTask|downloadTask|uploadTask" Sources/
no matches

$ grep -rnE "NWConnection|NWEndpoint|CFSocket|Socket|getaddrinfo|connect\(|import Network" Sources/
no matches

$ grep -rnE "https?://" Sources/
no matches            # (no http/https string literals anywhere in app code)

$ grep -rniE "analytics|telemetry|beacon|track(ing)?|crashlytics|sentry|firebase|mixpanel|amplitude|posthog|segment" Sources/
Sources/JVoice/UI/SettingsView.swift:215:  .pickerStyle(.segmented)   # false positive ("segmented")
Sources/JVoice/UI/SettingsView.swift:226:  .pickerStyle(.segmented)
Sources/JVoice/UI/SettingsView.swift:257:  .pickerStyle(.segmented)
# => no analytics/telemetry SDKs

$ grep -rnE "URL\(string:" Sources/
Sources/JVoice/Services/SettingsURLs.swift:7-12   # all are x-apple.systempreferences: deep links (open System Settings panes), NOT network
```

The only `URL(string:)` uses are six `x-apple.systempreferences:` deep links (open the Microphone/Accessibility/etc. Settings panes) — local URL-scheme handoffs to System Settings, not network requests. `NSWorkspace.shared.open(deepLink)` (`PermissionError.swift:48`) opens those panes.

The single genuine network path is in the WhisperKit dependency, reached only when a selected model is absent locally:

- `Sources/JVoice/Services/TranscriptionManager.swift:351-358` — `performLoad()` calls `WhisperKit(..., download: localFolder == nil)`. `download` is `true` only when `WhisperModelLocator.completeModelFolder(...)` returns `nil` (model not fully present under `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/...`). Once downloaded, every subsequent launch passes `download: false` and is fully offline.
- WhisperKit's endpoint: `.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Models.swift:1463` → `defaultRemoteEndpoint = "https://huggingface.co"` (HTTPS). Our `Info.plist` declares no ATS exception (`grep -i ATS Resources/Info.plist` → none), so default App Transport Security (TLS 1.2+, valid cert) applies.

This matches the advertised behavior exactly. The README claim is accurate.

---

### [SEC-01] Full transcript text persisted indefinitely in plaintext UserDefaults; no clear affordance; survives settings reset
- **Severity:** Medium
- **Tier:** T1 (safe auto-fix, locally verifiable)
- **Location:** `Sources/JVoice/Services/LastTranscriptStore.swift:3-15`; `Sources/JVoice/VoiceCoordinator.swift:528-529, 324-334`; `Sources/JVoice/UI/SettingsView.swift:140-187`
- **What:** Every successful dictation writes the *entire processed transcript* to `UserDefaults.standard` under `jvoice.app.lastTranscript`. UserDefaults persists to `~/Library/Preferences/com.jvoice.app.plist` — a plaintext, unencrypted, indefinitely-retained, Time-Machine-backed-up, iCloud-syncable-by-class file. The transcript is whatever the user dictated (could be a password, medical note, message). For a "privacy-first" product the most recent dictation is left at rest in cleartext forever, until overwritten by the next dictation.
- **Evidence:**
  ```swift
  // LastTranscriptStore.swift
  var transcript: String {
      get { defaults.string(forKey: Self.key) ?? "" }
      set { defaults.set(newValue, forKey: Self.key) }   // plaintext, .standard suite
  }
  // VoiceCoordinator.finishTranscription()
  lastTranscriptStore.transcript = processed   // :528
  ```
  `resetSettings()` (VoiceCoordinator.swift:324-334) re-defaults `mode/model/language/customWords/removeFillerWords` but **never touches `lastTranscriptStore`** — so "reset settings" leaves the last transcript on disk. The Settings UI (`SettingsView.swift:140-187`) renders the transcript in an editable field with "Fix" and "Revert" buttons but **no "Clear"/"Delete"** button.
- **Impact:** Sensitive dictated content sits in cleartext at rest indefinitely; another local user/process with read access to the prefs plist, a backup, or a forensic image recovers the last transcript. Undercuts the privacy promise even though nothing leaves the machine.
- **Fix (minimal):** (1) Add a "Clear" button in the Last Transcript section that calls a new `coordinator.clearLastTranscript()` setting the store to `""`. (2) Clear it in `resetSettings()`. Optionally (smaller blast radius, no UI): store only in-memory and drop the persisted key entirely if cross-launch retention isn't a required feature — but the "Fix last transcript / promote to custom word" feature relies on it surviving, so keep persistence + add a clear control. Encryption (Keychain) is heavier than warranted for a single most-recent string; a user-visible clear + reset-clears-it is the proportionate fix.
- **Verification:** Dictate text → quit → relaunch → confirm transcript reappears (current behavior). After fix: press Clear (and separately, Reset Settings) → relaunch → field shows "No transcript yet." and `defaults read com.jvoice.app jvoice.app.lastTranscript` errors (key absent) or is empty.

### [SEC-02] Transcript transits the general pasteboard un-marked; capturable by clipboard managers / Universal Clipboard
- **Severity:** Medium
- **Tier:** T2 (needs running app / behavioral to fully verify; the marking change itself is T1)
- **Location:** `Sources/JVoice/Services/PasteManager.swift:92-96, 102-140, 153-166`
- **What:** Paste works by writing the transcript to `NSPasteboard.general` (`stage()` → `clearContents()` + `setString`), synthesizing Cmd+V into the target app, then restoring the user's prior clipboard after `AppTimings.pasteRestoreDelay`. During that window the transcript is the system general pasteboard's content. The pasteboard item is **not** marked with the conventional clipboard-manager opt-out types (`org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType`). This is the price of the Cmd+V approach and is inherent — but the standard mitigations are not applied.
- **Evidence:**
  ```swift
  public func stage(_ text: String) {
      stagedText = text
      pasteboard.clearContents()
      _ = pasteboard.setString(text, forType: .string)   // plain .string, no concealed/transient marker
  }
  ```
  `grep -rniE "concealed|transient|org.nspasteboard|autoGenerated" Sources/` → only unrelated comment hits ("transient error in the HUD"). No pasteboard-history opt-out markers exist.
- **Impact:** (a) Third-party clipboard managers (Maccy, Paste, Raycast, etc.) and macOS pasteboard history snapshot the transcript into their own persistent stores even though JVoice restores the clipboard afterward — the transcript outlives the paste in software JVoice doesn't control. (b) With Universal Clipboard / Handoff enabled, the general pasteboard syncs to nearby Apple devices — a transcript briefly leaving the Mac via iCloud Continuity, contradicting "zero network." (c) The restore window (`pasteRestoreDelay`) is a TOCTOU window where the transcript is the live clipboard.
- **Fix (minimal, partial):** Mark the staged item with `org.nspasteboard.ConcealedType` (and optionally `TransientType` / `AutoGeneratedType`) so well-behaved clipboard managers skip it, and to discourage Universal Clipboard capture. Because `setString(_:forType:)` writes only one type, switch `stage()` to build an `NSPasteboardItem` that sets both `.string` (so Cmd+V still works) and the concealed/transient markers, then `writeObjects([item])`. This does not stop Universal Clipboard with certainty (Apple gates that on type heuristics, not a public opt-out), so also document the recommendation that privacy-sensitive users disable Handoff, and keep `pasteRestoreDelay` as short as the target apps tolerate. Note: this is a partial mitigation; the only complete fix (typing the text via synthesized keystrokes instead of paste) is a larger behavioral change — flag, don't auto-apply.
- **Verification:** With a clipboard manager (e.g. Maccy) running, dictate → confirm the transcript appears in its history today (repro), then after marking confirm it is skipped. Inspect the pasteboard item types during the window via a small AppKit probe.

### [SEC-03] No App Sandbox / hardened-runtime entitlements (unsigned distribution context)
- **Severity:** Low
- **Tier:** T2 (propose only — affects distribution/signing, not a code edit)
- **Location:** repo-wide — `find . -name "*.entitlements"` → none; `Resources/Info.plist` (no sandbox keys)
- **What:** There is no `.entitlements` file and no App Sandbox. The app runs unsandboxed with full user-level file access (it reads/writes `~/Documents/huggingface/...` for models and the temp dir, and needs to, plus Accessibility for paste). Given the project's documented `$0 / no Apple Developer account / unsigned ad-hoc DMG` constraint, the Hardened Runtime and notarization aren't available either. This is an accepted constraint, not a bug, but it widens the trust surface: a compromised/poisoned dependency runs with the user's full file privileges.
- **Evidence:** No entitlements file; `Info.plist` contains only `LSUIElement`, usage strings, and bundle metadata — no `com.apple.security.app-sandbox`.
- **Impact:** Any RCE in WhisperKit/KeyboardShortcuts/transitive code executes with full user file access (read `~/Documents`, `~/Library`, etc.). Sandboxing would confine that. Without notarization, Gatekeeper protections are also reduced (documented in `docs/launch/unsigned-distribution-findings.md`).
- **Fix:** Out of scope under current $0/unsigned constraints. If a Developer ID is ever obtained, enable App Sandbox with `com.apple.security.device.audio-input`, a scoped `~/Documents` model path (or move models to the sandbox container), plus Hardened Runtime + notarization. Track as a release-hardening item, not a code change now.
- **Verification:** `codesign -d --entitlements - /Applications/JVoice.app` on a future signed build shows the sandbox/hardened-runtime entitlements.

### [SEC-04] Model download has no content/signature pinning beyond TLS + size check (supply-chain / MITM-with-trusted-cert)
- **Severity:** Low
- **Tier:** T2 (propose only — depends on upstream WhisperKit)
- **Location:** `Sources/JVoice/Services/TranscriptionManager.swift:351-366`; WhisperKit `Models.swift:1463`, `ArgmaxCore/External/Hub/Downloader.swift:340`
- **What:** The model is fetched from `https://huggingface.co/argmaxinc/whisperkit-coreml` by WhisperKit's Hub downloader. Integrity is enforced by (a) HTTPS/TLS cert validation and (b) a downloaded-file-size check (`Downloader.swift:340` "Verify the downloaded file size matches the expected size"). There is **no SHA-256 / signature verification** of the CoreML weights pinned by JVoice. JVoice's own `WhisperModelLocator` only checks that required `.mlmodelc/weights/weight.bin` + `config.json` files *exist* (completeness), not that their contents match a known-good hash.
- **Evidence:**
  ```swift
  // WhisperModelLocator.requiredWeightPaths — existence-only check, no hashing
  static let requiredWeightPaths = [
      "MelSpectrogram.mlmodelc/weights/weight.bin",
      "AudioEncoder.mlmodelc/weights/weight.bin",
      "TextDecoder.mlmodelc/weights/weight.bin",
      "config.json",
  ]
  ```
- **Impact:** An attacker who can present a trusted TLS cert for `huggingface.co` (CA compromise, corporate TLS-intercepting proxy with a locally-trusted root, or a HuggingFace-account/repo compromise) could serve a malicious CoreML model of the same size. CoreML models execute compiled compute graphs; a poisoned model is a code/behavior-integrity risk and could corrupt transcripts. Practically low likelihood (one-time, HTTPS, reputable host), hence Low.
- **Fix:** True content pinning lives upstream in WhisperKit's Hub layer (it already records expected size; it does not expose a per-file hash gate to consumers), so JVoice can't cleanly add SHA pinning without forking the downloader — disproportionate for a $0 project. Proportionate steps: keep the WhisperKit revision pinned (already done in `Package.resolved`); document the trust assumption (model integrity == HuggingFace + TLS); and re-run `--bench --vocab/--stream` after any WhisperKit bump (already an established practice per project memory). Optionally pin the exact model commit SHA in the HuggingFace repo reference if WhisperKit's API allows it.
- **Verification:** Confirm `download: false` on every launch after first run (offline test: pull the network, relaunch, dictate — must transcribe with no error), proving no repeat fetch/MITM window after the one-time download.

### [SEC-05] Settings "corrupt backup" copies the raw settings blob to a second UserDefaults key, retained indefinitely
- **Severity:** Low
- **Tier:** T1
- **Location:** `Sources/JVoice/Services/SettingsStore.swift:72-85`
- **What:** When the settings JSON fails to decode, the raw bytes are copied to `jvoice.app.settings.state.corrupt.bak` and kept forever for manual recovery. That blob contains `customWords` (user-chosen vocabulary — names, project codenames, medical terms, etc.). It is duplicated into a second plaintext prefs key with no expiry and no cleanup once recovered.
- **Evidence:**
  ```swift
  defaults.set(data, forKey: backupKey)   // SettingsStore.swift:81 — corrupt blob retained
  ```
- **Impact:** Minor at-rest duplication of potentially-sensitive custom vocabulary in plaintext prefs, never garbage-collected. Lower stakes than SEC-01 (vocabulary, not free-form dictation) but the same class of issue.
- **Fix:** Acceptable to keep for recoverability, but clear `corruptBackupKey` once the user has successfully saved fresh settings (e.g. delete it in `performSave` after a successful encode), and include it in `resetSettings()`'s cleanup. One-line `defaults.removeObject(forKey: corruptBackupKey)` additions.
- **Verification:** Corrupt the key (write garbage), relaunch (backup created), save a setting → confirm `defaults read com.jvoice.app jvoice.app.settings.state.corrupt.bak` is then absent.

### [SEC-06] `--bench` CLI prints raw + processed transcripts to stdout (dev-only, not unified logging)
- **Severity:** Info
- **Tier:** T1 (no change recommended)
- **Location:** `Sources/JVoice/Services/BenchRunner.swift:72, 90, 93, 148-155`; entry `Sources/JVoice/JVoiceApp.swift:11-13`
- **What:** The hidden `--bench` mode `print()`s the raw and processed transcript to **stdout** (terminal), gated entirely on the user passing `--bench` on the command line. It is a developer harness (the README/CLAUDE.md document it), not reachable from the GUI launch path (`JVoiceMain.main()` only enters it when `arguments.contains("--bench")`). Output goes to the invoking terminal, **not** to `os_log`/unified logging, so it does not persist in Console.
- **Evidence:** `print("raw: \"\(raw)\"")`, `print("processed: \"\(processed)\"")` — only inside `BenchRunner`. No `os_log`/`NSLog` anywhere (`grep` for those → no matches in app code).
- **Impact:** None in normal use; a developer explicitly running `--bench` on their own audio sees their own transcript in their own terminal. No exposure to other users or to system logs.
- **Fix:** None needed. (If ever paranoid, it could be `#if DEBUG`-gated, but it's already opt-in and dev-documented.)
- **Verification:** `grep -rE "os_log|NSLog|Logger\(" Sources/` → no matches confirms no transcript reaches unified logging.

### [SEC-07] No logging of transcripts, audio paths, or PII to unified logging
- **Severity:** Info
- **Tier:** —
- **Location:** repo-wide
- **What:** Confirmation (positive finding). The only output sinks in app code are `FileHandle.standardError.write`/`print` inside `BenchRunner` (SEC-06) and user-facing HUD strings. There is no `os_log`, `os.Logger`, `NSLog`, or `debugPrint`. `TranscriptionError.errorDescription` does include the audio file *path* (e.g. `"Audio file not found at \(url.path)"`), and that string can reach the HUD via `updateHUD(.error(error.localizedDescription))` (VoiceCoordinator.swift:537) — but it is shown transiently on screen, not logged, and the path is a UUID temp filename, not transcript content.
- **Evidence:** `grep -rnE "\bprint\(|NSLog|os_log|os\.Logger|Logger\(|debugPrint|dump\(" Sources/` → only `BenchRunner` hits.
- **Impact:** None. This is the behavior a privacy-first product wants.
- **Fix:** None. Maintain this discipline (don't add `os_log` of transcript/audio in future work).
- **Verification:** Same grep on future diffs.

### [SEC-08] Temp WAV lifecycle is correct and the temp dir is owner-only (0700)
- **Severity:** Info
- **Tier:** —
- **Location:** `Sources/JVoice/Services/RecordingManager.swift:174-177, 224-248`; `Sources/JVoice/VoiceCoordinator.swift:166, 277-283, 423-425, 447`
- **What:** Confirmation (positive finding) for the audio-on-disk vector. Recordings are written to `FileManager.default.temporaryDirectory` as `jvoice-<UUID>.wav`. Deletion is covered on every path: success (`defer { try? FileManager.default.removeItem(at: audioURL) }`, VoiceCoordinator.swift:447); mid-recording failure (`tearDownFailedRecording()` removes the partial WAV, RecordingManager.swift:229-232); quit-mid-recording (VoiceCoordinator.swift:279-281); no-target-app abort (VoiceCoordinator.swift:423-425); too-short/unusable (still hits the `defer`); and a launch-time orphan sweep for crash/force-quit leftovers (`sweepOrphanedRecordings()`, RecordingManager.swift:239-248, called at `start()`:166). On-machine check: the resolved per-user temp dir (`DARWIN_USER_TEMP_DIR`, `/var/folders/.../T/`) is `drwx------` (mode 0700, owner-only) — so a transiently-lingering WAV is **not** world-readable. The streaming bench's growing WAV is also `defer`-deleted (BenchRunner.swift:122).
- **Evidence:** `ls -ld $(getconf DARWIN_USER_TEMP_DIR)` → `drwx------ ... /var/folders/.../T/`. Deletion sites enumerated above.
- **Impact:** The "recording lingers in a world-readable temp dir" concern is largely mitigated by the 0700 mode and the comprehensive deletion paths. Residual edge: between write and the orphan sweep, a power-loss crash leaves a WAV until next launch — but only the owner can read it.
- **Fix:** None required. (Optional defense-in-depth: the orphan sweep could also run on a periodic timer or `applicationDidBecomeActive`, but the launch-time sweep is sufficient for the threat model.)
- **Verification:** Force-quit (`kill -9`) mid-recording → confirm a `jvoice-*.wav` is left → relaunch → confirm sweep removes it. `ls -ld` the temp dir confirms 0700.

### [SEC-09] Permissions handling is least-privilege; no over-broad entitlements or automation
- **Severity:** Info
- **Tier:** —
- **Location:** `Resources/Info.plist:33-36`; `Sources/JVoice/Services/PasteManager.swift:35,54,104,129`; `Sources/JVoice/VoiceCoordinator.swift:201-216, 343-347`
- **What:** Confirmation (positive finding). The app declares exactly two TCC usage strings — `NSMicrophoneUsageDescription` and `NSAccessibilityUsageDescription` — both with accurate purpose strings. Microphone access is requested at recording time via `AVCaptureDevice.requestAccess(for: .audio)`. Accessibility is gated with `AXIsProcessTrusted()` before every paste (PasteManager.swift:35/54/104/129) and prompted at most once per launch (`ensureAccessibilityOnceForLaunch`, with a reset so a future revocation re-prompts). There is **no AppleScript / NSAppleScript / osascript / Apple Events automation** (`grep` confirms the only "automation" hits are the `PermissionError.automationDenied` enum case + a Settings deep link, neither of which sends Apple Events). The `PermissionError`/`SettingsURLs` plumbing for Bluetooth/Location/ScreenRecording/Automation appears to be inherited surface from the MacOSUtils provenance and is not exercised by JVoice's flows.
- **Evidence:** Info.plist declares only Microphone + Accessibility usage strings. `grep -niE "NSAppleScript|osascript|AppleEvent" Sources/` → no matches.
- **Impact:** None. Minimal, correctly-scoped permission surface.
- **Fix:** None required. Minor cleanliness note (not a security issue): the unused `PermissionError` cases (`bluetoothDenied`, `locationDenied`, `screenRecordingDenied`, `automationDenied`) and their `SettingsURLs` look like dead code carried over from MacOSUtils — mention to David per the "don't delete pre-existing dead code unless asked" rule; removing them shrinks the apparent permission surface but is non-urgent.
- **Verification:** `codesign`/Info.plist inspection of a build shows only the two usage strings; runtime TCC prompts only for Microphone + Accessibility.

---

## Notes on non-findings (explicitly checked, clean)

- **Network:** no `URLSession`/socket/`NWConnection`/analytics in `Sources/` (grep evidence above). Only egress = one-time WhisperKit HuggingFace download over HTTPS.
- **ATS:** no `NSAppTransportSecurity` / `allowsArbitraryLoads` in `Info.plist` — default secure ATS applies to the model download.
- **Clipboard restore:** `PasteManager` captures the prior clipboard (`captureClipboard`) and restores it after the paste (success: `pasteRestoreDelay`; failure: 0.05s), with `restoreTask` cancellation so back-to-back pastes don't clobber each other (PasteManager.swift:153-166). The user's clipboard is **not** permanently overwritten — good. (The in-transit exposure is SEC-02.)
- **HUDState:** `Codable` but never persisted to disk (`grep` confirms no encode/UserDefaults write of HUDState) — the `.done(transcript)` payload lives only in memory.
- **Supply chain:** `Package.resolved` pins exact revisions for WhisperKit (1.0.0 @ 25c6299), KeyboardShortcuts (1.10.0 @ 70caa8d), and transitive swift-argument-parser (1.8.2 @ 6a52f32); the file is deliberately tracked (reproducible builds). KeyboardShortcuts is exact-pinned in `Package.swift`; WhisperKit uses `from: 1.0.0` in the manifest but is revision-pinned in `Package.resolved`.
