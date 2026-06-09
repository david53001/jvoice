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
