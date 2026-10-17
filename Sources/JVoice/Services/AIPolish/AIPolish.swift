import Foundation

/// The façade `VoiceCoordinator` and Settings call. Everything that decides lives in
/// `AIPolishRequest` (pure) and `AIPolishClient` (the deadline); this file only wires in the real
/// transport, the app's timeout and the Keychain.
enum AIPolish {
    /// Polishes `text`, or returns it unchanged on ANY failure within `AppTimings.aiPolishTimeout`.
    static func polish(_ text: String, previous: [String], mode: AppMode, vocabulary: [String],
                       transport: any AIPolishTransport = EphemeralTransport.shared,
                       apiKey: @escaping @Sendable () -> String? = { APIKeyStore.read() }) async -> AIPolishResult {
        await AIPolishClient(transport: transport, deadline: AppTimings.aiPolishTimeout)
            .polish(text, previous: previous, mode: mode, vocabulary: vocabulary, apiKey: apiKey)
    }

    /// Dictations shorter than this many words go out unpolished: "ok", "thanks", "sounds good" have
    /// nothing to fix that is worth a round trip.
    static let minWords = 3

    static func isWorthPolishing(_ text: String) -> Bool {
        text.split(whereSeparator: { $0.isWhitespace }).count >= minWords
    }

    // MARK: - Test key

    enum KeyCheck: Equatable, Sendable {
        case works
        case invalidKey
        case rateLimited
        case unreachable
        case failed(String)

        /// Plain words for the Settings status line.
        var message: String {
            switch self {
            case .works: return "Key works."
            case .invalidKey: return "Invalid key — Anthropic didn't accept it."
            case .rateLimited: return "The key works, but Anthropic is rate-limiting it right now."
            case .unreachable: return "Couldn't reach Anthropic. Check your internet connection."
            case .failed(let detail): return detail
            }
        }
    }

    static let keyCheckTimeout: TimeInterval = 10

    /// One tiny request (a 1-token reply) to see whether Anthropic accepts `key`.
    static func checkKey(_ key: String, transport: any AIPolishTransport = EphemeralTransport.shared) async -> KeyCheck {
        let body: [String: Any] = [
            "model": AIPolishRequest.defaultModel,
            "max_tokens": 1,
            "thinking": ["type": "disabled"],
            "messages": [["role": "user", "content": "Hi"]],
        ]
        let request = AIPolishRequest.urlRequest(body: body, apiKey: key, timeout: keyCheckTimeout)
        let check: KeyCheck = await AIPolishClient.withDeadline(
            keyCheckTimeout, timedOut: .unreachable, cancelled: .unreachable
        ) {
            do {
                let (data, response) = try await transport.send(request)
                return keyCheck(status: response.statusCode, data: data)
            } catch {
                return .unreachable
            }
        }
        return check
    }

    static func keyCheck(status: Int, data: Data) -> KeyCheck {
        switch status {
        case 200: return .works
        case 401: return .invalidKey
        case 429: return .rateLimited
        default:
            // Anthropic's own error message (e.g. "Your credit balance is too low…") — shown in
            // Settings only, never logged.
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (object?["error"] as? [String: Any])?["message"] as? String
            if let detail, !detail.isEmpty {
                return .failed("Anthropic said (\(status)): \(String(detail.prefix(160)))")
            }
            return .failed("Anthropic returned an error (\(status)).")
        }
    }
}
