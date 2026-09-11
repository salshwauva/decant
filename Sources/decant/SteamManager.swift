import Foundation
import CryptoKit

// a game decant knows about: its steam app id and display name, read from
// the windows steam install inside the bottle.
struct Game: Identifiable, Equatable {
    var id: String { appID }
    let appID: String
    let name: String
}

// installs and drives the windows steam client inside a bottle, and reads
// back which games are installed. login and the game downloads happen in
// steam's own window; decant just sets the table.
enum SteamManager {
    static let steamSetupURL = "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

    // optional integrity pin for SteamSetup.exe. empty means mz-header only.
    // set DECANT_STEAMSETUP_SHA256 to enforce a full hash after download.
    static var steamSetupSHA256: String? {
        if let s = ProcessInfo.processInfo.environment["DECANT_STEAMSETUP_SHA256"], !s.isEmpty {
            return s.lowercased()
        }
        return nil
    }

    static func steamDir(_ bottle: URL) -> URL {
        bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }
    static func steamExe(_ bottle: URL) -> URL {
        steamDir(bottle).appendingPathComponent("steam.exe")
    }
    static func isInstalled(_ bottle: URL) -> Bool {
        FileManager.default.fileExists(atPath: steamExe(bottle).path)
    }

    // download valve's installer (if needed) and run it silently into the
    // bottle. throws if steam.exe is not present afterward.
    static func installSteam(into bottle: URL, engine: Engine) throws {
        let dl = EnginePaths.support.appendingPathComponent("downloads/SteamSetup.exe")
        if !FileManager.default.fileExists(atPath: dl.path) {
            try FileManager.default.createDirectory(
                at: dl.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let url = URL(string: steamSetupURL) else {
                throw DecantError.launch("bad SteamSetup url")
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw DecantError.launch("could not download SteamSetup.exe: \(error.localizedDescription)")
            }
            try validateSteamSetup(data)
            try data.write(to: dl, options: .atomic)
            DecantLog.line("downloaded SteamSetup.exe (\(data.count) bytes)")
        } else {
            // re-check cached installer
            try validateSteamSetup(Data(contentsOf: dl))
        }
        let r = try EngineManager.run(engine.wine, [dl.path, "/S"], extraEnv: EngineManager.bottleEnv(bottle))
        if r.code != 0 || !isInstalled(bottle) {
            throw DecantError.launch("steam install did not produce steam.exe: \(r.err.isEmpty ? r.out : r.err)")
        }
    }

    static func validateSteamSetup(_ data: Data) throws {
        guard data.count > 64, data[0] == 0x4D, data[1] == 0x5A else {
            throw DecantError.launch("SteamSetup.exe is not a PE (missing MZ header)")
        }
        let offset = (0..<4).reduce(0) { $0 | (Int(data[60 + $1]) << (8 * $1)) }
        guard offset >= 64, offset <= data.count - 4,
              Array(data[offset..<(offset + 4)]) == [0x50, 0x45, 0, 0] else {
            throw DecantError.launch("SteamSetup.exe has no valid PE signature")
        }
        if let expected = steamSetupSHA256 {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == expected else {
                throw DecantError.launch("SteamSetup.exe sha256 mismatch (got \(hex), expected \(expected))")
            }
        }
    }

    static var launchScript: URL { EnginePaths.launchScript }

    static func validAppID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private static func request(_ args: [String], bottle: URL, engine: Engine) throws {
        let script = try requireLaunchScript()
        var env = EngineManager.bottleEnv(bottle)
        env["WINE_BIN"] = engine.wine
        let bin = URL(fileURLWithPath: engine.wine).deletingLastPathComponent()
        env["WINESERVER_BIN"] = bin.appendingPathComponent("wineserver").path
        env["WINE_APP"] = bin.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path
        let result = try EngineManager.run("/bin/bash", [script.path] + args, extraEnv: env)
        if !result.err.isEmpty { DecantLog.line(result.err) }
        guard result.code == 0 else {
            throw DecantError.launch(result.err.isEmpty ? "launcher exited \(result.code)" : result.err)
        }
    }

    private static func requireLaunchScript() throws -> URL {
        let url = launchScript
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw DecantError.launch(
                "launch script missing at \(url.path). run ./scripts/bundle.sh from the monorepo")
        }
        return url
    }

    // result message for the ui (e.g. dump trim note). throws on hard failure.
    @discardableResult
    static func launchClient(_ bottle: URL, engine: Engine) throws -> String? {
        let note = try clearDumpsIfBig(bottle)
        try request(["steam"], bottle: bottle, engine: engine)
        DecantLog.line("steam open request sent")
        return note
    }

    @discardableResult
    static func launchGame(appID: String, bottle: URL, engine: Engine) throws -> String? {
        guard validAppID(appID) else {
            throw DecantError.launch("invalid steam app id: \(appID)")
        }
        let note = try clearDumpsIfBig(bottle)
        try request(["play", appID], bottle: bottle, engine: engine)
        DecantLog.line("game launch request sent appid=\(appID)")
        return [note, "launch request sent to steam; game startup is not yet verified"].compactMap { $0 }.joined(separator: "; ")
    }

    static func uninstallGame(appID: String, bottle: URL, engine: Engine) throws {
        guard validAppID(appID) else {
            throw DecantError.launch("invalid steam app id: \(appID)")
        }
        try request(["uninstall", appID], bottle: bottle, engine: engine)
        DecantLog.line("uninstall requested appid=\(appID)")
    }

    // clear crash dumps before launching if they've grown past the cap.
    // returns a short note when bytes were freed.
    private static func clearDumpsIfBig(_ bottle: URL) throws -> String? {
        let report = Housekeeping.evaluateDumps(bottle)
        guard report.overCap else { return nil }
        let freed = try Housekeeping.trimDumps(report)
        if freed > 0 {
            let note = "cleared \(Housekeeping.human(freed)) of crash dumps"
            DecantLog.line(note)
            return note
        }
        return nil
    }

    // games installed in the bottle, read from steam's appmanifest files.
    // covers the default library plus any extra library folders.
    static func installedGames(_ bottle: URL) throws -> [Game] {
        let fm = FileManager.default
        var roots = [steamDir(bottle).appendingPathComponent("steamapps", isDirectory: true)]
        roots.append(contentsOf: try extraLibraryFolders(bottle))

        var games: [Game] = []
        var seen = Set<String>()
        for root in roots {
            if !fm.fileExists(atPath: root.path) { continue }
            let items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for f in items
            where f.lastPathComponent.hasPrefix("appmanifest_") && f.pathExtension == "acf" {
                let txt = try String(contentsOf: f, encoding: .utf8)
                guard let app = ValveKeyValues.parse(txt)?["AppState"]?.object,
                      let appid = app["appid"]?.text, validAppID(appid),
                      let name = app["name"]?.text else {
                    throw DecantError.launch("invalid Steam manifest: \(f.lastPathComponent); refresh after Steam completes its update")
                }
                guard app["StateFlags"] == nil || (UInt(app["StateFlags"]?.text ?? "") ?? 0) & 4 != 0,
                      !seen.contains(appid),
                      !isSupportPackage(appID: appid, name: name)
                else { continue }
                seen.insert(appid)
                games.append(Game(appID: appid, name: name))
            }
        }
        let keyed: [(game: Game, name: String)] = games.map { ($0, $0.name.lowercased()) }
        let sorted = keyed.sorted { left, right in
            if left.name == right.name { return left.game.appID < right.game.appID }
            return left.name < right.name
        }
        return sorted.map { $0.game }
    }

    // steam ships shared runtimes/redistributables as "apps" in steamapps;
    // they aren't games and shouldn't land on the shelf.
    static func isSupportPackage(appID: String, name: String) -> Bool {
        let junkIDs: Set<String> = ["228980", "1070560", "1391110", "1628350"]
        return junkIDs.contains(appID)
    }

    // additional steam library folders declared in libraryfolders.vdf, mapped
    // from windows paths back to the bottle's drive_c.
    static func extraLibraryFolders(_ bottle: URL) throws -> [URL] {
        let vdf = steamDir(bottle).appendingPathComponent("steamapps/libraryfolders.vdf")
        if !FileManager.default.fileExists(atPath: vdf.path) { return [] }
        let txt = try String(contentsOf: vdf, encoding: .utf8)
        var out: [URL] = []
        guard let libraries = ValveKeyValues.parse(txt)?["libraryfolders"]?.object else {
            throw DecantError.launch("invalid libraryfolders.vdf; refresh after Steam completes its update")
        }
        for value in libraries.values {
            guard let path = value.object?["path"]?.text,
                  let root = libraryURL(path, bottle: bottle) else { continue }
            out.append(root.appendingPathComponent("steamapps", isDirectory: true))
        }
        return out
    }

    static func libraryURL(_ path: String, bottle: URL) -> URL? {
        let bytes = Array(path.utf8)
        guard bytes.count >= 3, bytes[1] == 58,
              (65...90).contains(bytes[0]) || (97...122).contains(bytes[0]),
              bytes[2] == 92 || bytes[2] == 47 else { return nil }
        let drive = String(UnicodeScalar(bytes[0])).lowercased()
        let mapping = bottle.appendingPathComponent("dosdevices/\(drive):")
        let root: URL
        if FileManager.default.fileExists(atPath: mapping.path) {
            root = mapping.resolvingSymlinksInPath()
        } else if drive == "c" {
            root = bottle.appendingPathComponent("drive_c")
        } else {
            return nil
        }
        let rest = path.dropFirst(3).replacingOccurrences(of: "\\", with: "/")
        let components = rest.split(separator: "/")
        guard !components.contains("..") else { return nil }
        return components.reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    static func vdfValue(_ s: String, _ key: String) -> String? {
        vdfValues(s, key).first
    }

    static func vdfValues(_ s: String, _ key: String) -> [String] {
        guard let root = ValveKeyValues.parse(s) else { return [] }
        var pending = [root]
        var values: [String] = []
        while let object = pending.popLast() {
            if let value = object[key]?.text { values.append(value) }
            for value in object.values {
                if let child = value.object { pending.append(child) }
            }
        }
        return values
    }
}
