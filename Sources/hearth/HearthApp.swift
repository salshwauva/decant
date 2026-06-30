import SwiftUI

@main
struct HearthApp: App {
    var body: some Scene {
        WindowGroup("hearth") {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 980, height: 640)
        .windowStyle(.hiddenTitleBar)
    }
}
