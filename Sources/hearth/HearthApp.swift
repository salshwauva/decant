import SwiftUI

@main
struct HearthApp: App {
    init() {
        handleCLI()
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

// headless command paths for testing the engine + steam wiring from a
// terminal before the gui drives them. each one prints and exits; with no
// recognized flag this returns and the window opens normally.
private func handleCLI() {
    let args = CommandLine.arguments
    let bottle = EnginePaths.bottle(EngineManager.defaultBottle)

    if args.contains("--doctor") {
        EngineManager.doctor()
        exit(0)
    }

    if args.contains("--init-bottle") {
        runOrDie {
            print("hearth: creating bottle (first boot can take a minute)...")
            try EngineManager.createBottle()
            print("hearth: bottle ready")
            EngineManager.doctor()
        }
    }

    if args.contains("--install-steam") {
        runOrDie {
            try SteamManager.installSteam(into: bottle, engine: try requireEngine())
            print("hearth: steam installed")
        }
    }

    if args.contains("--steam") {
        runOrDie {
            try SteamManager.launchClient(bottle, engine: try requireEngine())
            print("hearth: launched steam client (sign in there)")
        }
    }

    if args.contains("--games") {
        let games = SteamManager.installedGames(bottle)
        if games.isEmpty { print("hearth: no games installed in the bottle yet") }
        for g in games { print("  \(g.appID)\t\(g.name)") }
        exit(0)
    }

    if let i = args.firstIndex(of: "--play"), i + 1 < args.count {
        let appid = args[i + 1]
        runOrDie {
            try SteamManager.launchGame(appID: appid, bottle: bottle, engine: try requireEngine())
            print("hearth: launching app \(appid)")
        }
    }
}

private func requireEngine() throws -> Engine {
    guard let e = Engine.detect() else { throw HearthError.noEngine }
    return e
}

private func runOrDie(_ body: () throws -> Void) -> Never {
    do { try body() } catch {
        print("hearth: \(error)")
        exit(1)
    }
    exit(0)
}
