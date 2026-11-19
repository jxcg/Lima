import SwiftUI

// The app's starting point. `@main` tells iOS to run this when Lima opens.
// `WindowGroup` owns the window. Both tabs stay alive while the window resizes.
@main
struct LimaApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Test bench", systemImage: "text.badge.checkmark") { TestBenchView() }
                Tab("Welcome", systemImage: "hand.wave") { ContentView() }
            }
            .tint(.indigo)
        }
    }
}
