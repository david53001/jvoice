import Foundation

/// Hidden CLI bench mode:
///
///     JVoice --bench <audio.wav> [--model tiny|base|small|large] [--vocab "Word1,Word2"] [--stream [--realtime]] [--repeat N [--idle S]]
///
/// Transcribes one file with timing and prints both the raw transcript and the
/// TextProcessor-processed output. Dev-only: this machine cannot execute
/// XCTest, so this is how transcription speed and vocabulary biasing are
/// actually verified end-to-end.
enum BenchRunner {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--bench")
    }

    static func runAndExit(arguments: [String]) -> Never {
        var exitCode: Int32 = 0
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            exitCode = await run(arguments: arguments)
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }

    private static func run(arguments: [String]) async -> Int32 {
        guard let benchIndex = arguments.firstIndex(of: "--bench"),
              arguments.count > benchIndex + 1 else {
            FileHandle.standardError.write(Data("usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab \"Word1,Word2\"] [--stream [--realtime]] [--repeat N [--idle S]]\n".utf8))
            return 64
        }
        let audioURL = URL(fileURLWithPath: arguments[benchIndex + 1])
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            FileHandle.standardError.write(Data("no such file: \(audioURL.path)\n".utf8))
            return 66
        }

        var model: WhisperModelOption = .base
        if let modelIndex = arguments.firstIndex(of: "--model"), arguments.count > modelIndex + 1 {
            switch arguments[modelIndex + 1] {
            case "tiny": model = .tiny
            case "base": model = .base
            case "small": model = .small
            case "large", "large-v3_turbo", "largeTurbo", "large-v3-v20240930": model = .largeTurbo
            default:
                FileHandle.standardError.write(Data("unknown model \(arguments[modelIndex + 1])\n".utf8))
                return 64
            }
        }

        var language: TranscriptionLanguage = .english
        if let langIndex = arguments.firstIndex(of: "--lang"), arguments.count > langIndex + 1 {
            switch arguments[langIndex + 1] {
            case "en", "english": language = .english
            case "ro", "romanian": language = .romanian
            default:
                FileHandle.standardError.write(Data("unknown lang \(arguments[langIndex + 1])\n".utf8))
                return 64
            }
        }

        var vocabulary: [String] = []
        if let vocabIndex = arguments.firstIndex(of: "--vocab"), arguments.count > vocabIndex + 1 {
            vocabulary = arguments[vocabIndex + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let useDecoderPrompt = !arguments.contains("--no-prompt")
        print("model: \(model.rawValue)   audio: \(audioURL.lastPathComponent)   lang: \(language.whisperCode)   vocab: \(vocabulary.isEmpty ? "—" : vocabulary.joined(separator: ", "))   decoderPrompt: \(useDecoderPrompt ? "on" : "off")")

        #if canImport(WhisperKit)
        let engine = WhisperKitTranscriptionEngine(model: model, language: language, vocabulary: vocabulary, useVocabularyPrompt: useDecoderPrompt)

        let loadStart = Date()
        await engine.prewarm()
        print(String(format: "load+prewarm: %.2fs", Date().timeIntervalSince(loadStart)))

        if arguments.contains("--stream") {
            return await runStream(audioURL: audioURL, engine: engine, realtime: arguments.contains("--realtime"))
        }

        do {
            // --repeat N [--idle S]: decode the same clip N times in ONE process,
            // sleeping S seconds between runs — separates cold (first decode after
            // idle: Neural Engine/CPU power state) from warm per-decode cost.
            if let repeatIndex = arguments.firstIndex(of: "--repeat"), arguments.count > repeatIndex + 1,
               let repeats = Int(arguments[repeatIndex + 1]), repeats > 1 {
                var idle: Double = 0
                if let idleIndex = arguments.firstIndex(of: "--idle"), arguments.count > idleIndex + 1 {
                    idle = Double(arguments[idleIndex + 1]) ?? 0
                }
                for i in 1...repeats {
                    if i > 1, idle > 0 { try? await Task.sleep(nanoseconds: UInt64(idle * 1_000_000_000)) }
                    let t0 = Date()
                    _ = try? await engine.transcribe(audioURL: audioURL)
                    print(String(format: "run %d%@: %.2fs", i, idle > 0 && i > 1 ? " (after \(Int(idle)) s idle)" : "", Date().timeIntervalSince(t0)))
                }
                return 0
            }
            let transcribeStart = Date()
            let raw = try await engine.transcribe(audioURL: audioURL)
            let elapsed = Date().timeIntervalSince(transcribeStart)
            print(String(format: "transcribe:   %.2fs", elapsed))
            print("raw:       \"\(raw)\"")
            let userDict = TextProcessor.buildUserDictionary(from: vocabulary)
            let processed = TextProcessor.process(raw, mode: .casual, extraDictionary: userDict, vocabulary: vocabulary)
            print("processed: \"\(processed)\"")
            return 0
        } catch {
            FileHandle.standardError.write(Data("transcription failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
        #else
        FileHandle.standardError.write(Data("WhisperKit unavailable in this build\n".utf8))
        return 70
        #endif
    }

    #if canImport(WhisperKit)
    /// Streaming E2E without a microphone: replays `audioURL` into a growing
    /// temp WAV at ~10× real time (or 1× with `--realtime`, which also uses the
    /// app's own poll cadence + speculative tail decode so a clip that ends in
    /// a pause shows the "speculative tail HIT" path) while a real
    /// StreamingTranscriptionSession consumes it, then compares against the
    /// whole-file transcript.
    private static func runStream(audioURL: URL, engine: WhisperKitTranscriptionEngine, realtime: Bool) async -> Int32 {
        guard let sourceBytes = try? Data(contentsOf: audioURL),
              let info = WavTail.parseHeader([UInt8](sourceBytes.prefix(WavTail.headerProbeBytes))) else {
            FileHandle.standardError.write(Data("not a 16 kHz mono 16-bit PCM wav: \(audioURL.path)\n".utf8))
            return 65
        }
        let pollNanoseconds: UInt64 = realtime ? UInt64(AppTimings.streamingPoll * 1_000_000_000) : 100_000_000
        guard let session = await engine.makeStreamingSession(pollNanoseconds: pollNanoseconds,
                                                              log: { print("  [stream] \($0)") }) else {
            FileHandle.standardError.write(Data("engine has no loaded model\n".utf8))
            return 70
        }

        let growingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jv-stream-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: growingURL) }
        FileManager.default.createFile(atPath: growingURL.path, contents: sourceBytes.prefix(info.dataOffset))

        let payload = sourceBytes.dropFirst(info.dataOffset)
        let sliceBytes = info.sampleRate * info.bytesPerSample / 2 // 0.5 s of audio…
        let writer = Task {
            guard let handle = try? FileHandle(forWritingTo: growingURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            var offset = payload.startIndex
            while offset < payload.endIndex {
                let end = min(offset + sliceBytes, payload.endIndex)
                try? handle.write(contentsOf: payload[offset..<end])
                offset = end
                // …every 50 ms ⇒ 10× real time; every 500 ms ⇒ real time
                try? await Task.sleep(nanoseconds: realtime ? 500_000_000 : 50_000_000)
            }
        }

        let wallStart = Date()
        await session.start(url: growingURL)
        await writer.value // "recording" ends here
        let stopStart = Date()
        let streamed = await session.finish()
        let tailTime = Date().timeIntervalSince(stopStart)
        let wallTime = Date().timeIntervalSince(wallStart)

        print(String(format: "stream wall: %.2fs   post-stop (finish): %.2fs", wallTime, tailTime))
        print("streamed:  \(streamed.map { "\"\($0)\"" } ?? "nil (session fell back)")")

        do {
            let wholeStart = Date()
            let whole = try await engine.transcribe(audioURL: audioURL)
            print(String(format: "wholefile: %.2fs", Date().timeIntervalSince(wholeStart)))
            print("wholefile: \"\(whole)\"")
        } catch {
            FileHandle.standardError.write(Data("whole-file comparison failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
        return 0
    }
    #endif
}
