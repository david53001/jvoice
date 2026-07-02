import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

// MARK: - Section card (theme-aware)

private struct SettingsSection<Content: View>: View {
    let title: String
    let theme: Theme
    let content: Content

    init(_ title: String, theme: Theme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(theme.textMuted)
                    .frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.7)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(theme.hairline).frame(height: 0.5)

            content.padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Button style (theme-aware)

private struct SettingsButtonStyle: ButtonStyle {
    let theme: Theme
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        let c = destructive ? theme.danger : theme.textPrimary
        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(c.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(c.opacity(0.25), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.70 : 1.0)
    }
}

// MARK: - Sun/moon theme toggle

private struct ThemeToggle: View {
    @Binding var selection: AppTheme
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            icon("sun.max.fill", on: selection == .light) { selection = .light }
            icon("moon.fill", on: selection == .dark) { selection = .dark }
        }
        .padding(3)
        .background(
            Capsule().fill(theme.inputBackground)
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
        )
        .accessibilityLabel("Appearance")
    }

    private func icon(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? theme.textPrimary : theme.textMuted)
                .frame(width: 26, height: 20)
                .background(
                    Capsule().fill(on ? theme.barFill.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var coordinator: VoiceCoordinator
    @State private var newWord = ""
    @State private var newAppMatch = ""
    @State private var showResetConfirm = false

    var body: some View {
        let theme = coordinator.appTheme.theme

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header with sun/moon toggle (top-right)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("JVoice")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Menu bar transcription controls")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    ThemeToggle(selection: $coordinator.appTheme, theme: theme)
                }
                .padding(.bottom, 2)

                // Stats — full width
                statsSection(theme)

                // Two columns: controls (left) · your data (right)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        modelSection(theme)
                        processingSection(theme)
                        voiceStyleSection(theme)
                        languageSection(theme)
                        appModesSection(theme)
                        shortcutSection(theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 12) {
                        recentTranscriptsSection(theme)
                        customWordsSection(theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                footer(theme)
            }
            .padding(18)
        }
        .background(theme.windowBackground)
        .preferredColorScheme(theme.colorScheme)
        .frame(width: 700, height: 560)
    }

    // MARK: Sections

    private func statsSection(_ theme: Theme) -> some View {
        SettingsSection("Stats", theme: theme) {
            HStack(spacing: 0) {
                stat("\(coordinator.totalWordsSpoken)", "total words", theme)
                Rectangle().fill(theme.hairline).frame(width: 0.5, height: 44)
                stat(coordinator.averageWPM > 0 ? String(format: "%.0f", coordinator.averageWPM) : "—", "avg WPM", theme)
                Rectangle().fill(theme.hairline).frame(width: 0.5, height: 44)
                stat(timeSavedDisplay(coordinator.minutesSaved), "time saved", theme)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Human-readable "time saved" cell: "—" under a minute, "{n} min" up to an
    /// hour, "{n} h" beyond. Mirrors the Windows port's display.
    private func timeSavedDisplay(_ minutes: Double) -> String {
        if minutes < 1 { return "—" }
        if minutes < 60 { return "\(Int(minutes)) min" }
        return "\(Int(minutes / 60)) h"
    }

    private func stat(_ value: String, _ label: String, _ theme: Theme) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func modelSection(_ theme: Theme) -> some View {
        SettingsSection("Whisper Model", theme: theme) {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Model", selection: $coordinator.whisperModel) {
                    ForEach(WhisperModelChoice.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(coordinator.whisperModel.guidance)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func processingSection(_ theme: Theme) -> some View {
        SettingsSection("Processing", theme: theme) {
            VStack(spacing: 12) {
                toggleRow("Developer Terms",
                          "Fix coding terms: Node.js, GitHub, TypeScript, JSON, C#…",
                          isOn: $coordinator.developerTerms, theme)
                toggleRow("Remove Filler Words",
                          "Strip um, uh, er, ah, hmm from output",
                          isOn: $coordinator.removeFillerWords, theme)
                toggleRow("Copy to Clipboard",
                          "Copy the text instead of auto-pasting it",
                          isOn: $coordinator.copyToClipboardOnly, theme)
            }
        }
    }

    /// A labelled switch row matching the original Processing toggle style.
    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>, _ theme: Theme) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func voiceStyleSection(_ theme: Theme) -> some View {
        SettingsSection("Voice Style", theme: theme) {
            Picker("Tone", selection: $coordinator.toneMode) {
                ForEach(ToneMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func languageSection(_ theme: Theme) -> some View {
        SettingsSection("Language", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Language", selection: $coordinator.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                toggleRow("Translate to English",
                          "Speak the language above, paste English",
                          isOn: $coordinator.translateToEnglish, theme)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appModesSection(_ theme: Theme) -> some View {
        SettingsSection("App Modes", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                toggleRow("Auto-switch by App",
                          "Match the app's bundle ID; code apps → Code tone",
                          isOn: $coordinator.appAwareModes, theme)

                if coordinator.appAwareModes {
                    if coordinator.appModeRules.isEmpty {
                        Text("No rules yet. Terminals and editors already default to Code.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(coordinator.appModeRules, id: \.appMatch) { rule in
                                HStack(spacing: 6) {
                                    Text(rule.appMatch)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        coordinator.cycleAppModeRuleMode(rule)
                                    } label: {
                                        Text(rule.mode.displayName)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(theme.textPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(theme.barFill.opacity(0.14))
                                                    .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Click to change tone")

                                    Button {
                                        coordinator.removeAppModeRule(rule)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(theme.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("App bundle ID or name (e.g. slack)", text: $newAppMatch)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(theme.inputBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(theme.hairline, lineWidth: 1)
                                    )
                            )
                            .onSubmit { submitAppRule() }

                        Button("Add") { submitAppRule() }
                            .buttonStyle(SettingsButtonStyle(theme: theme))
                            .disabled(newAppMatch.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutSection(_ theme: Theme) -> some View {
        SettingsSection("Keyboard Shortcut", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                #if canImport(KeyboardShortcuts)
                KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
                    .foregroundStyle(theme.textSecondary)
                #else
                Text("Shortcut customization is unavailable in this build.")
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                #endif
                Text("Default: ⌥ Space")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)

                #if canImport(KeyboardShortcuts)
                Rectangle().fill(theme.hairline).frame(height: 0.5).padding(.vertical, 2)
                KeyboardShortcuts.Recorder("Undo Last Paste:", name: .undoLastPaste)
                    .foregroundStyle(theme.textSecondary)
                Text("Optional — sends the app's Undo (⌘Z) to reverse the last paste")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentTranscriptsSection(_ theme: Theme) -> some View {
        SettingsSection("Recent Transcripts", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.recentTranscripts.isEmpty {
                    Text("No transcripts yet.")
                        .font(.footnote)
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(coordinator.recentTranscripts) { entry in
                                TranscriptRow(
                                    text: entry.text,
                                    theme: theme,
                                    onCopy: { coordinator.copyToClipboard(entry.text) },
                                    onDelete: { coordinator.deleteTranscript(entry.id) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 220)

                    HStack {
                        Spacer()
                        Button("Clear all") { coordinator.clearTranscriptHistory() }
                            .buttonStyle(SettingsButtonStyle(theme: theme))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customWordsSection(_ theme: Theme) -> some View {
        SettingsSection("Custom Words", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.customWords.isEmpty {
                    Text("No custom words added.")
                        .font(.footnote)
                        .foregroundStyle(theme.textMuted)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(coordinator.customWords, id: \.self) { word in
                                HStack {
                                    Text(word)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    Button {
                                        coordinator.removeCustomWord(word)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(theme.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 150)
                }

                HStack(spacing: 6) {
                    TextField("Add word (e.g. VS Code)", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(theme.hairline, lineWidth: 1)
                                )
                        )
                        .onSubmit { submitWord() }

                    Button("Add") { submitWord() }
                        .buttonStyle(SettingsButtonStyle(theme: theme))
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ theme: Theme) -> some View {
        HStack {
            Button("Restore Default Settings") { showResetConfirm = true }
                .buttonStyle(SettingsButtonStyle(theme: theme, destructive: true))
                .confirmationDialog(
                    "Reset all JVoice settings to defaults?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) { coordinator.resetSettings() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your custom words, model choice, and language will be restored to defaults, and your recent transcripts will be cleared. Recording statistics will not be affected.")
                }

            Spacer()
            Button("Quit JVoice", role: .destructive) { coordinator.quitApp() }
                .buttonStyle(SettingsButtonStyle(theme: theme, destructive: true))
        }
    }

    private func submitWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coordinator.addCustomWord(trimmed)
        newWord = ""
    }

    private func submitAppRule() {
        let trimmed = newAppMatch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coordinator.addAppModeRule(match: trimmed, mode: .code)
        newAppMatch = ""
    }
}

// MARK: - TranscriptRow

private struct TranscriptRow: View {
    let text: String
    let theme: Theme
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                Button {
                    onCopy()
                    flashCopied()
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? theme.inputBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func flashCopied() {
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            justCopied = false
        }
    }
}
