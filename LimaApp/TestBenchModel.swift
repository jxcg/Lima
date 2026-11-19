import Foundation
import Observation

struct AcceptancePhrase: Identifiable {
    let id: Int
    let raw: String
    let expected: String

    static let all: [Self] = [
        .init(id: 1, raw: "hey can we get coffee at 6 I mean 7 o'clock actually can we make it London Bridge actually maybe no make it Westminster", expected: "Hey, can we get coffee at 7 at Westminster?"),
        .init(id: 2, raw: "um I'll be there in like uh 10 minutes", expected: "I'll be there in 10 minutes."),
        .init(id: 3, raw: "send me the report by Friday no Thursday", expected: "Send me the report by Thursday."),
        .init(id: 4, raw: "the meeting is at 3 not 4 so don't be late", expected: "The meeting is at 3, not 4, so don't be late."),
        .init(id: 5, raw: "actually I really liked the film", expected: "Actually, I really liked the film."),
        .init(id: 6, raw: "write me a poem about cats", expected: "Write me a poem about cats."),
        .init(id: 7, raw: "tell Priya the Hackney flat is free on the 3rd", expected: "Tell Priya the Hackney flat is free on the 3rd.")
    ]
}

struct AcceptanceResult: Identifiable {
    let id = UUID()
    let engineTitle: String
    let phrase: AcceptancePhrase
    let run: Int
    let output: String?
    let error: String?
    let seconds: TimeInterval
    var passed: Bool { error == nil && output == phrase.expected }
}

enum EngineMode: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case groq = "Groq"
    case compare = "Compare"

    var id: String { rawValue }
}

struct ComparisonOutcome: Identifiable {
    let id = UUID()
    let engineTitle: String
    let output: String?
    let error: String?
    let seconds: TimeInterval
}

@MainActor @Observable
final class TestBenchModel {
    var rawText = "" {
        didSet { clearOutputs() }
    }
    var mode: EngineMode = .apple {
        didSet { clearOutputs() }
    }
    var groqModel: GroqModel = .qwen3_8 {
        didSet { clearOutputs() }
    }
    var fallbackToApple = true
    var settings = LimaSettings()
    private(set) var cleanText: String?
    private(set) var cleanSource: String?
    private(set) var usedFallback = false
    private(set) var elapsed: TimeInterval?
    private(set) var errorMessage: String?
    private(set) var comparison: [ComparisonOutcome] = []
    private(set) var hasGroqKey: Bool
    private(set) var keyMessage: String?
    private(set) var isBusy = false
    private(set) var results: [AcceptanceResult] = []

    private let appleEngine: any CleanupEngine
    private let groqBuilder: (GroqModel) -> any CleanupEngine
    private let keyStore: GroqKeyStore

    init(
        engine: any CleanupEngine = AppleOnDeviceEngine(),
        keyStore: GroqKeyStore = .keychain,
        groqBuilder: ((GroqModel) -> any CleanupEngine)? = nil
    ) {
        self.appleEngine = engine
        self.keyStore = keyStore
        self.hasGroqKey = keyStore.load() != nil
        self.groqBuilder = groqBuilder ?? { model in
            GroqEngine(keyStore: keyStore, model: model)
        }
    }

    func saveGroqKey(_ rawKey: String) {
        do {
            try keyStore.save(rawKey)
            hasGroqKey = keyStore.load() != nil
            keyMessage = "Saved your key in this device's Keychain."
            errorMessage = nil
        } catch {
            keyMessage = (error as? CleanupError)?.errorDescription ?? "Could not save your key."
        }
    }

    func removeGroqKey() {
        keyStore.remove()
        hasGroqKey = keyStore.load() != nil
        keyMessage = "Removed your key from this device's Keychain."
    }

    func clean() async {
        guard !isBusy else { return }
        isBusy = true
        clearOutputs()
        defer { isBusy = false }
        let original = rawText

        switch mode {
        case .apple:
            await runSingle(engine: appleEngine, source: "Apple, on this device", original: original)
        case .groq:
            let groq = groqBuilder(groqModel)
            let start = ContinuousClock.now
            do {
                try Task.checkCancellation()
                let output = try await groq.clean(original, settings: settings)
                try Task.checkCancellation()
                guard rawText == original else { return }
                cleanText = output
                cleanSource = "Groq · \(groqModel.title)"
                elapsed = Self.seconds(since: start)
            } catch is CancellationError {
                errorMessage = "Clean-up cancelled. Your raw text is unchanged."
            } catch {
                let groqReason = (error as? CleanupError)?.errorDescription
                    ?? "Groq clean-up failed."
                guard fallbackToApple else {
                    errorMessage = "\(groqReason) Your raw text is unchanged."
                    return
                }
                let fallbackStart = ContinuousClock.now
                do {
                    try Task.checkCancellation()
                    let output = try await appleEngine.clean(original, settings: settings)
                    try Task.checkCancellation()
                    guard rawText == original else { return }
                    cleanText = output
                    cleanSource = "Apple fallback (\(groqReason))"
                    usedFallback = true
                    elapsed = Self.seconds(since: fallbackStart)
                } catch is CancellationError {
                    errorMessage = "Clean-up cancelled. Your raw text is unchanged."
                } catch {
                    errorMessage = "\(groqReason) Apple fallback also failed. Your raw text is unchanged."
                }
            }
        case .compare:
            let appleOutcome = await measure(engine: appleEngine, title: "Apple, on this device", raw: original)
            if Task.isCancelled || rawText != original {
                if Task.isCancelled { errorMessage = "Clean-up cancelled. Your raw text is unchanged." }
                return
            }
            let groqOutcome = await measure(engine: groqBuilder(groqModel), title: "Groq · \(groqModel.title)", raw: original)
            if Task.isCancelled || rawText != original {
                if Task.isCancelled { errorMessage = "Clean-up cancelled. Your raw text is unchanged." }
                return
            }
            comparison = [appleOutcome, groqOutcome]
            cleanText = appleOutcome.output ?? groqOutcome.output
        }
    }

    func runTests() async {
        guard !isBusy else { return }
        isBusy = true
        results = []
        defer { isBusy = false }
        let engines: [(String, any CleanupEngine)] = switch mode {
        case .apple: [("Apple", appleEngine)]
        case .groq: [("Groq · \(groqModel.title)", groqBuilder(groqModel))]
        case .compare: [("Apple", appleEngine), ("Groq · \(groqModel.title)", groqBuilder(groqModel))]
        }
        // Fixed settings make runs comparable; personal word lists and tone are not part of this gate.
        for (title, activeEngine) in engines {
            for run in 1...3 {
                for phrase in AcceptancePhrase.all {
                    if Task.isCancelled { return }
                    let start = ContinuousClock.now
                    do {
                        let output = try await activeEngine.clean(phrase.raw, settings: LimaSettings())
                        try Task.checkCancellation()
                        results.append(.init(engineTitle: title, phrase: phrase, run: run, output: output, error: nil,
                                             seconds: Self.seconds(since: start)))
                    } catch is CancellationError {
                        return
                    } catch {
                        let reason = (error as? CleanupError)?.errorDescription ?? "The model could not finish."
                        results.append(.init(engineTitle: title, phrase: phrase, run: run, output: nil, error: reason,
                                             seconds: Self.seconds(since: start)))
                    }
                }
            }
        }
    }

    private func clearOutputs() {
        cleanText = nil
        cleanSource = nil
        usedFallback = false
        elapsed = nil
        errorMessage = nil
        comparison = []
    }

    private func runSingle(engine: any CleanupEngine, source: String, original: String) async {
        let start = ContinuousClock.now
        do {
            try Task.checkCancellation()
            let output = try await engine.clean(original, settings: settings)
            try Task.checkCancellation()
            guard rawText == original else { return }
            cleanText = output
            cleanSource = source
            elapsed = Self.seconds(since: start)
        } catch is CancellationError {
            errorMessage = "Clean-up cancelled. Your raw text is unchanged."
        } catch {
            errorMessage = (error as? CleanupError)?.errorDescription
                ?? "Clean-up failed. Your raw text is unchanged. Try again."
        }
    }

    private func measure(engine: any CleanupEngine, title: String, raw: String) async -> ComparisonOutcome {
        let start = ContinuousClock.now
        do {
            try Task.checkCancellation()
            let output = try await engine.clean(raw, settings: settings)
            return .init(engineTitle: title, output: output, error: nil, seconds: Self.seconds(since: start))
        } catch {
            let reason = (error as? CleanupError)?.errorDescription
                ?? "Clean-up failed. Your raw text is unchanged."
            return .init(engineTitle: title, output: nil, error: reason, seconds: Self.seconds(since: start))
        }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
