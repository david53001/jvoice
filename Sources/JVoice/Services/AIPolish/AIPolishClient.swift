import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one request and returns the raw reply. The app uses `EphemeralTransport`; tests inject a
/// fake, so no test ever touches the network.
protocol AIPolishTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSessionConfiguration.ephemeral` with every store switched off: no cache, no cookies, no
/// credential storage — the key exists only in the one request's `x-api-key` header.
struct EphemeralTransport: AIPolishTransport {
    static let shared = EphemeralTransport()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// One polish attempt: the text to paste (the polished text, or the original on any fallback),
/// why, how long it took and what it cost.
struct AIPolishResult: Sendable {
    var text: String
    var outcome: AIPolishRequest.Outcome
    var milliseconds: Int
    var usage: AIPolishRequest.Usage?

    var isPolished: Bool {
        if case .polished = outcome { return true }
        return false
    }

    /// `ok` or `fallback(<reason>)` — the only part of a polish that is ever logged.
    var logLabel: String {
        switch outcome {
        case .polished: return "ok"
        case .fallback(let reason): return "fallback(\(reason.logLabel))"
        }
    }
}

struct AIPolishClient: Sendable {
    var transport: any AIPolishTransport
    /// Hard deadline on the WHOLE attempt (key read + request + reply), after which the local text
    /// is returned whatever the transport is doing.
    var deadline: TimeInterval

    func polish(_ text: String, previous: [String], mode: AppMode, vocabulary: [String],
                options: AIPolishRequest.Options = .standard,
                apiKey: @escaping @Sendable () -> String?) async -> AIPolishResult {
        let started = DispatchTime.now()
        let transport = self.transport
        let deadline = self.deadline
        let attempt: (AIPolishRequest.Outcome, AIPolishRequest.Usage?) = await Self.withDeadline(
            deadline,
            timedOut: (.fallback(.timeout), nil),
            cancelled: (.fallback(.cancelled), nil)
        ) {
            // The Keychain read is synchronous (and can sit on a permission prompt): do it on a GCD
            // thread, never on one of Swift's few cooperative threads.
            let key = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: apiKey()) }
            }
            guard let key, !key.isEmpty else { return (.fallback(.noKey), nil) }
            let body = AIPolishRequest.body(transcript: text, previous: previous, mode: mode,
                                            vocabulary: vocabulary, options: options)
            let request = AIPolishRequest.urlRequest(body: body, apiKey: key, timeout: deadline)
            do {
                let (data, response) = try await transport.send(request)
                let outcome = AIPolishRequest.outcome(status: response.statusCode, data: data,
                                                      original: text, previous: previous)
                return (outcome, AIPolishRequest.decode(data)?.usage)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return (.fallback(.cancelled), nil)
                }
                if (error as? URLError)?.code == .timedOut { return (.fallback(.timeout), nil) }
                return (.fallback(.network), nil)
            }
        }
        let milliseconds = Int((DispatchTime.now().uptimeNanoseconds &- started.uptimeNanoseconds) / 1_000_000)
        let finalText: String
        if case .polished(let polished) = attempt.0 { finalText = polished } else { finalText = text }
        return AIPolishResult(text: finalText, outcome: attempt.0, milliseconds: milliseconds, usage: attempt.1)
    }

    /// Runs `operation`, but returns `timedOut` once `seconds` have passed and `cancelled` as soon as
    /// the calling task is cancelled — WITHOUT waiting for `operation` to notice (it is cancelled and
    /// left to wind down). A task group can't promise that: it waits for every child before it
    /// returns, so one transport that ignores cancellation would hold the paste hostage. The timer is
    /// a GCD timer, not a `Task.sleep`, so a busy cooperative thread pool can't make it late.
    static func withDeadline<T: Sendable>(_ seconds: TimeInterval, timedOut: T, cancelled: T,
                                          _ operation: @escaping @Sendable () async -> T) async -> T {
        let race = DeadlineRace<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                race.attach(continuation)
                race.track(Task { race.finish(await operation()) })
                let timer = DispatchWorkItem { race.finish(timedOut) }
                race.track(timer)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0, seconds), execute: timer)
            }
        } onCancel: {
            race.finish(cancelled)
        }
    }
}

/// The first `finish` wins: it resumes the continuation (or holds the value until one is attached)
/// and cancels the other tasks and the timer.
private final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var result: T?
    private var tasks: [Task<Void, Never>] = []
    private var timers: [DispatchWorkItem] = []

    func attach(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        let finished = result != nil
        if !finished { tasks.append(task) }
        lock.unlock()
        if finished { task.cancel() }
    }

    func track(_ timer: DispatchWorkItem) {
        lock.lock()
        let finished = result != nil
        if !finished { timers.append(timer) }
        lock.unlock()
        if finished { timer.cancel() }
    }

    func finish(_ value: T) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        let timers = self.timers
        self.tasks = []
        self.timers = []
        lock.unlock()
        continuation?.resume(returning: value)
        tasks.forEach { $0.cancel() }
        timers.forEach { $0.cancel() }
    }
}
