import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

// MARK: - Section card

/// A MacStats-style inset card: a `.caption2` semibold secondary label (no dot, no kerning) over the
/// content, on a faint tint of the window's material (`CardBackground`).
private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}

// MARK: - Appearance picker

/// System / Light / Dark, as a native segmented control (SF Symbols, like Control Center's).
private struct AppearancePicker: View {
    @Binding var selection: AppTheme

    var body: some View {
        Picker("Appearance", selection: $selection) {
            ForEach(AppTheme.allCases) { theme in
                Label(theme.displayName, systemImage: Self.symbol(theme))
                    .labelStyle(.iconOnly)
                    .help(theme.displayName)
                    .tag(theme)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Appearance")
    }

    private static func symbol(_ theme: AppTheme) -> String {
        switch theme {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

// MARK: - Row with hover actions

/// A row inside a card: its trailing actions (copy, remove…) appear on hover, over a
/// `Color.primary` 0.07 continuous-rounded highlight (the MacStats list-row pattern).
private struct HoverRow<Label: View, Actions: View>: View {
    @ViewBuilder let label: () -> Label
    @ViewBuilder let actions: () -> Actions
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions() }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(minHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(hovering ? Design.rowHoverFill : 0))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// The quiet row action: an SF Symbol in `.secondary`, `.primary` while pressed.
private struct RowActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var coordinator: VoiceCoordinator
    @State private var newWord = ""
    @State private var newAppMatch = ""
    /// Why the last Add was turned away — shown under its field, cleared on edit.
    @State private var wordNotice: String?
    @State private var appMatchNotice: String?
    /// Mirror of `TourSettings.firstUseToursEnabled` (a plain UserDefaults key SwiftUI can't observe):
    /// refreshed on appear and whenever a window becomes key, written through on change.
    @State private var toursEnabled = false
    /// Settings → Appearance → Opacity; shared with every window and pill, which follow it live.
    @ObservedObject private var opacity = UIOpacityStore.shared

    var body: some View {
        let theme = coordinator.appTheme.theme

        // No background of its own: the window's content view is a behind-window material
        // (`WindowMaterial`), and its appearance (System / Light / Dark) is set on the NSWindow.
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header: title left, appearance picker right
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("JVoice")
                            .font(.title2.bold())
                        Text("Menu bar transcription controls")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AppearancePicker(selection: $coordinator.appTheme)
                }

                // Stats — full width
                statsSection

                // Two columns: controls (left) · your data (right)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        modelSection
                        processingSection
                        voiceStyleSection
                        languageSection
                        appModesSection(theme)
                        shortcutSection(theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 12) {
                        recentTranscriptsSection
                        customWordsSection(theme)
                        // The right column is the shorter one, so these cards cost no height.
                        toursSection
                        appearanceSection
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                footer
            }
            .padding(20)
        }
        .frame(width: 700, height: 560)
    }

    // MARK: Sections

    private var statsSection: some View {
        SettingsSection("Stats") {
            HStack(spacing: 0) {
                stat("\(coordinator.totalWordsSpoken)", "total words", number: Double(coordinator.totalWordsSpoken))
                Divider().frame(height: 36)
                stat(coordinator.averageWPM > 0 ? String(format: "%.0f", coordinator.averageWPM) : "—", "avg WPM",
                     number: coordinator.averageWPM)
                Divider().frame(height: 36)
                stat(timeSavedDisplay(coordinator.minutesSaved), "time saved", number: coordinator.minutesSaved)
            }
            .frame(maxWidth: .infinity)
        }
        .tourAnchor("settings.stats")
    }

    /// Human-readable "time saved" cell: "—" under a minute, "{n} min" up to an
    /// hour, "{n} h" beyond. Mirrors the Windows port's display.
    private func timeSavedDisplay(_ minutes: Double) -> String {
        if minutes < 1 { return "—" }
        if minutes < 60 { return "\(Int(minutes)) min" }
        return "\(Int(minutes / 60)) h"
    }

    /// The MacStats stat pattern: a `.title2` semibold monospaced value that fades (not rolls) when it
    /// changes, over a `.caption2` secondary label.
    private func stat(_ value: String, _ label: String, number: Double) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 0.25), value: number)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var modelSection: some View {
        SettingsSection("Whisper Model") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Model", selection: $coordinator.whisperModel) {
                    ForEach(WhisperModelChoice.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(coordinator.whisperModel.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tourAnchor("settings.model")
    }

    private var processingSection: some View {
        SettingsSection("Processing") {
            VStack(spacing: 10) {
                toggleRow("Developer Terms",
                          "Fix coding terms: Node.js, GitHub, TypeScript, JSON, C#…",
                          isOn: $coordinator.developerTerms)
                toggleRow("Math Notation",
                          "Spoken equations become symbols: x squared equals 4 → x² = 4",
                          isOn: $coordinator.mathNotation)
                toggleRow("Remove Filler Words",
                          "Strip um, uh, er, ah, hmm from output",
                          isOn: $coordinator.removeFillerWords)
                toggleRow("Copy to Clipboard",
                          "Copy the text instead of auto-pasting it",
                          isOn: $coordinator.copyToClipboardOnly)
            }
        }
        .tourAnchor("settings.processing")
    }

    /// A labelled switch row, System-Settings style: `.callout` title, `.caption` secondary subtitle,
    /// a small native switch.
    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var voiceStyleSection: some View {
        SettingsSection("Voice Style") {
            Picker("Tone", selection: $coordinator.toneMode) {
                ForEach(ToneMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .tourAnchor("settings.voiceStyle")
    }

    private var languageSection: some View {
        SettingsSection("Language") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Language", selection: $coordinator.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                toggleRow("Translate to English",
                          "Speak the language above, paste English",
                          isOn: $coordinator.translateToEnglish)
            }
        }
    }

    private func appModesSection(_ theme: Theme) -> some View {
        SettingsSection("App Modes") {
            VStack(alignment: .leading, spacing: 10) {
                toggleRow("Auto-switch by App",
                          "Match the app's bundle ID; code apps → Code tone",
                          isOn: $coordinator.appAwareModes)

                if coordinator.appAwareModes {
                    if coordinator.appModeRules.isEmpty {
                        Text("No rules yet. Terminals and editors already default to Code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(coordinator.appModeRules, id: \.appMatch) { rule in
                                HoverRow {
                                    HStack(spacing: 8) {
                                        Text(rule.appMatch)
                                            .font(.callout)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button(rule.mode.displayName) {
                                            coordinator.cycleAppModeRuleMode(rule)
                                        }
                                        .buttonStyle(SubtleButtonStyle())
                                        .help("Click to change tone")
                                    }
                                } actions: {
                                    RowActionButton(symbol: "minus.circle", help: "Remove") {
                                        coordinator.removeAppModeRule(rule)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, -6)
                    }

                    HStack(spacing: 6) {
                        TextField("App name or bundle ID (e.g. Slack)", text: $newAppMatch)
                            .inputFieldStyle()
                            .onSubmit { submitAppRule() }

                        Button("Add") { submitAppRule() }
                            .buttonStyle(SubtleButtonStyle())
                            .disabled(newAppMatch.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .onChange(of: newAppMatch) { appMatchNotice = nil }

                    if let appMatchNotice {
                        InlineNotice(text: appMatchNotice, theme: theme)
                    }
                }
            }
        }
        .tourAnchor("settings.appModes")
    }

    private func shortcutSection(_ theme: Theme) -> some View {
        SettingsSection("Keyboard Shortcut") {
            VStack(alignment: .leading, spacing: 6) {
                #if canImport(KeyboardShortcuts)
                ShortcutRecorder(label: "Toggle Recording", name: .toggleRecording, theme: theme)
                #else
                Text("Shortcut customization is unavailable in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
                Text("Default: ⌥ Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if canImport(KeyboardShortcuts)
                Divider().padding(.vertical, 4)
                ShortcutRecorder(label: "Undo Last Paste", name: .undoLastPaste, theme: theme)
                Text("Optional — sends the app's Undo (⌘Z) to reverse the last paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }
        }
        .tourAnchor("settings.shortcut")
    }

    private var recentTranscriptsSection: some View {
        SettingsSection("Recent Transcripts") {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.recentTranscripts.isEmpty {
                    Text("No transcripts yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(coordinator.recentTranscripts) { entry in
                                TranscriptRow(
                                    text: entry.text,
                                    onCopy: { coordinator.copyToClipboard(entry.text) },
                                    onDelete: { coordinator.deleteTranscript(entry.id) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .padding(.horizontal, -6)

                    HStack {
                        Spacer()
                        Button("Clear All", role: .destructive) { coordinator.clearTranscriptHistory() }
                            .buttonStyle(SubtleButtonStyle(destructive: true))
                    }
                }
            }
        }
        .tourAnchor("settings.transcripts")
    }

    private func customWordsSection(_ theme: Theme) -> some View {
        SettingsSection("Custom Words") {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.customWords.isEmpty {
                    Text("No custom words added.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(coordinator.customWords, id: \.self) { word in
                                HoverRow {
                                    Text(word)
                                        .font(.callout)
                                        .lineLimit(1)
                                } actions: {
                                    RowActionButton(symbol: "minus.circle", help: "Remove") {
                                        coordinator.removeCustomWord(word)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal, -6)
                }

                HStack(spacing: 6) {
                    TextField("Add word (e.g. VS Code)", text: $newWord)
                        .inputFieldStyle()
                        .onSubmit { submitWord() }

                    Button("Add") { submitWord() }
                        .buttonStyle(SubtleButtonStyle())
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .onChange(of: newWord) { wordNotice = nil }

                if let wordNotice {
                    InlineNotice(text: wordNotice, theme: theme)
                }
            }
        }
        .tourAnchor("settings.customWords")
    }

    /// "Tours & Tips": the first-use tours switch, plus replay/reset (see `Tours/TourCatalog.swift`).
    private var toursSection: some View {
        SettingsSection("Tours & Tips") {
            VStack(alignment: .leading, spacing: 10) {
                toggleRow("Show Me Around",
                          "Point out each part the first time you use it.",
                          isOn: Binding(get: { toursEnabled },
                                        set: { toursEnabled = $0; TourSettings.firstUseToursEnabled = $0 }))

                HStack(spacing: 6) {
                    Button("Replay Welcome Tour") { TourEvents.replay(.welcome, in: nil) }
                        .buttonStyle(SubtleButtonStyle())
                    Button("Reset All Tours") { TourEvents.resetAll() }
                        .buttonStyle(SubtleButtonStyle())
                }
            }
        }
        .onAppear { toursEnabled = TourSettings.firstUseToursEnabled }
        // The Welcome window's "Show Me Around" can flip it while Settings stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            toursEnabled = TourSettings.firstUseToursEnabled
        }
    }

    /// "Appearance": the Opacity slider shared by MacStats, JVoice and BetterScreenshot
    /// (`../MacStats/docs/design-language/opacity-setting.md` §2). Applies live; "Default" = 0.5.
    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opacity")
                        .font(.callout)
                    Spacer(minLength: 0)
                    Button("Default") { opacity.value = UIOpacity.defaultValue }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(abs(opacity.value - UIOpacity.defaultValue) < 0.001)
                        .help("Back to the standard look")
                }
                Slider(value: $opacity.value, in: 0...1) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Text("Transparent").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Opaque").font(.caption).foregroundStyle(.secondary)
                }
                .labelsHidden()
                .controlSize(.small)
                Text("How much of what's behind JVoice shows through its windows and the recording pill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The MacStats footer: the secondary/destructive actions as small buttons, red where destructive.
    private var footer: some View {
        HStack {
            Button("Restore Default Settings…", role: .destructive) { confirmReset() }
                .buttonStyle(SubtleButtonStyle(destructive: true))
            Spacer()
            Button("Quit JVoice", role: .destructive) { coordinator.quitApp() }
                .buttonStyle(SubtleButtonStyle(destructive: true))
        }
        .padding(.top, 2)
    }

    /// A native `NSAlert` sheet, not a SwiftUI `.confirmationDialog`: in an accessory (menu-bar) app a
    /// SwiftUI dialog can lose focus (MacStats hit exactly this — `AppModel.confirmAndEmptyTrash`).
    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all JVoice settings to defaults?"
        alert.informativeText = "Your custom words, model choice, and language will be restored to defaults, and your recent transcripts will be cleared. Recording statistics will not be affected."
        alert.alertStyle = .warning
        // Return must not wipe settings: Cancel is the default button, Reset is click-only (red).
        let resetButton = alert.addButton(withTitle: "Reset")
        resetButton.hasDestructiveAction = true
        resetButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        let reset = { (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { coordinator.resetSettings() }
        }
        if let window = NSApp.windows.first(where: { $0 is SettingsWindow && $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: reset)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            reset(alert.runModal())
        }
    }

    private func submitWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // A rejected word keeps its text in the field, with the reason under it.
        guard coordinator.addCustomWord(trimmed) != nil else {
            wordNotice = SettingsEntryPolicy.customWordRejection(trimmed, existing: coordinator.customWords)
                ?? "Couldn't add that word."
            return
        }
        newWord = ""
    }

    private func submitAppRule() {
        let trimmed = newAppMatch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Rules match bundle IDs, so a typed app name is resolved to its
        // bundle ID first; an app that can't be found is reported rather than
        // stored as a rule that could never match.
        let target = SettingsEntryPolicy.appRuleTarget(for: trimmed, installed: SettingsEntryPolicy.installedApps())
        let match: String
        let shownName: String
        switch target {
        case .app(let app):
            match = app.bundleID
            shownName = app.name
        case .bundleID(let bundleID):
            match = bundleID
            shownName = bundleID
        case .ambiguous, .notFound:
            appMatchNotice = SettingsEntryPolicy.appRuleNotice(for: target, typed: trimmed)
            return
        }
        guard coordinator.addAppModeRule(match: match, mode: .code) else {
            appMatchNotice = "There's already a rule for \(shownName)."
            return
        }
        newAppMatch = ""
    }
}

// MARK: - TranscriptRow

private struct TranscriptRow: View {
    let text: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var justCopied = false

    var body: some View {
        HoverRow {
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        } actions: {
            RowActionButton(symbol: justCopied ? "checkmark" : "doc.on.doc", help: "Copy to clipboard") {
                onCopy()
                flashCopied()
            }
            RowActionButton(symbol: "minus.circle", help: "Remove", action: onDelete)
        }
    }

    private func flashCopied() {
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            justCopied = false
        }
    }
}
