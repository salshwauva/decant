import Foundation

// the engine is the wine 11 + dxmt stack built by engine/install.sh and kept
// under Application Support/decant. decant owns its bottle (a wine prefix).
// nothing here is emulation: wine runs the windows program, rosetta 2
// translates the x86-64, dxmt turns directx into metal.

enum DecantError: Error, CustomStringConvertible {
    case noEngine
    case noBottle
    case bottleInit(String)
    case launch(String)

    var description: String {
        switch self {
        case .noEngine:
            return "no engine: run bash engine/install.sh (wine 11 + dxmt)"
        case .noBottle:
            return "no bottle: run decant --init-bottle, then --install-steam"
        case .bottleInit(let s):
            return "bottle init failed: \(s)"
        case .launch(let s):
            return "launch failed: \(s)"
        }
    }
}

enum EnginePaths {
    // only the monorepo engine install counts: patched wine 11 under
    // Application Support/decant (rebuilt winemac.so + dxmt).
    static var wineBinary: String {
        support.appendingPathComponent(
            "engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
        ).path
    }

    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/decant", isDirectory: true)
    }
    static var bottles: URL { support.appendingPathComponent("bottles", isDirectory: true) }
    static func bottle(_ name: String) -> URL {
        bottles.appendingPathComponent(name, isDirectory: true)
    }

    // launch wrapper deployed by bundle.sh / install.sh.
    static var launchScript: URL {
        support.appendingPathComponent("engine/decant-launch.sh")
    }
}

// a located engine: the wine binary under decant's engine home.
struct Engine {
    let wine: String

    static func detect() -> Engine? {
        let wine = EnginePaths.wineBinary
        guard FileManager.default.isExecutableFile(atPath: wine) else { return nil }
        return Engine(wine: wine)
    }
}

enum EngineStatus {
    case noEngine
    case engineNoBottle(Engine)
    case ready(Engine, bottle: URL)

    var headline: String {
        switch self {
        case .noEngine: return "engine: not installed yet"
        case .engineNoBottle: return "engine: installed, no bottle yet"
        case .ready: return "engine: ready"
        }
    }

    var isFullyReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var engine: Engine? {
        switch self {
        case .noEngine: return nil
        case .engineNoBottle(let e), .ready(let e, _): return e
        }
    }
}

struct RunResult {
    let code: Int32
    let out: String
    let err: String
}

enum EngineManager {
    static let defaultBottle = "steam11"

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

    // require fully ready (wine + bottle) for launch paths.
    static func requireReady(bottle name: String = defaultBottle) throws -> (Engine, URL) {
        switch status(bottle: name) {
        case .noEngine:
            throw DecantError.noEngine
        case .engineNoBottle:
            throw DecantError.noBottle
        case .ready(let e, let b):
            return (e, b)
        }
    }

    // run a process, capturing stdout/stderr on background queues so a full
    // pipe cannot deadlock the waiter (classic dual-pipe hang).
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

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        p.waitUntilExit()
        group.wait()

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
            "DECANT_HOME": EnginePaths.support.path,
        ]
    }

    // launch a process without waiting. stdout/stderr append to the decant
    // log so gui failures are reconstructable.
    @discardableResult
    static func spawn(_ launch: String, _ args: [String], extraEnv: [String: String] = [:]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env

        let logURL = try DecantLog.ensureFile()
        let fh = try FileHandle(forWritingTo: logURL)
        try fh.seekToEnd()
        p.standardOutput = fh
        p.standardError = fh

        DecantLog.line("spawn: \(launch) \(args.joined(separator: " "))")
        try p.run()
        // leave the handle open for the child; process will inherit it.
        // do not close fh here.
        return p.processIdentifier
    }

    // create a fresh bottle by booting wine against a new prefix.
    static func createBottle(_ name: String = defaultBottle) throws {
        guard let engine = Engine.detect() else { throw DecantError.noEngine }
        let bottle = EnginePaths.bottle(name)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        let r = try run(engine.wine, ["wineboot", "--init"], extraEnv: bottleEnv(bottle))
        if r.code != 0 {
            let msg = r.err.isEmpty ? (r.out.isEmpty ? "exit \(r.code)" : r.out) : r.err
            throw DecantError.bottleInit(msg)
        }
    }

    // headless status report, for `decant --doctor`.
    static func doctor() {
        print("decant doctor")
        print("  support: \(EnginePaths.support.path)")
        print("  log:     \(DecantLog.fileURL.path)")
        print("  launch:  \(EnginePaths.launchScript.path)")
        switch status() {
        case .noEngine:
            print("  engine:  NOT installed")
            print("  looked:  \(EnginePaths.wineBinary)")
            print("  next:    bash engine/install.sh   (from the decant monorepo)")
        case .engineNoBottle(let e):
            print("  wine:    \(e.wine)")
            print("  bottle:  none yet at \(EnginePaths.bottle(defaultBottle).path)")
            print("  next:    decant --init-bottle  then  decant --install-steam")
        case .ready(let e, let bottle):
            print("  wine:    \(e.wine)")
            print("  bottle:  \(bottle.path)")
            let dumps = Housekeeping.dumpBytes(bottle)
            print("  dumps:   \(Housekeeping.human(dumps)) (cap \(Housekeeping.human(Housekeeping.dumpCapBytes)))")
            if FileManager.default.fileExists(atPath: EnginePaths.launchScript.path) {
                print("  script:  ok")
            } else {
                print("  script:  MISSING (run ./scripts/bundle.sh)")
            }
        }
        let pins = EnginePaths.support.appendingPathComponent("engine/PINS.md")
        if FileManager.default.fileExists(atPath: pins.path) {
            print("  pins:    \(pins.path)")
        }
    }
}
