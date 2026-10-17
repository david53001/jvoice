#if canImport(Testing)
import Foundation
import Testing
@testable import JVoice

// AI Polish plumbing, with a fake transport: no test makes a network call, and the "key" below is
// an obvious placeholder, never a real one.
private let fakeKey = "test-key-not-real-0000"
private let transcript = "so we pushed it to versails and it worked"

/// Records every request and answers with a canned reply (or throws / stalls).
private final class FakeTransport: AIPolishTransport, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String)
        case failure(Error)
        /// Answers only after 5 s and ignores cancellation — the deadline must still win. Waits on a
        /// timer, not a sleeping thread, so it never starves the other tests' cooperative threads.
        case stall
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let reply: Reply

    init(_ reply: Reply) { self.reply = reply }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); _requests.append(request); lock.unlock()
        switch reply {
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        case .stall:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { continuation.resume() }
            }
            throw URLError(.timedOut)
        }
    }
}

private func reply(_ text: String, stop: String = "end_turn") -> String {
    let object: [String: Any] = [
        "type": "message", "role": "assistant", "stop_reason": stop,
        "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
        "usage": ["input_tokens": 120, "output_tokens": 14],
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

private func run(_ transport: FakeTransport, text: String = transcript, previous: [String] = [],
                 mode: AppMode = .casual, vocabulary: [String] = [], deadline: TimeInterval = 3,
                 key: String? = fakeKey) async -> AIPolishResult {
    await AIPolishClient(transport: transport, deadline: deadline)
        .polish(text, previous: previous, mode: mode, vocabulary: vocabulary, apiKey: { key })
}

private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

// MARK: - The request

@Test func requestCarriesTheHeadersModelAndNoSamplingParams() async throws {
    let transport = FakeTransport(.response(status: 200, body: reply("So we pushed it to Vercel and it worked.")))
    _ = await run(transport, mode: .formal, vocabulary: ["JVoice", "Supabase"])
    let request = try #require(transport.requests.first)

    #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == fakeKey)
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

    let body = try jsonBody(request)
    #expect(body["model"] as? String == "claude-haiku-5-5")
    #expect((body["thinking"] as? [String: Any])?["type"] as? String == "disabled")
    for banned in ["temperature", "top_p", "top_k"] { #expect(body[banned] == nil) }

    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 1)                                  // no assistant prefill
    #expect(messages[0]["role"] as? String == "user")
    let content = try #require(messages[0]["content"] as? String)
    #expect(content == "<transcript>\n\(transcript)\n</transcript>")

    let system = try #require(body["system"] as? String)
    #expect(system.contains("Tone: formal"))
    #expect(system.contains("custom words exactly when they occur: JVoice, Supabase."))
}

@Test func systemPromptSaysNoneWithoutCustomWordsAndNamesEachTone() {
    #expect(AIPolishRequest.systemPrompt(mode: .casual, vocabulary: []).contains("when they occur: none."))
    #expect(AIPolishRequest.systemPrompt(mode: .veryCasual, vocabulary: [" ", ""]).contains("when they occur: none."))
    #expect(AIPolishRequest.systemPrompt(mode: .veryCasual, vocabulary: []).contains("Tone: very casual"))
    #expect(AIPolishRequest.systemPrompt(mode: .code, vocabulary: []).contains("Tone: code"))
}

@Test func previousDictationsGoInTheirOwnTagsBeforeTheTranscript() {
    let content = AIPolishRequest.userContent(transcript: "deploy it to versails",
                                              previous: ["We're building the website.", "It runs on next JS."])
    #expect(content == "<previous>\nWe're building the website.\nIt runs on next JS.\n</previous>\n<transcript>\ndeploy it to versails\n</transcript>")
    #expect(AIPolishRequest.userContent(transcript: "hi", previous: [" "]) == "<transcript>\nhi\n</transcript>")
}

@Test func maxTokensScalesWithTheTranscriptWithinBounds() {
    #expect(AIPolishRequest.maxTokens(for: "short", thinking: .off) == 256)
    #expect(AIPolishRequest.maxTokens(for: String(repeating: "a", count: 900), thinking: .off) == 900)
    #expect(AIPolishRequest.maxTokens(for: String(repeating: "a", count: 50_000), thinking: .off) == 4096)
    #expect(AIPolishRequest.maxTokens(for: "short", thinking: .low) == 256 + 2048)
}

@Test func lowThinkingIsAdaptiveAtLowEffort() throws {
    let body = AIPolishRequest.body(transcript: "x", previous: [], mode: .casual, vocabulary: [],
                                    options: .init(model: "claude-sonnet-5-5", thinking: .low))
    #expect(body["model"] as? String == "claude-sonnet-5-5")
    #expect((body["thinking"] as? [String: Any])?["type"] as? String == "adaptive")
    #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
}

// MARK: - Success

@Test func endTurnReplyIsPasted() async {
    let result = await run(FakeTransport(.response(status: 200, body: reply("So we pushed it to Vercel, and it worked."))))
    #expect(result.text == "So we pushed it to Vercel, and it worked.")
    #expect(result.isPolished)
    #expect(result.logLabel == "ok")
    #expect(result.usage == AIPolishRequest.Usage(inputTokens: 120, outputTokens: 14))
}

@Test func aReplyStillWrappedInTranscriptTagsIsUnwrapped() async {
    let result = await run(FakeTransport(.response(status: 200, body: reply("<transcript>\nFixed.\n</transcript>"))),
                           text: "fixed")
    #expect(result.text == "Fixed.")
}

// MARK: - Every failure pastes the local text

@Test(arguments: [401, 403, 429, 500, 529])
func httpErrorsFallBack(_ status: Int) async {
    let result = await run(FakeTransport(.response(status: status, body: #"{"type":"error","error":{"type":"x","message":"nope"}}"#)))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(http\(status))")
}

@Test func networkErrorsFallBack() async {
    let offline = await run(FakeTransport(.failure(URLError(.notConnectedToInternet))))
    #expect(offline.text == transcript)
    #expect(offline.logLabel == "fallback(network)")
    let timedOut = await run(FakeTransport(.failure(URLError(.timedOut))))
    #expect(timedOut.text == transcript)
    #expect(timedOut.logLabel == "fallback(timeout)")
}

@Test func theDeadlineWinsEvenOverATransportThatNeverAnswers() async {
    let started = Date()
    let result = await run(FakeTransport(.stall), deadline: 0.3)
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(timeout)")
    #expect(Date().timeIntervalSince(started) < 2)
}

@Test func malformedJSONFallsBack() async {
    let result = await run(FakeTransport(.response(status: 200, body: "<html>proxy error</html>")))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(malformed)")
}

@Test(arguments: ["max_tokens", "refusal"])
func nonEndTurnStopsFallBack(_ stop: String) async {
    let result = await run(FakeTransport(.response(status: 200, body: reply("So we pushed", stop: stop))))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(stop:\(stop))")
}

@Test func emptyTextFallsBack() async {
    let result = await run(FakeTransport(.response(status: 200, body: reply("   \n"))))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(empty)")
}

@Test func overLongOutputFallsBack() async {
    let essay = String(repeating: "Vercel is a cloud platform for frontend developers. ", count: 10)
    let result = await run(FakeTransport(.response(status: 200, body: reply(essay))))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(too-long)")
}

@Test(arguments: ["Here is the cleaned transcript: So we pushed it to Vercel.",
                  "Sure! So we pushed it to Vercel.",
                  "I'm sorry, I can't help with that."])
func chattyOutputFallsBack(_ chatty: String) async {
    let result = await run(FakeTransport(.response(status: 200, body: reply(chatty))))
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(chatty)")
}

@Test func aDictationThatReallyOpensWithSureIsKept() async {
    let result = await run(FakeTransport(.response(status: 200, body: reply("Sure, I'll be there at five."))),
                           text: "sure i'll be there at five")
    #expect(result.text == "Sure, I'll be there at five.")
    // …and "sure" only counts as a whole word.
    #expect(AIPolishRequest.opens("surely not", with: "sure") == false)
}

@Test func echoingThePreviousDictationFallsBack() async {
    let previous = ["We're moving the marketing site off the old server."]
    let result = await run(FakeTransport(.response(status: 200, body: reply("We're moving the marketing site off the old server. Deploy it to Vercel."))),
                           text: "deploy it to versails", previous: previous)
    #expect(result.text == "deploy it to versails")
    #expect(result.logLabel == "fallback(leaked-context)")
}

@Test func noKeyMeansNoRequest() async {
    let transport = FakeTransport(.response(status: 200, body: reply("unused")))
    let result = await run(transport, key: nil)
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(no-key)")
    #expect(transport.requests.isEmpty)
    let blank = await run(transport, key: "")
    #expect(blank.logLabel == "fallback(no-key)")
    #expect(transport.requests.isEmpty)
}

@Test func theLogLabelNeverCarriesTextOrTheKey() async {
    for transportReply in [FakeTransport.Reply.response(status: 200, body: reply("So we pushed it to Vercel.")),
                           .response(status: 401, body: "{}"),
                           .response(status: 200, body: reply("x", stop: "something new"))] {
        let label = await run(FakeTransport(transportReply)).logLabel
        #expect(!label.contains("versails") && !label.contains("Vercel") && !label.contains(fakeKey))
        #expect(!label.contains("something new"))
    }
}

@Test func aShortAnswerOrASummaryLosesTheUsersWordsAndFallsBack() async {
    let answer = await run(FakeTransport(.response(status: 200, body: reply("Paris."))), text: "what's the capital of france")
    #expect(answer.text == "what's the capital of france")
    #expect(answer.logLabel == "fallback(too-short)")
    let runOn = "so on saturday we need to get groceries and then pick up the kids from practice and after that we visit grandma"
    let summary = await run(FakeTransport(.response(status: 200, body: reply("Saturday: groceries, then the kids, then a visit, all in one long and busy day out."))), text: runOn)
    #expect(summary.text == runOn)
    #expect(summary.logLabel == "fallback(dropped-words)")
    // Sound-alike fixes and number words turned into digits are not "dropped words".
    #expect((AIPolishRequest.wordRetention(of: "The sine wave repeats every 2π.", original: "the sign wave repeats every two pi") ?? 0) >= AIPolishRequest.minWordRetention)
}

@Test func surroundingQuotesAreStrippedUnlessTheDictationHasThem() {
    #expect(AIPolishRequest.validate("\"Fixed it.\"", original: "fixed it", previous: []) == .polished("Fixed it."))
    #expect(AIPolishRequest.validate("“Fixed it.”", original: "fixed it", previous: []) == .polished("Fixed it."))
    #expect(AIPolishRequest.validate("He said \"hi\".", original: "he said \"hi\"", previous: []) == .polished("He said \"hi\"."))
}

@Test func saying_the_previous_sentence_again_is_not_a_leak() {
    let previous = ["We're moving the marketing site off the old server."]
    #expect(AIPolishRequest.validate("We're moving the marketing site off the old server.",
                                     original: "we're moving the marketing site off the old server", previous: previous)
            == .polished("We're moving the marketing site off the old server."))
}

@Test func theDeadlineAlsoCoversABlockingKeychainRead() async {
    let started = Date()
    let result = await AIPolishClient(transport: FakeTransport(.response(status: 200, body: reply("unused"))), deadline: 0.2)
        .polish(transcript, previous: [], mode: .casual, vocabulary: [], apiKey: {
            usleep(5_000_000)   // a synchronous Keychain read stuck on a permission prompt
            return fakeKey
        })
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(timeout)")
    // Far below the 5 s read (slack for a busy CI runner resuming this test).
    #expect(Date().timeIntervalSince(started) < 3)
}

@Test func cancellingTheDictationEndsThePolishAtOnce() async {
    let task = Task { await run(FakeTransport(.stall), deadline: 10) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    let started = Date()
    task.cancel()
    let result = await task.value
    #expect(result.text == transcript)
    #expect(result.logLabel == "fallback(cancelled)")
    #expect(Date().timeIntervalSince(started) < 2)
}

@Test func shortDictationsAreNotSentAndEachToneIsSpelledOut() {
    #expect(!AIPolish.isWorthPolishing("ok thanks"))
    #expect(AIPolish.isWorthPolishing("deploy it now"))
    #expect(AIPolishRequest.systemPrompt(mode: .casual, vocabulary: []).contains("no period at the very end"))
    #expect(AIPolishRequest.systemPrompt(mode: .veryCasual, vocabulary: []).contains("all lowercase"))
}

// MARK: - Test key

@Test func keyCheckMapsStatusesToPlainWords() {
    #expect(AIPolish.keyCheck(status: 200, data: Data()) == .works)
    #expect(AIPolish.keyCheck(status: 401, data: Data()) == .invalidKey)
    #expect(AIPolish.keyCheck(status: 429, data: Data()) == .rateLimited)
    let lowCredit = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low."}}"#.utf8)
    #expect(AIPolish.keyCheck(status: 400, data: lowCredit) == .failed("Anthropic said (400): Your credit balance is too low."))
    #expect(AIPolish.KeyCheck.invalidKey.message.lowercased().contains("invalid key"))
}

@Test func keyCheckSendsOneTinyRequestWithTheGivenKey() async throws {
    let transport = FakeTransport(.response(status: 200, body: reply("H", stop: "max_tokens")))
    #expect(await AIPolish.checkKey(fakeKey, transport: transport) == .works)
    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == fakeKey)
    #expect(try jsonBody(request)["max_tokens"] as? Int == 1)
    #expect(await AIPolish.checkKey(fakeKey, transport: FakeTransport(.failure(URLError(.notConnectedToInternet)))) == .unreachable)
}

// MARK: - Context buffer

@Test func contextKeepsTheSameAppFromTheLastTenMinutesOldestFirst() {
    var context = AIPolishContext()
    let now = Date()
    context.append("Old note.", bundleId: "com.apple.Notes", at: now.addingTimeInterval(-11 * 60))
    context.append("We're building the website.", bundleId: "com.apple.Notes", at: now.addingTimeInterval(-120))
    context.append("Slack message.", bundleId: "com.tinyspeck.slackmacgap", at: now.addingTimeInterval(-60))
    context.append("It runs on Next.js.", bundleId: "com.apple.Notes", at: now.addingTimeInterval(-30))
    #expect(context.entries.count == AIPolishContext.capacity)     // the 11-minute-old one fell off the ring
    #expect(context.previous(for: "com.apple.Notes", now: now) == ["We're building the website.", "It runs on Next.js."])
    #expect(context.previous(for: "com.tinyspeck.slackmacgap", now: now) == ["Slack message."])
    #expect(context.previous(for: nil, now: now).isEmpty)
    #expect(context.previous(for: "com.apple.Notes", now: now.addingTimeInterval(11 * 60)).isEmpty)
    context.clear()
    #expect(context.previous(for: "com.apple.Notes", now: now).isEmpty)
}

@Test func contextIsCappedInLengthDroppingTheOldestFirst() {
    var context = AIPolishContext()
    let now = Date()
    context.append(String(repeating: "a", count: 900), bundleId: "app", at: now.addingTimeInterval(-3))
    context.append(String(repeating: "b", count: 900), bundleId: "app", at: now.addingTimeInterval(-2))
    #expect(context.previous(for: "app", now: now) == [String(repeating: "b", count: 900)])
    context.append(String(repeating: "c", count: 2_000), bundleId: "app", at: now.addingTimeInterval(-1))
    #expect(context.previous(for: "app", now: now) == [String(repeating: "c", count: AIPolishContext.maxCharacters)])
}
// MARK: - Eval harness (grading only — the eval itself needs a real key and runs on David's Mac)

@Test func evalGradingIsCaseSensitiveSubstringsPlusLengthTolerance() {
    let testCase = PolishEvalCase(id: "x", category: "preserve", previous: nil, transcript: String(repeating: "a", count: 100),
                                  mode: nil, mustContain: ["Vercel"], mustNotContain: ["versails"], holdout: nil,
                                  customWords: nil, lengthTolerance: 0.25)
    #expect(PolishEval.failures(of: "Deploy to Vercel" + String(repeating: "a", count: 84), for: testCase).isEmpty)
    #expect(PolishEval.failures(of: "deploy to vercel" + String(repeating: "a", count: 84), for: testCase) == ["missing “Vercel”"])
    #expect(PolishEval.failures(of: "Vercel versails" + String(repeating: "a", count: 85), for: testCase) == ["contains “versails”"])
    #expect(PolishEval.failures(of: "Vercel", for: testCase) == ["length 6% of the transcript"])
    #expect(testCase.appMode == .casual)
}

@Test func evalPercentilesAreNearestRank() {
    #expect(PolishEval.percentile([], 50) == 0)
    #expect(PolishEval.percentile([300, 100, 200], 50) == 200)
    #expect(PolishEval.percentile(Array(1...100), 95) == 95)
    #expect(PolishEval.percentile(Array(1...100), 100) == 100)
}

@Test func evalCaseFileCoversEveryCategoryWithAHoldOutMajority() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("scripts/ai-polish-eval/cases.json"))
    let cases = try JSONDecoder().decode([PolishEvalCase].self, from: data)
    #expect(cases.count >= 55)
    #expect(Set(cases.map(\.id)).count == cases.count)
    let categories = Set(cases.map(\.category))
    #expect(categories == ["context-fix", "context-from-previous", "no-false-fix", "no-answer", "preserve"])
    let contextFix = cases.filter { $0.category == "context-fix" }
    #expect(contextFix.filter { $0.holdout == true }.count * 2 >= contextFix.count)
    #expect(cases.filter { $0.category == "context-from-previous" }.allSatisfy { !($0.previous ?? []).isEmpty })
    #expect(cases.allSatisfy { ($0.mode ?? "casual").isEmpty == false && AppMode(rawValue: $0.mode ?? "casual") != nil })
}
// MARK: - Usage (what AI Polish has cost)

private func usageDefaults() -> UserDefaults {
    let suite = "jvoice.tests.aiPolishUsage.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

@Test func replyCostUsesThePerMillionRates() {
    let usage = AIPolishRequest.Usage(inputTokens: 1_000_000, outputTokens: 1_000_000)
    #expect(AIPolishRequest.cost(usage, model: "claude-haiku-5-5") == 0.60)
    #expect(AIPolishRequest.cost(usage, model: "claude-sonnet-5-5") == 12.0)
    #expect(AIPolishRequest.cost(usage, model: "some-other-model") == nil)
}

@Test func usageAddsUpThisMonthAndAllTime() {
    let store = AIPolishUsageStore(defaults: usageDefaults())
    let usage = AIPolishRequest.Usage(inputTokens: 700, outputTokens: 60)   // $0.0001
    store.record(usage, model: "claude-haiku-5-5", now: date(2026, 10, 3))
    store.record(usage, model: "claude-haiku-5-5", now: date(2026, 10, 17))
    let totals = store.totals(now: date(2026, 10, 20))
    #expect(totals.monthPolishes == 2 && totals.totalPolishes == 2)
    #expect(abs(totals.monthCost - 0.0002) < 1e-12)
    #expect(totals.monthCost == totals.totalCost)
}

@Test func aNewMonthStartsAtZeroButAllTimeKeepsCounting() {
    let store = AIPolishUsageStore(defaults: usageDefaults())
    let usage = AIPolishRequest.Usage(inputTokens: 700, outputTokens: 60)
    store.record(usage, model: "claude-haiku-5-5", now: date(2026, 10, 30))
    #expect(store.totals(now: date(2026, 11, 1)).monthPolishes == 0)
    store.record(usage, model: "claude-haiku-5-5", now: date(2026, 11, 2))
    let november = store.totals(now: date(2026, 11, 3))
    #expect(november.monthPolishes == 1 && november.totalPolishes == 2)
}

@Test func unknownModelsAreNotCountedAndResetKeepsTheBudget() {
    let store = AIPolishUsageStore(defaults: usageDefaults())
    store.record(.init(inputTokens: 10, outputTokens: 10), model: "some-other-model")
    #expect(store.totals().totalPolishes == 0)
    #expect(store.monthlyBudget == AIPolishUsageStore.defaultMonthlyBudget)
    store.monthlyBudget = 25
    store.record(.init(inputTokens: 10, outputTokens: 10), model: "claude-haiku-5-5")
    store.reset()
    #expect(store.totals() == AIPolishUsageStore.Totals())
    #expect(store.monthlyBudget == 25)
}

@Test func dollarsShowFourDecimalsUnderACent() {
    #expect(AIPolishUsageStore.dollars(0) == "$0.00")
    #expect(AIPolishUsageStore.dollars(0.000069) == "$0.0001")
    #expect(AIPolishUsageStore.dollars(0.42) == "$0.42")
}

@Test func refiningIsABusyVisibleStateThatRoundTrips() throws {
    #expect(HUDState.refining.isVisible && HUDState.refining.isBusy && !HUDState.refining.isTerminal)
    #expect(HUDState.refining.headline == "AI refining")
    let data = try JSONEncoder().encode(HUDState.refining)
    #expect(try JSONDecoder().decode(HUDState.self, from: data) == .refining)
}
#endif
