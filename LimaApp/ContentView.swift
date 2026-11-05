import SwiftUI

// The placeholder first screen. Phase 1 replaces it with the test bench (#1).
// `body` describes what the screen shows. SwiftUI redraws it when its data changes.
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

// Shows this screen in Xcode's preview canvas. It doesn't ship in the app.
#Preview {
    ContentView()
}
