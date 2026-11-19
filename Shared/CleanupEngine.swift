import Foundation
import FoundationModels
import Security

struct LimaSettings: Sendable {
    enum Tone: String, CaseIterable, Sendable { case casual, work }
    var tone: Tone = .casual
    var words: [String] = []
}

enum GroqModel: String, CaseIterable, Identifiable, Sendable {
    case qwen3_8 = "qwen/qwen3.8-27b"
    case qwen3_32 = "qwen/qwen3-32b"
    case gptOSS = "openai/gpt-oss-20b"
    case llama = "llama-3.3-70b-versatile"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .qwen3_8: "Qwen 3.8 27B (preview)"
        case .qwen3_32: "Qwen 3 32B (preview)"
        case .gptOSS: "GPT-OSS 20B"
        case .llama: "Llama 3.3 70B"
        }
    }
}

// Stores the user's own Groq API key in the device Keychain, never in code or git.
@MainActor
struct GroqKeyStore {
    var load: () -> String?
    var save: (String) throws -> Void
    var remove: () -> Void

    private static let account = "groq-api-key"
    // Unsigned Simulator builds lack the Keychain entitlement (-34018); keep a RAM-only session fallback.
    private static var unsignedSessionKey: String?
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "lima.keychain",
            kSecAttrAccount as String: account
        ]
    }

    static let keychain = Self(
        load: {
            var item: CFTypeRef?
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data,
               let key = String(data: data, encoding: .utf8), !key.isEmpty {
                return key
            }
            return unsignedSessionKey
        },
        save: { rawKey in
            let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CleanupError.failed("Paste your Groq API key first.") }
            let data = Data(trimmed.utf8)
            SecItemDelete(query as CFDictionary)
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecMissingEntitlement {
                unsignedSessionKey = trimmed
                return
            }
            guard status == errSecSuccess else {
                throw CleanupError.failed("Could not save the key to the Keychain (\(status)).")
            }
            unsignedSessionKey = nil
        },
        remove: {
            SecItemDelete(query as CFDictionary)
            unsignedSessionKey = nil
        }
    )
}

@MainActor
protocol CleanupEngine {
    func clean(_ raw: String, settings: LimaSettings) async throws -> String
}

enum CleanupError: LocalizedError, Equatable {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): message }
    }
}

@MainActor
struct AppleOnDeviceEngine: CleanupEngine {
    static func unavailableReason(_ availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings."
        case .unavailable(.modelNotReady): "Apple's model is not ready yet. Check its download in Settings."
        case .unavailable: "Apple's model is unavailable. Try again later."
        }
    }

    func clean(_ raw: String, settings: LimaSettings) async throws -> String {
        try Task.checkCancellation()
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.failed("Type or dictate a message first.")
        }
        if let reason = Self.unavailableReason(SystemLanguageModel.default.availability) {
            throw CleanupError.failed(reason)
        }
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(
                segments: [.text(.init(content: CleanupRules.instructions(settings: settings)))],
                toolDefinitions: []
            ))
        ]
        for (input, output) in CleanupRules.examples {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: CleanupRules.prompt(input)))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: output))])))
        }
        let session = LanguageModelSession(transcript: Transcript(entries: entries))
        do {
            let response = try await session.respond(
                to: CleanupRules.prompt(CleanupGuards.prepare(raw)), generating: CleanMessage.self,
                options: GenerationOptions(maximumResponseTokens: max(80, raw.split(separator: " ").count * 5))
            )
            try Task.checkCancellation()
            guard !response.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CleanupError.failed("The model returned no text. Try again.")
            }
            let text = CleanupGuards.finish(raw: raw, output: response.content.text)
            guard !text.isEmpty else { throw CleanupError.failed("The model returned no text. Try again.") }
            return text
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CleanupError {
            throw error
        } catch let error as LanguageModelError {
            switch error {
            case .rateLimited: throw CleanupError.failed("The model is busy. Wait a moment and try again.")
            case .timeout: throw CleanupError.failed("Apple's model timed out. Try again.")
            case .contextSizeExceeded: throw CleanupError.failed("This message is too long for the model. Try a shorter message.")
            case .guardrailViolation, .refusal: throw CleanupError.failed("Apple's safety checks stopped this clean-up. Your raw text is unchanged.")
            default: throw CleanupError.failed("Apple's model could not finish. Your raw text is unchanged.")
            }
        } catch {
            throw CleanupError.failed("Apple's model could not finish. Your raw text is unchanged.")
        }
    }
}

@MainActor
struct GroqEngine: CleanupEngine {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var keyStore: GroqKeyStore = .keychain
    var model: GroqModel = .qwen3_8
    var endpoint = URL(string: ProcessInfo.processInfo.environment["LIMA_GROQ_URL"]
        ?? "https://api.groq.com/openai/v1/chat/completions")!
    var transport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CleanupError.failed("Groq returned an invalid response.")
        }
        return (data, http)
    }

    func clean(_ raw: String, settings: LimaSettings) async throws -> String {
        try Task.checkCancellation()
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.failed("Type or dictate a message first.")
        }
        guard let apiKey = keyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw CleanupError.failed("Add your own Groq API key first.")
        }

        var messages: [[String: String]] = [[
            "role": "system",
            "content": CleanupRules.instructions(settings: settings)
                + "\nOutput only the final cleaned message, with no quotes, JSON, or extra commentary."
        ]]
        for (input, output) in CleanupRules.examples {
            messages.append(["role": "user", "content": CleanupRules.prompt(input)])
            messages.append(["role": "assistant", "content": output])
        }
        messages.append(["role": "user", "content": CleanupRules.prompt(CleanupGuards.prepare(raw))])

        var payload: [String: Any] = [
            "model": model.rawValue,
            "messages": messages,
            "temperature": 0.0,
            "max_completion_tokens": max(80, raw.split(separator: " ").count * 5),
            "stream": false
        ]
        switch model {
        case .qwen3_8, .qwen3_32:
            payload["reasoning_effort"] = "none"
            payload["reasoning_format"] = "hidden"
        case .gptOSS:
            payload["reasoning_effort"] = "low"
            payload["include_reasoning"] = false
        case .llama:
            break
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await transport(request)
        } catch let error as CleanupError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CleanupError.failed("Could not reach Groq. Check your connection.")
        }
        try Task.checkCancellation()

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw CleanupError.failed("Groq rejected your API key. Check the key and try again.")
        case 429:
            throw CleanupError.failed("Your Groq account hit its rate limit. Wait a moment and try again.")
        default:
            throw CleanupError.failed("Groq could not finish (HTTP \(http.statusCode)).")
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw CleanupError.failed("Groq returned an unreadable response.")
        }
        let rawContent = Self.stripThinking(decoded.choices.first?.message.content ?? "")
        guard !rawContent.isEmpty else {
            throw CleanupError.failed("Groq returned no text. Try again.")
        }
        let text = CleanupGuards.finish(raw: raw, output: rawContent)
        guard !text.isEmpty else {
            throw CleanupError.failed("Groq returned no text. Try again.")
        }
        return text
    }

    static func stripThinking(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
