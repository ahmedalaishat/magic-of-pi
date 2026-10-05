import SwiftUI

@main
struct PiVisualizerApp: App {
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if showingSplash {
                    SplashView { showingSplash = false }
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
