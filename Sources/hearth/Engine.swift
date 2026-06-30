import Foundation

// the engine is the wine + game porting toolkit stack hearth drives. hearth
// owns its own bottle (a wine prefix) rather than leaning on whisky or
// crossover at runtime. nothing here is emulation: wine runs the windows
// program, rosetta 2 translates the x86-64, d3dmetal turns directx into metal.

enum HearthError: Error, CustomStringConvertible {
    case noEngine
    case bottleInit(String)
    case launch(String)

    var description: String {
        switch self {
        case .noEngine:
            return "no engine: game porting toolkit / wine not installed"
        case .bottleInit(let s):
            return "bottle init failed: \(s)"
        case .launch(let s):
            return "launch failed: \(s)"
        }
    }
}

enum EnginePaths {
    // the gcenx game porting toolkit cask ships a prebuilt wine inside its
    // app bundle. fall back to the homebrew prefixes if a raw wine is around.
    // first executable path wins.
    static let candidateWine = [
        "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64",
        "/usr/local/bin/wine64",
        "/usr/local/bin/wine",
        "/opt/homebrew/bin/wine64",
        "/opt/homebrew/bin/wine",
    ]
    // the wrapper that sets up d3dmetal and the prefix for a launch.
    static let candidateGptk = [
        "/usr/local/bin/gameportingtoolkit",
        "/opt/homebrew/bin/gameportingtoolkit",
    ]

    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/hearth", isDirectory: true)
    }
    static var bottles: URL { support.appendingPathComponent("bottles", isDirectory: true) }
    static func bottle(_ name: String) -> URL {
        bottles.appendingPathComponent(name, isDirectory: true)
    }
}

// a located engine: a wine binary, and optionally the gptk launcher wrapper
// that wires up d3dmetal for direct3d.
struct Engine {
    let wine: String
    let gptk: String?

    static func detect() -> Engine? {
        let fm = FileManager.default
        guard let wine = EnginePaths.candidateWine.first(where: { fm.isExecutableFile(atPath: $0) })
        else { return nil }
        let gptk = EnginePaths.candidateGptk.first(where: { fm.isExecutableFile(atPath: $0) })
        return Engine(wine: wine, gptk: gptk)
    }
}

enum EngineStatus {
    case noEngine
    case engineNoBottle(Engine)
    case ready(Engine, bottle: URL)

    var headline: String {
        switch self {
        case .noEngine: return "engine: not installed yet"
        case .engineNoBottle: return "engine: ready, no bottle yet"
        case .ready: return "engine: ready"
        }
    }
}

struct RunResult {
    let code: Int32
    let out: String
    let err: String
}

enum EngineManager {
    static let defaultBottle = "default"

    static func status(bottle name: String = defaultBottle) -> EngineStatus {
        guard let engine = Engine.detect() else { return .noEngine }
        let bottle = EnginePaths.bottle(name)
        // a provisioned prefix has windows/system32; treat that as "ready".
        let marker = bottle.appendingPathComponent("drive_c/windows/system32")
        if FileManager.default.fileExists(atPath: marker.path) {
            return .ready(engine, bottle: bottle)
        }
        return .engineNoBottle(engine)
    }

    // run a process, capturing stdout/stderr. the gptk wine is an x86-64
    // binary, so the os runs it through rosetta automatically.
    @discardableResult
    static func run(_ launch: String, _ args: [String], extraEnv: [String: String] = [:]) throws -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return RunResult(
            code: p.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self)
        )
    }

    // environment for every wine call against a bottle: point at the prefix,
    // hush the debug spew, and disable the mono/.net and gecko/ie installers
    // so a headless boot never blocks on their popups (games rarely need them;
    // we can add them per game later if something asks).
    static func bottleEnv(_ bottle: URL) -> [String: String] {
        [
            "WINEPREFIX": bottle.path,
            "WINEDEBUG": "-all",
            "WINEDLLOVERRIDES": "mscoree=d;mshtml=d",
        ]
    }

    // env for launching a game: route the direct3d dlls to wine's builtin
    // versions, which are the gptk ones backed by d3dmetal, so directx lands
    // on metal. hush the metal hud by default.
    static func gameEnv(_ bottle: URL) -> [String: String] {
        var e = bottleEnv(bottle)
        e["WINEDLLOVERRIDES"] = "mscoree=d;mshtml=d;dxgi,d3d9,d3d10core,d3d11,d3d12,d3d12core=b"
        e["MTL_HUD_ENABLED"] = "0"
        return e
    }

    // launch a process without waiting (for long-running guis like the steam
    // client or a game). returns the child pid.
    @discardableResult
    static func spawn(_ launch: String, _ args: [String], extraEnv: [String: String] = [:]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        return p.processIdentifier
    }

    // create a fresh bottle by booting wine against a new prefix.
    static func createBottle(_ name: String = defaultBottle) throws {
        guard let engine = Engine.detect() else { throw HearthError.noEngine }
        let bottle = EnginePaths.bottle(name)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        let r = try run(engine.wine, ["wineboot", "--init"], extraEnv: bottleEnv(bottle))
        if r.code != 0 { throw HearthError.bottleInit(r.err.isEmpty ? "exit \(r.code)" : r.err) }
    }

    // headless status report, for `hearth --doctor`.
    static func doctor() {
        print("hearth doctor")
        switch status() {
        case .noEngine:
            print("  engine:  NOT installed (no wine / game porting toolkit found)")
            print("  looked:  \(EnginePaths.candidateWine.joined(separator: ", "))")
            print("  next:    install game porting toolkit, then hearth can make a bottle")
        case .engineNoBottle(let e):
            print("  wine:    \(e.wine)")
            print("  gptk:    \(e.gptk ?? "(not found)")")
            print("  bottle:  none yet at \(EnginePaths.bottle(defaultBottle).path)")
        case .ready(let e, let bottle):
            print("  wine:    \(e.wine)")
            print("  gptk:    \(e.gptk ?? "(not found)")")
            print("  bottle:  \(bottle.path)")
        }
    }
}
