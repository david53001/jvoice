import AVFoundation
import Combine
import Foundation

public protocol TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String
    /// Eagerly load the underlying model so the first transcription isn't a
    /// cold-start model load. Default is a no-op for engines needing no warm-up.
    func prewarm() async
    /// Update the user vocabulary used to bias decoding toward custom words.
    /// Default is a no-op for engines without vocabulary support.
    func updateVocabulary(_ words: [String]) async
    /// Whether the engine can transcribe immediately (model loaded). Engines
    /// without a load phase are always ready.
    func isReady() async -> Bool
    /// A session that transcribes chunks of a still-growing recording, or nil
    /// when the engine doesn't support sample input / hasn't loaded its model.
    /// Default is nil — streaming is strictly opt-in per engine.
    func makeStreamingSession() async -> StreamingTranscriptionSession?
}

extension TranscriptionEngine {
    public func prewarm() async {}
    public func updateVocabulary(_ words: [String]) async {}
    public func isReady() async -> Bool { true }
    public func makeStreamingSession() async -> StreamingTranscriptionSession? { nil }
}

public enum TranscriptionError: LocalizedError, Equatable {
    case audioFileMissing(URL)
    case unsupportedAudioFile(URL)
    case emptyTranscript
    case modelLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .audioFileMissing(let url):
            return "Audio file not found at \(url.path)."
        case .unsupportedAudioFile(let url):
            return "Unsupported audio file at \(url.path)."
        case .emptyTranscript:
            return "No transcript was produced."
        case .modelLoadFailed(let message):
            return message
        }
    }
}

public struct FileBackedTranscriptionEngine: TranscriptionEngine {
    public init() {}

    public func transcribe(audioURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileMissing(audioURL)
        }

        await Task.yield()

        let data = try Data(contentsOf: audioURL)
        guard let transcript = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.unsupportedAudioFile(audioURL)
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return trimmed
    }
}

/// Resolves the on-disk folder for an already-downloaded WhisperKit model, but
/// only when the download is *complete*.
///
/// WhisperKit, given a `modelFolder` with `download: false`, loads whatever is
/// there without validating it. An interrupted download leaves the `.mlmodelc`
/// directories present but missing their `weights/weight.bin`, so a naive
/// "does the folder exist?" check hands WhisperKit a weightless model that
/// never finishes loading — the "Large model hangs on Transcribing" bug.
/// Returning `nil` for an incomplete folder lets the engine fall back to
/// `download: true`, so the HuggingFace snapshot completes the missing files.
enum WhisperModelLocator {
    /// Every WhisperKit model ships MelSpectrogram/AudioEncoder/TextDecoder
    /// components whose weights live at `<component>.mlmodelc/weights/weight.bin`,
    /// plus a `config.json`. If any is absent the model is a half-finished
    /// download. (The tokenizer is deliberately NOT checked — WhisperKit
    /// stores it outside the model folder.)
    static let requiredWeightPaths = [
        "MelSpectrogram.mlmodelc/weights/weight.bin",
        "AudioEncoder.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc/weights/weight.bin",
        "config.json",
    ]

    /// The path of a *complete* local model folder named `folderName` under
    /// `documents`, or `nil` if it is absent or incompletely downloaded.
    static func completeModelFolder(named folderName: String, documentsDirectory documents: URL) -> String? {
        let fileManager = FileManager.default
        let folder = documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(folderName)")
        guard fileManager.fileExists(atPath: folder.path) else { return nil }
        for relativePath in requiredWeightPaths {
            if !fileManager.fileExists(atPath: folder.appendingPathComponent(relativePath).path) {
                return nil
            }
        }
        return folder.path
    }
}

#if canImport(WhisperKit)
import WhisperKit

public actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    private let model: WhisperModelOption
    private let language: TranscriptionLanguage
    private var vocabulary: [String]
    /// Master switch for conditioning the decoder with the vocabulary
    /// `promptTokens`. ON by default: the prompt is what gets hard custom words
    /// right at the source ("Li-Fraumeni" not "Leif or Meany", "VS Code" not
    /// "Versus Code") — accuracy the post-passes can't recover. Its failure mode
    /// (prompt regurgitation in low-confidence regions) is contained by a clean
    /// re-decode WITHOUT the prompt whenever a decode comes back looping/empty
    /// (see `decodeRecoveringFromRegurgitation`). Only the bench's `--no-prompt`
    /// turns this off, to A/B the biasing.
    private let useVocabularyPrompt: Bool
    /// Token IDs for the vocabulary prompt, computed once per vocabulary
    /// change (requires the loaded model's tokenizer). Empty array = computed,
    /// nothing to bias. nil = needs (re)computation.
    private var cachedPromptTokens: [Int]?
    private var whisperKit: WhisperKit?
    private var loadTask: Task<Void, Error>?

    public init(model: WhisperModelOption, language: TranscriptionLanguage = .english, vocabulary: [String] = [], useVocabularyPrompt: Bool = true) {
        self.model = model
        self.language = language
        self.vocabulary = vocabulary
        self.useVocabularyPrompt = useVocabularyPrompt
    }

    public func updateVocabulary(_ words: [String]) {
        guard words != vocabulary else { return }
        vocabulary = words
        cachedPromptTokens = nil
    }

    public func isReady() -> Bool {
        whisperKit != nil
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let kit = try await loadWhisperKit()
        // Single-window clips (≤25 s; Whisper's window is 30 s) never use
        // seek-advance, so timestamp decoding is pure overhead there —
        // skipping it removes the per-token TimestampRulesFilter logit pass
        // (measured ~10% faster on large-v3_turbo). Long clips KEEP
        // timestamps: WhisperKit 1.0.0 truncates multi-window transcripts
        // without them (verified empirically on 53 s audio — do not flip
        // this to unconditional `true`).
        let withoutTimestamps = Self.isSingleWindowClip(audioURL)
        let guarded = try await decodeRecoveringFromRegurgitation { usePrompt in
            try await self.decodeFile(audioURL, kit: kit, withoutTimestamps: withoutTimestamps, usePrompt: usePrompt)
        }
        if guarded.isEmpty {
            throw TranscriptionError.emptyTranscript
        }
        return guarded
    }

    /// Decode a chunk of raw 16 kHz mono samples cut by `ChunkPlanner`.
    /// Chunks are ≤ `maxChunkSeconds` (25 s) by construction — provably
    /// single-window, so the no-timestamps fast path is always safe here
    /// (the multi-window truncation trap can't apply to a single window).
    private func transcribeChunkSamples(_ samples: [Float]) async throws -> String {
        let kit = try await loadWhisperKit()
        // An all-loop chunk reduces to "" — the session treats that as a
        // failure and re-runs the lossless whole-file path (never a silent drop).
        return try await decodeRecoveringFromRegurgitation { usePrompt in
            try await self.decodeSamples(samples, kit: kit, usePrompt: usePrompt)
        }
    }

    /// Run `decode` with the vocabulary prompt and, if it regurgitated, re-decode
    /// without the prompt to recover the real speech. The clean re-decode only
    /// runs on the rare bad decode, so prompt-driven vocabulary accuracy and
    /// latency are kept in the common (clean) case. See `RegurgitationRecovery`.
    private func decodeRecoveringFromRegurgitation(_ decode: (_ usePrompt: Bool) async throws -> String) async throws -> String {
        try await RegurgitationRecovery.decode(
            useVocabularyPrompt: useVocabularyPrompt,
            vocabulary: vocabulary,
            decode: decode
        )
    }

    private func decodeFile(_ audioURL: URL, kit: WhisperKit, withoutTimestamps: Bool, usePrompt: Bool) async throws -> String {
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language.whisperCode
        // Language is fixed by the user — skip the language-detection pass.
        decodeOptions.detectLanguage = false
        // Fewer temperature-fallback retries on a hard window → lower tail latency.
        decodeOptions.temperatureFallbackCount = 2
        // VAD chunking parallelises long recordings across workers and skips
        // silence. No effect on short clips that fit in a single window.
        decodeOptions.chunkingStrategy = .vad
        decodeOptions.withoutTimestamps = withoutTimestamps
        applyVocabularyBiasing(to: &decodeOptions, kit: kit, usePrompt: usePrompt)
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove "[BLANK_AUDIO]"-style decoder sentinels that leak in on silence.
        return TextProcessor.stripDecoderArtifacts(text)
    }

    private func decodeSamples(_ samples: [Float], kit: WhisperKit, usePrompt: Bool) async throws -> String {
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language.whisperCode
        decodeOptions.detectLanguage = false
        decodeOptions.temperatureFallbackCount = 2
        decodeOptions.withoutTimestamps = true
        applyVocabularyBiasing(to: &decodeOptions, kit: kit, usePrompt: usePrompt)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return TextProcessor.stripDecoderArtifacts(text)
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

    /// Load (and CoreML-specialise) the model ahead of first use. Errors are
    /// ignored — a failed prewarm just means the next `transcribe` retries the
    /// load and surfaces the error.
    public func prewarm() async {
        _ = try? await loadWhisperKit()
    }

    /// Bias the decoder toward the user's custom words (initial_prompt) and
    /// keep the prompt safe (see installPromptCompatibilityFilter). The single
    /// shared implementation for the file path AND the streaming chunk path —
    /// the filter install/clear MUST stay symmetric between them, so don't
    /// inline this back into the call sites.
    private func applyVocabularyBiasing(to decodeOptions: inout DecodingOptions, kit: WhisperKit, usePrompt: Bool) {
        if usePrompt, let prompt = promptTokens(using: kit), !prompt.isEmpty {
            decodeOptions.promptTokens = prompt
            installPromptCompatibilityFilter(on: kit, promptTokenCount: prompt.count)
        } else {
            kit.textDecoder.logitsFilters = []
        }
    }

    /// Number of forced prefill tokens WhisperKit builds when a vocabulary
    /// prompt is present: [<|startofprev|>] + prompt + [SOT, language, task,
    /// timestamps]. The first *content* token is sampled at exactly this index.
    /// ASSUMES a multilingual model (all four shipped options are): an
    /// English-only ".en" variant prefills without language+task tokens, which
    /// would make this +3 — re-derive before ever adding such a model.
    static func promptedPrefillCount(promptTokenCount: Int) -> Int {
        promptTokenCount + 5
    }

    /// Make vocabulary prompts safe on models that predict <|endoftext|> as
    /// the FIRST content token when conditioned with <|startofprev|> context
    /// (observed on large-v3-v20240930: confident immediate EOT → empty
    /// transcript, no temperature fallback because the empty decode passes
    /// every quality gate). Reference Whisper forbids exactly this with its
    /// SuppressBlank filter at sample_begin; WhisperKit 1.0.0 ships that
    /// filter off-by-default AND wired to `prefilledIndex` (the kv-cache
    /// start) instead of the first-content index, so it can never fire for
    /// models without a context-prefill component. Installing our own
    /// correctly-indexed instance restores the reference behavior. Verified
    /// end-to-end via `--bench --vocab` (2026-06-07; see docs/HANDOFF.md).
    private func installPromptCompatibilityFilter(on kit: WhisperKit, promptTokenCount: Int) {
        guard let tokenizer = kit.tokenizer else { return }
        kit.textDecoder.logitsFilters = [
            SuppressBlankFilter(
                specialTokens: tokenizer.specialTokens,
                sampleBegin: Self.promptedPrefillCount(promptTokenCount: promptTokenCount)
            )
        ]
    }

    /// Encode (and cache) the vocabulary prompt with the loaded tokenizer.
    /// WhisperKit filters special tokens and trims length internally; the
    /// local cap just bounds the decode-cost increase.
    private func promptTokens(using kit: WhisperKit) -> [Int]? {
        if let cachedPromptTokens { return cachedPromptTokens }
        guard let text = VocabularyPrompt.text(for: vocabulary),
              let tokenizer = kit.tokenizer else {
            cachedPromptTokens = []
            return cachedPromptTokens
        }
        let raw = tokenizer.encode(text: text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        cachedPromptTokens = Array(raw.prefix(VocabularyPrompt.maxPromptTokens))
        return cachedPromptTokens
    }

    /// True when the clip provably fits in a single Whisper window (30 s),
    /// with margin. Unknown duration → false (the safe, timestamped path).
    private static func isSingleWindowClip(_ url: URL, threshold: TimeInterval = 25.0) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return false }
        return Double(file.length) / rate <= threshold
    }

    private func loadWhisperKit() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        // Dedupe concurrent loads (e.g. a background prewarm racing the first
        // transcription) so the model is only loaded once. The task returns
        // Void and the model is stored on the actor inside `performLoad`, so the
        // non-Sendable WhisperKit instance never crosses an isolation boundary.
        let task: Task<Void, Error>
        if let loadTask {
            task = loadTask
        } else {
            task = Task { try await self.performLoad() }
            loadTask = task
        }

        do {
            try await task.value
        } catch {
            // Drop the failed task so a later call can retry the load.
            loadTask = nil
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }

        guard let whisperKit else {
            throw TranscriptionError.modelLoadFailed("Model unavailable after load.")
        }
        return whisperKit
    }

    private func performLoad() async throws {
        let localFolder = Self.localModelFolderPath(for: model)
        whisperKit = try await WhisperKit(
            model: model.whisperKitModelName,
            modelFolder: localFolder,
            load: true,
            download: localFolder == nil
        )
    }

    private static func localModelFolderPath(for model: WhisperModelOption) -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return WhisperModelLocator.completeModelFolder(named: model.whisperKitFolderName, documentsDirectory: docs)
    }
}
#endif

@MainActor
public final class TranscriptionManager: ObservableObject {
    @Published public private(set) var isTranscribing = false

    public var engine: any TranscriptionEngine
    private var pendingEngine: (any TranscriptionEngine)?
    /// The most recent vocabulary pushed via `updateVocabulary`, re-applied
    /// when a pending engine is promoted so a vocabulary edit that raced an
    /// engine swap is never lost.
    private var lastPushedVocabulary: [String]?

    public init(engine: (any TranscriptionEngine)? = nil, model: WhisperModelOption = .base) {
        if let engine {
            self.engine = engine
        } else {
            self.engine = Self.makeDefaultEngine(model: model)
        }
    }

    public func transcribe(audioURL: URL) async throws -> String {
        isTranscribing = true
        defer {
            isTranscribing = false
            if let pending = pendingEngine {
                self.engine = pending
                pendingEngine = nil
                // The promoted engine was built with the vocabulary current at
                // swap-request time; re-apply the latest words so an edit that
                // landed during the transcription isn't lost.
                if let words = lastPushedVocabulary {
                    Task { await pending.updateVocabulary(words) }
                }
                prewarm()
            }
        }

        let transcript = try await engine.transcribe(audioURL: audioURL)
        guard !transcript.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }
        return transcript
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        try await transcribe(audioURL: audioURL)
    }

    public func updateEngine(_ engine: any TranscriptionEngine) {
        if isTranscribing {
            pendingEngine = engine
            return
        }
        self.engine = engine
        prewarm()
    }

    /// Push a vocabulary change to the active engine (and any engine queued
    /// behind an in-flight transcription) without reloading the model.
    public func updateVocabulary(_ words: [String]) {
        lastPushedVocabulary = words
        let active = engine
        Task { await active.updateVocabulary(words) }
        if let pending = pendingEngine {
            Task { await pending.updateVocabulary(words) }
        }
    }

    /// Whether the active engine's model is loaded and ready to transcribe.
    public func isEngineReady() async -> Bool {
        await engine.isReady()
    }

    /// Awaitable prewarm — used to show "Preparing model" feedback while the
    /// load completes (the fire-and-forget `prewarm()` can't be observed).
    public func prewarmAndWait() async {
        await engine.prewarm()
    }

    /// Warm the active engine's model in the background so the first
    /// transcription is instant. No-op for engines that need no warm-up.
    public func prewarm() {
        Task { await engine.prewarm() }
    }

    /// A streaming session bound to the active engine, or nil when the engine
    /// doesn't support streaming or hasn't loaded its model yet.
    public func makeStreamingSession() async -> StreamingTranscriptionSession? {
        await engine.makeStreamingSession()
    }

    private static func makeDefaultEngine(model: WhisperModelOption, language: TranscriptionLanguage = .english) -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperKitTranscriptionEngine(model: model, language: language)
        #else
        return FileBackedTranscriptionEngine()
        #endif
    }

    #if DEBUG
    public func setTranscribingForTesting(_ flag: Bool) { isTranscribing = flag }
    public var engineForTesting: any TranscriptionEngine { engine }
    public func applyPendingEngineForTesting() {
        if let pending = pendingEngine {
            engine = pending
            pendingEngine = nil
        }
    }
    #endif
}
