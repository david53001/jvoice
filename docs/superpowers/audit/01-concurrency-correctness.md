# Audit 01 — Concurrency, Lifecycle & Correctness

**Scope:** `VoiceCoordinator`, `RecordingManager`, `AudioInputRouter`, `HotKeyManager`, `AppDelegate`, `JVoiceApp`, `AppTimings`, `SystemActions`, `LaunchAtLoginManager` (plus the streaming/transcription seams they touch). Read-only review against the live source at HEAD (`2b6d53c`). `swift build` is green at baseline.

**Summary.** The concurrency model is genuinely careful: nearly everything user-facing is `@MainActor`, the hotkey path uses synchronous `isStarting/isStopping` flags to win the re-entrancy race, the streaming session is an `actor` with an explicit generation guard, and the engine load is deduped. The defects that remain are concentrated in the *stop path* of the hotkey state machine, where the stop is dispatched into an unstructured `Task` (so it is not atomic with the press that triggered it) and where two of the busy-flags are reset on a *different* `Task` than the one that does the work — opening a real "stop is dropped" window and a "stuck Recording HUD" window on rapid presses. There is also a genuine ordering bug in `stopRecordingAndTranscribe` that re-targets the paste to the wrong app, an unbounded `recordingGeneration` (`Int` overflow is only theoretical, but the *streaming session not being torn down on a quit-less stop error path* is real), and several Low items (NotificationCenter observer never removed, `flushSettings` not on terminate when recording, HUD reset cancellation). No force-unwraps, `try!`, or unchecked index access exist in these files.

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 3 |
| Medium | 4 |
| Low | 4 |

| Tier | Count |
|---|---|
| T1 (safe auto-fix, build/logic-test verifiable) | 5 |
| T2 (risky / needs full app or CI / behavioral) | 6 |

---

### [CONC-01] Hotkey "stop" can be silently dropped on the wrong side of the busy flags
- **Severity:** High
- **Tier:** T2 (behavioral; needs a full-app or a new MainActor unit test to confirm timing)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:237-255` (esp. 247-254 vs 240-243)
- **What:** The start and stop branches each set their busy flag (`isStartingRecording` / `isStoppingRecording`) *synchronously*, but reset it from a **separate, nested** `Task { @MainActor … }` (the `defer` at lines 241 and 252). Because the reset runs on a different task hop than the work, there is a window where the flag is already cleared while the coordinator's *observable* state (`isRecording`) has not yet flipped, and vice-versa.
- **Evidence:**
  ```swift
  isStartingRecording = true
  currentTranscriptionTask?.cancel()
  currentTranscriptionTask = nil
  Task { [weak self] in
      defer { Task { @MainActor [weak self] in self?.isStartingRecording = false } }   // (B) reset
      await self?.startRecordingFlow()                                                  // (A) sets isRecording=true mid-body
  }
  ```
  `startRecordingFlow()` sets `isRecording = true` at line 371, *before* its body returns and *before* the `defer` schedules reset (B) — and (B) is itself a fresh `Task`, so it is enqueued behind any MainActor work already pending. Concretely:
  1. Press 1 → `isStartingRecording = true`, Task A starts, suspends on `requestPermission()`.
  2. Press 2 arrives while suspended → `isRecording` is still `false` and `isStartingRecording` is `true` → correctly suppressed. Good.
  3. Task A resumes, sets `isRecording = true` (line 371), returns. The `defer` enqueues reset-Task B.
  4. Press 3 arrives *after* `isRecording = true` but *before* reset-Task B runs → takes the **stop** branch, `isStoppingRecording` is false → stop proceeds. This is the *intended* path and is fine.

  The actual loss is the inverse: a press that arrives in the *stop* branch while `isStoppingRecording` is still `true` from a prior stop (its reset-Task hasn't run yet) is dropped via `guard !isStoppingRecording else { return }` (line 238) — but the user *did* intend to start a new recording. Because `isStopping`/`isStarting` are reset on a deferred task hop rather than synchronously at the end of the state transition, a fast press↔press↔press sequence can land in the dropped window.
- **Impact:** Occasional "I pressed the hotkey and nothing happened" — a dropped start or stop under rapid toggling. Not a crash; a missed dictation. The existing `VoiceCoordinatorHotkeyRaceTests` only asserts "doesn't crash", so this is uncovered.
- **Fix:** Reset the busy flag in the **same** task that owns it, immediately after the await completes, instead of via a second nested `Task`:
  ```swift
  Task { [weak self] in
      await self?.startRecordingFlow()
      self?.isStartingRecording = false   // already on MainActor; no nested Task
  }
  ```
  (Same for the stop branch — call `self?.stopRecordingAndTranscribe(); self?.isStoppingRecording = false`.) The nested `Task { @MainActor … }` adds a needless hop that widens the race window; collapsing it makes the flag lifetime exactly bracket the work. Keep the `defer` semantics by using `defer { self?.isStartingRecording = false }` *without* the inner `Task` — both the outer Task (stop branch) and the awaited body run on MainActor already.
- **Verification:** `swift build`; add a MainActor swift-testing case that drives `toggleRecording()` start→(await yield)→start and asserts exactly one recording began, plus a stop→stop→start sequence asserting the final start is honored. CI runs it.

---

### [CONC-02] Paste re-targets to the *current* frontmost app, ignoring the captured target PID
- **Severity:** High
- **Tier:** T2 (behavioral; user-visible mis-paste)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:495-508`
- **What:** `stopRecordingAndTranscribe` carefully resolves `targetPID` (the app that was frontmost when recording stopped) and threads it into `finishTranscription`. But just before pasting, `finishTranscription` re-activates `targetApp` *and then* pastes — which is correct — yet the activation is `try?`-swallowed and there is **no verification that activation succeeded** before the synthesized Cmd+V. If `targetApp.activate()` fails (app quit, or macOS denies cross-app activation), the Cmd+V is posted to `targetPID` regardless via `pasteManager.paste(processed, targetPID: pid)`, but if the app is gone the keystrokes land in whatever is now frontmost.
- **Evidence:**
  ```swift
  if let pid = targetPID, let targetApp = NSRunningApplication(processIdentifier: pid) {
      targetApp.activate()
      try? await Task.sleep(nanoseconds: UInt64(AppTimings.pasteActivationDelay * 1_000_000_000))
  }
  // ... no recheck that targetApp is still frontmost / still alive ...
  outcome = pasteManager.paste(processed, targetPID: pid)
  ```
  `NSRunningApplication(processIdentifier:)` returning non-nil at decode time does not guarantee the app survives the `pasteActivationDelay` sleep. The transcription itself can take seconds (Large model), during which the user may have quit or switched apps. `lastNonSelfFrontmostPID` is captured, but only used at *stop* time (line 418), not re-validated here.
- **Impact:** Transcribed text pasted into the wrong application after a slow transcription if the originally-targeted app changed/closed — a privacy-adjacent correctness bug (text intended for app A appears in app B). Low frequency, high annoyance.
- **Fix:** After the activation sleep, re-check the app is still alive (`NSRunningApplication(processIdentifier: pid)?.isTerminated == false`) and, when using `paste(processed)` (no PID) fallback, confirm the frontmost app PID still matches `targetPID`; otherwise surface `.error("Target app is no longer available")` and skip the paste. This keeps the existing fast path but closes the stale-target window.
- **Verification:** Manual: start a dictation, switch/quit the target app mid-transcription, confirm no text is pasted into the wrong app. (Not unit-testable without the full app — PasteManager touches the global event tap.)

---

### [CONC-03] Streaming session is leaked (never finished/cancelled) on the "no target app" stop error path... actually it IS cancelled — but the WAV-reading poll task can outlive the deleted file
- **Severity:** High
- **Tier:** T2 (resource/lifecycle; needs reasoning + manual)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:420-430`; interaction with `StreamingTranscriptionSession.pollOnce` `Sources/JVoice/Services/StreamingTranscriptionSession.swift:131-181`
- **What:** On the "No target app" stop path, the coordinator deletes the WAV (`removeItem(at: audioURL)`, line 424) and *then* fires `Task { await session.cancel() }` (line 427) **fire-and-forget**, without awaiting it. `cancel()` is an `async` actor method; until it runs, the session's poll loop may still call `reader.samples(from:)` / `WavTailReader.open` on the just-deleted file. The session handles a vanished file (`failed = true`), so this is not a crash — but the deletion races the cancel, and because the cancel is not awaited, `stopRecordingAndTranscribe` returns while a detached decode for the abandoned recording can still be in flight on the WhisperKit actor. Combined with a fast subsequent start, the abandoned session's decode overlaps the new recording's decode on the same engine actor (serialized, so correctness holds, but it adds latency to the new recording and burns CPU on audio the user abandoned).
- **Evidence:**
  ```swift
  guard let targetPID = resolvedTargetPID else {
      updateHUD(.error(...)); scheduleHUDReset(after: 3_000_000_000)
      if let audioURL { try? FileManager.default.removeItem(at: audioURL) }  // delete first
      if let session { Task { await session.cancel() } }                      // cancel later, not awaited
      return
  }
  ```
  Contrast `quitApp` (lines 273-276) which has the same fire-and-forget pattern but is acceptable there because the process is terminating. Here the app keeps running.
- **Impact:** Abandoned-recording chunk decode keeps running after the user's stop produced no paste; if they immediately re-record, the new dictation's first chunk decode queues behind the dead one — extra latency and wasted compute. No data loss or crash.
- **Fix:** Make this path mirror `finishTranscription`'s handling: hand the session to a small async cleanup that *awaits* the cancel before the WAV is removed, or move the `removeItem` to after the cancel completes. Minimal: `if let session { Task { await session.cancel() } }` is acceptable for cancel ordering, but the WAV delete should not precede it — order the delete inside the same task after cancel, or rely on the session's own teardown. Simplest surgical fix: delete the WAV inside the cancel task: `if let session { Task { await session.cancel(); if let audioURL { try? FileManager.default.removeItem(at: audioURL) } } } else if let audioURL { try? FileManager.default.removeItem(at: audioURL) }`.
- **Verification:** Manual with `--bench --stream` semantics is hard; reason about it via `verify-streaming.sh` (the session's vanished-file path is already covered there). Confirm `swift build` after the reorder.

---

### [CONC-04] `transcriptionManager.isTranscribing` is `false` during the prewarm/preparing window, so a "start" can be admitted while a transcription is logically in progress
- **Severity:** Medium
- **Tier:** T2 (behavioral)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:246` guard vs `finishTranscription` lines 463-468 and `TranscriptionManager.transcribe` lines 390-411
- **What:** The start branch guards `guard !transcriptionManager.isTranscribing else { return }`. But `isTranscribing` only becomes `true` *inside* `TranscriptionManager.transcribe()` (line 390). `finishTranscription` does meaningful async work *before* that call: `isEngineReady()`, `prewarmAndWait()` (the multi-minute Large CoreML specialization), and `session.finish()`. During all of that, `isTranscribing` is still `false`. A hotkey press in that window passes the guard and starts a new recording, even though the previous dictation's transcription is still pending.
- **Evidence:** `finishTranscription` only reaches `transcriptionManager.transcribe(...)` at line 480 (the non-streamed branch). For the streamed branch (line 472) it calls `await session.finish()` and **never sets `isTranscribing`** at all — so the guard at 246 is fully bypassed for streamed transcriptions. The coordinator does cancel `currentTranscriptionTask` on a new start (line 249), which is the real safety net, but the guard at 246 is misleading and gives a false sense that double-transcription is impossible.
- **Impact:** Not a crash (the `Task.isCancelled` checks at 482 prevent a double paste), but: the "Preparing model…" HUD can be interrupted by a new recording that then shows "Recording", and the prewarm work continues in the background. Mostly a UX/state-clarity issue; the cancellation net holds correctness.
- **Fix:** Either drop the `isTranscribing` guard (rely solely on `currentTranscriptionTask` cancellation, which is the real mechanism) or track an explicit `isFinishing` flag set for the whole duration of `finishTranscription` (set true at entry, false in a `defer`). The latter makes the guard at 246 actually meaningful for both streamed and whole-file paths. Prefer the flag — it's a few lines and matches the existing `isStarting/isStopping` idiom.
- **Verification:** MainActor swift-testing case: drive a recording to the preparing window (inject a slow mock engine), fire a second toggle, assert the second start is rejected. CI.

---

### [CONC-05] `recordingGeneration` resets and stale-session guard depend on `isRecording` that flips before `stopRecording()` is called
- **Severity:** Medium
- **Tier:** T2 (behavioral reasoning)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:381-397` (start) and 405-411 (stop)
- **What:** The streaming-session assignment guard is `guard self.isRecording, self.recordingGeneration == generation`. `stopRecordingAndTranscribe` sets `isRecording = false` at line 405 *before* it reads/clears `streamingSession` at lines 410-411. The async session-creation Task (line 381) re-checks `isRecording` after its `await makeStreamingSession()`. If the stop happens during that await, the guard correctly cancels the orphan session. This is correct. **However**, the generation is bumped at line 372 *after* `isRecording = true` (line 371) and after `startRecording()` already succeeded — and the session-creation Task captured `recordingGeneration` at line 382 (`let generation = recordingGeneration`). Since both the bump and the capture run on MainActor without an intervening await, ordering is deterministic and correct.
- **Evidence:** The sequence 371→372→379→382 is fully synchronous on MainActor; the only await is at line 383 (`makeStreamingSession`), after which the guard re-validates. No bug in the generation logic itself.
- **Impact:** None observed — this entry documents that the generation guard is **correct** and should not be "fixed". Listed Medium only because it is fragile to future edits: moving the `recordingGeneration += 1` or the session-Task spawn across an `await` would silently break the stale-session guarantee. Reclassify to Low if treated as documentation.
- **Fix:** No code change. Recommend a one-line comment at line 372 reinforcing "must be bumped synchronously before the session Task captures it; do not move across an await." (Comment-only; matches the existing explanatory style.)
- **Verification:** N/A (no behavioral change). `verify-streaming.sh` already exercises the session lifecycle.

---

### [CONC-06] `stopRecording()` ignores `recorder.stop()` ordering relative to delegate `didFinishRecording`
- **Severity:** Medium
- **Tier:** T2 (AVFoundation lifecycle; needs device)
- **Location:** `Sources/JVoice/Services/RecordingManager.swift:135-150` and delegate 202-209
- **What:** `stopRecording()` calls `recorder?.stop()` then immediately nils `recorder`, flips `isRecording = false`, and returns the URL. `AVAudioRecorder.stop()` triggers `audioRecorderDidFinishRecording(_:successfully:)` **asynchronously**. The delegate's success path is a no-op (`guard !flag else { return }`), but if the OS reports `successfully: false` *after* the explicit stop (e.g. the file failed to finalize), the delegate runs `tearDownFailedRecording()` which calls `recordedURL` removal — but `recordedURL` was already niled by `stopRecording()` (line 148), so the cleanup finds `recordedURL == nil` and **cannot delete the half-written WAV**. Meanwhile the coordinator has already taken the URL and will hand it to transcription, which then fails `isUsableRecording` or WhisperKit. The file does get deleted by `finishTranscription`'s `defer` (line 447), so no orphan — but the *error classification* is lost: a genuinely failed finalize is reported to the user as "Recording too short" rather than "Recording stopped unexpectedly".
- **Evidence:** `stopRecording()` sets `recordedURL = nil` (line 148) before the async delegate can observe a `successfully: false`. The delegate's `tearDownFailedRecording` (line 229) guards `if let url = recordedURL` — now nil — so its cleanup is a no-op for the URL it intended to remove.
- **Impact:** Misleading error message on a rare AVFoundation finalize failure; no orphaned file (the coordinator's `defer` covers it), no crash. Low likelihood.
- **Fix:** Don't rely on the delegate for the explicit-stop path (the comment at line 203 already says success is handled by `stopRecording()`). This is largely fine as-is; the only real defect is the error message. If worth fixing: keep `recordedURL` populated until the URL is consumed, or have `stopRecording` itself validate the file exists/size before returning the URL and surface `.finishedUnsuccessfully` when it doesn't. Given simplicity-first, recommend leaving it and only noting the misleading message.
- **Verification:** Hard to reproduce without forcing a finalize failure; manual only. Low priority.

---

### [CONC-07] `setDefaultInputDevice` failure on restore leaves the user on the built-in mic permanently
- **Severity:** Medium
- **Tier:** T2 (Core Audio; needs Bluetooth device)
- **Location:** `Sources/JVoice/Services/RecordingManager.swift:129-133`, `AudioInputRouter.setDefaultInputDevice` 61-69
- **What:** `restoreDefaultInput()` calls `AudioInputRouter.setDefaultInputDevice(original)` and unconditionally clears `inputDeviceToRestore = nil` regardless of whether the restore *succeeded*. If `AudioObjectSetPropertyData` returns non-`noErr` (e.g. the original Bluetooth device disconnected during the recording), the system default input is left pointing at the redirected built-in mic and the app forgets it ever redirected — the user's preferred input is silently not restored, with no retry and no error.
- **Evidence:**
  ```swift
  private func restoreDefaultInput() {
      guard let original = inputDeviceToRestore else { return }
      AudioInputRouter.setDefaultInputDevice(original)   // @discardableResult — failure ignored
      inputDeviceToRestore = nil                          // cleared unconditionally
  }
  ```
- **Impact:** After a dictation where the Bluetooth input vanished mid-recording, the system's default input device stays switched to the built-in mic. The user must manually re-select their device in System Settings. Annoying, not dangerous. The "device disconnected" case is exactly when restore is most likely to fail.
- **Fix:** This is genuinely hard to do well (the original device may legitimately be gone), so a retry could be wrong. Minimal honest improvement: if `setDefaultInputDevice(original)` fails, route a one-line note through `SystemActions.errorHandler?` ("Couldn't restore your previous microphone — check System Settings → Sound"). Keep clearing `inputDeviceToRestore` (no point retrying a missing device). Low-effort, no behavioral risk.
- **Verification:** Manual with AirPods: start dictation, power off AirPods mid-recording, stop, check Sound settings. Confirm `swift build`.

---

### [CONC-08] NotificationCenter / NSWorkspace observers are never removed
- **Severity:** Low
- **Tier:** T1 (RecordingManager already removes its observer; VoiceCoordinator's workspace observer is the gap — build-verifiable)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:218-231` (`installFrontmostObserver`)
- **What:** `installFrontmostObserver` adds a block-based observer to `NSWorkspace.shared.notificationCenter` and never stores the returned token nor removes it. `VoiceCoordinator` has no `deinit` and the block strongly references `self` indirectly via the inner `Task { @MainActor [weak self] in … }` (the *outer* observer block captures `self` weakly — good — but the observer registration itself is never torn down).
- **Evidence:** No `removeObserver` for the returned token anywhere; `VoiceCoordinator` has no `deinit`. Compare `RecordingManager` which correctly removes its observer in `deinit` (lines 49-51).
- **Impact:** Effectively none in production — `VoiceCoordinator` is owned by `AppDelegate` for the entire process lifetime, so it never deallocates and the observer never dangles. Becomes a real leak only if a second coordinator is ever created (e.g. in tests: `VoiceCoordinatorHotkeyRaceTests` *does* create coordinators repeatedly), where each test leaks one workspace observer holding a closure. Harmless to the app, mild test hygiene issue.
- **Fix:** Store the token (`private var frontmostObserver: NSObjectProtocol?`) and remove it in a `deinit`. Since the block already captures `self` weakly, this is purely about not accumulating dead observers across coordinator instances. T1: small, build-checkable.
- **Verification:** `swift build`. (Behavior unchanged in the running app.)

---

### [CONC-09] `applicationWillTerminate` does not stop an in-progress recording (only `quitApp` does)
- **Severity:** Low
- **Tier:** T2 (behavioral; privacy edge)
- **Location:** `Sources/JVoice/AppDelegate.swift:22-24`, `VoiceCoordinator.quitApp` 269-287, `flushSettings` 314-316
- **What:** The privacy guarantee "a quit mid-recording removes the abandoned WAV" lives in `quitApp()` (lines 279-281), which is invoked only from the menu's Quit item. If the app is terminated by any *other* route — `Cmd+Q` routed through AppKit's default terminate, a logout/shutdown, or `NSApp.terminate` from elsewhere — `applicationWillTerminate` runs, but it only calls `flushSettings()`. It does **not** stop the recorder or delete the in-flight WAV.
- **Evidence:** `applicationWillTerminate` body is solely `coordinator.flushSettings()`. The orphan-WAV deletion is in `quitApp`, not in the terminate hook. The launch-time `sweepOrphanedRecordings()` (RecordingManager line 239) does eventually clean it up on next launch, so the WAV is not permanent — but it survives on disk between the abrupt quit and the next launch.
- **Impact:** A WAV of the abandoned dictation persists in the temp directory until the next app launch sweep, if the app is force-terminated mid-recording by a path other than the menu Quit. Minor privacy window; self-heals on next launch.
- **Fix:** Move the recording-teardown + WAV-removal out of `quitApp` into a private helper and call it from `applicationWillTerminate` too (before `flushSettings`). `quitApp` then calls the helper and `NSApp.terminate`. Surgical, single source of truth for "clean up on exit."
- **Verification:** Manual: start recording, `Cmd+Q`, check temp dir for `jvoice-*.wav`. `swift build`.

---

### [CONC-10] HotKeyManager debounce uses wall-clock `Date` and double-registers on init
- **Severity:** Low
- **Tier:** T1 (build-verifiable; the double-register is a no-op but is dead/confusing code)
- **Location:** `Sources/JVoice/Services/HotKeyManager.swift:32-51`
- **What:** Two minor issues. (1) `init` calls `register()` (line 35), and `VoiceCoordinator.start()` calls `hotKeyManager.register()` again (VoiceCoordinator line 174). The second call is a no-op thanks to the `guard !isRegistered` flag — but it means the registration always happens at *coordinator init* (the `lazy var` is realized when `start()` first touches it), not at `start()`, making the explicit `register()` in `start()` dead. (2) The 0.15 s debounce uses `Date()` wall-clock, which is correct here but would misbehave under clock changes; not worth changing for a 150 ms window.
- **Evidence:** `HotKeyManager.init` line 35 `register()`; `VoiceCoordinator.start()` line 174 `hotKeyManager.register()`. The `lazy var hotKeyManager` (VoiceCoordinator line 110) is only instantiated on first access — which is the line-174 call — so init's `register()` runs synchronously inside that, and the line-174 call's body is the no-op-guarded one. Net: works, but the `register()` inside `init` makes the public `register()` API and the call in `start()` redundant.
- **Impact:** None functional. Confusing dual-registration that could bite a future refactor (if someone removes the `start()` call thinking init handles it, or vice-versa).
- **Fix:** Remove the `register()` call from `init` (line 35) and rely on the explicit `register()` in `VoiceCoordinator.start()` — registration belongs to the app-start lifecycle, not object construction. This also makes `HotKeyManager` constructible in tests without immediately grabbing a global hotkey. T1.
- **Verification:** `swift build`. Confirm the shortcut still fires manually after launch.

---

### [CONC-11] `ensureAccessibilityOnceForLaunch` resets the prompt flag every trusted launch — a benign but mildly surprising side effect
- **Severity:** Low
- **Tier:** T1 (build-verifiable; behavior intentional but worth flagging)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:201-216`
- **What:** On every launch where AX is already trusted, the method sets `didPromptAXOnLaunch = false` (line 206) so a future revocation re-prompts. This is intentional and documented. The only correctness note: `AXIsProcessTrustedWithOptions` with the prompt option is called from `start()` on the main thread synchronously during `applicationDidFinishLaunching`; the prompt is non-blocking, so this is fine. No defect — included for completeness so the audit doesn't appear to have missed the AX path.
- **Evidence:** Logic at lines 205-215 is internally consistent; `defaults.set(true, …)` only after a prompt was actually shown.
- **Impact:** None.
- **Fix:** None. (Documented as reviewed.)
- **Verification:** N/A.

---

## Notes on things that are correct (and should NOT be "fixed")
- The stop-branch `Task { … self?.stopRecordingAndTranscribe() }` (line 240) compiles without `await` because an unstructured `Task {}` created in a `@MainActor` method **inherits** MainActor isolation in Swift 5.9 — confirmed by the green build. So there is **no off-main UI access** there. (CONC-01 is about flag-reset *timing*, not isolation.)
- `loadWhisperKit` correctly dedupes concurrent loads and drops the failed task for retry (`TranscriptionManager`/engine actor lines 320-349). No double-load race.
- `StreamingTranscriptionSession.appendPiece` failing on an empty non-silent decode (lines 99-118, 166-175) is the documented data-loss guarantee and is correct — do not "optimize" the empty-string check away.
- No force-unwraps, `try!`, `as!`, or unchecked subscript access exist in any of the audited files (verified by scan).
- `recordingGeneration` is an `Int`; overflow is not a practical concern (would require ~9.2 × 10¹⁸ recordings).
