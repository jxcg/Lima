import SwiftUI

// The first screen. Phase 1 replaces this with the test bench.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Lima")
                .font(.largeTitle.bold())
            Text("Dictation clean-up keyboard")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
