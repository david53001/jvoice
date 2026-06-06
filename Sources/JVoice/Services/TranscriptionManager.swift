import Foundation
import Combine

public protocol TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String
    /// Eagerly load the underlying model so the first transcription isn't a
    /// cold-start model load. Default is a no-op for engines needing no warm-up.
    func prewarm() async
}

extension TranscriptionEngine {
    public func prewarm() async {}
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
    /// Every WhisperKit model ships an AudioEncoder and a TextDecoder whose
    /// weights live at `<component>.mlmodelc/weights/weight.bin`. If either is
    /// absent the model is a half-finished download.
    static let requiredWeightPaths = [
        "AudioEncoder.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc/weights/weight.bin",
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
    private var whisperKit: WhisperKit?
    private var loadTask: Task<Void, Error>?

    public init(model: WhisperModelOption, language: TranscriptionLanguage = .english) {
        self.model = model
        self.language = language
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let kit = try await loadWhisperKit()
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language.whisperCode
        // Language is fixed by the user — skip the language-detection pass.
        decodeOptions.detectLanguage = false
        // Fewer temperature-fallback retries on a hard window → lower tail latency.
        decodeOptions.temperatureFallbackCount = 2
        // VAD chunking parallelises long recordings across workers and skips
        // silence. No effect on short clips that fit in a single window.
        decodeOptions.chunkingStrategy = .vad
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
        let transcript = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            throw TranscriptionError.emptyTranscript
        }

        return transcript
    }

    /// Load (and CoreML-specialise) the model ahead of first use. Errors are
    /// ignored — a failed prewarm just means the next `transcribe` retries the
    /// load and surfaces the error.
    public func prewarm() async {
        _ = try? await loadWhisperKit()
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

    /// Warm the active engine's model in the background so the first
    /// transcription is instant. No-op for engines that need no warm-up.
    public func prewarm() {
        Task { await engine.prewarm() }
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
