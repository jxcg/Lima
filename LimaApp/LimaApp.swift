import SwiftUI

// The app's starting point. `@main` tells iOS to run this when Lima opens.
// `WindowGroup` is the app's window, and `ContentView` is the first screen in it.
@main
struct LimaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
