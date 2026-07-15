import SwiftUI
import CoreText

@main
struct DecantApp: App {
    init() {
        handleCLI()
        registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("decant") {
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
            print("decant: creating bottle (first boot can take a minute)...")
            try EngineManager.createBottle()
            print("decant: bottle ready")
            EngineManager.doctor()
        }
    }

    if args.contains("--install-steam") {
        runOrDie {
            try SteamManager.installSteam(into: bottle, engine: try requireEngine())
            print("decant: steam installed")
        }
    }

    if args.contains("--steam") {
        runOrDie {
            try SteamManager.launchClient(bottle, engine: try requireEngine())
            print("decant: launched steam client (sign in there)")
        }
    }

    if args.contains("--gc") {
        let bytes = Housekeeping.dumpBytes(bottle)
        print("decant: crash dumps \(Housekeeping.human(bytes)) (cap \(Housekeeping.human(Housekeeping.dumpCapBytes)))")
        let freed = Housekeeping.trimDumps(bottle)
        print(freed > 0
            ? "decant: over cap, cleared \(Housekeeping.human(freed))"
            : "decant: under cap, nothing to clear")
        exit(0)
    }

    if args.contains("--games") {
        let games = SteamManager.installedGames(bottle)
        if games.isEmpty { print("decant: no games installed in the bottle yet") }
        for g in games { print("  \(g.appID)\t\(g.name)") }
        exit(0)
    }

    if args.contains("--theme-icons") {
        let games = SteamManager.installedGames(bottle)
        DesktopShortcuts.retheme(games, bottle: bottle)
        print("decant: re-themed desktop icons for \(games.count) game\(games.count == 1 ? "" : "s")")
        exit(0)
    }

    if let i = args.firstIndex(of: "--play"), i + 1 < args.count {
        let appid = args[i + 1]
        runOrDie {
            try SteamManager.launchGame(appID: appid, bottle: bottle, engine: try requireEngine())
            print("decant: launching app \(appid)")
        }
    }
}

// register the bundled Pixelify Sans weights so `.font(.custom(...))` can
// find them by PostScript name. SwiftPM app bundles have no Xcode "Fonts"
// build phase to do this automatically, so it's done by hand, once, before
// any view that uses the font renders.
private func registerBundledFonts() {
    guard let fontsDir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
    let names = ["PixelifySans-Regular", "PixelifySans-Medium", "PixelifySans-Bold"]
    for name in names {
        let url = fontsDir.appendingPathComponent("\(name).ttf")
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

private func requireEngine() throws -> Engine {
    guard let e = Engine.detect() else { throw DecantError.noEngine }
    return e
}

private func runOrDie(_ body: () throws -> Void) -> Never {
    do { try body() } catch {
        print("decant: \(error)")
        exit(1)
    }
    exit(0)
}
