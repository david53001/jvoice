import AppKit
import ApplicationServices
import Combine
import Foundation
import os

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
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords, translate: translateToEnglish))
            persistSettings()
        }
    }

    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords, translate: translateToEnglish))
            persistSettings()
        }
    }

    /// Dictate-to-translate: rebuild the engine (like a language change), then persist.
    @Published var translateToEnglish: Bool {
        didSet {
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords, translate: translateToEnglish))
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

    /// Opt-out curated developer-terms correction pack (post-processing only).
    @Published var developerTerms: Bool {
        didSet {
            persistSettings()
        }
    }

    /// Opt-out spoken-mathematics conversion (post-processing only).
    @Published var mathNotation: Bool {
        didSet {
            persistSettings()
        }
    }

    /// Copy the transcript to the clipboard instead of auto-pasting it.
    @Published var copyToClipboardOnly: Bool {
        didSet {
            persistSettings()
        }
    }

    /// Auto-switch tone by the target app (post-processing only; no engine reload).
    @Published var appAwareModes: Bool {
        didSet {
            persistSettings()
        }
    }

    /// Per-app tone rules (built-in code apps are implicit in `AppModeResolver`).
    @Published var appModeRules: [AppModeRule] {
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
    @Published private(set) var minutesSaved: Double = 0

    private let settingsStore: SettingsStore
    private let recordingManager: RecordingManager
    private let transcriptionManager: TranscriptionManager
    private let pasteManager: PasteManager
    private let statsStore = StatsStore()
    private lazy var hotKeyManager: HotKeyManager = {
        HotKeyManager(shortcutName: .toggleRecording) { [weak self] in
            // KeyboardShortcuts delivers on the main queue: take the press
            // synchronously — no extra actor hop between the key and the pill.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.toggleRecording() }
            } else {
                Task { @MainActor in self?.toggleRecording() }
            }
        }
    }()
    /// Latency instrumentation (read with `/usr/bin/log show --predicate
    /// 'subsystem == "com.jvoice.app"'`): restarted on each press — start AND
    /// stop — so the log reports press→mic-started and stop→transcript/pasted/done.
    private static let latencyLog = Logger(subsystem: "com.jvoice.app", category: "latency")
    private var pressedAt: DispatchTime = .now()
    private var millisecondsSincePress: Int {
        Int((DispatchTime.now().uptimeNanoseconds &- pressedAt.uptimeNanoseconds) / 1_000_000)
    }
    /// Second global hook for the opt-in "undo last paste" chord (unset by default
    /// → disabled until the user assigns one via the Settings recorder).
    private lazy var undoHotKeyManager: HotKeyManager = {
        HotKeyManager(shortcutName: .undoLastPaste) { [weak self] in
            Task { @MainActor in self?.undoLastPaste() }
        }
    }()
    /// One-shot undo record set on a successful paste (unset for clipboard-only);
    /// the undo hotkey only fires while `lastPastedPID` is still frontmost.
    private var lastPastedText: String = ""
    private var lastPastedPID: pid_t?
    private var hudDismissTask: Task<Void, Never>?
    private var currentTranscriptionTask: Task<Void, Never>?
    /// True from the stop press until `finishTranscription` returns — the whole
    /// post-stop pipeline, not just the whole-file decode. Blocks new starts.
    private var isTranscriptionInFlight = false
    /// The finished recording's WAV while it is being transcribed, so a quit
    /// mid-transcription can delete it (the task's own cleanup never runs then).
    private var inFlightAudioURL: URL?
    /// A press arrived while the mic was still opening: end that recording as
    /// soon as it opens (the pill already said "recording", so it was a stop).
    private var stopRequestedWhileStarting = false
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
            engine: Self.makeTranscriptionEngine(for: settingsStore.state.model, language: settingsStore.state.language, vocabulary: settingsStore.state.customWords, translate: settingsStore.state.translateToEnglish)
        )
        self.pasteManager = PasteManager()
        self.settingsState = settingsStore.state
        self.toneMode = ToneMode(appMode: settingsStore.state.mode)
        self.whisperModel = WhisperModelChoice(model: settingsStore.state.model)
        self.transcriptionLanguage = settingsStore.state.language
        self.translateToEnglish = settingsStore.state.translateToEnglish
        self.customWords = settingsStore.state.customWords
        self.removeFillerWords = settingsStore.state.removeFillerWords
        self.developerTerms = settingsStore.state.developerTerms
        self.mathNotation = settingsStore.state.mathNotation
        self.copyToClipboardOnly = settingsStore.state.copyToClipboardOnly
        self.appAwareModes = settingsStore.state.appAwareModes
        self.appModeRules = settingsStore.state.appModeRules
        self.appTheme = settingsStore.state.theme
        self.totalWordsSpoken = statsStore.totalWords
        self.averageWPM = statsStore.averageWPM
        self.minutesSaved = statsStore.estimatedMinutesSaved
        self.lastTranscript = lastTranscriptStore.transcript
        self.recentTranscripts = transcriptHistoryStore.entries
        self.isInitializing = false
    }

    deinit {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
    }

    /// Set before `start()` when the first-run Welcome window will show: it asks for Accessibility
    /// itself, so the launch-time system prompt would only stack a second dialog on top of it.
    var suppressLaunchAccessibilityPrompt = false

    func start() {
        guard !didStart else { return }
        didStart = true

        // Privacy: clear any recordings orphaned by a crash/force-quit.
        RecordingManager.sweepOrphanedRecordings()

        installFrontmostObserver()

        hudWindow.onStop = { [weak self] in self?.toggleRecording() }
        recordingManager.onRecordingFailed = { [weak self] _ in
            self?.handleRecordingFailure()
        }

        ensureAccessibilityOnceForLaunch()

        hotKeyManager.register()
        undoHotKeyManager.register()
        menuBarController.installStatusItem()
        updateHUD(.idle)

        // Zero-latency HUD: realize the pill's window once now (transparent,
        // never seen) so the first press pays a re-show, not window-server
        // surface creation + the hosting view's first layout; and warm the
        // audio stack's cold-start costs (first TCC lookup, first Core Audio
        // device enumeration) off the main thread.
        hudWindow.prewarm()
        RecordingManager.prewarmAudioStack()
        recordingManager.prepareSpareRecorder()

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
        guard !suppressLaunchAccessibilityPrompt else { return }
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
        // Every flag flips synchronously on the main actor, so a re-entry
        // from a fast hotkey press short-circuits here rather than
        // double-dispatching a startRecordingFlow / stopRecordingAndTranscribe.
        // The menu's Start/Stop Dictation item and the pill's stop button come
        // through here too, so they obey the same rules.
        //
        // A pending transcript outranks a new start request:
        // `transcriptionManager.isTranscribing` alone covers only the whole-file
        // decode, so a press during the streaming session's finish(), the
        // model-preparation wait or the paste used to start a new recording and
        // cancel the finished dictation (Windows §7 #44).
        let transcribing = isTranscriptionInFlight || transcriptionManager.isTranscribing
        switch CoordinatorDecisions.pressAction(isRecording: isRecording,
                                                isStartingRecording: isStartingRecording,
                                                isStoppingRecording: isStoppingRecording,
                                                isTranscribing: transcribing) {
        case .ignore:
            if !isRecording, transcribing {
                Self.latencyLog.info("Start press IGNORED — transcription in flight")
            }
        case .stopOnceOpened:
            stopRequestedWhileStarting = true
            Self.latencyLog.info("Stop press while the mic is opening — the recording ends once it opens")
        case .stop:
            isStoppingRecording = true
            Task { [weak self] in
                defer { Task { @MainActor [weak self] in self?.isStoppingRecording = false } }
                self?.stopRecordingAndTranscribe()
            }
        case .start:
            isStartingRecording = true
            stopRequestedWhileStarting = false
            // P1.7: abandon any transcription still running for an earlier recording.
            currentTranscriptionTask?.cancel()
            currentTranscriptionTask = nil
            // Zero-latency HUD: show the pill NOW, synchronously on the press,
            // BEFORE any microphone work. It used to appear only after the
            // permission round trip + device enumeration + AVAudioRecorder
            // start had all completed (tens to hundreds of ms, worse under
            // load). The mic open now runs off the main actor; a failure
            // replaces the pill with the error.
            pressedAt = .now()
            hudDismissTask?.cancel()
            updateHUD(.recording)
            Task { [weak self] in
                defer { Task { @MainActor [weak self] in self?.isStartingRecording = false } }
                await self?.startRecordingFlow()
            }
        }
    }

    /// The recorder tore a live recording down (encoder error, unsuccessful
    /// finish, input change) and already deleted its partial WAV. End our side
    /// of the recording and say so — otherwise the pill stays on "recording"
    /// and the next press reports "Couldn't start recording".
    private func handleRecordingFailure() {
        guard isRecording else { return }
        isRecording = false
        recordingStartDate = nil
        if let session = streamingSession {
            streamingSession = nil
            Task { await session.cancel() }
        }
        show(.recordingInterrupted)
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
        recordingManager.discardSpareRecorder()

        // Privacy: a quit while the previous dictation is still being
        // transcribed would orphan its WAV — the task's own cleanup never runs
        // once the process exits.
        if let pendingAudio = inFlightAudioURL {
            inFlightAudioURL = nil
            currentTranscriptionTask?.cancel()
            try? FileManager.default.removeItem(at: pendingAudio)
        }

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
        hudWindow.update(state: state, theme: appTheme, meter: recordingManager.levelMeter)
        // The menu bar mirrors the HUD so progress stays visible even when
        // the pill is dismissed or off-screen.
        switch state {
        case .recording:
            menuBarController.updateActivity(.recording)
        case .downloadingModel, .preparingModel, .transcribing:
            menuBarController.updateActivity(.transcribing)
        case .idle, .done, .copied, .error, .notice:
            menuBarController.updateActivity(.idle)
        }
    }

    /// Keep the HUD honest while the model loads. The wait has two very
    /// different halves and the user needs to tell them apart: a model folder
    /// that is missing or half-fetched means we are downloading it (hundreds of
    /// megabytes, needs the network), and once it is complete on disk the
    /// remaining wait is the CoreML/Neural-Engine compile. Collapsing both into
    /// one static label is what made a silent 632 MB fetch read as a hang.
    ///
    /// Polls once a second because neither half publishes progress we can
    /// subscribe to — see `ModelDownloadProgress` for why WhisperKit's own
    /// `Progress` is unusable here. Cancelled by the caller once the load ends.
    private func startModelPreparationHUD() -> Task<Void, Never> {
        let model = whisperModel.modelOption
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateHUD(Self.modelPreparationState(for: model))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private static func modelPreparationState(for model: WhisperModelOption) -> HUDState {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .preparingModel
        }
        let folderName = model.whisperKitFolderName
        if WhisperModelLocator.completeModelFolder(named: folderName, documentsDirectory: documents) != nil {
            return .preparingModel
        }
        return .downloadingModel(
            downloadedBytes: ModelDownloadProgress.downloadedBytes(folderName: folderName, documentsDirectory: documents),
            totalBytes: model.approximateDownloadBytes
        )
    }

    /// Re-render theme-dependent surfaces when the user picks System / Light /
    /// Dark. The Settings SwiftUI view re-renders automatically (it observes
    /// `appTheme` via `@ObservedObject`); the HUD pill and the Settings
    /// NSWindow chrome need an explicit nudge.
    private func applyTheme() {
        settingsWindow?.appearance = appTheme.nsAppearance
        hudWindow.update(state: hudState, theme: appTheme, meter: recordingManager.levelMeter)
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
        translateToEnglish = settingsStore.state.translateToEnglish
        customWords = settingsStore.state.customWords
        removeFillerWords = settingsStore.state.removeFillerWords
        developerTerms = settingsStore.state.developerTerms
        mathNotation = settingsStore.state.mathNotation
        copyToClipboardOnly = settingsStore.state.copyToClipboardOnly
        appAwareModes = settingsStore.state.appAwareModes
        appModeRules = settingsStore.state.appModeRules
        appTheme = settingsStore.state.theme
        isInitializing = false
        settingsStore.flush()
        // A reset is an explicit user action, so also clear the persisted
        // plaintext transcript and the corruption-recovery backup blob.
        clearLastTranscript()
        settingsStore.clearCorruptBackup()
    }

    /// Everything after the pill is already on screen (see `toggleRecording`):
    /// the permission fast path, the device check and the off-main-actor mic
    /// open. Any failure replaces the recording pill with the error, exactly
    /// as it used to appear instead of it.
    private func startRecordingFlow() async {
        // A stop press during the open applies to THIS start only.
        defer { stopRequestedWhileStarting = false }
        let granted = await recordingManager.requestPermission()
        guard granted else {
            PermissionError.microphoneDenied.surfaceAndOpenSettings()
            return
        }

        guard AudioInputRouter.hasInputDevice() else {
            show(.noMicrophone)
            return
        }

        guard await recordingManager.startRecording() else {
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
        // The pill went up on the press; only re-assert it if something
        // (a surfaced error) replaced it meanwhile.
        if hudState != .recording { updateHUD(.recording) }
        Self.latencyLog.info("MicStarted +\(self.millisecondsSincePress, privacy: .public)ms after press")

        // Tours: the pill is up and the mic is open — only now does this count as
        // a started recording (a failed open above posts nothing). Deferred to the
        // next main-queue turn so tour-tag window work never runs on the
        // press → pill → mic path. The pill tour only attaches while THIS recording
        // is still on screen (a stop pressed while the mic opened ends it below).
        let tourGeneration = recordingGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            TourEvents.post(.action(TourEventName.recordingStarted))
            if self.isRecording, self.recordingGeneration == tourGeneration, self.hudState == .recording {
                TourEvents.surfaceShown(.recordingPill, in: self.hudWindow)
            }
        }

        // The user pressed stop while the mic was still opening: honour it now.
        if stopRequestedWhileStarting {
            stopRecordingAndTranscribe()
            return
        }

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
        pressedAt = .now()

        let session = streamingSession
        streamingSession = nil
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let resolvedTargetPID = Self.resolveTargetPID(frontmostPID: frontmost?.processIdentifier,
                                                       ownPID: ownPID,
                                                       lastNonSelfPID: lastNonSelfFrontmostPID)
        guard let targetPID = resolvedTargetPID else {
            show(.noTextFieldFocused)
            if let abandoned = recordingManager.stopRecording() {
                try? FileManager.default.removeItem(at: abandoned)
            }
            if let session {
                Task { await session.cancel() }
            }
            return
        }
        // Tours: the pill tour's Try step completes on this — it must be posted
        // while the pill still shows the recording row (its anchor), or the
        // tour pauses instead of finishing.
        TourEvents.post(.action(TourEventName.recordingStopped))
        // The pill switches to "transcribing" BEFORE the recorder is stopped
        // (the stop finalizes the WAV — ~10 ms of coreaudiod teardown that no
        // longer delays the state change the user is waiting to see).
        updateHUD(.transcribing)
        let audioURL = recordingManager.stopRecording()
        Self.latencyLog.info("RecorderStopped +\(self.millisecondsSincePress, privacy: .public)ms after press  recSecs=\(self.lastRecordingDuration, format: .fixed(precision: 2), privacy: .public)  streaming=\(session != nil, privacy: .public)")

        // Capture the paste target's bundle id now (for app-aware modes) — the
        // frontmost app may change while WhisperKit runs.
        let targetBundleId = NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier
        let captureDeviceName = recordingManager.captureDeviceName

        currentTranscriptionTask?.cancel()
        isTranscriptionInFlight = true
        inFlightAudioURL = audioURL
        currentTranscriptionTask = Task { [weak self] in
            await self?.finishTranscription(audioURL: audioURL, targetPID: targetPID, targetBundleId: targetBundleId, session: session, captureDeviceName: captureDeviceName)
            // Every exit path of finishTranscription (paste, error, no speech,
            // cancellation) lands here, so the start branch always re-opens.
            self?.isTranscriptionInFlight = false
            self?.inFlightAudioURL = nil
        }
    }

    private func finishTranscription(audioURL: URL?, targetPID: pid_t?, targetBundleId: String? = nil, session: StreamingTranscriptionSession? = nil, captureDeviceName: String? = nil) async {
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
            // Already judged silent — this only picks the wording: a capture of
            // exact-zero samples is a dead INPUT (e.g. BlackHole as the default
            // mic), so name the device instead of blaming the user's voice.
            showError(SilentCaptureDetector.noSpeechMessage(
                stats: RecordingManager.captureSignalStats(at: audioURL),
                deviceName: captureDeviceName))
            return
        }

        // If the model isn't loaded yet (first dictation after launch, a model
        // switch, or the Large model's first-ever multi-minute CoreML
        // specialization), tell the user instead of showing a silent
        // "Transcribing…" hang.
        if await !transcriptionManager.isEngineReady() {
            let progress = startModelPreparationHUD()
            // The poll is an unstructured task, so cancelling THIS task doesn't
            // reach it: without the handler it would keep repainting "Preparing
            // model…" over whatever the HUD shows next until the load ends.
            await withTaskCancellationHandler {
                await transcriptionManager.prewarmAndWait()
            } onCancel: {
                progress.cancel()
            }
            progress.cancel()
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
            let transcribedMs = millisecondsSincePress
            // App-aware modes: dictate under the target app's tone (a user rule,
            // or a built-in code app → Code) instead of the global one; gated on
            // the master toggle so the bundle-id probe is skipped when off.
            let effectiveMode = appAwareModes
                ? (AppModeResolver.resolve(bundleId: targetBundleId, userRules: appModeRules, enabled: true) ?? toneMode.appMode)
                : toneMode.appMode
            let userDict = TextProcessor.buildUserDictionary(from: customWords)
            // Lay the curated developer-terms pack UNDER the user's own custom-word
            // variants (their words win); the built-in dictionary still wins over both.
            let extra = developerTerms ? DeveloperTerms.augment(userDict) : userDict
            let styled = removeBlankTranscriptPlaceholder(from: TextProcessor.process(transcript, mode: effectiveMode, extraDictionary: extra, removeFillerWords: removeFillerWords, vocabulary: customWords))
            // Spoken mathematics runs LAST, deliberately: tone, filler removal and the
            // correction packs are all word-based, so no symbol this produces can be
            // mangled by them. When nothing in the text is mathematics `convert` hands
            // back the very same string (see MathSpeech's activation rules).
            let processed = mathNotation ? MathSpeech.convert(styled) : styled

            guard !processed.isEmpty else {
                show(.noSpeechHeard)
                return
            }

            var completedState: HUDState = .done(processed)
            if copyToClipboardOnly {
                // Clipboard-only: put the text on the clipboard and stop — the user
                // pastes it themselves. No Cmd+V is synthesized, so this path needs
                // NO Accessibility trust. Nothing landed in an app, so the undo
                // record stays unset.
                pasteManager.copyOnly(processed)
                completedState = .copied(processed)
            } else {
                // Bring the target app back to focus before synthesizing Cmd+V —
                // but ONLY if it lost it. It nearly always is still frontmost (the
                // user dictates into the app they're in), and this activate + settle
                // pair was a fixed 80 ms on every paste. When the user did switch
                // away during a long decode, the old path runs unchanged.
                if let pid = targetPID,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier != pid,
                   let targetApp = NSRunningApplication(processIdentifier: pid) {
                    targetApp.activate()
                    try? await Task.sleep(nanoseconds: UInt64(AppTimings.pasteActivationDelay * 1_000_000_000))
                    // `try?` swallows a cancellation: re-check before pasting.
                    if Task.isCancelled { return }
                }

                let outcome: PasteOutcome
                if let pid = targetPID {
                    outcome = pasteManager.paste(processed, targetPID: pid)
                } else {
                    outcome = pasteManager.paste(processed)
                }

                switch outcome {
                case .ok:
                    // Remember the paste (and where it landed) so the opt-in undo
                    // hotkey can reverse it, but only while that app stays frontmost.
                    if let pid = targetPID {
                        lastPastedText = processed
                        lastPastedPID = pid
                    }
                case .accessibilityDenied:
                    // Never lose the dictation: the clipboard needs no
                    // Accessibility, so leave the text there for a manual ⌘V.
                    keepUnpastedTranscript(processed)
                    PermissionError.accessibilityDenied.surfaceAndOpenSettings()
                    // The usual 3 s like every other error (this was a 1 s reset
                    // that cut the permission message short).
                    scheduleHUDReset(after: 3_000_000_000)
                    return
                case .pasteboardLocked:
                    show(.clipboardBusy)
                    return
                case .targetRejected:
                    keepUnpastedTranscript(processed)
                    show(.pasteFailed)
                    return
                }
            }

            // The text is in the user's app: flip the pill FIRST, then do the
            // bookkeeping (three UserDefaults writes + history) behind it.
            let pastedMs = millisecondsSincePress
            updateHUD(completedState)
            scheduleHUDReset()
            Self.latencyLog.info("Timing stop->transcript=\(transcribedMs, privacy: .public)ms stop->pasted=\(pastedMs, privacy: .public)ms stop->done=\(self.millisecondsSincePress, privacy: .public)ms recSecs=\(self.lastRecordingDuration, format: .fixed(precision: 2), privacy: .public)")

            let wordCount = processed.split(separator: " ").count
            rememberTranscript(processed)
            statsStore.record(words: wordCount, durationSeconds: lastRecordingDuration)
            totalWordsSpoken = statsStore.totalWords
            averageWPM = statsStore.averageWPM
            minutesSaved = statsStore.estimatedMinutesSaved
            // Tours: the text reached the user (pasted, or "Copied" in
            // clipboard-only mode). Failed pastes returned above without it.
            TourEvents.post(.action(TourEventName.dictationPasted))
        } catch {
            // A cancelled decode throws; the user moved on — no error pill.
            if Task.isCancelled || error is CancellationError { return }
            show(dictationError(for: error))
        }
    }

    /// Record a finished transcript as the last transcript + history entry.
    private func rememberTranscript(_ text: String) {
        lastTranscriptStore.transcript = text
        lastTranscript = text
        recentTranscripts = transcriptHistoryStore.add(text)
    }

    /// A paste that failed must not lose the dictation: put it on the clipboard
    /// (no Accessibility needed; this also cancels the paste's pending clipboard
    /// restore) and keep it in the history / last transcript.
    private func keepUnpastedTranscript(_ text: String) {
        pasteManager.copyOnly(text)
        rememberTranscript(text)
    }

    private func removeBlankTranscriptPlaceholder(from text: String) -> String {
        return TextProcessor.removeWhisperHallucinations(text)
    }

    func scheduleHUDReset(after delayNanoseconds: UInt64 = 1_000_000_000) {
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
        s.developerTerms = developerTerms
        s.mathNotation = mathNotation
        s.translateToEnglish = translateToEnglish
        s.copyToClipboardOnly = copyToClipboardOnly
        s.appAwareModes = appAwareModes
        s.appModeRules = appModeRules
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

    /// Opt-in one-shot: send the target app's own Undo (Cmd+Z) to reverse the last
    /// paste — but only while that same app is still frontmost (so alt-tabbing away
    /// can't undo an unrelated app's edit). Clears the record after firing so a
    /// second press never re-sends. Clipboard-only dictations leave the record
    /// unset, so this is a no-op for them.
    private func undoLastPaste() {
        guard !lastPastedText.isEmpty, let pid = lastPastedPID else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        _ = pasteManager.sendUndo(targetPID: pid)
        lastPastedText = ""
        lastPastedPID = nil
    }

    /// Add a per-app tone rule. No-op when the match is blank or a rule with the
    /// same match (case-insensitive) already exists. Post-processing only.
    @discardableResult
    func addAppModeRule(match: String, mode: AppMode = .code) -> Bool {
        let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !appModeRules.contains(where: { $0.appMatch.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return false }
        appModeRules.append(AppModeRule(appMatch: trimmed, mode: mode))
        return true
    }

    func removeAppModeRule(_ rule: AppModeRule) {
        appModeRules.removeAll { $0 == rule }
    }

    /// Cycle a rule's tone through all four styles (Casual → Formal → Very Casual →
    /// Code → …). Distinct from `AppMode.toggled`, which excludes Code — a per-app
    /// rule is the only place Code is selectable.
    func cycleAppModeRuleMode(_ rule: AppModeRule) {
        guard let idx = appModeRules.firstIndex(where: { $0.appMatch.caseInsensitiveCompare(rule.appMatch) == .orderedSame }) else { return }
        appModeRules[idx].mode = Self.nextAppModeChip(appModeRules[idx].mode)
    }

    private static func nextAppModeChip(_ mode: AppMode) -> AppMode {
        switch mode {
        case .casual: return .formal
        case .formal: return .veryCasual
        case .veryCasual: return .code
        case .code: return .casual
        }
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

    #if DEBUG
    func setTranscriptionInFlightForTesting(_ flag: Bool) { isTranscriptionInFlight = flag }
    #endif

    private static func makeTranscriptionEngine(for model: WhisperModelOption, language: TranscriptionLanguage = .english, vocabulary: [String] = [], translate: Bool = false) -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperKitTranscriptionEngine(model: model, language: language, vocabulary: vocabulary, translate: translate)
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
        // `.code` is only ever an effective per-app override (never the persisted
        // global tone), so it should not reach here; fall back to Casual in the
        // 3-way UI picker if it somehow does.
        case .code:
            self = .casual
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
