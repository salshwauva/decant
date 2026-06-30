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
        // create the default bottle, then report. for testing the engine
        // wiring from a terminal before the gui drives it.
        if CommandLine.arguments.contains("--init-bottle") {
            do {
                print("hearth: creating bottle (first boot can take a minute)...")
                try EngineManager.createBottle()
                print("hearth: bottle ready")
                EngineManager.doctor()
            } catch {
                print("hearth: \(error)")
                exit(1)
            }
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
