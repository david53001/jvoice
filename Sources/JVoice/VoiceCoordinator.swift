import AppKit
import ApplicationServices
import Combine
import Foundation

enum ToneMode: String, CaseIterable, Identifiable {
    case casual
    case formal
    case veryCasual

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .casual:
            return "Casual"
        case .formal:
            return "Formal"
        case .veryCasual:
            return "Very Casual"
        }
    }
}

enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case largeTurbo

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .tiny, .base, .small:
            return rawValue.capitalized
        case .largeTurbo:
            return "Large"
        }
    }

    /// One-line guidance shown under the model picker so users know the
    /// speed/accuracy/download trade-off before switching.
    var guidance: String {
        switch self {
        case .tiny:
            return "Fastest · smallest download · least accurate"
        case .base:
            return "Fast · balanced accuracy"
        case .small:
            return "Slower · more accurate"
        case .largeTurbo:
            return "Most accurate · ~630 MB download · first use prepares the model for a few minutes"
        }
    }
}

@MainActor
final class VoiceCoordinator: ObservableObject {
    @Published var toneMode: ToneMode {
        didSet {
            persistSettings()
        }
    }

    @Published var whisperModel: WhisperModelChoice {
        didSet {
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords))
            persistSettings()
        }
    }

    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords))
            persistSettings()
        }
    }

    @Published var customWords: [String] {
        didSet {
            persistSettings()
            transcriptionManager.updateVocabulary(customWords)
        }
    }

    @Published var removeFillerWords: Bool {
        didSet {
            persistSettings()
        }
    }

    @Published var appTheme: AppTheme {
        didSet {
            persistSettings()
            applyTheme()
        }
    }

    @Published private(set) var settingsState: SettingsState
    /// Reflects the live `SMAppService` registration state, not a stored setting.
    @Published private(set) var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @Published private(set) var isRecording = false
    @Published private(set) var hudState: HUDState = .idle
    @Published private(set) var totalWordsSpoken: Int = 0
    @Published private(set) var averageWPM: Double = 0

    private let settingsStore: SettingsStore
    private let recordingManager: RecordingManager
    private let transcriptionManager: TranscriptionManager
    private let pasteManager: PasteManager
    private let statsStore = StatsStore()
    private lazy var hotKeyManager: HotKeyManager = {
        HotKeyManager(shortcutName: .toggleRecording) { [weak self] in
            Task { @MainActor in
                await self?.handleHotKeyToggle()
            }
        }
    }()
    private var hudDismissTask: Task<Void, Never>?
    private var currentTranscriptionTask: Task<Void, Never>?
    private var streamingSession: StreamingTranscriptionSession?
    /// Bumped on every recording start so a session created for recording N
    /// (asynchronously — see startRecordingFlow) is never assigned once
    /// recording N+1 has begun.
    private var recordingGeneration = 0
    private var isInitializing = true
    private var frontmostObserver: NSObjectProtocol?
    @MainActor private var lastNonSelfFrontmostPID: pid_t?
    private var isStartingRecording = false
    private var isStoppingRecording = false
    private var recordingStartDate: Date?
    private var lastRecordingDuration: TimeInterval = 0
    private let lastTranscriptStore = LastTranscriptStore()
    private let transcriptHistoryStore = TranscriptHistoryStore()
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var recentTranscripts: [TranscriptEntry] = []
    @Published private(set) var canRevert: Bool = false
    private var pendingRevertWords: [String] = []
    private var preFixTranscript: String = ""

    private lazy var menuBarController = MenuBarController(coordinator: self)
    private var settingsWindow: SettingsWindow?
    private lazy var hudWindow = HUDWindow()
    private var didStart = false

    init() {
        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore
        self.recordingManager = RecordingManager()
        self.transcriptionManager = TranscriptionManager(
            engine: Self.makeTranscriptionEngine(for: settingsStore.state.model, language: settingsStore.state.language, vocabulary: settingsStore.state.customWords)
        )
        self.pasteManager = PasteManager()
        self.settingsState = settingsStore.state
        self.toneMode = ToneMode(appMode: settingsStore.state.mode)
        self.whisperModel = WhisperModelChoice(model: settingsStore.state.model)
        self.transcriptionLanguage = settingsStore.state.language
        self.customWords = settingsStore.state.customWords
        self.removeFillerWords = settingsStore.state.removeFillerWords
        self.appTheme = settingsStore.state.theme
        self.totalWordsSpoken = statsStore.totalWords
        self.averageWPM = statsStore.averageWPM
        self.lastTranscript = lastTranscriptStore.transcript
        self.recentTranscripts = transcriptHistoryStore.entries
        self.isInitializing = false
    }

    deinit {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        // Privacy: clear any recordings orphaned by a crash/force-quit.
        RecordingManager.sweepOrphanedRecordings()

        installFrontmostObserver()

        hudWindow.onStop = { [weak self] in self?.toggleRecording() }

        ensureAccessibilityOnceForLaunch()

        hotKeyManager.register()
        menuBarController.installStatusItem()
        updateHUD(.idle)

        // Warm the selected Whisper model in the background so the first
        // dictation after launch isn't a cold-start model load.
        transcriptionManager.prewarm()
    }

    /// Run once on launch: auto-enable launch-at-login the first time, then
    /// sync the published mirror to the live OS status.
    func bootstrapLaunchAtLogin() {
        LaunchAtLoginManager.performFirstRunEnableIfNeeded()
        launchAtLogin = LaunchAtLoginManager.isEnabled
    }

    /// Toggle launch-at-login. Re-reads the OS status afterward so the UI shows
    /// the real state, and routes any failure through the HUD error path.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
        } catch {
            SystemActions.errorHandler?("Couldn't \(enabled ? "enable" : "disable") Launch at Login: \(error.localizedDescription)")
        }
        launchAtLogin = LaunchAtLoginManager.isEnabled
    }

    private func ensureAccessibilityOnceForLaunch() {
        let defaults = UserDefaults.standard
        let key = "jvoice.app.didPromptAXOnLaunch"
        let trusted = AXIsProcessTrusted()
        if trusted {
            defaults.set(false, forKey: key)   // reset so a future revocation triggers prompt
            return
        }
        let hasPrompted = defaults.bool(forKey: key)
        guard Self.shouldPromptAX(trusted: trusted, hasPrompted: hasPrompted) else { return }
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)
        defaults.set(true, forKey: key)
    }

    private func installFrontmostObserver() {
        let center = NSWorkspace.shared.notificationCenter
        frontmostObserver = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                           object: nil,
                           queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            guard app.processIdentifier != ownPID else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.lastNonSelfFrontmostPID = pid
            }
        }
    }

    func toggleRecording() {
        // Both flags flip synchronously on the main actor, so a re-entry
        // from a fast hotkey press will short-circuit here rather than
        // double-dispatching a startRecordingFlow / stopRecordingAndTranscribe.
        if isRecording {
            guard !isStoppingRecording else { return }
            isStoppingRecording = true
            Task { [weak self] in
                defer { Task { @MainActor [weak self] in self?.isStoppingRecording = false } }
                self?.stopRecordingAndTranscribe()
            }
        } else {
            guard !isStartingRecording else { return }
            guard !transcriptionManager.isTranscribing else { return }
            isStartingRecording = true
            // P1.7: abandon any transcription still running for an earlier recording.
            currentTranscriptionTask?.cancel()
            currentTranscriptionTask = nil
            Task { [weak self] in
                defer { Task { @MainActor [weak self] in self?.isStartingRecording = false } }
                await self?.startRecordingFlow()
            }
        }
    }

    func showSettings() {
        openSettingsWindow()
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(coordinator: self)
        }
        settingsWindow?.show()
    }

    func quitApp() {
        cleanUpForTermination()
        updateHUD(.idle)
        NSApp.terminate(nil)
    }

    /// Idempotent exit cleanup: stop an in-flight recording and remove the
    /// abandoned WAV so a quit mid-recording (via any path — menu Quit, Cmd+Q,
    /// logout) never orphans audio. A no-op when not recording / nothing to
    /// remove, so it's safe to call more than once (quitApp → terminate →
    /// applicationWillTerminate).
    func cleanUpForTermination() {
        hudDismissTask?.cancel()

        if isRecording {
            if let session = streamingSession {
                streamingSession = nil
                Task { await session.cancel() }
            }
            // Privacy: don't orphan the in-flight WAV in the temp directory —
            // a quit mid-recording means the user abandoned that audio.
            if let abandonedAudio = recordingManager.stopRecording() {
                try? FileManager.default.removeItem(at: abandonedAudio)
            }
            isRecording = false
        }
    }

    func updateHUD(_ state: HUDState) {
        hudState = state
        hudWindow.update(state: state)
        // The menu bar mirrors the HUD so progress stays visible even when
        // the pill is dismissed or off-screen.
        switch state {
        case .recording:
            menuBarController.updateActivity(.recording)
        case .preparingModel, .transcribing:
            menuBarController.updateActivity(.transcribing)
        case .idle, .done, .error:
            menuBarController.updateActivity(.idle)
        }
    }

    /// Re-render theme-dependent surfaces when the user flips the sun/moon
    /// toggle. The Settings SwiftUI view re-renders automatically (it observes
    /// `appTheme` via `@ObservedObject`); the HUD pill and the Settings
    /// NSWindow chrome need an explicit nudge.
    private func applyTheme() {
        settingsWindow?.appearance = NSAppearance(named: appTheme == .dark ? .darkAqua : .aqua)
        // HUD restyle wired in Task 13 (update(state:theme:meter:)).
    }

    /// Surface a transient error in the HUD and auto-dismiss after the
    /// usual delay.
    func showError(_ message: String) {
        updateHUD(.error(message))
        scheduleHUDReset(after: 3_000_000_000)
    }

    /// Single funnel for specific dictation failures — guarantees the HUD never
    /// shows a generic message and the copy stays in one tested place.
    private func show(_ error: DictationError) {
        updateHUD(.error(error.message))
        scheduleHUDReset(after: 3_000_000_000)
    }

    /// Map a thrown transcription error to a specific user-facing failure.
    private func dictationError(for error: Error) -> DictationError {
        if let t = error as? TranscriptionError {
            switch t {
            case .emptyTranscript:
                return .noSpeechHeard
            case .modelLoadFailed:
                return .modelLoadFailed
            case .audioFileMissing, .unsupportedAudioFile:
                return .transcriptionFailed
            }
        }
        return .transcriptionFailed
    }

    /// Synchronously flush any pending debounced settings write.
    /// Called from `applicationWillTerminate` so the last keystrokes
    /// aren't lost when the user quits mid-debounce.
    func flushSettings() {
        settingsStore.flush()
    }

    /// Reset all persisted settings to defaults and re-pull every
    /// @Published mirror so the UI reflects the fresh state. The
    /// `isInitializing` guard suppresses the cascade of didSet →
    /// persistSettings writes that would otherwise re-encode the blob
    /// N times during reset. A final explicit `flush()` persists the
    /// freshly-defaulted state.
    public func resetSettings() {
        isInitializing = true
        settingsStore.reset()
        toneMode = ToneMode(appMode: settingsStore.state.mode)
        whisperModel = WhisperModelChoice(model: settingsStore.state.model)
        transcriptionLanguage = settingsStore.state.language
        customWords = settingsStore.state.customWords
        removeFillerWords = settingsStore.state.removeFillerWords
        appTheme = settingsStore.state.theme
        isInitializing = false
        settingsStore.flush()
        // A reset is an explicit user action, so also clear the persisted
        // plaintext transcript and the corruption-recovery backup blob.
        clearLastTranscript()
        settingsStore.clearCorruptBackup()
    }

    private func handleHotKeyToggle() async {
        toggleRecording()
    }

    private func startRecordingFlow() async {
        hudDismissTask?.cancel()

        let granted = await recordingManager.requestPermission()
        guard granted else {
            PermissionError.microphoneDenied.surfaceAndOpenSettings()
            return
        }

        guard AudioInputRouter.hasInputDevice() else {
            show(.noMicrophone)
            return
        }

        guard recordingManager.startRecording() else {
            if let err = recordingManager.lastError {
                switch err {
                case .permissionDenied:
                    PermissionError.microphoneDenied.surfaceAndOpenSettings()
                    return
                case .engineSetupFailed:
                    show(.recorderFailedToStart)
                case .encodeFailure, .finishedUnsuccessfully:
                    show(.recordingInterrupted)
                case .fileTooSmall:
                    show(.recordingTooShort)
                }
            } else {
                show(.recorderFailedToStart)
            }
            return
        }

        isRecording = true
        recordingGeneration += 1
        recordingStartDate = Date()
        updateHUD(.recording)

        // Best-effort streaming overlay: transcribe completed chunks while the
        // user is still talking so only the tail remains on hotkey release.
        // nil when the engine has no loaded model — never trigger a load here.
        if let url = recordingManager.recordedURL {
            let generation = recordingGeneration
            Task { [weak self] in
                guard let self else { return }
                let session = await self.transcriptionManager.makeStreamingSession()
                // (MainActor) the recording may have stopped — or a NEWER one
                // started — during the await; a stale session must never be
                // assigned, or recording N's session (bound to N's deleted WAV)
                // could shadow recording N+1's.
                guard self.isRecording, self.recordingGeneration == generation else {
                    if let session { await session.cancel() }
                    return
                }
                self.streamingSession = session
                if let session {
                    await session.start(url: url)
                }
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else {
            return
        }

        isRecording = false
        lastRecordingDuration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartDate = nil

        let audioURL = recordingManager.stopRecording()
        let session = streamingSession
        streamingSession = nil
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let resolvedTargetPID = Self.resolveTargetPID(frontmostPID: frontmost?.processIdentifier,
                                                       ownPID: ownPID,
                                                       lastNonSelfPID: lastNonSelfFrontmostPID)
        guard let targetPID = resolvedTargetPID else {
            show(.noTextFieldFocused)
            if let audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            if let session {
                Task { await session.cancel() }
            }
            return
        }
        updateHUD(.transcribing)

        currentTranscriptionTask?.cancel()
        currentTranscriptionTask = Task { [weak self] in
            await self?.finishTranscription(audioURL: audioURL, targetPID: targetPID, session: session)
        }
    }

    private func finishTranscription(audioURL: URL?, targetPID: pid_t?, session: StreamingTranscriptionSession? = nil) async {
        guard let audioURL else {
            if let session { await session.cancel() }
            show(.recorderFailedToStart)
            return
        }

        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard RecordingManager.isUsableRecording(at: audioURL) else {
            // The user tapped+released too fast to capture audio. Surface a clear
            // message instead of waiting for WhisperKit to fail with an opaque
            // 'unsupportedAudioFile' several seconds later.
            if let session { await session.cancel() }
            show(.recordingTooShort)
            return
        }

        if RecordingManager.isSilentRecording(at: audioURL) {
            if let session { await session.cancel() }
            show(.noSpeechHeard)
            return
        }

        // If the model isn't loaded yet (first dictation after launch, a model
        // switch, or the Large model's first-ever multi-minute CoreML
        // specialization), tell the user instead of showing a silent
        // "Transcribing…" hang.
        if await !transcriptionManager.isEngineReady() {
            updateHUD(.preparingModel)
            await transcriptionManager.prewarmAndWait()
            if Task.isCancelled { return }
            updateHUD(.transcribing)
        }

        do {
            let transcript: String
            if let session, let streamed = await session.finish() {
                // Chunks were decoded while the user was talking; finish()
                // handled the tail (plus any backlog the poll loop didn't get
                // to). nil (failed/cancelled/never-streamed/all-silence) falls
                // back to the whole-file path below — worst case is exactly
                // today's behavior.
                transcript = streamed
            } else {
                transcript = try await transcriptionManager.transcribe(audioURL: audioURL)
            }
            if Task.isCancelled {
                // The user moved on; don't paste into whatever app is now frontmost.
                return
            }
            let userDict = TextProcessor.buildUserDictionary(from: customWords)
            let processed = removeBlankTranscriptPlaceholder(from: TextProcessor.process(transcript, mode: toneMode.appMode, extraDictionary: userDict, removeFillerWords: removeFillerWords, vocabulary: customWords))

            guard !processed.isEmpty else {
                show(.noSpeechHeard)
                return
            }

            // Bring the target app back to focus before synthesizing Cmd+V.
            // WhisperKit can take several seconds; the window may have lost key status.
            if let pid = targetPID,
               let targetApp = NSRunningApplication(processIdentifier: pid) {
                targetApp.activate()
                try? await Task.sleep(nanoseconds: UInt64(AppTimings.pasteActivationDelay * 1_000_000_000))
            }

            let outcome: PasteOutcome
            if let pid = targetPID {
                outcome = pasteManager.paste(processed, targetPID: pid)
            } else {
                outcome = pasteManager.paste(processed)
            }

            switch outcome {
            case .ok:
                break
            case .accessibilityDenied:
                PermissionError.accessibilityDenied.surfaceAndOpenSettings()
                scheduleHUDReset()
                return
            case .pasteboardLocked:
                show(.clipboardBusy)
                return
            case .targetRejected:
                show(.pasteFailed)
                return
            }

            let wordCount = processed.split(separator: " ").count
            lastTranscriptStore.transcript = processed
            lastTranscript = processed
            recentTranscripts = transcriptHistoryStore.add(processed)
            statsStore.record(words: wordCount, durationSeconds: lastRecordingDuration)
            totalWordsSpoken = statsStore.totalWords
            averageWPM = statsStore.averageWPM

            updateHUD(.done(processed))
            scheduleHUDReset()
        } catch {
            show(dictationError(for: error))
        }
    }

    private func removeBlankTranscriptPlaceholder(from text: String) -> String {
        return TextProcessor.removeWhisperHallucinations(text)
    }

    private func scheduleHUDReset(after delayNanoseconds: UInt64 = 1_000_000_000) {
        hudDismissTask?.cancel()
        hudDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.updateHUD(.idle)
        }
    }

    private func persistSettings() {
        guard !isInitializing else { return }
        var s = settingsState
        s.mode = toneMode.appMode
        s.model = whisperModel.modelOption
        s.language = transcriptionLanguage
        s.customWords = customWords
        s.removeFillerWords = removeFillerWords
        s.theme = appTheme
        settingsStore.state = s
        settingsState = s
    }

    // NOTE: comma-splitting (e.g. "React, Swift" → two entries) is deliberately
    // NOT done here — it's a separate behavior decision (see UI-09).
    @discardableResult
    func addCustomWord(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 60 else { return nil }
        guard trimmed.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        guard !customWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        customWords.append(trimmed)
        return trimmed
    }

    func removeCustomWord(_ word: String) {
        customWords.removeAll { $0 == word }
    }

    func fixLastTranscript(_ corrected: String) {
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        preFixTranscript = lastTranscript
        let newWords = TextProcessor.extractCorrections(from: lastTranscript, corrected: trimmed)
        var inserted: [String] = []
        for word in newWords {
            if let added = addCustomWord(word) {
                inserted.append(added)
            }
        }
        pendingRevertWords = inserted
        canRevert = !inserted.isEmpty

        lastTranscriptStore.transcript = trimmed
        lastTranscript = trimmed
    }

    func revertLastFix() {
        for word in pendingRevertWords {
            removeCustomWord(word)
        }
        pendingRevertWords = []
        canRevert = false
        lastTranscript = preFixTranscript
        lastTranscriptStore.transcript = preFixTranscript
        preFixTranscript = ""
    }

    func clearRevertBuffer() {
        pendingRevertWords = []
        canRevert = false
    }

    /// Erase the persisted last transcript (privacy: it's stored in plaintext
    /// prefs). Clears the in-memory mirror, the recent-transcript history, and
    /// the revert buffer too.
    func clearLastTranscript() {
        lastTranscriptStore.transcript = ""
        lastTranscript = ""
        clearTranscriptHistory()
        clearRevertBuffer()
    }

    /// Remove a single transcript from the recent-history list.
    func deleteTranscript(_ id: UUID) {
        recentTranscripts = transcriptHistoryStore.remove(id: id)
    }

    /// Empty the recent-transcript history (privacy: plaintext in prefs).
    func clearTranscriptHistory() {
        transcriptHistoryStore.clear()
        recentTranscripts = []
    }

    /// Copy a transcript back onto the system clipboard for reuse.
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Decide which app the transcription should be pasted into. Mirrors the
    /// original inline logic exactly: use the frontmost app's PID unless it's
    /// our own process, in which case fall back to the last non-self frontmost
    /// PID (nil when none was ever recorded).
    static func resolveTargetPID(frontmostPID: pid_t?, ownPID: pid_t, lastNonSelfPID: pid_t?) -> pid_t? {
        if let frontmostPID, frontmostPID != ownPID {
            return frontmostPID
        } else {
            return lastNonSelfPID
        }
    }

    /// Whether to surface the one-shot Accessibility prompt: only when the
    /// process isn't already trusted and hasn't been prompted this launch.
    static func shouldPromptAX(trusted: Bool, hasPrompted: Bool) -> Bool {
        return !trusted && !hasPrompted
    }

    private static func makeTranscriptionEngine(for model: WhisperModelOption, language: TranscriptionLanguage = .english, vocabulary: [String] = []) -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperKitTranscriptionEngine(model: model, language: language, vocabulary: vocabulary)
        #else
        return FileBackedTranscriptionEngine()
        #endif
    }
}

private extension ToneMode {
    init(appMode: AppMode) {
        switch appMode {
        case .casual:
            self = .casual
        case .formal:
            self = .formal
        case .veryCasual:
            self = .veryCasual
        }
    }

    var appMode: AppMode {
        switch self {
        case .casual:
            return .casual
        case .formal:
            return .formal
        case .veryCasual:
            return .veryCasual
        }
    }
}

private extension WhisperModelChoice {
    init(model: WhisperModelOption) {
        switch model {
        case .tiny:
            self = .tiny
        case .base:
            self = .base
        case .small:
            self = .small
        case .largeTurbo:
            self = .largeTurbo
        }
    }

    var modelOption: WhisperModelOption {
        switch self {
        case .tiny:
            return .tiny
        case .base:
            return .base
        case .small:
            return .small
        case .largeTurbo:
            return .largeTurbo
        }
    }
}
