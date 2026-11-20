import FoundationModels
import SwiftUI

struct TestBenchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var bench = TestBenchModel()
    @State private var unavailable: String?
    @State private var keyDraft = ""
    @State private var operation: Task<Void, Never>?
    @State private var showResults = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    ArrangementView {
                        Form { inputSections }
                    } secondary: {
                        Form { outputSections }
                    }
                    .arrangementViewStyle(.split)
                } else {
                    Form {
                        inputSections
                        outputSections
                    }
                }
            }
            .navigationTitle("Test bench")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", systemImage: "keyboard.chevron.compact.down") { editing = false }
                }
            }
            .sheet(isPresented: $showResults) { resultsView }
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active { refreshAvailability() }
        }
    }

    private var canRunSelectedEngine: Bool {
        switch bench.mode {
        case .apple: unavailable == nil
        case .groq: bench.hasGroqKey || (bench.fallbackToApple && unavailable == nil)
        case .compare: unavailable == nil || bench.hasGroqKey
        }
    }

    private var inputSections: some View {
        @Bindable var bench = bench
        return Group {
            Section {
                Picker("Engine", selection: $bench.mode) {
                    ForEach(EngineMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(bench.isBusy)
                .accessibilityIdentifier("engine-picker")

                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple, on this device", systemImage: "iphone")
                        .font(.headline)
                    Text(unavailable ?? "Text stays on this device. Check the result before sending.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Check availability", systemImage: "arrow.clockwise") { refreshAvailability() }
                        .disabled(bench.isBusy)
                }
            }

            if bench.mode != .apple {
                Section {
                    Label(
                        bench.hasGroqKey ? "Your Groq key is saved in Keychain" : "No Groq API key saved",
                        systemImage: bench.hasGroqKey ? "key.fill" : "key"
                    )
                    .foregroundStyle(bench.hasGroqKey ? .primary : .secondary)
                    .accessibilityIdentifier("groq-key-status")

                    SecureField("Paste your own Groq API key", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($editing)
                        .disabled(bench.isBusy)
                        .accessibilityIdentifier("groq-key-field")

                    Button(bench.hasGroqKey ? "Replace key in Keychain" : "Save key in Keychain", systemImage: "lock.fill") {
                        editing = false
                        bench.saveGroqKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(bench.isBusy || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-groq-key")

                    if bench.hasGroqKey {
                        Button("Remove key from Keychain", systemImage: "trash", role: .destructive) {
                            bench.removeGroqKey()
                        }
                        .disabled(bench.isBusy)
                        .accessibilityIdentifier("remove-groq-key")
                    }

                    if let keyMessage = bench.keyMessage {
                        Text(keyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Groq model", selection: $bench.groqModel) {
                        ForEach(GroqModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .disabled(bench.isBusy)

                    if bench.mode == .groq {
                        Toggle("Fall back to Apple if Groq fails", isOn: $bench.fallbackToApple)
                            .disabled(bench.isBusy)
                    }
                } header: {
                    Text("Groq (your own key)")
                } footer: {
                    Text("Lima never ships with a shared Groq key. Your key stays in this device's Keychain. Turn on Zero Data Retention in your Groq console so your text is not stored.")
                }
            }

            Section {
                TextField("Type or dictate a message", text: $bench.rawText, axis: .vertical)
                    .lineLimit(3...12)
                    .focused($editing)
                    .disabled(bench.isBusy)
                    .accessibilityLabel("Raw text")
                    .accessibilityIdentifier("raw-text")
                Menu("Load an example", systemImage: "text.badge.plus") {
                    ForEach(AcceptancePhrase.all) { phrase in
                        Button("\(phrase.id). \(phrase.expected)") { bench.rawText = phrase.raw }
                    }
                }
                .disabled(bench.isBusy)
            } header: {
                Text("Raw text")
            } footer: {
                Text("Your raw text stays unchanged, even if clean-up fails.")
            }

            Section {
                Button("Clean", systemImage: "sparkles") {
                    editing = false
                    operation = Task { await bench.clean() }
                }
                .disabled(!canRunSelectedEngine || bench.isBusy || bench.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("clean")
                if bench.isBusy {
                    ProgressView(bench.mode == .apple ? "Working on this device…" : "Cleaning message…")
                    Button("Cancel", systemImage: "stop.circle") { operation?.cancel() }
                }
            }
        }
    }

    private var outputSections: some View {
        Group {
            Section("Clean text") {
                if !bench.comparison.isEmpty {
                    ForEach(bench.comparison) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.engineTitle)
                                .font(.subheadline.weight(.semibold))
                            if let output = item.output {
                                Text(output)
                                    .textSelection(.enabled)
                                ShareLink("Share \(item.engineTitle) text", item: output)
                                    .font(.caption)
                            } else if let error = item.error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                            Text("\(item.seconds, format: .number.precision(.fractionLength(2))) seconds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("comparison-results")
                } else if let error = bench.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("cleanup-error")
                } else if let cleanText = bench.cleanText {
                    Text(cleanText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("clean-text")
                    if let elapsed = bench.elapsed {
                        if let source = bench.cleanSource {
                            Label(source, systemImage: bench.usedFallback ? "arrow.uturn.backward.circle" : "cpu")
                                .font(.subheadline)
                        }
                        Text("\(elapsed, format: .number.precision(.fractionLength(2))) seconds")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ShareLink("Share clean text", item: cleanText)
                } else {
                    Text("Your cleaned message will appear here.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Run tests", systemImage: "checklist") {
                    editing = false
                    showResults = true
                    operation = Task { await bench.runTests() }
                }
                .disabled(!canRunSelectedEngine || bench.isBusy)
                .accessibilityIdentifier("run-tests")
                if !bench.results.isEmpty {
                    Button("View results", systemImage: "list.bullet.rectangle") { showResults = true }
                }
            } header: {
                Text("Acceptance checks")
            } footer: {
                Text("Seven phrases, three runs each. Exact matches only. This is an experimental iOS port; earlier Mac scores are not results for this build.")
            }
        }
    }

    private func refreshAvailability() {
        unavailable = AppleOnDeviceEngine.unavailableReason(SystemLanguageModel.default.availability)
    }

    private var resultsView: some View {
        NavigationStack {
            List {
                Section {
                    let total = max(21, bench.results.count)
                    Text("\(bench.results.filter(\.passed).count)/\(total) exact matches")
                        .font(.headline)
                    Text(bench.isBusy ? "Completed \(bench.results.count) of \(total)" : "Completed \(bench.results.count) of \(total). A partial run does not pass the gate.")
                        .foregroundStyle(.secondary)
                    if bench.isBusy {
                        ProgressView()
                        Button("Cancel tests", systemImage: "stop.circle") { operation?.cancel() }
                    }
                }
                ForEach(bench.results) { result in
                    DisclosureGroup {
                        Text("Raw: \(result.phrase.raw)")
                        Text("Expected: \(result.phrase.expected)")
                        Text("Got: \(result.output ?? result.error ?? "No output")")
                            .textSelection(.enabled)
                        Text("\(result.seconds, format: .number.precision(.fractionLength(2))) seconds")
                    } label: {
                        Label("\(result.engineTitle) · Phrase \(result.phrase.id), run \(result.run): \(result.passed ? "Pass" : "Fail")",
                              systemImage: result.passed ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            }
            .navigationTitle("Test results")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { showResults = false }
                }
            }
        }
    }
}

#Preview { TestBenchView() }
