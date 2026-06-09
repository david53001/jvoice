import AppKit

enum HUDLayout {
    static let hudPillSize = NSSize(width: 220, height: 50)

    static func minimumSize(for state: HUDState) -> NSSize {
        switch state {
        case .recording, .preparingModel, .transcribing, .done, .error, .idle:
            return hudPillSize
        }
    }
}
