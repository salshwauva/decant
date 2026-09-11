import Foundation
import Darwin

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
        if let path = ProcessInfo.processInfo.environment["DECANT_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
    case incomplete(Engine, bottle: URL, issues: [String])
    case ready(Engine, bottle: URL)

    var headline: String {
        switch self {
        case .noEngine: return "engine: not installed yet"
        case .engineNoBottle: return "engine: installed, no bottle yet"
        case .incomplete: return "engine: setup incomplete"
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
        case .engineNoBottle(let e), .ready(let e, _), .incomplete(let e, _, _): return e
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
        let marker = bottle.appendingPathComponent("drive_c/windows/system32")
        if FileManager.default.fileExists(atPath: marker.path) {
            let issues = readinessIssues(engine: engine, bottle: bottle)
            if !issues.isEmpty { return .incomplete(engine, bottle: bottle, issues: issues) }
            return .ready(engine, bottle: bottle)
        }
        return .engineNoBottle(engine)
    }

    static func readinessIssues(engine: Engine, bottle: URL, includeGraphics: Bool = true) -> [String] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: engine.wine).deletingLastPathComponent().deletingLastPathComponent()
        var issues: [String] = []
        let version = try? run(engine.wine, ["--version"], timeout: 5)
        if version?.code != 0 || version?.out.trimmingCharacters(in: .whitespacesAndNewlines) != "wine-11.0" {
            issues.append("Wine 11.0 is required")
        }
        var artifacts = [SteamManager.steamExe(bottle), EnginePaths.launchScript,
            EnginePaths.support.appendingPathComponent("engine/scripts/launch-steam.sh"),
            EnginePaths.support.appendingPathComponent("engine/wrapper/steamwebhelper.exe")]
        if !includeGraphics {
            for path in artifacts where !fm.isReadableFile(atPath: path.path) {
                issues.append("missing \(path.lastPathComponent) at \(path.path)")
            }
            return issues
        }
        for arch in ["x86_64-windows", "i386-windows"] {
            for dll in ["dxgi.dll", "d3d11.dll", "d3d10core.dll", "winemetal.dll"] {
                artifacts.append(root.appendingPathComponent("lib/wine/\(arch)/\(dll)"))
            }
        }
        for folder in ["system32", "syswow64"] {
            artifacts.append(bottle.appendingPathComponent("drive_c/windows/\(folder)/winemetal.dll"))
        }
        artifacts.append(root.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so"))
        for path in artifacts where !fm.isReadableFile(atPath: path.path) {
            issues.append("missing \(path.lastPathComponent) at \(path.path)")
        }
        let bridge = root.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so")
        let bridgeData = try? Data(contentsOf: bridge, options: .mappedIfSafe)
        if bridgeData?.range(of: Data("CreateMetalViewFromHWND: content_view=%p".utf8)) == nil {
            issues.append("DXMT window patch is missing; full engine setup is required")
        }
        let driver = root.appendingPathComponent("lib/wine/x86_64-unix/winemac.so")
        let symbols = try? run("/usr/bin/nm", ["-gU", driver.path], timeout: 5)
        let names = Set((symbols?.out ?? "").split(whereSeparator: \.isNewline).compactMap {
            $0.split(whereSeparator: \.isWhitespace).last.map(String.init)
        })
        for symbol in ["_macdrv_get_cocoa_window", "_macdrv_view_create_metal_view", "_macdrv_view_get_metal_layer"] {
            if !names.contains(symbol) { issues.append("driver does not export \(symbol)") }
        }
        return issues
    }

    static func requireSteam(bottle name: String = defaultBottle) throws -> (Engine, URL) {
        guard let engine = Engine.detect() else { throw DecantError.noEngine }
        let bottle = EnginePaths.bottle(name)
        guard FileManager.default.fileExists(atPath: bottle.appendingPathComponent("drive_c/windows/system32").path)
        else { throw DecantError.noBottle }
        let issues = readinessIssues(engine: engine, bottle: bottle, includeGraphics: false)
        if !issues.isEmpty { throw DecantError.launch(issues.joined(separator: "; ")) }
        return (engine, bottle)
    }

    // require fully ready (wine + bottle) for launch paths.
    static func requireReady(bottle name: String = defaultBottle) throws -> (Engine, URL) {
        switch status(bottle: name) {
        case .noEngine:
            throw DecantError.noEngine
        case .engineNoBottle:
            throw DecantError.noBottle
        case .incomplete(_, _, let issues):
            throw DecantError.launch(issues.joined(separator: "; "))
        case .ready(let e, let b):
            return (e, b)
        }
    }

    // files avoid pipe deadlocks when descendants retain output handles.
    // only the output tail enters memory.
    @discardableResult
    static func run(_ launch: String, _ args: [String], extraEnv: [String: String] = [:], timeout: TimeInterval = 120) throws -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("decant-process-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        try p.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                p.waitUntilExit()
            }
            throw DecantError.launch("command timed out: \(URL(fileURLWithPath: launch).lastPathComponent)")
        }
        return RunResult(code: p.terminationStatus, out: try outputTail(outURL), err: try outputTail(errURL))
    }

    private static func outputTail(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
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
    @discardableResult
    static func doctor() -> Bool {
        print("decant doctor")
        print("  support: \(EnginePaths.support.path)")
        print("  log:     \(DecantLog.fileURL.path)")
        print("  launch:  \(EnginePaths.launchScript.path)")
        let current = status()
        switch current {
        case .noEngine:
            print("  engine:  NOT installed")
            print("  looked:  \(EnginePaths.wineBinary)")
            print("  next:    bash engine/install.sh   (from the decant monorepo)")
        case .engineNoBottle(let e):
            print("  wine:    \(e.wine)")
            print("  bottle:  none yet at \(EnginePaths.bottle(defaultBottle).path)")
            print("  next:    decant --init-bottle  then  decant --install-steam")
        case .incomplete(_, _, let issues):
            for issue in issues { print("  issue:   \(issue)") }
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
        return current.isFullyReady
    }
}
