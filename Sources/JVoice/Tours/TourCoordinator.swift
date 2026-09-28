import AppKit

/// The app side of JVoice's guided tours (ported from BetterScreenshot, its v3 spec §14 / §14.9). Owns
/// who gets tours, what starts when, persistence, and driving the on-screen tag; the rules themselves
/// are the pure `TourAudience`, `TourRules` and `TourEngine` in `Tours/Kit/`. Surfaces never talk to
/// this class — they post through `TourEvents`. `AppDelegate` creates the one instance and sets the hooks.
///
/// New users only: `classifyAudienceIfNeeded` runs in `JVoiceMain.main()` before anything writes a
/// preference; only a `.new` user is asked "Want a quick tour?" (the Welcome window), and nothing ever
/// starts by itself unless that user said yes (or later turned first-use tours on in Settings).
///
/// Persisted (UserDefaults, `TourPreferenceKey`): `tourAudience`, `tourQuestionAnswered`,
/// `firstUseToursEnabled`, `toursSeen` (tour id → version), `toursPaused` (tour id → step index).
@MainActor
final class TourCoordinator {
    private let defaults: UserDefaults
    private let catalog: [Tour]
    private let makePresenter: () -> TourTagPresenting
    private let shortcutText: (String) -> String?
    /// Opens a surface's window so a tour asked for from the menu can start (Welcome, Settings).
    /// Returns false when that surface can't be opened on demand (the recording pill) — the tour then
    /// waits for the user to get there.
    var openSurface: ((TourSurface) -> Bool)?
    /// A short confirmation for the user (JVoice shows it in the HUD pill).
    var notify: ((String) -> Void)?
    /// A tour was finished (its last step done or handed over — not Skip tour). The app closes the Welcome
    /// window when the Welcome tour ends, so it isn't left behind the tours that follow (review W4).
    var onFinished: ((TourID) -> Void)?
    /// Windows besides a tour's host where a step's anchor may live, searched after the host: the
    /// menu-bar status item's window (the Welcome tour's first step points at the icon). The tag then
    /// attaches to that window; the host still decides pausing.
    var extraAnchorWindows: () -> [NSWindow] = { [] }
    /// How long a completed Try step shows its "done" state before the next step.
    var completedDelay: TimeInterval = 0.8

    private struct Session {
        var engine: TourEngine
        weak var window: NSWindow?
    }
    private struct WeakWindow {
        let surface: TourSurface
        weak var window: NSWindow?
    }
    private struct Suspended {
        let id: TourID
        weak var window: NSWindow?
        /// What the paused run had seen, so a step that `requires` one of those events still shows on resume.
        let observed: Set<TourEvent>
    }

    private var running: Session?
    /// Tours paused because another surface's tour took over, newest last — resumed when that one ends.
    private var suspended: [Suspended] = []
    /// Tours asked for (menu, ⓘ with no window, hand-over) waiting for their surface or trigger.
    private var pending: [TourID] = []
    private var surfaceWindows: [WeakWindow] = []
    private var presenter: TourTagPresenting?
    /// Bumped on every presentation change so a delayed "show next step" can tell it's stale.
    private var generation = 0
    private var showingCompleted = false
    /// The "n of m" on screen — redone by the watchdog when a later step's control appears or goes.
    private var shownProgress: (number: Int, total: Int)?
    private var closeObserver: NSObjectProtocol?
    private var watchdog: Timer?

    init(defaults: UserDefaults = .standard, catalog: [Tour] = TourCatalog.all,
         makePresenter: @escaping () -> TourTagPresenting,
         shortcutText: @escaping (String) -> String?) {
        self.defaults = defaults
        self.catalog = catalog
        self.makePresenter = makePresenter
        self.shortcutText = shortcutText
    }

    /// Connects the `TourEvents` bus to this coordinator (events, surfaces, replay, and Reset All Tours —
    /// which also confirms through `notify`).
    func install() {
        TourEvents.onEvent = { [weak self] event in self?.handle(event) }
        TourEvents.onSurfaceShown = { [weak self] surface, window in self?.surfaceShown(surface, in: window) }
        TourEvents.onReplayRequested = { [weak self] id, window in self?.replay(id, in: window) }
        TourEvents.onResetRequested = { [weak self] in self?.resetAllToursAndConfirm() }
    }

    // MARK: - Who gets tours (§14.9)

    /// Call first thing at launch, before anything writes a preference. Classifies once and stores
    /// `tourAudience`; later launches just read it. Returns the stored audience.
    @discardableResult
    static func classifyAudienceIfNeeded(
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        permissionGranted: Bool
    ) -> TourAudience {
        if let stored = TourAudience(stored: defaults.string(forKey: TourPreferenceKey.audience)) {
            return stored
        }
        // Only the app's own domain — `defaults.dictionaryRepresentation()` would include global keys.
        let keys = domainName.flatMap { defaults.persistentDomain(forName: $0) }.map { Set($0.keys) } ?? []
        let audience = TourAudience.classify(TourAudience.Signals(
            preferenceKeys: keys,
            permissionGranted: permissionGranted,
            bundleIdentifier: bundleIdentifier))
        defaults.set(audience.rawValue, forKey: TourPreferenceKey.audience)
        return audience
    }

    var audience: TourAudience? { TourAudience(stored: defaults.string(forKey: TourPreferenceKey.audience)) }
    var questionAnswered: Bool { defaults.bool(forKey: TourPreferenceKey.questionAnswered) }

    /// "Want a quick tour?" on the Welcome window's last page — new users who haven't answered only.
    var shouldAskQuestion: Bool {
        TourRules.shouldAskQuestion(audience: audience, answered: questionAnswered)
    }

    /// At launch with permission already granted: open the Welcome window on its last page to ask.
    func shouldOpenWelcomeOnLaunch(permissionGranted: Bool) -> Bool {
        TourRules.shouldOpenWelcomeOnLaunch(audience: audience, answered: questionAnswered,
                                            permissionGranted: permissionGranted)
    }

    /// The answer (closing the window unanswered = No). Show Me Around turns first-use tours on and
    /// starts the Welcome tour in `window` (the Welcome window) right away.
    func answerQuestion(showMeAround: Bool, in window: NSWindow?) {
        defaults.set(showMeAround, forKey: TourPreferenceKey.firstUseToursEnabled)
        defaults.set(true, forKey: TourPreferenceKey.questionAnswered)
        guard showMeAround else { return }
        if let window, start(.welcome, in: window, from: 0) { return }
        queue(.welcome)
    }

    // MARK: - Settings → "Tours & tips"

    /// Absent = false (existing users, and new users until they say yes).
    var firstUseToursEnabled: Bool {
        get { defaults.object(forKey: TourPreferenceKey.firstUseToursEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: TourPreferenceKey.firstUseToursEnabled) }
    }

    /// Clears `toursSeen` and `toursPaused` only — never `tourAudience` or the answer.
    func resetAllTours() {
        defaults.removeObject(forKey: TourPreferenceKey.seen)
        defaults.removeObject(forKey: TourPreferenceKey.paused)
        suspended.removeAll()
    }

    /// `resetAllTours()` + the HUD confirmation. With first-use tours off nothing starts by itself
    /// afterwards, so the confirmation says how to get them back.
    func resetAllToursAndConfirm() {
        resetAllTours()
        notify?(TourRules.resetConfirmation(firstUseToursEnabled: firstUseToursEnabled))
    }

    // MARK: - Menu bar "Tours" / ⓘ

    /// Runs `id` from its first step: now in `window` (the ⓘ), or — from the menu (nil) — now if its
    /// surface is on screen, otherwise when it next appears (opening it first if we can).
    func replay(_ id: TourID, in window: NSWindow?) {
        guard let tour = tour(id) else { return }
        if let window {
            track(tour.surface, window)
            if !start(id, in: window, from: 0, restart: true) { queue(id) }
            return
        }
        if let window = visibleWindow(for: tour.surface), start(id, in: window, from: 0, restart: true) { return }
        queue(id)
        if openSurface?(tour.surface) != true {
            notify?(Self.startsLaterMessage(for: id))
        }
    }

    /// The HUD note when a requested tour can't start now (its surface can't be opened on demand).
    static func startsLaterMessage(for id: TourID) -> String {
        switch id {
        case .recordingPill: return "The recording tour starts at your next dictation"
        case .welcome, .settings: return "\(id.menuTitle) starts the next time you open it"
        }
    }

    // MARK: - Bus handlers

    private func surfaceShown(_ surface: TourSurface, in window: NSWindow) {
        track(surface, window)
        if let id = pending.first(where: { tour($0)?.surface == surface }) {
            start(id, in: window, from: 0, restart: true)
            return
        }
        let paused = pausedIndexes
        for tour in catalog where tour.surface == surface && tour.id != running?.engine.tour.id {
            if let index = paused[tour.id.rawValue], start(tour.id, in: window, from: index) { return }
        }
        for tour in TourRules.tours(triggeredBy: .surfaceShown(surface), in: catalog)
        where tour.id != running?.engine.tour.id && mayAutoStart(tour) {
            if start(tour.id, in: window, from: 0) { return }
        }
    }

    private func handle(_ event: TourEvent) {
        let wasRunning = running != nil
        if var session = running {
            let effect = session.engine.handle(event, isPresent: presence(in: session.window))
            running = session
            if effect != .none {
                apply(effect, completedTry: true)
            } else {
                // The action may have hidden the step's control (window closed, pill gone): check after
                // the UI has updated.
                DispatchQueue.main.async { [weak self] in self?.checkHost() }
            }
        }
        // Event-triggered tours never interrupt a running tour; they stay eligible for the next time.
        guard !wasRunning, running == nil else { return }
        let trigger = TourTrigger.event(event)
        let requested = pending.compactMap { tour($0) }.filter { $0.trigger == trigger }
        let automatic = TourRules.tours(triggeredBy: trigger, in: catalog).filter { mayAutoStart($0) }
        for tour in requested + automatic {
            guard let window = visibleWindow(for: tour.surface) else { continue }
            if start(tour.id, in: window, from: 0, restart: true) { return }
        }
    }

    // MARK: - Running a tour

    /// Starts `id` in `window` at `index`. False (and nothing changed) when none of its steps can be
    /// shown there yet. One tour on screen at a time: a running one is paused — or, if it was on its
    /// last step and hands over to `id`, finished.
    @discardableResult
    private func start(_ id: TourID, in window: NSWindow, from index: Int, restart: Bool = false,
                       observed: Set<TourEvent> = []) -> Bool {
        guard let tour = tour(id) else { return false }
        if !restart, let current = running, current.engine.tour.id == id, current.window === window { return true }
        var engine = TourEngine(tour: tour, observed: observed)
        let effect = engine.start(at: index, isPresent: presence(in: window))
        guard case .show = effect else { return false }

        finishToursHandingOver(to: id)
        if let current = running {
            if current.engine.tour.id == id {
                stopRunning()                       // replay of the running tour: start over
            } else {
                var engine = current.engine
                if case .paused(let at) = engine.pause() {
                    setPausedIndex(at, for: current.engine.tour.id)
                    suspended.append(Suspended(id: current.engine.tour.id, window: current.window,
                                               observed: engine.observed))
                }
                stopRunning()
            }
        }
        running = Session(engine: engine, window: window)
        pending.removeAll { $0 == id }
        clearPausedIndex(for: id)
        watch(window)
        apply(effect)
        return true
    }

    /// Explain → Next; Try → Skip step; Esc → Skip tour (the presenter's buttons).
    private func presenterNext() { advance { $0.next(isPresent: $1) } }
    private func presenterSkipStep() { advance { $0.skipStep(isPresent: $1) } }
    private func presenterSkipTour() {
        guard var session = running else { return }
        let effect = session.engine.skipTour()
        running = session
        apply(effect)
    }

    private func advance(_ step: (inout TourEngine, (String) -> Bool) -> TourEngine.Effect) {
        guard var session = running else { return }
        let effect = step(&session.engine, presence(in: session.window))
        running = session
        apply(effect)
    }

    private func apply(_ effect: TourEngine.Effect, completedTry: Bool = false) {
        guard let session = running else { return }
        let tour = session.engine.tour
        switch effect {
        case .none, .nothingToShow:
            return
        case .show(let index):
            if completedTry {
                afterCompleted { [weak self] in self?.present(index) }
            } else {
                present(index)
            }
        case .finished(let next):
            markSeen(tour)
            // Queued now, so the hand-over survives even if something else takes the screen first.
            if let next { queue(next) }
            let end = { [weak self] in
                guard let self else { return }
                self.stopRunning()   // reports `onFinished`
                if let next { self.handOver(to: next) }
                self.resumeSuspended()
            }
            if completedTry { afterCompleted(end) } else { end() }
        case .skipped:
            markSeen(tour)
            stopRunning()
            resumeSuspended()
        case .paused(let at):
            setPausedIndex(at, for: tour.id)
            stopRunning()
            resumeSuspended()
        }
    }

    private func present(_ index: Int) {
        guard let session = running, let window = session.window,
              session.engine.tour.steps.indices.contains(index) else { return }
        let step = session.engine.tour.steps[index]
        guard let (anchor, anchorWindow) = locate(step.anchor, in: window) else {
            checkHost()
            return
        }
        // A control further down a scrolling window (Settings' Keyboard Shortcuts card) is brought
        // into view first; no-op when it's already visible.
        anchor.scrollToVisible(anchor.bounds)
        generation += 1
        showingCompleted = false
        let body = TourText.resolvingShortcuts(in: step.body, shortcutText)
        // Counted over the steps that actually show (anchor present, precondition met) — never 1 → 3.
        let progress = session.engine.progress(isPresent: presence(in: window))
            ?? (index + 1, session.engine.tour.steps.count)
        shownProgress = progress
        tagPresenter.show(step: step, body: body, number: progress.number,
                          total: progress.total, anchor: anchor, host: anchorWindow)
    }

    /// Redoes "n of m" for the step on screen; the tag is told only when it changed.
    private func refreshProgress() {
        guard let session = running, !showingCompleted, let shown = shownProgress,
              let now = session.engine.progress(isPresent: presence(in: session.window)),
              now != shown else { return }
        shownProgress = now
        presenter?.updateProgress(number: now.number, total: now.total)
    }

    /// The Try step's brief "done" state, then `then` (unless something else was shown meanwhile).
    private func afterCompleted(_ then: @escaping () -> Void) {
        generation += 1
        let token = generation
        showingCompleted = true
        tagPresenter.showCompleted()
        DispatchQueue.main.asyncAfter(deadline: .now() + completedDelay) { [weak self] in
            guard let self, self.generation == token else { return }
            self.showingCompleted = false
            then()
        }
    }

    /// Takes the running tour off screen. One that had finished (its last Try step done, maybe still
    /// showing "Done" when the next tour replaces it) is reported through `onFinished`.
    private func stopRunning() {
        let finished = running.flatMap { $0.engine.status == .finished ? $0.engine.tour.id : nil }
        generation += 1
        showingCompleted = false
        shownProgress = nil
        running = nil
        presenter?.hide()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        watchdog?.invalidate()
        watchdog = nil
        if let finished { onFinished?(finished) }
    }

    /// Starts `id` (already queued) after the tour that handed over to it: now if its surface is on
    /// screen, otherwise when it next appears. Runs even with first-use tours off (a replayed chain
    /// continues).
    private func handOver(to id: TourID) {
        guard let tour = tour(id), let window = visibleWindow(for: tour.surface) else { return }
        start(id, in: window, from: 0, restart: true)
    }

    /// A tour that hands over to `id` and stopped on its last step (running or paused) is done once
    /// `id` starts. (No JVoice tour hands over today; kept so a future chain behaves like BetterScreenshot's.)
    private func finishToursHandingOver(to id: TourID) {
        let paused = pausedIndexes
        for tour in catalog where tour.handsOverTo == id && !tour.steps.isEmpty {
            let last = tour.steps.count - 1
            if let current = running, current.engine.tour.id == tour.id, current.engine.current == last {
                markSeen(tour)
                stopRunning()
                onFinished?(tour.id)
            } else if paused[tour.id.rawValue] == last {
                markSeen(tour)
                onFinished?(tour.id)
            }
        }
    }

    /// After a tour ends: pick up the newest one it interrupted, if its window is still on screen.
    private func resumeSuspended() {
        guard running == nil else { return }
        let paused = pausedIndexes
        while let entry = suspended.popLast() {
            guard let window = entry.window, window.isVisible, let index = paused[entry.id.rawValue] else { continue }
            if start(entry.id, in: window, from: index, observed: entry.observed) { return }
        }
    }

    // MARK: - Host window watching (close / order-out pauses; vanished anchors are skipped)

    private func watch(_ window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseRunning() }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHost() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Host gone or hidden (the HUD pill is ordered out, not closed) → pause; step's control gone → skip it.
    private func checkHost() {
        guard var session = running, !showingCompleted else { return }
        guard let window = session.window, window.isVisible else {
            pauseRunning()
            return
        }
        let effect = session.engine.skipIfAnchorMissing(isPresent: presence(in: window))
        running = session
        apply(effect)
        if effect == .none { refreshProgress() }
    }

    private func pauseRunning() {
        guard var session = running else { return }
        let effect = session.engine.pause()
        running = session
        apply(effect)
    }

    // MARK: - Helpers

    private var tagPresenter: TourTagPresenting {
        if let presenter { return presenter }
        let made = makePresenter()
        made.onNext = { [weak self] in self?.presenterNext() }
        made.onSkipStep = { [weak self] in self?.presenterSkipStep() }
        made.onSkipTour = { [weak self] in self?.presenterSkipTour() }
        presenter = made
        return made
    }

    private func tour(_ id: TourID) -> Tour? { catalog.first { $0.id == id } }

    private func presence(in window: NSWindow?) -> (String) -> Bool {
        { [weak self, weak window] anchor in self?.locate(anchor, in: window) != nil }
    }

    /// `anchor`'s view and the window it's in: the host first, then `extraAnchorWindows` — only ones
    /// visible on a screen (a status item hidden by a menu-bar manager, or never placed, counts as
    /// missing, so its step is skipped instead of pointing at nothing).
    private func locate(_ anchor: String, in window: NSWindow?) -> (NSView, NSWindow)? {
        guard let window else { return nil }
        if let view = window.view(forTourAnchor: anchor) { return (view, window) }
        for other in extraAnchorWindows() where other !== window && other.isVisible
            && NSScreen.screens.contains(where: { $0.frame.intersects(other.frame) }) {
            if let view = other.view(forTourAnchor: anchor) { return (view, other) }
        }
        return nil
    }

    private func mayAutoStart(_ tour: Tour) -> Bool {
        let enabled = defaults.object(forKey: TourPreferenceKey.firstUseToursEnabled) as? Bool
        return TourRules.shouldAutoStart(tour, firstUseToursEnabled: enabled, seen: seenVersions)
    }

    private func queue(_ id: TourID) {
        if !pending.contains(id) { pending.append(id) }
    }

    private func track(_ surface: TourSurface, _ window: NSWindow) {
        surfaceWindows.removeAll { $0.window == nil || $0.window === window }
        surfaceWindows.append(WeakWindow(surface: surface, window: window))
    }

    /// The key window if it's one of `surface`'s, else the newest visible one.
    private func visibleWindow(for surface: TourSurface) -> NSWindow? {
        let mine = surfaceWindows.filter { $0.surface == surface }.compactMap(\.window).filter(\.isVisible)
        if let key = NSApp.keyWindow, mine.contains(where: { $0 === key }) { return key }
        return mine.last
    }

    private var seenVersions: [String: Int] { intDictionary(TourPreferenceKey.seen) }
    private var pausedIndexes: [String: Int] { intDictionary(TourPreferenceKey.paused) }

    private func intDictionary(_ key: String) -> [String: Int] {
        (defaults.dictionary(forKey: key) ?? [:]).compactMapValues { $0 as? Int }
    }

    private func markSeen(_ tour: Tour) {
        var seen = seenVersions
        seen[tour.id.rawValue] = max(seen[tour.id.rawValue] ?? 0, tour.version)
        defaults.set(seen, forKey: TourPreferenceKey.seen)
        clearPausedIndex(for: tour.id)
    }

    private func setPausedIndex(_ index: Int, for id: TourID) {
        var paused = pausedIndexes
        paused[id.rawValue] = index
        defaults.set(paused, forKey: TourPreferenceKey.paused)
    }

    private func clearPausedIndex(for id: TourID) {
        var paused = pausedIndexes
        guard paused.removeValue(forKey: id.rawValue) != nil else { return }
        if paused.isEmpty {
            defaults.removeObject(forKey: TourPreferenceKey.paused)
        } else {
            defaults.set(paused, forKey: TourPreferenceKey.paused)
        }
    }
}
