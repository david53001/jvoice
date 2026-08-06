import Foundation

public enum HUDState: Equatable, Codable, Sendable {
    case idle
    case recording
    /// Fetching the model over the network. Split out from `preparingModel` so
    /// a multi-hundred-megabyte download never hides behind a label that reads
    /// as a hang — `downloadedBytes` is measured on disk each poll, `totalBytes`
    /// is the model's approximate published size (see `ModelDownloadProgress`).
    case downloadingModel(downloadedBytes: Int64, totalBytes: Int64)
    case preparingModel
    case transcribing
    case done(String)
    case error(String)

    public enum AccentRole: String, Codable, Sendable {
        case secondary
        case red
        case blue
        case green
        case orange
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
        case downloadedBytes
        case totalBytes
    }

    private enum Kind: String, Codable {
        case idle
        case recording
        case downloadingModel
        case preparingModel
        case transcribing
        case done
        case error
    }

    public var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .downloadingModel(let downloaded, let total):
            return "Downloading model… \(ModelDownloadProgress.label(downloaded: downloaded, total: total))"
        case .preparingModel:
            return "Preparing model…"
        case .transcribing:
            return "Transcribing…"
        case .done:
            return "Pasted"
        case .error(let message):
            return message.isEmpty ? "Something went wrong" : message
        }
    }

    public var headline: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening"
        case .downloadingModel:
            return "Downloading Model"
        case .preparingModel:
            return "Optimizing for Neural Engine"
        case .transcribing:
            return "Transcribing"
        case .done:
            return "Pasted"
        case .error:
            return "Something Went Wrong"
        }
    }

    public var subtitle: String? {
        switch self {
        case .idle:
            return "JVoice is standing by."
        case .recording:
            return "Capturing audio for transcription."
        case .downloadingModel(let downloaded, let total):
            return "\(ModelDownloadProgress.label(downloaded: downloaded, total: total)) — needs the network."
        case .preparingModel:
            return "One-time per login. Keep JVoice open."
        case .transcribing:
            return "Processing the latest recording…"
        case .done:
            return nil
        case .error(let message):
            return message.isEmpty ? "Something went wrong" : message
        }
    }

    public var systemImageName: String {
        switch self {
        case .idle:
            return "waveform"
        case .recording:
            return "mic.fill"
        case .downloadingModel:
            return "arrow.down.circle"
        case .preparingModel:
            return "gearshape.2"
        case .transcribing:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    public var accentRole: AccentRole {
        switch self {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .downloadingModel:
            return .blue
        case .preparingModel:
            return .blue
        case .transcribing:
            return .blue
        case .done:
            return .green
        case .error:
            return .orange
        }
    }

    public var isVisible: Bool {
        switch self {
        case .idle:
            return false
        case .recording, .downloadingModel, .preparingModel, .transcribing, .done, .error:
            return true
        }
    }

    public var isBusy: Bool {
        switch self {
        case .recording, .downloadingModel, .preparingModel, .transcribing:
            return true
        case .idle, .done, .error:
            return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .done, .error:
            return true
        case .idle, .recording, .downloadingModel, .preparingModel, .transcribing:
            return false
        }
    }

    public var payload: String? {
        switch self {
        case .done(let text), .error(let text):
            return text
        case .idle, .recording, .downloadingModel, .preparingModel, .transcribing:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .idle:
            self = .idle
        case .recording:
            self = .recording
        case .downloadingModel:
            self = .downloadingModel(
                downloadedBytes: try container.decode(Int64.self, forKey: .downloadedBytes),
                totalBytes: try container.decode(Int64.self, forKey: .totalBytes)
            )
        case .preparingModel:
            self = .preparingModel
        case .transcribing:
            self = .transcribing
        case .done:
            self = .done(try container.decode(String.self, forKey: .payload))
        case .error:
            self = .error(try container.decode(String.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .recording:
            try container.encode(Kind.recording, forKey: .kind)
        case .downloadingModel(let downloadedBytes, let totalBytes):
            try container.encode(Kind.downloadingModel, forKey: .kind)
            try container.encode(downloadedBytes, forKey: .downloadedBytes)
            try container.encode(totalBytes, forKey: .totalBytes)
        case .preparingModel:
            try container.encode(Kind.preparingModel, forKey: .kind)
        case .transcribing:
            try container.encode(Kind.transcribing, forKey: .kind)
        case .done(let text):
            try container.encode(Kind.done, forKey: .kind)
            try container.encode(text, forKey: .payload)
        case .error(let message):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(message, forKey: .payload)
        }
    }
}
