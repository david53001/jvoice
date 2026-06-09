import Foundation

public enum HUDState: Equatable, Codable, Sendable {
    case idle
    case recording
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
    }

    private enum Kind: String, Codable {
        case idle
        case recording
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
        case .preparingModel:
            return "Preparing Model"
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
        case .preparingModel:
            return "First use of a model can take a few minutes."
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
        case .recording, .preparingModel, .transcribing, .done, .error:
            return true
        }
    }

    public var isBusy: Bool {
        switch self {
        case .recording, .preparingModel, .transcribing:
            return true
        case .idle, .done, .error:
            return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .done, .error:
            return true
        case .idle, .recording, .preparingModel, .transcribing:
            return false
        }
    }

    public var payload: String? {
        switch self {
        case .done(let text), .error(let text):
            return text
        case .idle, .recording, .preparingModel, .transcribing:
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
