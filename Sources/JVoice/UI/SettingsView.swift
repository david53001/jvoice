import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

// MARK: - Section card

/// A MacStats-style inset card: a `.caption2` semibold secondary label (no dot, no kerning) over the
/// content, on a faint tint of the window's material (`CardBackground`).
private struct SettingsSection<Content: View>: View {
    let title: String
    /// The AI Polish card's title gets the subtle Claude-orange sweep (David, 2026-10-17).
    var glows = false
    let content: Content

    init(_ title: String, glows: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.glows = glows
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if glows {
                    ClaudeGlowText(text: title.uppercased(), base: .secondary, style: .subtle)
                } else {
                    Text(title.uppercased())
                        .foregroundStyle(.secondary)
                }
            }
                .font(.caption2)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}

// MARK: - Masonry

/// Cards in `columns` equal columns, each placed in the column that is shortest so far (in order), so
/// the columns end up nearly the same height at any window width — no holes under a short column.
/// Re-laid out on every pass, so a live window resize reflows instantly.
private struct MasonryColumns: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 660
        return CGSize(width: width, height: arrange(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (origins, _, columnWidth) = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: columnWidth, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], height: CGFloat, columnWidth: CGFloat) {
        let count = max(1, columns)
        let columnWidth = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        var heights = Array(repeating: CGFloat(0), count: count)
        var origins: [CGPoint] = []
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            origins.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            heights[column] += height + spacing
        }
        return (origins, max(0, (heights.max() ?? 0) - spacing), columnWidth)
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
    /// AI Polish key field. `revealKey` is never persisted and resets whenever Settings closes;
    /// `draftIsSavedKey` marks a field filled by the eye button, which hiding clears again.
    @State private var apiKeyDraft = ""
    @State private var revealKey = false
    @State private var draftIsSavedKey = false
    @State private var keyStatus: String?
    @State private var testingKey = false
    /// AI Polish top-up amount (USD) typed next to "Add"; `topUpNotice` explains a refused amount.
    @State private var topUpDraft: Double? = 5
    @State private var topUpNotice: String?

    var body: some View {
        let theme = coordinator.appTheme.theme

        // No background of its own: the window's content view is a behind-window material
        // (`WindowMaterial`), and its appearance (System / Light / Dark) is set on the NSWindow.
        // The window's real width picks the column count (re-read on every layout pass, so a live
        // resize reflows instantly). Not `ViewThatFits`: it compares IDEAL widths, and the long
        // Recent Transcripts lines make every layout's ideal width "too wide".
        return GeometryReader { proxy in
        let contentWidth = min(proxy.size.width, Self.maxContentWidth) - 40
        ScrollView {
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

                // The cards, masonry-style: each goes into the column that is currently shortest, so no
                // column is left with a hole whatever the width. Two columns, three once it's wide enough.
                MasonryColumns(columns: contentWidth >= Self.threeColumnMinWidth ? 3 : 2, spacing: 12) {
                    modelSection
                    recentTranscriptsSection
                    processingSection
                    customWordsSection(theme)
                    voiceStyleSection
                    languageSection
                    appModesSection(theme)
                    shortcutSection(theme)
                    aiPolishSection(theme)
                    toursSection
                    appearanceSection
                }

                footer
            }
            .padding(20)
            // Filling a big screen: the content stops at a readable width and stays centred.
            .frame(maxWidth: Self.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        }
        // Resizable (2026-10-17): opens at 700 × 560, never smaller than the 2-column minimum, as big
        // as the screen. `SettingsWindow` takes its minimum size from this frame.
        .frame(minWidth: Self.minWindowWidth, idealWidth: 700, maxWidth: .infinity,
               minHeight: Self.minWindowHeight, idealHeight: 560, maxHeight: .infinity)
    }

    static let minWindowWidth: CGFloat = 700
    static let minWindowHeight: CGFloat = 420
    /// Below this the three columns would be narrower than the two-column cards were designed for.
    static let threeColumnMinWidth: CGFloat = 1000
    static let maxContentWidth: CGFloat = 1400

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

    /// AI Polish (opt-in, bring your own Anthropic key, paid from a prepaid balance). Full width:
    /// the switch + key on the left, the balance + what it has cost on the right. The key lives only
    /// in its owner-only file (`APIKeyStore`): the field is masked, the eye button is the only thing that reads it back,
    /// Save clears the field.
    private func aiPolishSection(_ theme: Theme) -> some View {
        SettingsSection("AI Polish", glows: true) {
            // A normal card in the masonry columns: switch + key on top, the balance under it.
            VStack(alignment: .leading, spacing: 10) {
                aiPolishKeyColumn
                Divider()
                polishBalanceColumn(theme)
            }
        }
        .onAppear {
            coordinator.refreshAPIKeyStatus()
            coordinator.refreshPolishUsage()
        }
        // Reveal never outlives the window: hidden again (and a revealed key cleared) on close.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if note.object is SettingsWindow { hideKey() }
        }
        .onDisappear { hideKey() }
    }

    /// The switch, the key field (masked + eye) and Save / Test Key / Remove Key.
    private var aiPolishKeyColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // At $0 the switch reads OFF (nothing is being polished) and can't be turned on; the
            // stored choice comes back by itself once money is added.
            toggleRow("Polish with Claude",
                      "Sends dictations to Claude to fix mistakes.",
                      isOn: Binding(get: { coordinator.aiPolish && coordinator.polishBalance > 0 },
                                    set: { coordinator.aiPolish = $0 }))
                .disabled(coordinator.apiKeyHint == nil || coordinator.polishBalance <= 0)

            if coordinator.apiKeyHint == nil {
                Text("Save your Anthropic API key below to turn this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if coordinator.polishBalance <= 0 {
                Text("Add a balance to turn this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Typing clears the last status line and makes the field a NEW key (not the revealed one).
            let draft = Binding(get: { apiKeyDraft },
                                set: { apiKeyDraft = $0; draftIsSavedKey = false; keyStatus = nil })
            HStack(spacing: 6) {
                Group {
                    if revealKey {
                        TextField(coordinator.apiKeyHint ?? "sk-ant-…", text: draft)
                    } else {
                        // A saved key shows as dots + its last 4 — never the key itself.
                        SecureField(coordinator.apiKeyHint ?? "sk-ant-…", text: draft)
                    }
                }
                .inputFieldStyle()
                .onSubmit { saveKey() }

                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelPressableButtonStyle())
                .help(revealKey ? "Hide key" : "Show key")
                .accessibilityLabel(revealKey ? "Hide key" : "Show key")
            }

            // The buttons get their own row and the status goes under them, so the card works at
            // any column width (the hint + three buttons on one line needed ~350 pt).
            HStack(spacing: 6) {
                Button("Save") { saveKey() }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftIsSavedKey)
                Button(testingKey ? "Testing…" : "Test Key") { testKey() }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled(testingKey || (coordinator.apiKeyHint == nil
                                             && apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                Button("Remove Key", role: .destructive) { removeKey() }
                    .buttonStyle(SubtleButtonStyle(destructive: true))
                    .disabled(coordinator.apiKeyHint == nil)
                Spacer(minLength: 0)
            }
            Text(coordinator.apiKeyHint == nil ? "No key saved" : "Key saved")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let keyStatus {
                Text(keyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The prepaid balance (what's left of the last top-up, with a bar), "$ [5] Add / Remove", and
    /// what AI Polish has cost this month / all time.
    private func polishBalanceColumn(_ theme: Theme) -> some View {
        let usage = coordinator.polishUsage
        let balance = coordinator.polishBalance
        let topUp = coordinator.polishLastTopUp
        let fraction = topUp > 0 ? min(1, max(0, balance / topUp)) : 0
        let usedUp = balance <= 0 && topUp > 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Balance: \(AIPolishUsageStore.dollars(balance)) left")
                .font(.callout)
                .monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.accentColor)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("\(Int((fraction * 100).rounded())) percent of the last top-up left")
            HStack(spacing: 6) {
                Text("Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("$")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("5", value: $topUpDraft, format: .number)
                    .font(.caption)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .inputFieldStyle()
                    .frame(width: 56)
                    .onSubmit { addBalance() }
                    .onChange(of: topUpDraft) { topUpNotice = nil }
                    .accessibilityLabel("Amount to add or remove, in dollars")
                Button("Add") { addBalance() }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled((topUpDraft ?? 0) <= 0)
                    .help("Adds this many dollars to what AI Polish may spend. Anthropic bills your own account.")
                Button("Remove") { removeBalance() }
                    .buttonStyle(SubtleButtonStyle())
                    .disabled((topUpDraft ?? 0) <= 0 || balance <= 0)
                    .help("Takes this many dollars off the balance (never below $0).")
            }

            if let topUpNotice {
                Text(topUpNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if usedUp {
                Text("Balance used up — add more to keep polishing.")
                    .font(.caption)
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.vertical, 2)
            Text("This month: \(AIPolishUsageStore.dollars(usage.monthCost)) · \(usage.monthPolishes) \(usage.monthPolishes == 1 ? "polish" : "polishes")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("All time: \(AIPolishUsageStore.dollars(usage.totalCost)) · \(usage.totalPolishes) \(usage.totalPolishes == 1 ? "polish" : "polishes")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func addBalance() {
        let amount = topUpDraft ?? 0
        if coordinator.addPolishBalance(amount) {
            topUpNotice = nil
        } else {
            topUpNotice = "Enter an amount between $0.01 and \(AIPolishUsageStore.dollars(AIPolishUsageStore.maxTopUp))."
        }
    }

    private func removeBalance() {
        if coordinator.removePolishBalance(topUpDraft ?? 0) {
            topUpNotice = nil
        } else {
            topUpNotice = "Enter an amount above $0 to remove."
        }
    }

    private func toggleReveal() {
        if revealKey {
            hideKey()
        } else {
            // Only an empty field is filled from the saved key; a key being typed is just unmasked.
            if apiKeyDraft.isEmpty, let saved = coordinator.revealAPIKey() {
                apiKeyDraft = saved
                draftIsSavedKey = true
            }
            revealKey = true
        }
    }

    private func hideKey() {
        revealKey = false
        if draftIsSavedKey {
            apiKeyDraft = ""
            draftIsSavedKey = false
        }
    }

    private func saveKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !draftIsSavedKey else { return }
        if coordinator.saveAPIKey(key) {
            apiKeyDraft = ""
            revealKey = false
            keyStatus = "Saved on this Mac."
        } else {
            keyStatus = "Couldn't save the key."
        }
    }

    private func removeKey() {
        coordinator.removeAPIKey()
        hideKey()
        apiKeyDraft = ""
        keyStatus = "Key removed. AI Polish is off."
    }

    private func testKey() {
        let candidate = draftIsSavedKey ? "" : apiKeyDraft
        testingKey = true
        keyStatus = nil
        Task {
            let check = await coordinator.testAPIKey(candidate)
            testingKey = false
            keyStatus = check.message
        }
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
        // The Settings tour's Opacity step plays the slider down and up here (`OpacityTourDemo`).
        .tourAnchor(OpacityTourDemo.anchor)
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
