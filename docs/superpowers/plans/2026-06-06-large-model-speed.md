# Large-Model Transcription Speed Implementation Plan

> **SUPERSEDED BY IMPLEMENTATION (same day):** Task 3's unconditional
> `withoutTimestamps = true` was rejected during verification — WhisperKit
> 1.0.0 truncates multi-window (>30 s) transcripts without timestamps
> (measured: 53 s clip lost ~10 of 12 sentences). The shipped behavior is
> **duration-gated**: `withoutTimestamps = isSingleWindowClip(audioURL)`
> (≤25 s clips, provably single-window, get the ~10% speedup; longer clips
> keep timestamps for correctness). See `TranscriptionManager.swift`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce time-to-paste when the Large (large-v3 turbo) model is selected, with measured before/after evidence, without changing transcription quality for dictation.

**Architecture:** Two parts. (1) A hidden `--bench` CLI mode in the JVoice binary (entry-point shim around the SwiftUI app) that transcribes a WAV with timing — the only way to measure real WhisperKit performance on this machine, and also the end-to-end verifier for the vocabulary plan. (2) The actual optimization: `withoutTimestamps = true` in `DecodingOptions`.

**Tech Stack:** WhisperKit 1.0.0, SwiftPM.

**Session constraint:** NO git commits/pushes (David's explicit instruction).

**Why `withoutTimestamps` and not something else (verified against the WhisperKit 1.0.0 checkout):**
- With timestamps ON (current state), every decoded window emits timestamp tokens *and* runs `TimestampRulesFilter` on **every token step** — per-step MLMultiArray logit masking that is pure overhead for dictation (we never use the timestamps; `VoiceCoordinator` pastes plain text).
- Compute units are already optimal by default: `ModelComputeOptions` defaults to `.cpuAndNeuralEngine` for both encoder and decoder on Apple Silicon (`Models.swift:100-115`). Nothing to change.
- `temperatureFallbackCount` is already lowered to 2 (engine code comment).
- The recorder already produces 16 kHz/16-bit/mono WAV (`RecordingManager.recordingSettings`) — zero resample cost.
- Model cold-load is already mitigated: `prewarm()` on app start and on engine swap.
- **Safety of removing timestamps:** seek-advance for >30 s audio normally uses predicted timestamps. `chunkingStrategy = .vad` (already enabled) splits long audio at silence into ≤30 s chunks *before* decoding, so windows align with natural pauses and full-window seek advance is correct. This is the standard configuration for dictation apps built on WhisperKit.
- Considered and rejected: raising `concurrentWorkerCount` (only affects multi-chunk audio; ANE serializes anyway), streaming/eager decoding (large architectural change, hallucination-prone — out of scope), smaller `sampleLength` (risks truncating long dictations).

---

### Task 1: `--bench` CLI mode

**Files:**
- Create: `Sources/JVoice/Services/BenchRunner.swift`
- Modify: `Sources/JVoice/JVoiceApp.swift` (entry-point shim)

**Why an entry shim:** `@main` on the SwiftUI `App` struct gives no chance to intercept CLI arguments. A `@main` enum checks for `--bench` first and otherwise delegates to `JVoiceApp.main()` — zero behavior change for normal launches.

- [ ] **Step 1: Rewrite `Sources/JVoice/JVoiceApp.swift`:**

```swift
import AppKit
import SwiftUI

@main
enum JVoiceMain {
    static func main() {
        // Hidden dev/bench mode: `JVoice --bench <wav> [--model …] [--vocab …]`.
        // Lets transcription speed and vocabulary biasing be verified on this
        // machine, where XCTest cannot execute. Normal launches fall through
        // to the SwiftUI app unchanged.
        if BenchRunner.shouldRun(arguments: CommandLine.arguments) {
            BenchRunner.runAndExit(arguments: CommandLine.arguments)
        }
        JVoiceApp.main()
    }
}

struct JVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // No scenes. Windows are managed imperatively by AppDelegate / SettingsWindow.
        // SwiftUI requires at least one Scene; an empty Settings scene is acceptable as a placeholder.
        Settings { EmptyView() }
    }
}
```

(The only changes from the current file: `@main` moves from `JVoiceApp` to the new `JVoiceMain` enum.)

- [ ] **Step 2: Create `Sources/JVoice/Services/BenchRunner.swift`:**

```swift
import Foundation

/// Hidden CLI bench mode:
///
///     JVoice --bench <audio.wav> [--model tiny|base|small|large] [--vocab "Word1,Word2"]
///
/// Transcribes one file with timing and prints both the raw transcript and the
/// TextProcessor-processed output. Dev-only: this machine cannot execute
/// XCTest, so this is how transcription speed and vocabulary biasing are
/// actually verified end-to-end.
enum BenchRunner {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--bench")
    }

    static func runAndExit(arguments: [String]) -> Never {
        var exitCode: Int32 = 0
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            exitCode = await run(arguments: arguments)
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }

    private static func run(arguments: [String]) async -> Int32 {
        guard let benchIndex = arguments.firstIndex(of: "--bench"),
              arguments.count > benchIndex + 1 else {
            FileHandle.standardError.write(Data("usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--vocab \"Word1,Word2\"]\n".utf8))
            return 64
        }
        let audioURL = URL(fileURLWithPath: arguments[benchIndex + 1])
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            FileHandle.standardError.write(Data("no such file: \(audioURL.path)\n".utf8))
            return 66
        }

        var model: WhisperModelOption = .base
        if let modelIndex = arguments.firstIndex(of: "--model"), arguments.count > modelIndex + 1 {
            switch arguments[modelIndex + 1] {
            case "tiny": model = .tiny
            case "base": model = .base
            case "small": model = .small
            case "large", "large-v3_turbo", "largeTurbo": model = .largeTurbo
            default:
                FileHandle.standardError.write(Data("unknown model \(arguments[modelIndex + 1])\n".utf8))
                return 64
            }
        }

        var vocabulary: [String] = []
        if let vocabIndex = arguments.firstIndex(of: "--vocab"), arguments.count > vocabIndex + 1 {
            vocabulary = arguments[vocabIndex + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        print("model: \(model.rawValue)   audio: \(audioURL.lastPathComponent)   vocab: \(vocabulary.isEmpty ? "—" : vocabulary.joined(separator: ", "))")

        #if canImport(WhisperKit)
        let engine = WhisperKitTranscriptionEngine(model: model, vocabulary: vocabulary)

        let loadStart = Date()
        await engine.prewarm()
        print(String(format: "load+prewarm: %.2fs", Date().timeIntervalSince(loadStart)))

        do {
            let transcribeStart = Date()
            let raw = try await engine.transcribe(audioURL: audioURL)
            let elapsed = Date().timeIntervalSince(transcribeStart)
            print(String(format: "transcribe:   %.2fs", elapsed))
            print("raw:       \"\(raw)\"")
            let userDict = TextProcessor.buildUserDictionary(from: vocabulary)
            let processed = TextProcessor.process(raw, mode: .casual, extraDictionary: userDict, vocabulary: vocabulary)
            print("processed: \"\(processed)\"")
            return 0
        } catch {
            FileHandle.standardError.write(Data("transcription failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
        #else
        FileHandle.standardError.write(Data("WhisperKit unavailable in this build\n".utf8))
        return 70
        #endif
    }
}
```

(Note: the `vocabulary:` init parameter and `TextProcessor.process(... vocabulary:)` come from the vocabulary-v2 plan — implement that plan's Tasks 1-5 first, or temporarily drop those two arguments if executing this plan standalone.)

- [ ] **Step 3: Build**

Run: `swift build -c release`
Expected: `Build complete!`

- [ ] **Step 4: Smoke-test the bench mode**

```bash
say -o /tmp/jv-bench.aiff "hello world this is a quick test of dictation speed"
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/jv-bench.aiff /tmp/jv-bench.wav
.build/release/JVoice --bench /tmp/jv-bench.wav --model base
```

Expected: timings + a transcript resembling the spoken text. (First run of a never-downloaded model will download it — use `base`, which is small. Check `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` to see which models are already local before benching large.)

- [ ] **Step 5: Verify normal app launch is unaffected**

Run: `swift build 2>&1 | tail -1` then `timeout 5 .build/debug/JVoice --help 2>&1; echo "exit: $?"` — without `--bench` the binary must start the app (it will run until the timeout kills it; that *is* the pass signal, exit 124).

---

### Task 2: Baseline measurements (BEFORE the optimization)

- [ ] **Step 1: Create test clips of both lengths**

```bash
say -o /tmp/jv-short.aiff "hey can we move practice to thursday at five"
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/jv-short.aiff /tmp/jv-short.wav
say -o /tmp/jv-long.aiff "$(python3 -c "print('this is a longer dictation about the weekly schedule. ' * 12)")"
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/jv-long.aiff /tmp/jv-long.wav
```

- [ ] **Step 2: Bench the models that are locally downloaded** (run each 3×, note the 2nd/3rd runs — first run includes CoreML specialization):

```bash
for i in 1 2 3; do .build/release/JVoice --bench /tmp/jv-short.wav --model large; done
for i in 1 2 3; do .build/release/JVoice --bench /tmp/jv-long.wav --model large; done
```

Record the `transcribe:` numbers in a scratch table. If the large model isn't downloaded locally, bench `base` and `small` instead and extrapolate honestly in the final summary (decoder-step savings scale with model size).

---

### Task 3: The optimization

**Files:**
- Modify: `Sources/JVoice/Services/TranscriptionManager.swift` (engine `transcribe`, after the `chunkingStrategy` line)

- [ ] **Step 1: Add to `WhisperKitTranscriptionEngine.transcribe`:**

```swift
        // Dictation never uses timestamps — skipping them removes the
        // per-token TimestampRulesFilter logit pass and the timestamp tokens
        // themselves from decoding. Safe with VAD chunking: windows are
        // pre-split at silence, so full-window seek advance is correct.
        decodeOptions.withoutTimestamps = true
```

- [ ] **Step 2: Build**

Run: `swift build -c release`
Expected: `Build complete!`

---

### Task 4: After-measurements + regression check

- [ ] **Step 1: Re-run the exact Task 2 benches.** Expected: equal transcripts (modulo trivial punctuation) and lower `transcribe:` times — typically 10-25% on decode-bound runs. If transcripts DEGRADE (dropped words, hallucinations on the long clip), revert Step 3.1 and document why.

- [ ] **Step 2: Confirm the long clip is fully transcribed** (all 12 repetitions present in the long-clip transcript — guards the VAD/seek-advance assumption).

- [ ] **Step 3: Build tests still compile**

Run: `swift build --build-tests`
Expected: `Build complete!`

---

### Self-review checklist
- [x] Measurement before AND after, same clips, warm runs compared
- [x] Regression check for long-audio seek advance
- [x] Bench mode does not alter normal app startup (Task 1 Step 5)
- [x] No commits (session constraint)
