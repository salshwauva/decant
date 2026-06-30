import SwiftUI

@main
struct HearthApp: App {
    init() {
        // headless engine check: `hearth --doctor` prints status and exits,
        // no window. handy for testing the engine wiring from a terminal.
        if CommandLine.arguments.contains("--doctor") {
            EngineManager.doctor()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("hearth") {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 980, height: 640)
        .windowStyle(.hiddenTitleBar)
    }
}
