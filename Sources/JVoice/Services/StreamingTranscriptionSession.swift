import Foundation

/// Transcribes completed speech chunks in the background *while the user is
/// still recording*, by reading the growing WAV that `RecordingManager`'s
/// AVAudioRecorder writes. This is a read-only overlay on the proven pipeline:
/// any failure marks the session failed and `finish()` returns nil, telling
/// the caller to fall back to whole-file transcription — worst case equals
/// today's behavior, and audio is never lost (correctness is anchored at the
/// finalized file, which is read after the recorder stops).
public actor StreamingTranscriptionSession {
    public typealias SampleTranscriber = @Sendable ([Float]) async throws -> String

    private let transcribe: SampleTranscriber
    private let config: ChunkPlanner.Config
    private let pollNanoseconds: UInt64

    private var url: URL?
    private var reader: WavTailReader?
    private var consumedSamples = 0
    private var pieces: [String] = []
    private var pollTask: Task<Void, Never>?
    private var failed = false
    private var cancelled = false
    /// Polls tolerated before a never-parseable header is fatal (the recorder
    /// may still be flushing its first buffer right after start).
    private var openRetriesRemaining = 10
    /// Enforces the finish-once contract: a second `finish()` would re-drain
    /// the backlog from the un-advanced `consumedSamples` and duplicate audio.
    private var finished = false

    public init(
        transcribe: @escaping SampleTranscriber,
        config: ChunkPlanner.Config = .init(),
        pollNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.transcribe = transcribe
        self.config = config
        self.pollNanoseconds = pollNanoseconds
    }

    public func start(url: URL) {
        // `!finished` matters: the coordinator assigns the session and then
        // suspends before calling start — a fast stop can finish() the session
        // in that window, and starting it afterwards would spawn an orphan
        // poll loop.
        guard pollTask == nil, !cancelled, !failed, !finished else { return }
        self.url = url
        pollTask = Task { await runPollLoop() }
    }

    /// Stop polling, transcribe whatever remains in the (now finalized) file,
    /// and return the combined raw transcript. nil ⇒ the caller MUST fall back
    /// to whole-file transcription (session failed, was cancelled, or never
    /// streamed anything — in which case the fallback is equally fast).
    public func finish() async -> String? {
        guard !finished else { return nil }
        finished = true
        pollTask?.cancel()
        await pollTask?.value
        pollTask = nil
        guard !failed, !cancelled, let url else { return nil }
        guard consumedSamples > 0 || !pieces.isEmpty else { return nil }

        if reader == nil { reader = WavTailReader.open(url: url) }
        guard let reader, var tail = reader.samples(from: consumedSamples) else { return nil }

        // Drain any backlog the poll loop didn't get to (slow decodes), keeping
        // every transcribed piece a provable single window. Terminates because
        // `plan` never cuts at 0 — every `.cut` strictly shrinks `tail`.
        while case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: tail, config: config) {
            if !silent {
                guard await appendPiece(WavTail.floatSamples(tail[..<at])) else { return nil }
            }
            tail = Array(tail[at...])
        }
        // After the drain the tail is < maxChunkSeconds by construction.
        if !tail.isEmpty, !ChunkPlanner.isSilent(tail, config: config) {
            guard await appendPiece(WavTail.floatSamples(tail[...])) else { return nil }
        }

        let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // All-silence audio: let the fallback produce today's exact
        // empty-transcript behavior rather than inventing a new path.
        return joined.isEmpty ? nil : joined
    }

    /// The user abandoned this recording (new hotkey press, quit): discard
    /// everything; `finish()` will return nil if it is ever called. Joins the
    /// poll task so no chunk decode from this session is still in flight when
    /// cancel returns — the next recording's decodes never overlap ours.
    public func cancel() async {
        cancelled = true
        pollTask?.cancel()
        await pollTask?.value
        pollTask = nil
        pieces = []
    }

    private func appendPiece(_ samples: [Float]) async -> Bool {
        do {
            let text = try await transcribe(samples)
            guard !text.isEmpty else {
                // A non-silent chunk (callers only pass non-silent audio here)
                // that decodes to nothing is anomalous — an empty WhisperKit
                // decode or a regurgitation the guard stripped to "". Appending
                // nothing while advancing past it would SILENTLY DELETE up to
                // maxChunkSeconds of speech. Fail instead so finish() returns
                // nil and the lossless whole-file path re-covers this audio.
                failed = true
                return false
            }
            pieces.append(text)
            return true
        } catch {
            failed = true
            return false
        }
    }

    private func runPollLoop() async {
        while !Task.isCancelled, !failed, !cancelled {
            await pollOnce()
            do {
                try await Task.sleep(nanoseconds: pollNanoseconds)
            } catch {
                break // cancelled during sleep
            }
        }
    }

    private func pollOnce() async {
        guard let url else {
            failed = true
            return
        }
        if reader == nil {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed = true // recorder torn down — abort, fallback handles it
                return
            }
            guard let opened = WavTailReader.open(url: url) else {
                openRetriesRemaining -= 1
                if openRetriesRemaining <= 0 { failed = true }
                return
            }
            reader = opened
        }
        guard let reader else { return }
        guard let unconsumed = reader.samples(from: consumedSamples) else {
            failed = true // file vanished mid-recording (failure teardown)
            return
        }
        guard case let .cut(atSample, isSilent) = ChunkPlanner.plan(unconsumed: unconsumed, config: config) else {
            return
        }
        if isSilent {
            consumedSamples += atSample // dropped, never transcribed
            return
        }
        let chunk = WavTail.floatSamples(unconsumed[..<atSample])
        do {
            let text = try await transcribe(chunk)
            // Cancelled mid-decode: don't consume — finish()/the fallback
            // re-covers these samples, so nothing is lost or duplicated.
            guard !Task.isCancelled, !cancelled else { return }
            guard !text.isEmpty else {
                // Non-silent chunk (silent ones were dropped above) decoded to
                // nothing: consuming it would silently delete up to
                // maxChunkSeconds of speech. Fail the session so finish()
                // returns nil and the caller re-runs the lossless whole-file
                // path over the finalized recording. (This is the data-loss bug
                // behind "it cut out a big chunk of my dictation".)
                failed = true
                return
            }
            pieces.append(text)
            consumedSamples += atSample
        } catch {
            failed = true
        }
    }
}
