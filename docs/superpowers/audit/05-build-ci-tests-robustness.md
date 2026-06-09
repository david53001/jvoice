# Audit 05 — Build / CI / Tests / Robustness

**Scope:** build system, CI, the 21-file swift-testing suite, the 5 verification scripts, app-wide failure-mode robustness, and packaging. Read-only audit; no files changed other than this report.

**Summary.** The project is in genuinely good shape for a solo, $0-budget, CLT-only workflow: `swift build` passes, both local execution harnesses (`run-logic-tests.sh`, `verify-streaming.sh`) compile and pass with exit code 0, and the CI's "≥90 swift-testing cases executed" gate is a real, well-reasoned defense against the `#if canImport(Testing)` silent-skip trap that the team already got burned by. The pure-logic core (TextProcessor, PhoneticMatcher, RepetitionGuard, ChunkPlanner, WavTail, RegurgitationRecovery, StreamingTranscriptionSession) is heavily and meaningfully tested — these are not tautological tests; they encode hard-won bug regressions. The real gaps are at the edges: CI never compiles the *non-test* product in a way that catches a broken `#else`/fallback path, never runs the two local scripts (so a script that silently stops testing what it claims wouldn't be caught), there is no lint/format gate, and several robustness paths (disk-full during recording, second-instance launch, the `ensureAccessibilityOnceForLaunch` UserDefaults flag living in the wrong suite) are unhandled or untested. None are crash-class for the common path; most are "silent degradation" or "stale state" class.

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 4 |
| Medium | 9 |
| Low | 7 |
| **Total** | **20** |

Verified locally: `swift build` → Build complete (exit 0); `./scripts/run-logic-tests.sh` → all logic tests passed (exit 0); `./scripts/verify-streaming.sh` → all streaming + recovery verification passed (exit 0).

---

## CI findings

### [BLD-01] CI never asserts a clean release/product build (only `swift test`)
- **Severity:** High
- **Tier:** T1
- **Location:** `.github/workflows/test.yml:26-29`
- **What:** The only build CI does is the implicit debug build inside `swift test`. There is no `swift build -c release`, and no build of the executable product on its own.
- **Evidence:** The workflow runs `swift package resolve` then `swift test`. `swift test` builds the test target (which `@testable import JVoice` pulls in the lib) in debug. The release configuration, the `#else` (non-WhisperKit) branches in `VoiceCoordinator.makeTranscriptionEngine`, `TranscriptionManager.makeDefaultEngine`, and `HotKeyManager`/`BenchRunner`'s `#if canImport(WhisperKit)` are never exercised in release. `install.sh` is the *only* thing that does `swift build -c release`, and it is run by hand on David's machine.
- **Impact:** A release-only compile error, or an optimizer-sensitive bug, ships undetected. The shipped artifact (release DMG) is built in a config CI never touches.
- **Fix:** Add a step `swift build -c release` (the executable product) to the existing job, or a small parallel matrix leg. It catches release-mode breakage and the actual distribution config.
- **Verification:** CI green requires the release build to succeed; locally `swift build -c release` already works.

### [BLD-02] CI never runs `run-logic-tests.sh` or `verify-streaming.sh`
- **Severity:** High
- **Tier:** T1
- **Location:** `.github/workflows/test.yml` (absent); `scripts/run-logic-tests.sh`, `scripts/verify-streaming.sh`
- **What:** The two scripts that are the *local* source of truth on a CLT-only machine are never run in CI. Their headers explicitly say "Mirrors `Tests/JVoiceTests/...` — keep both in sync; the suite is the authority," but nothing enforces that the scripts still *compile and pass* after a source change.
- **Evidence:** The scripts `xcrun swiftc` a hand-maintained subset of sources plus an assertion `main.swift`. If a refactor renames a symbol or changes a signature, the script breaks; on David's machine that's caught only if he remembers to run it. CI is the place that should guard it.
- **Impact:** The scripts silently rot. The next contributor (or David in 3 months) trusts a green CI but the documented local verification path no longer compiles. Worse, a behavior change could pass the swift-testing suite but the script's mirrored assertions go stale, defeating their stated "smoke check" purpose.
- **Fix:** Add two CI steps: `./scripts/run-logic-tests.sh` and `./scripts/verify-streaming.sh`. They need only the Swift toolchain (no WhisperKit, no mic), so they run on the same `macos-15` runner with no extra setup. Both already exit non-zero on failure.
- **Verification:** Both scripts return exit 0 today (confirmed); wiring them in CI makes future drift a red build.

### [BLD-03] Test-count gate's threshold is a hard-coded magic number with no lower-bound tie to authored count
- **Severity:** Medium
- **Tier:** T1
- **Location:** `.github/workflows/test.yml:30-49`
- **What:** The gate asserts `COUNT >= 90` against an authored count noted as "96 as of 2026-06-06." Authored count has since grown (RegurgitationRecovery + several Streaming/RepetitionGuard cases added 2026-06-09). The 90 floor now has much more headroom than intended (real count is well above 96), so a regression that silently drops, say, 20 cases would still pass.
- **Evidence:** Comment says "96 cases as of 2026-06-06"; files dated 2026-06-09 (`RegurgitationRecoveryTests`, `RepetitionGuardTests`, `StreamingTranscriptionSessionTests`, `WhisperModelOptionTests`) add cases beyond that. The floor wasn't bumped.
- **Impact:** The gate's sensitivity has eroded. It still catches *wholesale* skips (the original trap, where 78/96 vanished), which is its primary job — so this is Medium, not High — but it no longer catches a moderate silent-skip regression.
- **Fix:** Either bump the floor to a value tracking the current authored count (count `@Test` occurrences ≈ a more accurate floor), or compute the floor in CI: `grep -roh '@Test' Tests | wc -l` minus a small slack, and compare. The latter is self-maintaining.
- **Verification:** Print both authored and executed counts in the step; assert executed ≥ authored − slack.

### [BLD-04] No lint / format / `swift build -warnings-as-errors` gate
- **Severity:** Low
- **Tier:** T1
- **Location:** `.github/workflows/test.yml` (absent)
- **What:** No SwiftFormat/SwiftLint, and warnings are not promoted to errors. Style drift and accumulating warnings go unflagged.
- **Impact:** Low for a solo project, but warnings (e.g. unused results, deprecations from a WhisperKit bump) can hide real issues. For a public OSS repo aiming at PRs, a format gate reduces review churn.
- **Fix:** Optional. If desired, add `swift build -Xswiftc -warnings-as-errors` as a non-blocking informational step first, then promote. SwiftFormat-lint is a separate, low-cost add.
- **Verification:** N/A unless adopted.

### [BLD-05] CI triggers omit tags and `release/**`; `concurrency` cancellation absent
- **Severity:** Low
- **Tier:** T1
- **Location:** `.github/workflows/test.yml:3-6`
- **What:** Push triggers cover `main`, `feat/**`, `fix/**` but not tags or a `release/**` branch. There is no `concurrency:` block, so rapid pushes run redundant macOS minutes (a cost concern on free CI when the eventual release workflow lands).
- **Impact:** A tagged release commit (the planned DMG flow) wouldn't run tests on the tag. Redundant runs waste the free macOS minutes pool.
- **Fix:** Add `tags: ['v*']` (or rely on the future release workflow to invoke tests), and add a `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }` block.
- **Verification:** N/A (config-only).

---

## Test-suite findings

### [BLD-06] No coverage for the whole-app orchestration in `VoiceCoordinator` beyond a no-crash smoke test
- **Severity:** High
- **Tier:** T2
- **Location:** `Tests/JVoiceTests/VoiceCoordinatorHotkeyRaceTests.swift:5-14`; `Sources/JVoice/VoiceCoordinator.swift`
- **What:** The single VoiceCoordinator test calls `toggleRecording()` twice and asserts nothing ("No invariant we can assert on without exposing more state"). The coordinator is the highest-risk file in the app — it owns the record→transcribe→paste flow, the streaming-session generation guard (`recordingGeneration`), the target-PID resolution, the revert buffer, and all the HUD error branches in `finishTranscription` — and none of that decision logic is unit-tested.
- **Evidence:** The test's own comment concedes it asserts only "don't crash." Pure-ish policy that *is* testable but isn't: target-PID resolution (`stopRecordingAndTranscribe` lines 412-430: own-PID exclusion, `lastNonSelfFrontmostPID` fallback, the "No target app" error), `extractCorrections`→`fixLastTranscript`→`revertLastFix` round-trip (custom-word insertion + revert), and the `streamed ?? whole-file` fallback selection in `finishTranscription`.
- **Impact:** The most consequential glue logic ships unverified. A regression in the generation guard (already a subtle, documented race fix) or in revert could silently corrupt custom words or paste into the wrong app, with no test to catch it.
- **Fix:** Extract the two genuinely pure pieces into testable seams and test them: (a) a `resolveTargetPID(frontmostPID:ownPID:lastNonSelfPID:)` static/free function tested with all three branches; (b) the revert flow via the already-`@MainActor`-testable `fixLastTranscript`/`revertLastFix` (seed `lastTranscript`, fix, assert `customWords` + `canRevert`, revert, assert restoration). Both are T1 once the PID seam exists; today the coordinator's `@MainActor` + private state makes them T2.
- **Verification:** New swift-testing cases under the existing suite; they raise the authored count (and the BLD-03 floor).

### [BLD-07] `PasteManager` clipboard-restore on the *success* path is untested
- **Severity:** Medium
- **Tier:** T2
- **Location:** `Tests/JVoiceTests/PasteManagerTests.swift`; `Sources/JVoice/Services/PasteManager.swift:120-166`
- **What:** Tests cover stage, empty-text rejection, and *failed*-paste clipboard restore. The success path's delayed restore (restore the user's prior clipboard 0.30 s after a successful paste) and the `restoreTask?.cancel()` two-pastes-in-a-window coalescing are not tested. Because `AXIsProcessTrusted()` is false in CI, the success branch is structurally unreachable there.
- **Evidence:** `failedPasteRestoresOriginalClipboard` exists; no equivalent for `result == true`. The tests note "AX-trusted in CI is unknowable," so they can only assert the denied/rejected branches.
- **Impact:** The clipboard-preservation feature — a privacy/UX promise (don't permanently clobber the user's clipboard) — is verified only on failure, not on the common success path. The restore-coalescing (two quick dictations) is wholly untested.
- **Fix:** Inject the AX-trusted check (e.g. a `accessibilityTrusted: () -> Bool` closure defaulting to `AXIsProcessTrusted`) so the success branch is reachable under test with a mock performer returning `true`. Then assert the prior clipboard is restored after the delay and that a second paste cancels the first restore. This requires a small (build-safe) seam in `PasteManager`, so it's T2 today.
- **Verification:** New case waits past `pasteRestoreDelay` and asserts restoration; another fires two pastes and asserts only the latest restore runs.

### [BLD-08] `WhisperKitTranscriptionEngine` decode/recovery/biasing logic is only indirectly tested
- **Severity:** Medium
- **Tier:** T2
- **Location:** `Tests/JVoiceTests/TranscriptionManagerTests.swift`; `Sources/JVoice/Services/TranscriptionManager.swift:114-367`
- **What:** The actor's substantial logic — `loadWhisperKit` dedupe/retry, `isSingleWindowClip` duration gating, `withoutTimestamps` selection, prompt-token caching/invalidation on vocab change, `applyVocabularyBiasing` filter install/clear symmetry — is gated behind `#if canImport(WhisperKit)` and unreachable in unit tests without the framework loaded. Only `promptedPrefillCount` (the off-by-one filter index) is directly unit-tested.
- **Evidence:** Most of the file is inside `#if canImport(WhisperKit)`; the swift-testing cases that touch it are the prefill-count math and the engine-swap deferral (`updateEngineDuringTranscriptionDefersSwap`). The real decode paths are only covered by the manual `--bench` / `verify-transcription.py` harnesses, which need a downloaded model and don't run in CI.
- **Impact:** The duration-gating trap (long clips MUST keep timestamps — documented as a WhisperKit 1.0.0 truncation bug) and the prompt-compatibility filter (empty-transcript trap) are the two scariest WhisperKit-version-sensitive behaviors, and both are verified only by hand. A WhisperKit bump could silently re-break either.
- **Fix:** Pull the two pure decisions out into testable static helpers: `isSingleWindowClip` already nearly is (it takes a URL — give it an injectable duration or a `(URL)->TimeInterval?` probe so the threshold logic is tested with synthetic durations), and add a focused test that `updateVocabulary` invalidates `cachedPromptTokens`. The deeper decode coverage stays the bench harnesses' job (correctly so). Keep the bench/verify-transcription runbook in HANDOFF as the post-WhisperKit-bump gate.
- **Verification:** New cases for the duration-gate boundary (24.9 s → true, 25.1 s → false) without WhisperKit.

### [BLD-09] No test that the *whole-file* path strips regurgitation end-to-end via `RegurgitationRecovery` wiring
- **Severity:** Low
- **Tier:** T1
- **Location:** `Tests/JVoiceTests/RegurgitationRecoveryTests.swift`; `Sources/JVoice/Services/TranscriptionManager.swift:161-167, 187-193`
- **What:** `RegurgitationRecovery.decode` is well tested with a mock decode closure (4 cases, mirrored in verify-streaming). But the engine's wiring (`decodeRecoveringFromRegurgitation` passing `useVocabularyPrompt`/`vocabulary` correctly, and `transcribe` throwing `emptyTranscript` when recovery yields "") is `#if canImport(WhisperKit)`-gated and untested.
- **Impact:** Low — the policy unit is solid; only the (thin) wiring is unverified. A wiring mistake (e.g. passing the wrong vocab) would surface in the bench harness.
- **Fix:** Optional. If the engine's `transcribe` empty-throw is worth pinning, a tiny seam over the decode closure would let it be tested without WhisperKit. Likely not worth the seam.
- **Verification:** N/A unless adopted.

### [BLD-10] `StatsStore` has zero tests (WPM math + guard conditions)
- **Severity:** Medium
- **Tier:** T1
- **Location:** `Sources/JVoice/Services/StatsStore.swift` (no test file)
- **What:** `StatsStore` is fully testable (UserDefaults-injectable... almost — see below) pure-ish arithmetic with guard branches (`record` ignores zero words/duration; `averageWPM` guards divide-by-zero) and accumulation, and has no tests at all.
- **Evidence:** No `StatsStoreTests.swift`. `init(defaults:)` accepts an injected `UserDefaults`, so a suite-scoped test is trivial — *but* the convenience `init()` used by `VoiceCoordinator` hard-codes `.standard`, and `record`/`averageWPM`/`totalWords` are the surface to test.
- **Impact:** A regression in the WPM formula or the zero-guards (e.g. a future "reset stats" feature, or a divide-by-zero on the very first dictation) would be unnoticed. Low blast radius (cosmetic stat), but it's free coverage.
- **Fix:** Add `StatsStoreTests` with an injected suite: record(10, 60) → totalWords 10, averageWPM 10; record(0, 5) and record(5, 0) → no-op; averageWPM with totalSeconds 0 → 0; accumulation across two records.
- **Verification:** New swift-testing cases; raises authored count.

### [BLD-11] `LaunchAtLoginManager` first-run logic is untested (and not seam-injectable for the OS call)
- **Severity:** Low
- **Tier:** T2
- **Location:** `Sources/JVoice/Services/LaunchAtLoginManager.swift:27-31` (no test file)
- **What:** `performFirstRunEnableIfNeeded(defaults:)` takes an injectable `UserDefaults` but calls `SMAppService.mainApp.register()` directly, which can't run in a CLT/CI environment (no app bundle, no SM service). The "only enable once, never re-enable after user disables" invariant — its whole reason to exist — is untested.
- **Impact:** Low. The `didInitialize` flag flip is the only testable part; the OS call is correctly best-effort/`try?`. A regression that re-enables on every launch (annoying users who turned it off) wouldn't be caught.
- **Fix:** Optional. Could split the "should we attempt enable?" decision (pure, defaults-only) from the OS call. Only worth it if this behavior is touched again.
- **Verification:** N/A unless adopted.

### [BLD-12] `extractCorrections` lives in `LastTranscriptTests` and lacks adversarial cases
- **Severity:** Low
- **Tier:** T1
- **Location:** `Tests/JVoiceTests/LastTranscriptTests.swift:26-47`; `Sources/JVoice/Services/TextProcessor.swift`
- **What:** `extractCorrections` (the source of auto-added custom words from a user's manual fix — a feature that mutates persisted state) is tested only for happy paths (case change, merge, multi-change, no-op). No test for: deletions (corrected shorter than original), reordering, or pathological inputs (whole sentence rewritten) that could flood the vocabulary with garbage words.
- **Impact:** Low–Medium: `fixLastTranscript` adds whatever `extractCorrections` returns to the user's custom-word list (which then biases all future decoding). A bad extraction injects junk vocab. `VoiceCoordinator.fixLastTranscript` trims/dedupes but doesn't bound count or filter non-words.
- **Fix:** Add adversarial `extractCorrections` cases (full rewrite → bounded/empty result; deletion → empty) and consider a length/sanity guard in `fixLastTranscript` before `addCustomWord`. Tests are T1.
- **Verification:** New cases assert no spurious words on full-rewrite input.

### [BLD-13] Several tests assert weak existential conditions
- **Severity:** Low
- **Tier:** T1
- **Location:** `PasteManagerTests.swift:42-72`, `RecordingManagerDelegateTests.swift:43-66`, `VoiceCoordinatorHotkeyRaceTests.swift`
- **What:** A handful of tests assert disjunctions (`outcome == .targetRejected || outcome == .accessibilityDenied`) or "either nil or different" because the AX-trusted state is unknowable in CI. They're defensible given the environment, but they pass regardless of which branch ran, so they verify less than they appear to.
- **Impact:** Low. These are honest about their limits (good comments), but the only fix is to make the AX gate injectable (see BLD-07), which would turn the disjunctions into exact assertions.
- **Fix:** Same seam as BLD-07 (`accessibilityTrusted` closure). Then `PasteManagerTests` can assert `.ok` exactly and `RecordingManager`'s entry-clear contract can be pinned.
- **Verification:** Exact-outcome assertions once the seam exists.

### [BLD-14] No test asserting the bench/CLI argument parser rejects malformed input
- **Severity:** Low
- **Tier:** T1
- **Location:** `Sources/JVoice/Services/BenchRunner.swift:27-71` (no test)
- **What:** `BenchRunner` arg parsing (model/lang/vocab/--no-prompt, missing-file, unknown-model exit codes) is dev-only but is pure, deterministic, and currently untested. Not user-facing, so Low.
- **Impact:** Minimal — it's a dev tool. Listed for completeness of the coverage map.
- **Fix:** Skip unless the bench surface grows; the exit-code contract could be pinned cheaply if desired.
- **Verification:** N/A.

---

## Script findings

### [BLD-15] `run-logic-tests.sh` / `verify-streaming.sh` duplicate test assertions by hand with no drift guard
- **Severity:** Medium
- **Tier:** T1
- **Location:** `scripts/run-logic-tests.sh:21-201`, `scripts/verify-streaming.sh:18-149`
- **What:** Both scripts inline a `main.swift` that re-states a subset of the canonical swift-testing assertions. The headers acknowledge the manual-sync requirement, but there's no mechanism preventing drift (the assertions could diverge from the suite and no one would know until a behavior change surprises someone).
- **Evidence:** `run-logic-tests.sh:10-13` and `verify-streaming.sh:11-12` both say "keep both in sync; the suite is the authority." This is a process control, not a technical one.
- **Impact:** Medium. The whole point of these scripts is local trust on a CLT-only machine. If they drift, that trust is misplaced. Wiring them into CI (BLD-02) plus the test-count floor mitigates the worst case but doesn't detect *assertion* drift between the script and the suite.
- **Fix:** Lowest-effort: run them in CI (BLD-02) so at least they keep compiling/passing against current sources. Higher-effort (probably not worth it): generate the script's assertions from a shared source. Recommend BLD-02 only.
- **Verification:** Both compile + pass today; CI keeps them honest going forward.

### [BLD-16] `setup-signing.sh` hard-depends on a Homebrew OpenSSL 3 with `-legacy`; no fallback, opaque failure for fresh machines
- **Severity:** Medium
- **Tier:** T1
- **Location:** `scripts/setup-signing.sh:30-43`
- **What:** The script needs an OpenSSL 3.x binary with the `-legacy` PKCS12 flag, searched only under three Homebrew paths. macOS ships LibreSSL (no `-legacy`); a machine without `brew install openssl@3` gets a hard error. It also uses a fixed PKCS12 password (`jvoice`) and pipes the cert creation through `2>/dev/null`, hiding any OpenSSL diagnostic.
- **Evidence:** Lines 33-43 loop over `/opt/homebrew/...` and `/usr/local/...` only; line 39-43 errors out if none found. Password `pass:jvoice` is hard-coded (fine for a local self-signed dev cert, but worth a comment that it's intentionally non-secret).
- **Impact:** Medium for reproducibility: a contributor (or David on a fresh Mac) following the documented `setup-signing.sh` → `install.sh` flow hits a wall unless OpenSSL 3 is brewed. The error message is good (tells you to `brew install openssl@3`), so it's not silent — hence Medium not High.
- **Fix:** Either (a) document the `brew install openssl@3` prerequisite in the script header / install docs, or (b) generate the identity with `security` + a `.p12` produced via Swift/`security` APIs that don't need legacy OpenSSL. (a) is the simple, surgical choice. Drop the `2>/dev/null` on `req` so failures are diagnosable.
- **Verification:** Run on a machine without brew OpenSSL → clear, actionable error (already true); document it.

### [BLD-17] `install.sh` uses deprecated `codesign --deep` and signs without entitlements/hardened runtime
- **Severity:** Medium
- **Tier:** T2
- **Location:** `scripts/install.sh:74-78`
- **What:** Signing uses `codesign --force --deep --sign … --identifier com.jvoice.app`. `--deep` is deprecated by Apple (and unreliable for nested code/bundles); there are no entitlements and no `--options runtime` (hardened runtime). For the dogfood/self-signed flow this works, but it's not the shape a public DMG should ship in, and `--deep` re-signing the SPM resource bundles (`KeyboardShortcuts` .lproj) can subtly mis-sign nested code.
- **Evidence:** Line 75 `codesign --force --deep --sign "$SIGN_IDENTITY" --identifier com.jvoice.app "$APP_PATH"`. No `.entitlements` file exists in the repo (confirmed via find). The repo plans ad-hoc-signed DMG distribution.
- **Impact:** Medium. For local dogfooding it's fine. For the eventual release DMG, `--deep` is the wrong tool (Apple's guidance: sign nested code inside-out explicitly); and no hardened runtime means future notarization (if ever pursued) would need rework. Microphone + Accessibility TCC work without entitlements for an unsigned/ad-hoc app, so no functional break today.
- **Fix:** When the release-DMG workflow is built (it isn't yet), sign nested bundles first then the outer app (`codesign` each `*.bundle`, then the app, without `--deep`). For the dogfood script, this is optional now. Defer to the release-flow task; flagged so it isn't forgotten.
- **Verification:** `codesign -vvv --deep-verify /Applications/JVoice.app` on a release build; revisit when the DMG workflow lands.

### [BLD-18] `install.sh` non-atomic in-place overwrite of a running app; relies on `pkill` + `sleep 0.5`
- **Severity:** Low
- **Tier:** T2
- **Location:** `scripts/install.sh:22-49`
- **What:** It `pkill -x JVoice`, sleeps 0.5 s, then `cp`s the binary and bundles directly over `/Applications/JVoice.app`. If the process is slow to die (or a launchd relaunch races, given launch-at-login), the copy can land on a live bundle. There's no `mktemp` staging + atomic `mv`.
- **Impact:** Low — it's a developer install script, and the failure mode is a re-run fixes it. But launch-at-login is auto-enabled on first run, so a relaunch race is plausible.
- **Fix:** Stage into a temp dir and `mv` over the destination, or `osascript`-quit and poll for exit instead of a fixed sleep. Optional.
- **Verification:** N/A (dev tooling).

### [BLD-19] `verify-transcription.py` swallows bench failures (no returncode check) and has no model-present guard
- **Severity:** Low
- **Tier:** T1
- **Location:** `scripts/verify-transcription.py:95-123`
- **What:** `run_bench` calls `subprocess.run(...).stdout` and never checks `returncode` or stderr. If the bench binary errors (missing model, crash, WhisperKit load failure), `stdout` is empty, every retention score is 0, and the harness reports a flood of FAILs with empty `hyp:` — not "the model isn't downloaded." There's also no upfront check that `.build/release/JVoice` exists.
- **Evidence:** Line 105 `out = subprocess.run(cmd, capture_output=True, text=True).stdout` — `.stderr` and `.returncode` discarded. `BIN` existence never asserted.
- **Impact:** Low (dev harness), but it turns "model not downloaded / binary not built" into a confusing wall of fake transcription failures rather than a clear setup error.
- **Fix:** Assert `os.path.exists(BIN)` at startup; in `run_bench`, capture `returncode`/`stderr` and surface a clear "bench invocation failed" message instead of scoring empty output.
- **Verification:** Run without a built binary → clear error; with model missing → clear error.

---

## Robustness / failure-mode findings

### [BLD-20] `ensureAccessibilityOnceForLaunch` and `didInitialize` flags use `UserDefaults.standard`, not the `jvoice.app.*` suite — and the AX one-shot can wedge
- **Severity:** Medium
- **Tier:** T1 (the namespace fix) / T2 (the wedge behavior)
- **Location:** `Sources/JVoice/VoiceCoordinator.swift:201-216`; `LaunchAtLoginManager.swift:10`; `StatsStore.swift:11-17`
- **What:** Two correctness/namespace issues:
  1. **Namespace:** CLAUDE.md states the UserDefaults namespace is `jvoice.app.*`, and most keys follow it (`jvoice.app.settings.state`, `jvoice.app.stats.*`, `jvoice.app.launchAtLogin.didInitialize`, `jvoice.app.didPromptAXOnLaunch`). All of these live in `UserDefaults.standard`, which for `com.jvoice.app` is keyed by bundle ID — fine — *but* the bench/CLI mode and any non-bundled run (e.g. `swift run`) write to a different domain. Not a bug per se, just worth noting the prefix is a manual convention with no central definition.
  2. **AX one-shot wedge (the real issue):** `ensureAccessibilityOnceForLaunch` sets `didPromptAXOnLaunch = true` immediately after the *first* prompt and only resets it to `false` once the process is *trusted at launch*. If the user denies on first launch and never grants, the app never prompts again on subsequent launches (by design) — but it also never re-surfaces guidance, and the prompt is fire-and-forget (`_ = AXIsProcessTrustedWithOptions`). Combined with `LaunchAtLoginManager` auto-enabling at first run, a user who denies AX can end up with an app that launches at login, never prompts again, and silently fails to paste (PasteManager returns `.accessibilityDenied` → `surfaceAndOpenSettings` only at dictation time).
- **Evidence:** Lines 202-215: `key = "jvoice.app.didPromptAXOnLaunch"`, set `true` after one prompt, reset `false` only when `trusted`. The paste-time path (`finishTranscription` → `.accessibilityDenied` → `surfaceAndOpenSettings`) is the recovery, which is reasonable — so the wedge is "no proactive re-prompt," not "no recovery at all." Hence Medium.
- **Impact:** A first-run-deny user gets no second launch-time nudge; they discover the AX requirement only when their first dictation fails (which does open Settings). Acceptable, but the one-shot flag logic is subtle and untested.
- **Fix:** (T1) Add a `VoiceCoordinatorAXPromptTests`-style unit test around an *extracted* pure decision `shouldPromptAX(trusted:hasPrompted:) -> Bool` so the one-shot/reset logic is pinned. (T2) Consider re-prompting after a paste-time `.accessibilityDenied` clears the one-shot flag, so a later launch re-nudges. Low-risk, but verify in the running app.
- **Verification:** Unit test the extracted predicate; manually verify the deny→relaunch→dictate flow in the app.

### [BLD-21] Disk-full / write-failure during recording is not surfaced distinctly
- **Severity:** Medium
- **Tier:** T2
- **Location:** `Sources/JVoice/Services/RecordingManager.swift:193-217`; `VoiceCoordinator.finishTranscription:447-457`
- **What:** A disk-full condition mid-recording manifests as either an `audioRecorderEncodeErrorDidOccur` (→ `.encodeFailure`, partial WAV deleted) or, more likely, a recording that stops short / produces a too-small file caught by `isUsableRecording`. There's no explicit free-space check before recording and no disk-specific message; the user sees "Recorder failed: …" or "Recording too short."
- **Evidence:** No `availableCapacity`/free-space query anywhere (grep confirmed zero hits). Recordings are 16 kHz/16-bit mono ≈ 32 KB/s, so disk-full is rare but possible on a near-full disk during a long dictation. The encode-error path does correctly delete the partial WAV (good — no orphaned audio).
- **Impact:** Medium-Low. The failure *is* handled (no crash, no orphan, an error HUD shows), just not with a disk-specific message. Given the tiny data rate, real-world likelihood is low.
- **Fix:** Optional. If desired, map `NSFileWriteOutOfSpaceError` (when present in the encode error) to a "Disk is full" message. Not worth a proactive free-space precheck given the data rate.
- **Verification:** Hard to test without filling a disk; T2.

### [BLD-22] No second-instance / duplicate-launch guard
- **Severity:** Medium
- **Tier:** T2
- **Location:** `Sources/JVoice/AppDelegate.swift`; `JVoiceApp.swift` (absent)
- **What:** Nothing prevents a second JVoice instance. Two instances → two menu-bar items, two global ⌥Space handlers (KeyboardShortcuts), two orphan-sweep passes, and two recorders fighting over the default-input redirect. The orphan-sweep on launch (`sweepOrphanedRecordings`) deletes *all* `jvoice-*.wav` in temp — if instance B launches while instance A is mid-recording, B's sweep deletes A's live WAV.
- **Evidence:** No `NSRunningApplication.runningApplications(withBundleIdentifier:)` check at launch (grep confirmed). `RecordingManager.sweepOrphanedRecordings` (lines 239-248) unconditionally removes every `jvoice-*.wav`.
- **Impact:** Medium. Launch-at-login + a manual open, or a fast double-open from Finder, can produce two instances. The sweep-deletes-live-WAV interaction is the sharpest edge (data loss for an in-flight recording in the other instance), though the window is narrow.
- **Fix:** At `applicationWillFinishLaunching`, if another instance with the same bundle ID is already running, surface it and terminate self (standard menu-bar-app pattern). This also makes the global sweep safe.
- **Verification:** Launch twice; second should no-op/terminate. T2 (needs the running app).

### [BLD-23] First-ever run with no model downloaded: long silent prepare, surfaced only at first dictation
- **Severity:** Low
- **Tier:** T2
- **Location:** `VoiceCoordinator.start:179-181` (`prewarm`); `finishTranscription:462-468` (`.preparingModel`)
- **What:** On first launch the model isn't downloaded. `start()` fires a background `prewarm()` (fire-and-forget, errors ignored). If the user dictates before the download finishes (or it failed — e.g. offline), `finishTranscription` shows `.preparingModel` then `prewarmAndWait()`. A *download failure* (offline) returns from `prewarmAndWait` without a loaded model, then `transcribe` throws `modelLoadFailed` → error HUD. That's correct, but the first-run download (hundreds of MB for Large) has no progress indication beyond "Preparing model," and an offline first-run gives a terse error.
- **Evidence:** `prewarm()` is `_ = try? await loadWhisperKit()` (errors swallowed); `WhisperModelLocator` correctly refuses *incomplete* downloads (well-tested), so a partial download falls back to `download: true` and re-fetches — good. But there's no surfaced download progress, and offline first-run is a generic `modelLoadFailed` message.
- **Impact:** Low — handled (no crash, partial-download self-heals via the locator, errors surface), just not a polished first-run. The Large model's multi-minute ANE compile is documented and shows `.preparingModel`.
- **Fix:** Optional UX: a one-time "Downloading speech model…" HUD on first run, and a clearer offline message. Not a correctness issue.
- **Verification:** T2 (needs app + network toggling).

### [BLD-24] No-input-device case relies on `AVAudioRecorder.record()` returning false; not unit-covered
- **Severity:** Low
- **Tier:** T2
- **Location:** `RecordingManager.startRecording:99-103`; `AudioInputRouter`
- **What:** With zero usable input devices, `recorder.record()` returns false → `.engineSetupFailed("audio device is unavailable")` → clean error HUD. `AudioInputRouter.redirectTarget` correctly returns nil when every input is Bluetooth (tested). The all-Bluetooth case (recording proceeds on the BT mic, breaking A2DP, because no non-BT fallback exists) is the documented accepted limitation.
- **Impact:** Low — handled gracefully (error HUD, no crash). The pure redirect policy is well-tested; the no-device hardware path is inherently T2.
- **Fix:** None needed. Noted for completeness.
- **Verification:** T2 (hardware).

### [BLD-25] `StreamingTranscriptionSession` "finish() then late poll consume" duplication guard rests on actor serialization — covered, but worth a regression note
- **Severity:** Low
- **Tier:** T1
- **Location:** `Sources/JVoice/Services/StreamingTranscriptionSession.swift:55-85, 137-181`; tested in `StreamingTranscriptionSessionTests.swift`
- **What:** The data-loss guarantees (empty non-silent chunk → fail → whole-file fallback; silent region dropped without failing; finish idempotent; vanished file fails safely; transcriber error → fallback) are *thoroughly* and meaningfully tested — both in the swift-testing suite and the executable `verify-streaming.sh`. This is a model example of the right testing depth. No gap; flagged positively, with one note: the tests use timing (`Task.sleep`) to let polls run, which is inherently slightly flaky under heavy CI load.
- **Impact:** None functional. Possible rare CI flakiness from the sleep-based synchronization.
- **Fix:** None required. If CI flakiness ever appears, consider an injectable poll-completion signal instead of fixed sleeps. Not worth pre-emptive change.
- **Verification:** `verify-streaming.sh` passes deterministically locally.

---

## Packaging findings (consolidated)

- **Package.swift / Package.resolved:** Correct. `Package.resolved` is tracked deliberately (documented in `.gitignore`), pinning WhisperKit `1.0.0` (rev `25c6299…`), KeyboardShortcuts `1.10.0` (exact, rev `70caa8d…`), and the transitive `swift-argument-parser 1.8.2`. WhisperKit is `from: "1.0.0"` (allows minor bumps) — given the documented WhisperKit-version traps (`withoutTimestamps` truncation, prompt-token empty-transcript), consider pinning WhisperKit `exact` too, or at least an upper bound, so a `swift package update` can't silently pull a version that re-breaks the hand-verified behaviors. **(Medium-value, T1, folds into BLD list as a recommendation.)** Platform `.macOS(.v14)` matches Info.plist `LSMinimumSystemVersion 14.0`. ✔
- **Info.plist:** Correct and complete: `LSUIElement true` (menu-bar accessory), `com.jvoice.app` bundle ID (correctly distinct from MacOSUtils' `com.jvoice.JVoice`), both usage strings present (`NSMicrophoneUsageDescription`, `NSAccessibilityUsageDescription`), version `1.0.0`/build `1`. ✔ Note: `NSAccessibilityUsageDescription` is not a real consumed key (Accessibility/AX trust isn't gated by a usage string the way Microphone is) — harmless, but it's decorative.
- **Entitlements:** None present. For an unsigned/ad-hoc menu-bar app using Microphone (TCC) + Accessibility (AX trust) + AppleEvents (target activation), no entitlements are *required*. Correct for the $0/unsigned model. If notarization is ever pursued, hardened runtime + a microphone entitlement would be needed — see BLD-17.
- **CI runner pinning:** `macos-15` + Xcode 16.4/16.2/16 fallback chain is sound and documented; the Xcode-select fallback is robust against runner image drift. ✔

### [BLD-26] WhisperKit dependency uses `from:` (open upper bound) despite documented version-sensitive behaviors
- **Severity:** Medium
- **Tier:** T1
- **Location:** `Package.swift:17-20`; `Package.resolved` (whisperkit 1.0.0)
- **What:** WhisperKit is `from: "1.0.0"` while the codebase encodes two behaviors verified against *exactly* 1.0.0 (the `withoutTimestamps` multi-window truncation workaround, and the `SuppressBlankFilter` prompt-compatibility shim with its prefill-index math). `Package.resolved` pins the tested revision, so fresh clones/CI are safe — but anyone running `swift package update` jumps to the latest 1.x, which could silently re-break both.
- **Evidence:** Memory + code comments (`TranscriptionManager.swift:155-167, 277-294`) repeatedly tie behavior to "WhisperKit 1.0.0." MEMORY note: "re-run `--bench --vocab`/`--stream` after any WhisperKit bump."
- **Impact:** Medium. The pin protects CI/clones; the risk is a deliberate-but-uninformed `update`. The mitigation (re-run bench after a bump) is a manual process control.
- **Fix:** Either pin WhisperKit `exact: "1.0.0"` (matching the KeyboardShortcuts treatment and the documented bench-after-bump rule), or add an upper bound (`"1.0.0"..<"1.1.0"`). Pairs naturally with the BLD-08 note that the deep WhisperKit behaviors are bench-verified only.
- **Verification:** `swift package resolve` still resolves to 1.0.0; a future `update` can't escape the bound.

---

## Test coverage map

| Sources file | Covered? | Gap |
|---|---|---|
| `VoiceCoordinator.swift` | Weak | Only a no-assert no-crash smoke test. Target-PID resolution, revert flow, fallback selection, AX one-shot all untested. **BLD-06, BLD-20** |
| `Services/RecordingManager.swift` | Partial | Delegate failures, config-change, file-size gate, stale-error clear covered. Start/stop happy path, BT redirect integration, disk-full untested. **BLD-21** |
| `Services/AudioInputRouter.swift` | Good (policy) | Pure `redirectTarget` fully tested (6 cases). HAL glue inherently untestable (T2). ✔ |
| `Services/PasteManager.swift` | Partial | Stage, empty-reject, failed-restore covered. Success-path restore + restore-coalescing untested (AX gate not injectable). **BLD-07, BLD-13** |
| `Services/TranscriptionManager.swift` | Partial | Engine-swap deferral, binary-audio reject, prefill-count math covered. Decode/biasing/duration-gate/prompt-cache `#if WhisperKit`-gated, bench-only. **BLD-08, BLD-26** |
| `Services/WhisperModelLocator` (in TranscriptionManager) | Good | 5 completeness cases (missing config/encoder/decoder weights, absent folder). ✔ |
| `Services/StreamingTranscriptionSession.swift` | Excellent | Suite + executable script; data-loss guarantees pinned. Exemplary. **BLD-25 (note only)** |
| `Services/RegurgitationRecovery.swift` | Good | 4 policy cases (suite + script). Engine wiring untested. **BLD-09** |
| `Services/RepetitionGuard.swift` | Excellent | Suite + a 120-case loop fuzz in the script; false-positive guards, generic loops, scrub flag, vocab cores. ✔ |
| `Services/ChunkPlanner.swift` | Excellent | Suite + script; wait/cut/silence/forced-cut/window-RMS. ✔ |
| `Services/WavTail.swift` | Excellent | Header parse, FLLR padding, stale size, foreign-format refusal, growing-file stream, vanished-file, float scaling. ✔ |
| `Services/TextProcessor.swift` | Good | Tone modes, fillers, dictionary, dollar/backslash injection, hallucination strip, artifacts. `extractCorrections` adversarial cases missing. **BLD-12** |
| `Services/PhoneticMatcher.swift` | Good | phoneticKey, levenshtein, correct (+ false-positive guards). ✔ |
| `Services/VocabularyPrompt.swift` | Good | empty→nil, comma-join, cap. ✔ |
| `Services/SettingsStore.swift` | Good | Corruption-backup, debounce-coalesce covered. ✔ |
| `Models/SettingsState.swift` | Good | Schema version, legacy decode, future-version refusal, unknown-enum fallbacks. ✔ |
| `Models/WhisperModelOption.swift` | Good | Turbo mapping, display name, Codable round-trip, legacy rawValue, unknown→tiny. ✔ |
| `Services/LastTranscriptStore.swift` | Good | Persist + default-empty. ✔ |
| `Services/StatsStore.swift` | **None** | WPM math, zero-guards, accumulation untested (trivially testable). **BLD-10** |
| `Services/LaunchAtLoginManager.swift` | **None** | First-run-once invariant untested (OS call not injectable). **BLD-11** |
| `Services/HotKeyManager.swift` | **None** | 0.15 s debounce / re-register guard untested (KeyboardShortcuts-gated). |
| `Services/BenchRunner.swift` | **None** | Arg parsing / exit codes untested (dev-only). **BLD-14** |
| `Services/PermissionError.swift` | Good | Message + deep-link + all-cases. ✔ |
| `Services/SystemActions.swift` | n/a | Trivial hook. ✔ |
| `Services/AppTimings.swift` / `SettingsURLs.swift` | n/a | Constants. ✔ |
| `UI/MenuBarController.swift` | Partial | Icon is-template + non-empty pixels covered; menu wiring untested (UI, T2). ✔ |
| `UI/*` (HUDView/Window, SettingsView/Window, components) | **None** | SwiftUI views untested (expected for this project size). |
| `AppDelegate.swift` / `JVoiceApp.swift` | **None** | Lifecycle wiring untested (T2). **BLD-22 (no second-instance guard)** |

---

## Recommended priority order

1. **BLD-02** (run both scripts in CI) and **BLD-01** (`swift build -c release` in CI) — highest value, pure T1 YAML, closes the two largest CI blind spots.
2. **BLD-26** (pin WhisperKit `exact`/upper-bound) — one-line, protects the hand-verified version-sensitive behaviors.
3. **BLD-10** (StatsStore tests) and **BLD-06** (extract + test VoiceCoordinator PID resolution and revert) — free meaningful coverage on untested, state-mutating logic.
4. **BLD-03** (make the test-count floor track authored count) — keeps the gate sharp.
5. **BLD-20 / BLD-22** (AX one-shot wedge, second-instance guard) — real robustness edges; T2, verify in the running app.
