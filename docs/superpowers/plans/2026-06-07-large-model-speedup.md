# Large-Model Speedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut hotkey-release → text-pasted latency on the Large model: Phase 1 swaps "Large" to OpenAI's real large-v3-turbo (`large-v3-v20240930`); Phase 2 transcribes completed speech chunks *during* recording so only the tail remains on stop.

**Architecture:** Phase 1 is a rawValue swap in `WhisperModelOption` with a legacy-decode shim, gated by a `--bench` head-to-head. Phase 2 is a read-only overlay: an actor polls the WAV that AVAudioRecorder is still writing, cuts chunks at silence (pure `ChunkPlanner`), transcribes them via the existing WhisperKit engine, and `finish()` returns the combined transcript — any failure returns nil and the coordinator falls back to today's whole-file path. The capture pipeline is untouched.

**Tech Stack:** Swift 5.9 / SwiftPM, WhisperKit 1.0.0 (pinned), swift-testing (CI-executed; locally compile-only), `scripts/run-logic-tests.sh` (locally executed assertions for pure logic), hidden `JVoice --bench` CLI for real transcription measurement.

**Spec:** `docs/superpowers/specs/2026-06-07-large-model-speedup-design.md`

## ⚠️ Session rules (override the usual plan template)

- **NO `git commit`, `git push`, `gh`, remotes — ever.** Project rule: commits only when David asks. All "Commit" steps from the standard template are replaced by verification steps. Work stays in the working tree. **Never run destructive git commands** (`checkout --`, `reset`, `clean`, `stash`) — the tree holds unrelated uncommitted work.
- `swift test` COMPILES but EXECUTES 0 tests on this machine. Local execution truth = `./scripts/run-logic-tests.sh` and `.build/release/JVoice --bench`. swift-testing files must still be written/updated (CI runs them, asserts ≥90 cases).
- Long-running model downloads (~1.5 GB) and first-run ANE compiles (~2–3 min) are expected during bench tasks; do not abort them.

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/JVoice/Models/WhisperModelOption.swift` | modify | Phase 1: new rawValue + legacy decode shim |
| `Tests/JVoiceTests/WhisperModelOptionTests.swift` | modify | Phase 1 expectations + legacy mapping test |
| `Sources/JVoice/Services/BenchRunner.swift` | modify | Phase 1: model parser; Phase 2: `--stream` mode |
| `Sources/JVoice/Services/WavTail.swift` | create | Growing-WAV header parse (pure) + tail reader (FileHandle) |
| `Sources/JVoice/Services/ChunkPlanner.swift` | create | Pure silence-cut chunk policy + RMS energy |
| `Sources/JVoice/Services/StreamingTranscriptionSession.swift` | create | Actor: poll → cut → transcribe → assemble; nil on any failure |
| `Sources/JVoice/Services/TranscriptionManager.swift` | modify | `makeStreamingSession()` on protocol (default nil) + WhisperKit impl |
| `Sources/JVoice/VoiceCoordinator.swift` | modify | Wire session start/finish/cancel around the existing flow |
| `Tests/JVoiceTests/WavTailTests.swift` | create | Header variants incl. FLLR + zero-size data |
| `Tests/JVoiceTests/ChunkPlannerTests.swift` | create | Synthetic-signal decisions |
| `Tests/JVoiceTests/StreamingTranscriptionSessionTests.swift` | create | Session lifecycle with fake transcriber + temp WAVs |
| `scripts/run-logic-tests.sh` | modify | Compile WavTail+ChunkPlanner; add executable assertions |

---

### Task 1: Bench clips + Phase 1 baseline (BEFORE any code change)

The old model must be benched with the *current* code — after the swap, `--model large` resolves to the new model.

**Files:** none (artifacts in `/tmp`, results recorded in `/tmp/jv-bench-notes.md`)

- [ ] **Step 1: Generate the three test clips**

```bash
say -o /tmp/jv-short.aiff "Quick reminder for tomorrow. Move the planning meeting to ten thirty, book the small conference room, and send the agenda to the team before lunch."
say -o /tmp/jv-long.aiff "Here are my notes from today's design review. The recording pipeline stays exactly as it is, because it has been stable for months and nobody wants to debug live audio again. The transcription side however is getting a significant upgrade. We are moving the large model to the pruned decoder variant, which keeps the same encoder but cuts the decoder from thirty two layers down to four. That should make every dictation noticeably faster without hurting accuracy. After that lands, the next step is streaming, where chunks of speech are transcribed in the background while the user is still talking, so that when they release the hotkey only the last few seconds remain to be processed. If both changes work as planned, long dictations like this one should feel almost instant instead of taking most of a minute to come back."
say -o /tmp/jv-vocab.aiff "I have been testing jay voice all week and jay voice keeps getting better."
for f in short long vocab; do afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/jv-$f.aiff /tmp/jv-$f.wav; done
afinfo /tmp/jv-long.wav | grep duration
```
Expected: three WAVs; long duration ≈ 45–60 s (must be > 30 s for multi-window). If < 35 s, extend the text and regenerate.

- [ ] **Step 2: Release-build current code**

```bash
cd /Users/davidghermansteinberg/Desktop/Home/Code/JVoice && swift build -c release
```
Expected: `Build complete!`

- [ ] **Step 3: Baseline the OLD model (run each clip twice, record the 2nd "transcribe:" time)**

```bash
.build/release/JVoice --bench /tmp/jv-short.wav --model large
.build/release/JVoice --bench /tmp/jv-short.wav --model large
.build/release/JVoice --bench /tmp/jv-long.wav --model large
.build/release/JVoice --bench /tmp/jv-long.wav --model large
.build/release/JVoice --bench /tmp/jv-vocab.wav --model large --vocab "JVoice"
```
Expected: HANDOFF-comparable numbers (short ~1.2 s warm, long ~40 s). First run may include model download/ANE compile — that's why the 2nd run is the number. Save all outputs (times + full `raw:` transcripts) to `/tmp/jv-bench-notes.md` under a heading `## old: large-v3_turbo`.

### Task 2: Phase 1 — model swap code

**Files:**
- Modify: `Tests/JVoiceTests/WhisperModelOptionTests.swift`
- Modify: `Sources/JVoice/Models/WhisperModelOption.swift`
- Modify: `Sources/JVoice/Services/BenchRunner.swift:39-50`

- [ ] **Step 1: Update tests first (they will fail to reflect reality until Step 3)**

In `Tests/JVoiceTests/WhisperModelOptionTests.swift`, replace the two tests that pin the rawValue, and add the legacy-decode test:

```swift
@Test func largeTurboMapsToOpenAITurboModel() {
    // OpenAI's actual large-v3-turbo (4-layer decoder), NOT WhisperKit's
    // "_turbo" compression of original large-v3 (32-layer decoder).
    #expect(WhisperModelOption.largeTurbo.whisperKitModelName == "large-v3-v20240930")
    #expect(WhisperModelOption.largeTurbo.whisperKitFolderName == "openai_whisper-large-v3-v20240930")
}

@Test func largeTurboRoundTripsThroughCodable() throws {
    let data = try JSONEncoder().encode(WhisperModelOption.largeTurbo)
    #expect(String(data: data, encoding: .utf8) == "\"large-v3-v20240930\"")
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: data)
    #expect(decoded == .largeTurbo)
}

@Test func legacyLargeTurboRawValueStillDecodesToLargeTurbo() throws {
    // Settings written before the 2026-06 model swap stored "large-v3_turbo";
    // they must keep resolving to the large option, not the .tiny fallback.
    let json = "\"large-v3_turbo\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: json)
    #expect(decoded == .largeTurbo)
}
```
(`largeTurboHasReadableDisplayName`, `largeTurboIsOfferedAsAModelOption`, `unknownModelStillFallsBackToTiny` stay unchanged.)

- [ ] **Step 2: Verify the suite still compiles (it should — tests assert future state but compile fine) and note `swift test` cannot execute it locally**

```bash
swift build --build-tests 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Apply the swap in `Sources/JVoice/Models/WhisperModelOption.swift`**

Change the case:
```swift
    case largeTurbo = "large-v3-v20240930"
```
Change the decoder extension to map the legacy rawValue:
```swift
extension WhisperModelOption {
    /// Fallback decoder: the pre-2026-06 "large-v3_turbo" rawValue maps to the
    /// renamed large case, and any other unknown rawValue (e.g. a model removed
    /// in a future build) decodes to `.tiny` instead of throwing, so a single
    /// stale enum case cannot torpedo the entire SettingsState decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "large-v3_turbo" {
            self = .largeTurbo
        } else {
            self = WhisperModelOption(rawValue: raw) ?? .tiny
        }
    }
}
```
`displayName`, `approximateRelativeSize`, `whisperKitModelName`, `whisperKitFolderName` computed properties are untouched (they derive from rawValue).

- [ ] **Step 4: Update the bench model parser in `Sources/JVoice/Services/BenchRunner.swift`**

```swift
            case "large", "large-v3_turbo", "largeTurbo", "large-v3-v20240930": model = .largeTurbo
```

- [ ] **Step 5: Sweep for stragglers**

```bash
grep -rn "large-v3_turbo" Sources/ Tests/
```
Expected: only (a) the legacy-decode shim + its test, (b) historical *comments* recording past measurements (e.g. `TranscriptionManager.swift` ~line 150 — leave those, they document history). Anything else referencing the old rawValue as *behavior* must be updated.

- [ ] **Step 6: Build + local logic tests + test-suite compile**

```bash
swift build && ./scripts/run-logic-tests.sh && swift build --build-tests 2>&1 | tail -3
```
Expected: `Build complete!`, `All logic tests passed.`, `Build complete!`

### Task 3: Phase 1 — bench gate (decides keep vs revert)

**Files:** none (results into `/tmp/jv-bench-notes.md`)

- [ ] **Step 1: Release-build and bench the NEW model (first run downloads ~1.5 GB + ANE-compiles; do not abort)**

```bash
swift build -c release
.build/release/JVoice --bench /tmp/jv-short.wav --model large
.build/release/JVoice --bench /tmp/jv-short.wav --model large
.build/release/JVoice --bench /tmp/jv-long.wav --model large
.build/release/JVoice --bench /tmp/jv-long.wav --model large
.build/release/JVoice --bench /tmp/jv-vocab.wav --model large --vocab "JVoice"
```
Record under `## new: large-v3-v20240930` in `/tmp/jv-bench-notes.md`.

- [ ] **Step 2: Apply the acceptance gate**

1. Warm `transcribe:` times materially faster on BOTH clips.
2. Transcripts word-for-word comparable to the old model's (punctuation/casing drift OK; missing/wrong words NOT OK).
3. Vocab clip's `processed:` contains "JVoice".
4. Long-clip transcript is complete (covers the final sentence of the spoken text — re-checks the multi-window truncation trap).

**If any check fails:** revert Task 2's three file edits (restore old rawValue, decoder, parser, tests — by re-applying the previous content, NOT via git), document the failure in `/tmp/jv-bench-notes.md`, and continue to Phase 2 (independent).

### Task 4: `WavTail` — growing-WAV parser + reader (TDD via logic script)

**Files:**
- Create: `Sources/JVoice/Services/WavTail.swift`
- Create: `Tests/JVoiceTests/WavTailTests.swift`
- Modify: `scripts/run-logic-tests.sh`

- [ ] **Step 1: Add failing assertions to `scripts/run-logic-tests.sh`**

In the heredoc `main.swift`, append before the `if failures > 0` block:

```swift
print("WavTail.parseHeader")
func wavHeader(format: UInt16 = 1, channels: UInt16 = 1, rate: UInt32 = 16_000, bits: UInt16 = 16, fllrBytes: Int = 0, dataSize: UInt32 = 0) -> [UInt8] {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16)
    b += le16(format) + le16(channels) + le32(rate)
    b += le32(rate * UInt32(channels) * UInt32(bits / 8)) + le16(channels * bits / 8) + le16(bits)
    if fllrBytes > 0 { b += Array("FLLR".utf8) + le32(UInt32(fllrBytes)) + [UInt8](repeating: 0, count: fllrBytes) }
    b += Array("data".utf8) + le32(dataSize)
    return b
}
let plain = wavHeader()
expectEqual(WavTail.parseHeader(plain)?.dataOffset ?? -1, 44, "plain 44-byte header")
let padded = wavHeader(fllrBytes: 4000)
expectEqual(WavTail.parseHeader(padded)?.dataOffset ?? -1, 44 + 8 + 4000, "FLLR-padded header")
expectEqual(WavTail.parseHeader(wavHeader(dataSize: 0))?.dataOffset ?? -1, 44, "stale zero data size tolerated")
expect(WavTail.parseHeader(wavHeader(rate: 44_100)) == nil, "wrong sample rate refused")
expect(WavTail.parseHeader(wavHeader(channels: 2)) == nil, "stereo refused")
expect(WavTail.parseHeader(wavHeader(format: 3)) == nil, "non-PCM refused")
expect(WavTail.parseHeader([UInt8]("RIFFxxxx".utf8)) == nil, "truncated header refused")
expectEqual(WavTail.floatSamples(([16_384, -16_384] as [Int16])[...]), [0.5, -0.5], "Int16→Float scaling")
```

And add the new source to the `xcrun swiftc` list (after `VocabularyPrompt.swift`):
```bash
    "$REPO_ROOT/Sources/JVoice/Services/WavTail.swift" \
```

- [ ] **Step 2: Run to verify failure (compile error: WavTail undefined)**

```bash
./scripts/run-logic-tests.sh
```
Expected: FAILS — `cannot find 'WavTail' in scope`.

- [ ] **Step 3: Implement `Sources/JVoice/Services/WavTail.swift`**

```swift
import Foundation

/// Parsed layout of a (possibly still-growing) RIFF/WAVE file.
public struct WavInfo: Equatable, Sendable {
    public let dataOffset: Int
    public let sampleRate: Int
    public let channels: Int
    public let bytesPerSample: Int
}

/// Header parsing for the WAV that AVAudioRecorder is *currently writing*.
///
/// Two realities of a mid-recording WAV that a naive parser trips over:
/// - CoreAudio pads the header with a `FLLR` filler chunk (the PCM payload can
///   start ~4 KB in), so the payload offset must come from chunk-walking,
///   never a hardcoded 44.
/// - The `RIFF` and `data` size fields are 0/stale until the recorder stops
///   and patches them, so the payload is treated as [dataOffset, EOF) and the
///   declared data size is deliberately ignored.
public enum WavTail {
    /// More than enough to cover Apple's filler padding before `data`.
    public static let headerProbeBytes = 16_384

    /// nil unless the header is parseable AND the format is exactly what
    /// `RecordingManager` writes (PCM, 16-bit, mono, 16 kHz) — anything else
    /// refuses to stream and the caller falls back to whole-file transcription.
    public static func parseHeader(_ bytes: [UInt8]) -> WavInfo? {
        guard bytes.count >= 12,
              fourCC(bytes, at: 0) == "RIFF",
              fourCC(bytes, at: 8) == "WAVE" else { return nil }
        var offset = 12
        var format: (rate: Int, channels: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = fourCC(bytes, at: offset)
            let size = Int(uint32LE(bytes, at: offset + 4))
            let payload = offset + 8
            if id == "fmt " {
                guard payload + 16 <= bytes.count else { return nil }
                let audioFormat = Int(uint16LE(bytes, at: payload))
                guard audioFormat == 1 else { return nil } // PCM only
                format = (
                    rate: Int(uint32LE(bytes, at: payload + 4)),
                    channels: Int(uint16LE(bytes, at: payload + 2)),
                    bits: Int(uint16LE(bytes, at: payload + 14))
                )
            } else if id == "data" {
                guard let format,
                      format.channels == 1, format.rate == 16_000, format.bits == 16 else {
                    return nil
                }
                return WavInfo(dataOffset: payload, sampleRate: format.rate, channels: 1, bytesPerSample: 2)
            }
            // Non-`data` chunks always carry a real size (only `data` grows),
            // and chunks are word-aligned.
            offset = payload + size + (size % 2)
        }
        return nil
    }

    public static func floatSamples(_ samples: ArraySlice<Int16>) -> [Float] {
        samples.map { Float($0) / 32_768.0 }
    }

    private static func fourCC(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
    }

    private static func uint16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

/// Incremental sample access to a growing WAV. Opens a fresh FileHandle per
/// read — the file is being appended to by another process-level writer and a
/// long-lived handle's EOF view is unreliable.
public struct WavTailReader: Sendable {
    public let url: URL
    public let info: WavInfo

    /// nil when the header can't be parsed yet (recorder may still be
    /// flushing its first buffer) — callers retry on the next poll.
    public static func open(url: URL) -> WavTailReader? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let probe = try? handle.read(upToCount: WavTail.headerProbeBytes),
              let info = WavTail.parseHeader([UInt8](probe)) else { return nil }
        return WavTailReader(url: url, info: info)
    }

    /// All samples from `sampleOffset` to the current EOF. `[]` = no new data
    /// yet; nil = file gone/unreadable (the session must abort and fall back).
    public func samples(from sampleOffset: Int) -> [Int16]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let byteOffset = UInt64(info.dataOffset + sampleOffset * info.bytesPerSample)
        guard (try? handle.seek(toOffset: byteOffset)) != nil else { return nil }
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data() // nil == already at EOF
        } catch {
            return nil
        }
        let usable = data.count - (data.count % 2) // a trailing odd byte is a mid-sample write
        guard usable > 0 else { return [] }
        var result = [Int16](repeating: 0, count: usable / 2)
        data.prefix(usable).withUnsafeBytes { raw in
            for i in 0..<result.count {
                result[i] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run the logic script — all WavTail assertions pass**

```bash
./scripts/run-logic-tests.sh
```
Expected: `All logic tests passed.` including the 8 new `WavTail` lines.

- [ ] **Step 5: Create `Tests/JVoiceTests/WavTailTests.swift` (canonical suite — mirrors + extends the script, CI-executed)**

```swift
#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

private func makeHeader(
    format: UInt16 = 1, channels: UInt16 = 1, rate: UInt32 = 16_000,
    bits: UInt16 = 16, fllrBytes: Int = 0, dataSize: UInt32 = 0
) -> [UInt8] {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16)
    b += le16(format) + le16(channels) + le32(rate)
    b += le32(rate * UInt32(channels) * UInt32(bits / 8)) + le16(channels * bits / 8) + le16(bits)
    if fllrBytes > 0 { b += Array("FLLR".utf8) + le32(UInt32(fllrBytes)) + [UInt8](repeating: 0, count: fllrBytes) }
    b += Array("data".utf8) + le32(dataSize)
    return b
}

@Test func parsesPlainHeader() {
    let info = WavTail.parseHeader(makeHeader())
    #expect(info?.dataOffset == 44)
    #expect(info?.sampleRate == 16_000)
}

@Test func parsesAppleFillerPaddedHeader() {
    // CoreAudio pads headers with a FLLR chunk; payload starts ~4 KB in.
    #expect(WavTail.parseHeader(makeHeader(fllrBytes: 4000))?.dataOffset == 44 + 8 + 4000)
}

@Test func toleratesStaleZeroDataSize() {
    // AVAudioRecorder patches RIFF/data sizes only on stop.
    #expect(WavTail.parseHeader(makeHeader(dataSize: 0))?.dataOffset == 44)
}

@Test func refusesForeignFormats() {
    #expect(WavTail.parseHeader(makeHeader(rate: 44_100)) == nil)
    #expect(WavTail.parseHeader(makeHeader(channels: 2)) == nil)
    #expect(WavTail.parseHeader(makeHeader(format: 3)) == nil)
    #expect(WavTail.parseHeader([UInt8]("RIFFxxxx".utf8)) == nil)
    #expect(WavTail.parseHeader([]) == nil)
}

@Test func readerStreamsGrowingFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wavtail-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var bytes = makeHeader()
    let firstSamples: [Int16] = [100, -200, 300]
    for s in firstSamples { bytes += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)] }
    try Data(bytes).write(to: url)

    let reader = try #require(WavTailReader.open(url: url))
    #expect(reader.samples(from: 0) == firstSamples)
    #expect(reader.samples(from: 3) == [])

    // File grows (plus a trailing odd byte mid-sample) — reader picks up only complete samples.
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0x2A, 0x00, 0x99])) // sample 42 + half a sample
    try handle.close()
    #expect(reader.samples(from: 3) == [42])
}

@Test func readerReportsVanishedFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wavtail-\(UUID().uuidString).wav")
    try Data(makeHeader()).write(to: url)
    let reader = try #require(WavTailReader.open(url: url))
    try FileManager.default.removeItem(at: url)
    #expect(reader.samples(from: 0) == nil)
}

@Test func floatScalingIsFullScale16Bit() {
    let floats = WavTail.floatSamples(([16_384, -16_384, 0] as [Int16])[...])
    #expect(abs(floats[0] - 0.5) < 0.001)
    #expect(abs(floats[1] + 0.5) < 0.001)
    #expect(floats[2] == 0)
}
#endif
```

- [ ] **Step 6: Build + suite compile**

```bash
swift build && swift build --build-tests 2>&1 | tail -3
```
Expected: both `Build complete!`

### Task 5: `ChunkPlanner` — pure silence-cut policy (TDD via logic script)

**Files:**
- Create: `Sources/JVoice/Services/ChunkPlanner.swift`
- Create: `Tests/JVoiceTests/ChunkPlannerTests.swift`
- Modify: `scripts/run-logic-tests.sh`

- [ ] **Step 1: Add failing assertions to `scripts/run-logic-tests.sh`** (append after the WavTail block; also add `ChunkPlanner.swift` to the `swiftc` source list)

```swift
print("ChunkPlanner")
func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}
let cfg = ChunkPlanner.Config()
expectEqual(ChunkPlanner.plan(unconsumed: tone(seconds: 10, amplitude: 0.5), config: cfg), .wait, "10s: below min → wait")
expectEqual(ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.5), config: cfg), .wait, "16s continuous speech: no pause → wait")
let speechWithPause = tone(seconds: 17, amplitude: 0.5) + tone(seconds: 1, amplitude: 0.0) + tone(seconds: 2, amplitude: 0.5)
if case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: speechWithPause, config: cfg) {
    expect(at >= 17 * 16_000 && at <= 18 * 16_000, "cut lands inside the 17-18s pause (at=\(at))")
    expect(!silent, "speech chunk not marked silent")
} else {
    expect(false, "pause after min → cut")
}
if case let .cut(at, _) = ChunkPlanner.plan(unconsumed: tone(seconds: 26, amplitude: 0.5), config: cfg) {
    expect(at >= 15 * 16_000 && at <= 25 * 16_000, "26s no pause → forced cut within [min,max] (at=\(at))")
} else {
    expect(false, "26s continuous → forced cut")
}
if case let .cut(_, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.0), config: cfg) {
    expect(silent, "16s of silence → silent chunk (dropped, not transcribed)")
} else {
    expect(false, "16s silence still produces a cut")
}
expect(ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.0), config: cfg), "isSilent: zeros")
expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.5), config: cfg), "isSilent: speech-level tone")
```

- [ ] **Step 2: Run to verify failure**

```bash
./scripts/run-logic-tests.sh
```
Expected: FAILS — `cannot find 'ChunkPlanner' in scope`.

- [ ] **Step 3: Implement `Sources/JVoice/Services/ChunkPlanner.swift`**

```swift
import Foundation

/// Pure chunking policy for streaming transcription: decides where to cut the
/// next chunk out of not-yet-transcribed audio. Cuts only at silence (so words
/// are never split) until `maxChunkSeconds` forces one — the same compromise
/// WhisperKit's VAD chunker makes on the whole-file path today. All functions
/// are pure so they run in both the swift-testing suite and
/// scripts/run-logic-tests.sh.
public enum ChunkPlanner {
    public struct Config: Sendable {
        public var sampleRate: Int = 16_000
        /// Don't chunk dictations shorter than this — post model-swap they are
        /// already fast transcribed whole.
        public var minChunkSeconds: Double = 15
        /// Hard cap keeping every chunk provably single-window and on the
        /// proven ≤25 s `withoutTimestamps` fast path (see
        /// WhisperKitTranscriptionEngine.isSingleWindowClip).
        public var maxChunkSeconds: Double = 25
        public var silenceWindowSeconds: Double = 0.3
        /// Absolute RMS floor (full scale = 1.0) below which audio is silence
        /// regardless of the relative threshold: ~-46 dBFS, far below speech.
        public var silenceRMSFloor: Float = 0.005
        /// A window quieter than this fraction of the loudest window counts as
        /// a pause in speech (relative, mirrors WhisperKit's energy VAD).
        public var relativeSilenceFraction: Float = 0.1
        public init() {}
    }

    public enum Decision: Equatable, Sendable {
        case wait
        /// Cut `unconsumed[..<atSample]` as the next chunk. `isSilent` chunks
        /// must be dropped, not transcribed — Whisper hallucinates on silence.
        case cut(atSample: Int, isSilent: Bool)
    }

    public static func plan(unconsumed: [Int16], config: Config = .init()) -> Decision {
        let minSamples = Int(config.minChunkSeconds * Double(config.sampleRate))
        let maxSamples = Int(config.maxChunkSeconds * Double(config.sampleRate))
        let window = max(1, Int(config.silenceWindowSeconds * Double(config.sampleRate)))
        guard unconsumed.count >= minSamples else { return .wait }

        let searchEnd = min(unconsumed.count, maxSamples)
        let energies = windowRMS(unconsumed[..<searchEnd], window: window)
        let peak = energies.map(\.rms).max() ?? 0
        let threshold = max(config.silenceRMSFloor, peak * config.relativeSilenceFraction)

        // Candidate cut points: complete windows starting at/after the minimum
        // chunk length.
        let candidates = energies.filter { $0.start >= minSamples && $0.start + window <= searchEnd }
        let quietest = candidates.min { $0.rms < $1.rms }

        if let quietest, quietest.rms < threshold {
            return makeCut(unconsumed, at: quietest.start + window / 2, config: config)
        }
        // No pause found: keep waiting until the single-window cap forces a cut
        // at the least-bad spot.
        guard unconsumed.count >= maxSamples else { return .wait }
        return makeCut(unconsumed, at: quietest.map { $0.start + window / 2 } ?? maxSamples, config: config)
    }

    /// True when `samples` never rise above the absolute silence floor — used
    /// for the final tail and to drop all-silence chunks.
    public static func isSilent(_ samples: [Int16], config: Config = .init()) -> Bool {
        let window = max(1, Int(config.silenceWindowSeconds * Double(config.sampleRate)))
        let peak = windowRMS(samples[...], window: window).map(\.rms).max() ?? 0
        return peak < config.silenceRMSFloor
    }

    private static func makeCut(_ unconsumed: [Int16], at sample: Int, config: Config) -> Decision {
        .cut(atSample: sample, isSilent: isSilent(Array(unconsumed[..<sample]), config: config))
    }

    struct WindowEnergy: Equatable {
        let start: Int // relative to the slice's first element
        let rms: Float
    }

    /// Non-overlapping RMS windows; the last (partial) window is included.
    static func windowRMS(_ samples: ArraySlice<Int16>, window: Int) -> [WindowEnergy] {
        guard !samples.isEmpty, window > 0 else { return [] }
        var result: [WindowEnergy] = []
        let base = samples.startIndex
        var start = base
        while start < samples.endIndex {
            let end = min(start + window, samples.endIndex)
            var sum: Double = 0
            for i in start..<end {
                let v = Double(samples[i]) / 32_768.0
                sum += v * v
            }
            result.append(WindowEnergy(start: start - base, rms: Float((sum / Double(end - start)).squareRoot())))
            start += window
        }
        return result
    }
}
```

- [ ] **Step 4: Run the logic script — all ChunkPlanner assertions pass**

```bash
./scripts/run-logic-tests.sh
```
Expected: `All logic tests passed.`

- [ ] **Step 5: Create `Tests/JVoiceTests/ChunkPlannerTests.swift`** (canonical suite; same scenarios + boundary extras)

```swift
#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

private func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}

@Test func waitsBelowMinimumChunkLength() {
    #expect(ChunkPlanner.plan(unconsumed: tone(seconds: 10, amplitude: 0.5)) == .wait)
    #expect(ChunkPlanner.plan(unconsumed: []) == .wait)
}

@Test func waitsThroughContinuousSpeechUntilCap() {
    // 16 s of nonstop speech: no pause to cut at, cap not reached → wait.
    #expect(ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.5)) == .wait)
}

@Test func cutsInsideAPauseAfterMinimum() throws {
    let audio = tone(seconds: 17, amplitude: 0.5) + tone(seconds: 1, amplitude: 0) + tone(seconds: 2, amplitude: 0.5)
    guard case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: audio) else {
        Issue.record("expected a cut inside the pause")
        return
    }
    #expect(at >= 17 * 16_000 && at <= 18 * 16_000)
    #expect(!silent)
}

@Test func forcesCutAtSingleWindowCap() {
    // 26 s of nonstop speech: cap exceeded → forced cut, never mid-word ideal
    // but bounded to the proven single-window range.
    guard case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 26, amplitude: 0.5)) else {
        Issue.record("expected a forced cut past the cap")
        return
    }
    #expect(at >= 15 * 16_000 && at <= 25 * 16_000)
    #expect(!silent)
}

@Test func marksAllSilenceChunksAsSilent() {
    guard case let .cut(_, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0)) else {
        Issue.record("silence still produces a cut (which is then dropped)")
        return
    }
    #expect(silent)
}

@Test func silenceDetectionUsesAbsoluteFloor() {
    #expect(ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0)))
    #expect(ChunkPlanner.isSilent([]))
    #expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.5)))
    #expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.05))) // quiet speech is NOT silence
}

@Test func windowRMSCoversPartialFinalWindow() {
    let energies = ChunkPlanner.windowRMS(tone(seconds: 0.5, amplitude: 0.5)[...], window: 4_800)
    #expect(energies.count == 2) // 0.3 s window over 0.5 s → full + partial
    #expect(energies[1].start == 4_800)
}
#endif
```

- [ ] **Step 6: Build + suite compile**

```bash
swift build && swift build --build-tests 2>&1 | tail -3
```
Expected: both `Build complete!`

### Task 6: `StreamingTranscriptionSession` actor

**Files:**
- Create: `Sources/JVoice/Services/StreamingTranscriptionSession.swift`
- Create: `Tests/JVoiceTests/StreamingTranscriptionSessionTests.swift`

- [ ] **Step 1: Implement `Sources/JVoice/Services/StreamingTranscriptionSession.swift`**

```swift
import Foundation

/// Transcribes completed speech chunks in the background *while the user is
/// still recording*, by reading the growing WAV that `RecordingManager`'s
/// AVAudioRecorder writes. This is a read-only overlay on the proven pipeline:
/// any failure marks the session failed and `finish()` returns nil, telling
/// the caller to fall back to whole-file transcription — worst case equals
/// today's behavior, and audio is never lost (correctness is anchored at the
/// finalized file, which is read after the recorder stops).
public actor StreamingTranscriptionSession {
    public typealias SampleTranscriber = @Sendable ([Float]) async throws -> String

    private let transcribe: SampleTranscriber
    private let config: ChunkPlanner.Config
    private let pollNanoseconds: UInt64

    private var url: URL?
    private var reader: WavTailReader?
    private var consumedSamples = 0
    private var pieces: [String] = []
    private var pollTask: Task<Void, Never>?
    private var failed = false
    private var cancelled = false
    /// Polls tolerated before a never-parseable header is fatal (the recorder
    /// may still be flushing its first buffer right after start).
    private var openRetriesRemaining = 10

    public init(
        transcribe: @escaping SampleTranscriber,
        config: ChunkPlanner.Config = .init(),
        pollNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.transcribe = transcribe
        self.config = config
        self.pollNanoseconds = pollNanoseconds
    }

    public func start(url: URL) {
        guard pollTask == nil, !cancelled, !failed else { return }
        self.url = url
        pollTask = Task { await runPollLoop() }
    }

    /// Stop polling, transcribe whatever remains in the (now finalized) file,
    /// and return the combined raw transcript. nil ⇒ the caller MUST fall back
    /// to whole-file transcription (session failed, was cancelled, or never
    /// streamed anything — in which case the fallback is equally fast).
    public func finish() async -> String? {
        pollTask?.cancel()
        await pollTask?.value
        pollTask = nil
        guard !failed, !cancelled, let url else { return nil }
        guard consumedSamples > 0 || !pieces.isEmpty else { return nil }

        if reader == nil { reader = WavTailReader.open(url: url) }
        guard let reader, var tail = reader.samples(from: consumedSamples) else { return nil }

        // Drain any backlog the poll loop didn't get to (slow decodes), keeping
        // every transcribed piece a provable single window.
        while case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: tail, config: config) {
            if !silent {
                guard await appendPiece(WavTail.floatSamples(tail[..<at])) else { return nil }
            }
            tail = Array(tail[at...])
        }
        // After the drain the tail is < maxChunkSeconds by construction.
        if !tail.isEmpty, !ChunkPlanner.isSilent(tail, config: config) {
            guard await appendPiece(WavTail.floatSamples(tail[...])) else { return nil }
        }

        let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // All-silence audio: let the fallback produce today's exact
        // empty-transcript behavior rather than inventing a new path.
        return joined.isEmpty ? nil : joined
    }

    /// The user abandoned this recording (new hotkey press, quit): discard
    /// everything; `finish()` will return nil if it is ever called.
    public func cancel() {
        cancelled = true
        pollTask?.cancel()
        pollTask = nil
        pieces = []
    }

    private func appendPiece(_ samples: [Float]) async -> Bool {
        do {
            let text = try await transcribe(samples)
            if !text.isEmpty { pieces.append(text) }
            return true
        } catch {
            failed = true
            return false
        }
    }

    private func runPollLoop() async {
        while !Task.isCancelled, !failed, !cancelled {
            await pollOnce()
            do {
                try await Task.sleep(nanoseconds: pollNanoseconds)
            } catch {
                break // cancelled during sleep
            }
        }
    }

    private func pollOnce() async {
        guard let url else {
            failed = true
            return
        }
        if reader == nil {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed = true // recorder torn down — abort, fallback handles it
                return
            }
            guard let opened = WavTailReader.open(url: url) else {
                openRetriesRemaining -= 1
                if openRetriesRemaining <= 0 { failed = true }
                return
            }
            reader = opened
        }
        guard let reader else { return }
        guard let unconsumed = reader.samples(from: consumedSamples) else {
            failed = true // file vanished mid-recording (failure teardown)
            return
        }
        guard case let .cut(atSample, isSilent) = ChunkPlanner.plan(unconsumed: unconsumed, config: config) else {
            return
        }
        if isSilent {
            consumedSamples += atSample // dropped, never transcribed
            return
        }
        let chunk = WavTail.floatSamples(unconsumed[..<atSample])
        do {
            let text = try await transcribe(chunk)
            // Cancelled mid-decode: don't consume — finish()/the fallback
            // re-covers these samples, so nothing is lost or duplicated.
            guard !Task.isCancelled, !cancelled else { return }
            if !text.isEmpty { pieces.append(text) }
            consumedSamples += atSample
        } catch {
            failed = true
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Create `Tests/JVoiceTests/StreamingTranscriptionSessionTests.swift`** (CI-executed; locally compile-only)

```swift
#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

// 20 ms polls + tiny "chunks" (override config) keep these tests fast.
private func fastConfig() -> ChunkPlanner.Config {
    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 0.5
    cfg.maxChunkSeconds = 1.0
    return cfg
}

private func makeWav(seconds: Double, amplitude: Double) -> Data {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16)
    b += Array("data".utf8) + le32(0)
    let n = Int(seconds * 16_000)
    for i in 0..<n {
        let s = Int16(amplitude * 32_000 * sin(Double(i) * 2 * .pi * 220 / 16_000))
        b += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)]
    }
    return Data(b)
}

private func tempWavURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID().uuidString).wav")
}

@Test func transcribesChunksAndTailInOrder() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // 2.6 s of speech-level audio: with max=1.0 s chunks the session must
    // forcibly cut ~1 s pieces and finish() drains the rest.
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)

    let counter = TranscribeCounter()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await counter.next(sampleCount: samples.count) },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 200_000_000) // a few polls
    let result = await session.finish()

    let calls = await counter.calls
    #expect(result == (1...calls.count).map { "piece\($0)" }.joined(separator: " "))
    #expect(calls.count >= 2) // at least one streamed chunk + the tail
    // Every piece stayed within the single-window cap (1.0 s here).
    #expect(calls.allSatisfy { $0 <= 16_000 + 1_600 })
    // Nothing lost, nothing duplicated.
    #expect(calls.reduce(0, +) == Int(2.6 * 16_000))
}

@Test func neverStreamedReturnsNilForFallback() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 0.2, amplitude: 0.5).write(to: url) // below min chunk

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "never" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await session.finish() == nil)
}

@Test func vanishedFileFailsSessionSafely() async throws {
    let url = tempWavURL()
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "x" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 60_000_000)
    try FileManager.default.removeItem(at: url) // mid-recording teardown
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await session.finish() == nil)
}

@Test func cancelDiscardsEverything() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "x" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 100_000_000)
    await session.cancel()
    #expect(await session.finish() == nil)
}

@Test func transcriberErrorTriggersFallback() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    struct Boom: Error {}
    let session = StreamingTranscriptionSession(
        transcribe: { _ in throw Boom() },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(await session.finish() == nil)
}

private actor TranscribeCounter {
    private(set) var calls: [Int] = []
    func next(sampleCount: Int) -> String {
        calls.append(sampleCount)
        return "piece\(calls.count)"
    }
}
#endif
```

- [ ] **Step 4: Build + suite compile**

```bash
swift build && swift build --build-tests 2>&1 | tail -3
```
Expected: both `Build complete!`

### Task 7: Engine + manager integration

**Files:**
- Modify: `Sources/JVoice/Services/TranscriptionManager.swift`

- [ ] **Step 1: Add the protocol hook (default: no streaming)**

In the `TranscriptionEngine` protocol declaration, after `isReady()`:
```swift
    /// A session that transcribes chunks of a still-growing recording, or nil
    /// when the engine doesn't support sample input / hasn't loaded its model.
    /// Default is nil — streaming is strictly opt-in per engine.
    func makeStreamingSession() async -> StreamingTranscriptionSession?
```
In the `extension TranscriptionEngine` defaults block:
```swift
    public func makeStreamingSession() async -> StreamingTranscriptionSession? { nil }
```

- [ ] **Step 2: Implement sample transcription + session factory on `WhisperKitTranscriptionEngine`** (inside the `#if canImport(WhisperKit)` actor, after `transcribe(audioURL:)`)

```swift
    /// Decode a chunk of raw 16 kHz mono samples cut by `ChunkPlanner`.
    /// Chunks are ≤ `maxChunkSeconds` (25 s) by construction — provably
    /// single-window, so the no-timestamps fast path is always safe here
    /// (the multi-window truncation trap can't apply to a single window).
    private func transcribeChunkSamples(_ samples: [Float]) async throws -> String {
        let kit = try await loadWhisperKit()
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language.whisperCode
        decodeOptions.detectLanguage = false
        decodeOptions.temperatureFallbackCount = 2
        decodeOptions.withoutTimestamps = true
        if let prompt = promptTokens(using: kit), !prompt.isEmpty {
            decodeOptions.promptTokens = prompt
            // Same prompt-compatibility requirement as the file path: without a
            // correctly-indexed SuppressBlankFilter, large-v3-v20240930 emits a
            // confident immediate <|endoftext|> under <|startofprev|> prompts
            // and the chunk comes back empty. See installPromptCompatibilityFilter.
            installPromptCompatibilityFilter(on: kit, promptTokenCount: prompt.count)
        } else {
            kit.textDecoder.logitsFilters = []
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func makeStreamingSession() -> StreamingTranscriptionSession? {
        makeStreamingSession(pollNanoseconds: 1_000_000_000)
    }

    /// Parameterized variant so the bench harness can poll faster than the
    /// app's 1 s cadence when it grows the file at 10× real time.
    public func makeStreamingSession(pollNanoseconds: UInt64) -> StreamingTranscriptionSession? {
        // Never trigger a model load from the polling path — no loaded model,
        // no streaming (the whole-file fallback covers it).
        guard whisperKit != nil else { return nil }
        return StreamingTranscriptionSession(
            transcribe: { [weak self] samples in
                guard let self else { throw CancellationError() }
                return try await self.transcribeChunkSamples(samples)
            },
            pollNanoseconds: pollNanoseconds
        )
    }
```

- [ ] **Step 3: Expose it through `TranscriptionManager`** (after `prewarm()`)

```swift
    /// A streaming session bound to the active engine, or nil when the engine
    /// doesn't support streaming or hasn't loaded its model yet.
    public func makeStreamingSession() async -> StreamingTranscriptionSession? {
        await engine.makeStreamingSession()
    }
```

- [ ] **Step 4: Build + suite compile + logic script**

```bash
swift build && swift build --build-tests 2>&1 | tail -3 && ./scripts/run-logic-tests.sh
```
Expected: `Build complete!` ×2, `All logic tests passed.` (If existing mock engines in `Tests/JVoiceTests/TranscriptionManagerTests.swift` fail to compile against the new protocol member, the default extension covers them — they should NOT need edits; investigate before touching them.)

### Task 8: Coordinator wiring

**Files:**
- Modify: `Sources/JVoice/VoiceCoordinator.swift` (anchors: property block ~line 118, `quitApp` ~264, `startRecordingFlow` ~331, `stopRecordingAndTranscribe` ~367, `finishTranscription` ~401)

- [ ] **Step 1: Add the session property** (next to `currentTranscriptionTask`)

```swift
    private var streamingSession: StreamingTranscriptionSession?
```

- [ ] **Step 2: Start the session in `startRecordingFlow`** — replace the final three lines (`isRecording = true` / `recordingStartDate` / `updateHUD(.recording)`) with:

```swift
        isRecording = true
        recordingStartDate = Date()
        updateHUD(.recording)

        // Best-effort streaming overlay: transcribe completed chunks while the
        // user is still talking so only the tail remains on hotkey release.
        // nil when the engine has no loaded model — never trigger a load here.
        if let url = recordingManager.recordedURL {
            Task { [weak self] in
                guard let self else { return }
                let session = await self.transcriptionManager.makeStreamingSession()
                // (MainActor) recording may have already stopped during the
                // await — don't start a session nobody will finish.
                guard self.isRecording else { return }
                self.streamingSession = session
                if let session {
                    await session.start(url: url)
                }
            }
        }
```

- [ ] **Step 3: Hand the session over in `stopRecordingAndTranscribe`** — after `let audioURL = recordingManager.stopRecording()` add:

```swift
        let session = streamingSession
        streamingSession = nil
```

In the `guard let targetPID` failure block (before its `return`), add:
```swift
            if let session {
                Task { await session.cancel() }
            }
```

And change the task dispatch to pass the session through:
```swift
        currentTranscriptionTask = Task { [weak self] in
            await self?.finishTranscription(audioURL: audioURL, targetPID: targetPID, session: session)
        }
```

- [ ] **Step 4: Use it in `finishTranscription`** — change the signature:

```swift
    private func finishTranscription(audioURL: URL?, targetPID: pid_t?, session: StreamingTranscriptionSession? = nil) async {
```

Cancel the session in both early-return guards (`guard let audioURL` and `guard RecordingManager.isUsableRecording`), inserting before each `return` path's HUD update:
```swift
            if let session { await session.cancel() }
```

Replace the single transcribe line `let transcript = try await transcriptionManager.transcribe(audioURL: audioURL)` inside the `do` block with:
```swift
            let transcript: String
            if let session, let streamed = await session.finish() {
                // Chunks were decoded while the user was talking; finish() only
                // had to handle the tail. nil (failed/cancelled/never-streamed/
                // all-silence) falls back to the whole-file path below — worst
                // case is exactly today's behavior.
                transcript = streamed
            } else {
                transcript = try await transcriptionManager.transcribe(audioURL: audioURL)
            }
```

- [ ] **Step 5: Cancel on quit-mid-recording in `quitApp`** — inside the `if isRecording {` block, before stopping the recorder:

```swift
            if let session = streamingSession {
                streamingSession = nil
                Task { await session.cancel() }
            }
```

- [ ] **Step 6: Build + full compile + logic script**

```bash
swift build && swift build --build-tests 2>&1 | tail -3 && ./scripts/run-logic-tests.sh
```
Expected: `Build complete!` ×2, `All logic tests passed.`

### Task 9: `--bench --stream` mode + streaming E2E gate

**Files:**
- Modify: `Sources/JVoice/Services/BenchRunner.swift`

- [ ] **Step 1: Add the `--stream` branch** — in `run(arguments:)`, inside `#if canImport(WhisperKit)` right after `print("load+prewarm: …")`:

```swift
        if arguments.contains("--stream") {
            return await runStream(audioURL: audioURL, engine: engine)
        }
```

- [ ] **Step 2: Implement `runStream`** (same enum, below `run`)

```swift
    #if canImport(WhisperKit)
    /// Streaming E2E without a microphone: replays `audioURL` into a growing
    /// temp WAV at ~10× real time while a real StreamingTranscriptionSession
    /// consumes it, then compares against the whole-file transcript.
    private static func runStream(audioURL: URL, engine: WhisperKitTranscriptionEngine) async -> Int32 {
        guard let sourceBytes = try? Data(contentsOf: audioURL),
              let info = WavTail.parseHeader([UInt8](sourceBytes.prefix(WavTail.headerProbeBytes))) else {
            FileHandle.standardError.write(Data("not a 16 kHz mono 16-bit PCM wav: \(audioURL.path)\n".utf8))
            return 65
        }
        guard let session = await engine.makeStreamingSession(pollNanoseconds: 100_000_000) else {
            FileHandle.standardError.write(Data("engine has no loaded model\n".utf8))
            return 70
        }

        let growingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jv-stream-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: growingURL) }
        FileManager.default.createFile(atPath: growingURL.path, contents: sourceBytes.prefix(info.dataOffset))

        let payload = sourceBytes.dropFirst(info.dataOffset)
        let sliceBytes = info.sampleRate * info.bytesPerSample / 2 // 0.5 s of audio…
        let writer = Task {
            guard let handle = try? FileHandle(forWritingTo: growingURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            var offset = payload.startIndex
            while offset < payload.endIndex {
                let end = min(offset + sliceBytes, payload.endIndex)
                try? handle.write(contentsOf: payload[offset..<end])
                offset = end
                try? await Task.sleep(nanoseconds: 50_000_000) // …every 50 ms ⇒ 10× real time
            }
        }

        let wallStart = Date()
        await session.start(url: growingURL)
        await writer.value // "recording" ends here
        let stopStart = Date()
        let streamed = await session.finish()
        let tailTime = Date().timeIntervalSince(stopStart)
        let wallTime = Date().timeIntervalSince(wallStart)

        print(String(format: "stream wall: %.2fs   post-stop (finish): %.2fs", wallTime, tailTime))
        print("streamed:  \(streamed.map { "\"\($0)\"" } ?? "nil (session fell back)")")

        do {
            let wholeStart = Date()
            let whole = try await engine.transcribe(audioURL: audioURL)
            print(String(format: "wholefile: %.2fs", Date().timeIntervalSince(wholeStart)))
            print("wholefile: \"\(whole)\"")
        } catch {
            FileHandle.standardError.write(Data("whole-file comparison failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
        return 0
    }
    #endif
```

Also update the usage strings (both the `guard let benchIndex` error and the header comment) to read:
```
usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--vocab "Word1,Word2"] [--stream]
```

- [ ] **Step 3: Release-build and run the streaming gate on the long clip**

```bash
swift build -c release
.build/release/JVoice --bench /tmp/jv-long.wav --model large --stream
.build/release/JVoice --bench /tmp/jv-long.wav --model large --stream
```
Record both runs in `/tmp/jv-bench-notes.md` under `## streaming`.

**Acceptance gate:**
1. `streamed:` is non-nil and word-for-word comparable to `wholefile:` (boundary punctuation drift OK; missing/duplicated words NOT OK).
2. `post-stop (finish):` ≪ `wholefile:` time (the whole point).
3. Re-run the non-stream benches (`--bench /tmp/jv-short.wav --model large` and `--vocab` clip) — unchanged from Task 3 (no regression on the normal path).

**If the gate fails:** diagnose (chunk boundaries are the usual suspect — inspect which words sit at cut points); if unresolvable, remove Phase 2's coordinator wiring (Task 8) so the feature is dark, keep the new files + tests, document in `/tmp/jv-bench-notes.md`.

### Task 10: Full regression sweep

- [ ] **Step 1: Everything compiles, logic passes**

```bash
swift build && swift build --build-tests 2>&1 | tail -3 && ./scripts/run-logic-tests.sh
```
Expected: `Build complete!` ×2, `All logic tests passed.`

- [ ] **Step 2: CI test-count sanity** — the workflow asserts ≥90 executed swift-testing cases; we only ADDED tests (~20). Verify no test file lost its `@Test` functions:

```bash
grep -rc "@Test" Tests/JVoiceTests/ | sort -t: -k2 -n
```
Expected: every existing file's count unchanged or higher; new files (WavTail/ChunkPlanner/StreamingTranscriptionSession) present.

### Task 11: Code review + fixes

- [ ] **Step 1:** Run the `code-review` skill over the working-tree diff at high effort; prioritize: session/coordinator races, FileHandle leaks, the finish() drain loop, decode-option parity with the file path.
- [ ] **Step 2:** Apply fixes for real findings; re-run Task 10 Step 1 after any fix.

### Task 12: Documentation + handoff

- [ ] **Step 1:** Update `docs/HANDOFF.md`: bench table (old vs new model; streamed vs whole-file), what changed, the first-app-use expectation (new model downloads ~1.5 GB + ~2¼ min ANE compile under the app's bundle ID — the CLI bench cache does NOT carry over), and a dogfood checklist (real-mic long dictation with pauses; Bluetooth headset attached; cancel mid-recording; quit mid-recording).
- [ ] **Step 2:** Update auto-memory (model swap result, streaming architecture, bench numbers).
- [ ] **Step 3:** Final report to David: numbers, transcript comparisons, what's NOT verifiable without him (live mic), explicit note that nothing was committed.
