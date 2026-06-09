import Foundation

public enum WhisperModelOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiny
    case base
    case small
    case largeTurbo = "large-v3-v20240930"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tiny, .base, .small:
            return rawValue.capitalized
        case .largeTurbo:
            return "Large v3 Turbo"
        }
    }

    /// The WhisperKit model identifier (HuggingFace folder stem). For
    /// `.largeTurbo` this is Argmax's turbo-optimized 632 MB build of OpenAI's
    /// large-v3-turbo — same 4-layer-decoder architecture, but ~21–36% faster
    /// warm decode AND a ~624 MB download vs the full ~1.5 GB build. Verified
    /// 2026-06-09 via `--bench` on en+ro clips (short/long/vocab): transcripts
    /// equivalent to the full build (Romanian diacritics actually slightly
    /// better), the vocabulary `promptTokens` path still spells custom words
    /// correctly, and no multi-window truncation on 31 s/36 s clips.
    /// Deliberately decoupled from `rawValue` so swapping the physical build
    /// never churns persisted settings or needs a new Codable migration shim.
    public var whisperKitModelName: String {
        switch self {
        case .largeTurbo:
            return "large-v3-v20240930_turbo_632MB"
        case .tiny, .base, .small:
            return rawValue
        }
    }

    public var whisperKitFolderName: String {
        "openai_whisper-\(whisperKitModelName)"
    }

    public var approximateRelativeSize: String {
        switch self {
        case .tiny:
            return "Smallest"
        case .base:
            return "Balanced"
        case .small:
            return "Larger"
        case .largeTurbo:
            return "Most capable"
        }
    }
}

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
