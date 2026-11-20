import Foundation

// swiftc -swift-version 6 Shared/*.swift LimaApp/TestBenchModel.swift Tests/TestBenchCheck.swift -o /tmp/lima-bench-check
@MainActor
private struct FixedEngine: CleanupEngine {
    let modelTitle = "Test model"
    let output: String
    func clean(_ raw: String, settings: LimaSettings) async throws -> String { output }
}

@MainActor
private struct FailingEngine: CleanupEngine {
    let modelTitle = "Unavailable test model"
    func clean(_ raw: String, settings: LimaSettings) async throws -> String {
        throw CleanupError.failed("The model is busy. Try again.")
    }
}

@main
struct TestBenchCheck {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--apple") {
            let apple = TestBenchModel()
            await apple.runTests()
            for result in apple.results {
                print("Phrase \(result.phrase.id), run \(result.run): \(result.passed ? "PASS" : "FAIL") (\(String(format: "%.3f", result.seconds)) s)")
                if !result.passed { print("Got: \(result.output ?? result.error ?? "No output")") }
            }
            let passed = apple.results.filter(\.passed).count
            print("Apple on this Mac: \(passed)/21 exact matches; not an iPhone result")
            exit(passed == 21 ? 0 : 1)
        }
        let bench = TestBenchModel(engine: FixedEngine(output: "I'll be there in 10 minutes."))
        bench.rawText = "um I'll be there in like uh 10 minutes"
        await bench.clean()
        precondition(bench.rawText == "um I'll be there in like uh 10 minutes")
        precondition(bench.cleanText == "I'll be there in 10 minutes.")
        precondition(bench.cleanSource == "Test model")
        precondition(bench.elapsed != nil && !bench.isBusy && bench.errorMessage == nil)
        bench.rawText = "A different message"
        precondition(bench.cleanText == nil && bench.elapsed == nil, "Editing must clear stale results")

        let failure = TestBenchModel(engine: FailingEngine())
        failure.rawText = "Keep my original words"
        await failure.clean()
        precondition(failure.rawText == "Keep my original words" && failure.cleanText == nil)
        precondition(failure.errorMessage == "The model is busy. Try again.")
        precondition(!failure.isBusy)
        await failure.runTests()
        precondition(failure.results.count == 21)
        precondition(failure.results.allSatisfy { !$0.passed && $0.error != nil })
        precondition(failure.rawText == "Keep my original words")

        let cancelled = TestBenchModel(engine: FixedEngine(output: "Never publish this"))
        cancelled.rawText = "Unchanged"
        let task = Task { await cancelled.clean() }
        task.cancel()
        await task.value
        precondition(cancelled.cleanText == nil && cancelled.rawText == "Unchanged" && !cancelled.isBusy)

        let score = TestBenchModel(engine: FixedEngine(output: "Actually, I really liked the film."))
        await score.runTests()
        precondition(score.results.filter(\.passed).count == 3, "Only the matching phrase should pass, once per run")
        precondition(score.results.allSatisfy { $0.engineTitle == "Test model" })
        precondition(Set(score.results.map(\.run)) == [1, 2, 3])
        precondition(score.results.filter { $0.phrase.id == 5 }.allSatisfy(\.passed))

        var storedKey: String?
        let memoryStore = GroqKeyStore(
            load: { storedKey },
            save: { key in
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw CleanupError.failed("Paste your Groq API key first.") }
                storedKey = trimmed
            },
            remove: { storedKey = nil }
        )
        let testEndpoint = URL(string: "https://test.local/openai/v1/chat/completions")!

        // 1. Missing user key falls back to Apple when fallbackToApple is on, and errors safely when off.
        let groqBench = TestBenchModel(
            engine: FixedEngine(output: "Send me the report by Thursday."),
            keyStore: memoryStore,
            groqBuilder: { model in
                GroqEngine(keyStore: memoryStore, model: model, endpoint: testEndpoint) { req in
                    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
                    let messages = body["messages"] as! [[String: String]]
                    precondition(messages.first?["role"] == "system", "Instructions must be in system message")
                    precondition(messages.dropFirst().first?["role"] == "user", "First example must be user turn")
                    let resp = #"{"choices":[{"message":{"content":"<think>check</think>Send me the report by Thursday"}}]}"#
                    return (Data(resp.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            }
        )
        groqBench.mode = .groq
        groqBench.rawText = "send me the report by Friday no Thursday"
        groqBench.fallbackToApple = false
        await groqBench.clean()
        precondition(groqBench.cleanText == nil && groqBench.rawText == "send me the report by Friday no Thursday")
        precondition(groqBench.errorMessage?.contains("Add your own Groq API key first.") == true)

        groqBench.fallbackToApple = true
        await groqBench.clean()
        precondition(groqBench.cleanText == "Send me the report by Thursday.")
        precondition(groqBench.usedFallback && groqBench.cleanSource?.contains("Apple fallback") == true)
        precondition(groqBench.cleanSource?.contains("Test model") == true)

        // 2. Saving a user key uses Groq directly, strips <think> blocks, and applies post-guards.
        groqBench.saveGroqKey("  gsk_user_supplied_test_key  ")
        precondition(groqBench.hasGroqKey && storedKey == "gsk_user_supplied_test_key")
        await groqBench.clean()
        precondition(groqBench.cleanText == "Send me the report by Thursday.")
        precondition(!groqBench.usedFallback && groqBench.cleanSource == "Groq · Qwen 3.8 27B (preview)")

        // 3. HTTP 429 handling and Compare mode.
        let compareBench = TestBenchModel(
            engine: FixedEngine(output: "I'll be there in 10 minutes."),
            keyStore: memoryStore,
            groqBuilder: { model in
                GroqEngine(keyStore: memoryStore, model: model, endpoint: testEndpoint) { req in
                    precondition(req.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_user_supplied_test_key")
                    return (Data(), HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
                }
            }
        )
        compareBench.mode = .compare
        compareBench.rawText = "um I'll be there in like uh 10 minutes"
        await compareBench.clean()
        precondition(compareBench.comparison.count == 2)
        precondition(compareBench.comparison[0].engineTitle == "Test model")
        precondition(compareBench.comparison[0].output == "I'll be there in 10 minutes." && compareBench.comparison[0].error == nil)
        precondition(compareBench.comparison[1].output == nil && compareBench.comparison[1].error?.contains("rate limit") == true)
        precondition(compareBench.rawText == "um I'll be there in like uh 10 minutes")

        compareBench.removeGroqKey()
        precondition(!compareBench.hasGroqKey && storedKey == nil)

        print("PASS: raw text preservation, errors, stale result clearing, cancellation, 21-result scoring, Groq BYOK Keychain flow, Apple fallback and Compare mode")
    }
}
