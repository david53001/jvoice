import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

// MARK: - Palette

private enum SettingsPalette {
    static let panelBg    = Color(red: 0.051, green: 0.051, blue: 0.086)
    static let sectionBg  = Color(red: 0.059, green: 0.059, blue: 0.102)
    static let border     = Color(red: 0.118, green: 0.118, blue: 0.173)
    static let headerText = Color(red: 0.290, green: 0.502, blue: 0.800)
    static let inputBg    = Color(red: 0.039, green: 0.039, blue: 0.078)

    static let blue    = Color(red: 0.290, green: 0.620, blue: 1.000)
    static let gray    = Color(white: 0.53)
    static let indigo  = Color(red: 0.376, green: 0.627, blue: 1.000)
    static let purple  = Color(red: 0.502, green: 0.376, blue: 1.000)
    static let cyan    = Color(red: 0.125, green: 0.847, blue: 1.000)
    static let orange  = Color(red: 0.941, green: 0.627, blue: 0.188)
    static let green   = Color(red: 0.290, green: 0.871, blue: 0.627)
    static let teal    = Color(red: 0.125, green: 0.753, blue: 0.627)
    static let red     = Color(red: 1.000, green: 0.376, blue: 0.376)
}

// MARK: - DarkSection

private struct DarkSection<Content: View>: View {
    let title: String
    let accentColor: Color
    let content: Content

    init(_ title: String, accentColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.55), radius: 3)
                    .frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.7)
                    .foregroundStyle(SettingsPalette.headerText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(SettingsPalette.border)
                .frame(height: 0.5)

            content
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsPalette.sectionBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsPalette.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Button Styles

private struct DarkPrimaryButtonStyle: ButtonStyle {
    var accentColor: Color = SettingsPalette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.28), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.70 : 1.0)
    }
}

private struct DarkDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsPalette.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SettingsPalette.red.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(SettingsPalette.red.opacity(0.24), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.70 : 1.0)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var coordinator: VoiceCoordinator
    @State private var newWord = ""
    @State private var editedTranscript: String = ""
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {

                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("JVoice")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Menu bar transcription controls")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.45))
                }
                .padding(.bottom, 4)

                // Last Transcript
                DarkSection("Last Transcript", accentColor: SettingsPalette.blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        if coordinator.lastTranscript.isEmpty {
                            Text("No transcript yet.")
                                .font(.footnote)
                                .foregroundStyle(Color(white: 0.40))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextEditor(text: $editedTranscript)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.75))
                                .frame(height: 56)
                                .scrollContentBackground(.hidden)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(SettingsPalette.inputBg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(SettingsPalette.border, lineWidth: 1)
                                        )
                                )
                        }

                        if !coordinator.lastTranscript.isEmpty {
                            HStack(spacing: 8) {
                                Button("Fix") {
                                    coordinator.fixLastTranscript(editedTranscript)
                                }
                                .buttonStyle(DarkPrimaryButtonStyle())
                                .disabled(
                                    editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines) ==
                                    coordinator.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                                )

                                Button("Revert") {
                                    coordinator.revertLastFix()
                                }
                                .buttonStyle(DarkPrimaryButtonStyle(accentColor: SettingsPalette.gray))
                                .disabled(!coordinator.canRevert)

                                Button("Clear") {
                                    coordinator.clearLastTranscript()
                                }
                                .buttonStyle(DarkPrimaryButtonStyle(accentColor: SettingsPalette.gray))
                                .disabled(coordinator.lastTranscript.isEmpty)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: coordinator.lastTranscript) { _, newValue in
                    editedTranscript = newValue
                }

                // Keyboard Shortcut
                DarkSection("Keyboard Shortcut", accentColor: SettingsPalette.gray) {
                    VStack(alignment: .leading, spacing: 8) {
                        #if canImport(KeyboardShortcuts)
                        KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
                            .foregroundStyle(Color(white: 0.75))
                        #else
                        Text("Shortcut customization is unavailable in this build.")
                            .font(.footnote)
                            .foregroundStyle(Color(white: 0.40))
                        #endif

                        Text("Default: ⌥ Space")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.35))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Language
                DarkSection("Language", accentColor: SettingsPalette.indigo) {
                    Picker("Language", selection: $coordinator.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Voice Style
                DarkSection("Voice Style", accentColor: SettingsPalette.purple) {
                    Picker("Tone", selection: $coordinator.toneMode) {
                        ForEach(ToneMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Processing
                DarkSection("Processing", accentColor: SettingsPalette.teal) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove Filler Words")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.85))
                            Text("Strip um, uh, er, ah, hmm from output")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.38))
                        }
                        Spacer()
                        Toggle("", isOn: $coordinator.removeFillerWords)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(SettingsPalette.teal)
                    }
                }

                // Whisper Model
                DarkSection("Whisper Model", accentColor: SettingsPalette.cyan) {
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
                            .foregroundStyle(Color(white: 0.38))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Custom Words
                DarkSection("Custom Words", accentColor: SettingsPalette.orange) {
                    VStack(alignment: .leading, spacing: 8) {
                        if coordinator.customWords.isEmpty {
                            Text("No custom words added.")
                                .font(.footnote)
                                .foregroundStyle(Color(white: 0.40))
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(coordinator.customWords, id: \.self) { word in
                                        HStack {
                                            Text(word)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color(white: 0.75))
                                            Spacer()
                                            Button {
                                                coordinator.removeCustomWord(word)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(SettingsPalette.red.opacity(0.80))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(maxHeight: 88)
                        }

                        HStack(spacing: 6) {
                            TextField("Add word (e.g. VS Code)", text: $newWord)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(SettingsPalette.inputBg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(SettingsPalette.border, lineWidth: 1)
                                        )
                                )
                                .onSubmit { submitWord() }

                            Button("Add") { submitWord() }
                                .buttonStyle(DarkPrimaryButtonStyle(accentColor: SettingsPalette.orange))
                                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Stats
                DarkSection("Stats", accentColor: SettingsPalette.green) {
                    HStack(spacing: 0) {
                        VStack(spacing: 3) {
                            Text("\(coordinator.totalWordsSpoken)")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .shadow(color: SettingsPalette.blue.opacity(0.45), radius: 8)
                                .shadow(color: SettingsPalette.blue.opacity(0.18), radius: 20)
                            Text("total words")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.38))
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(SettingsPalette.border)
                            .frame(width: 0.5, height: 44)

                        VStack(spacing: 3) {
                            Text(coordinator.averageWPM > 0 ? String(format: "%.0f", coordinator.averageWPM) : "—")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .shadow(color: SettingsPalette.green.opacity(0.45), radius: 8)
                                .shadow(color: SettingsPalette.green.opacity(0.18), radius: 20)
                            Text("avg WPM")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.38))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Restore defaults + Quit
                HStack {
                    Button("Restore Default Settings") {
                        showResetConfirm = true
                    }
                    .buttonStyle(DarkDestructiveButtonStyle())
                    .confirmationDialog(
                        "Reset all JVoice settings to defaults?",
                        isPresented: $showResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            coordinator.resetSettings()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your custom words, model choice, and language will be restored to defaults, and the last transcript will be cleared. Recording statistics will not be affected.")
                    }

                    Spacer()
                    Button("Quit JVoice", role: .destructive) {
                        coordinator.quitApp()
                    }
                    .buttonStyle(DarkDestructiveButtonStyle())
                }

            }
            .padding(16)
            .onAppear {
                editedTranscript = coordinator.lastTranscript
            }
            .onDisappear {
                coordinator.clearRevertBuffer()
            }
        }
        .background(SettingsPalette.panelBg)
        .preferredColorScheme(.dark)
        .frame(width: 320, height: 520)
    }

    private func submitWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coordinator.addCustomWord(trimmed)
        newWord = ""
    }
}
