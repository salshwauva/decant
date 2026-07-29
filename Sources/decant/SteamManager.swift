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
            try data.write(to: dl)
            DecantLog.line("downloaded SteamSetup.exe (\(data.count) bytes)")
        } else {
            // re-check cached installer
            if let data = try? Data(contentsOf: dl) {
                try validateSteamSetup(data)
            }
        }
        let r = try EngineManager.run(engine.wine, [dl.path, "/S"], extraEnv: EngineManager.bottleEnv(bottle))
        if !isInstalled(bottle) {
            throw DecantError.launch("steam install did not produce steam.exe: \(r.err.isEmpty ? r.out : r.err)")
        }
    }

    private static func validateSteamSetup(_ data: Data) throws {
        guard data.count > 64, data[0] == 0x4D, data[1] == 0x5A else {
            throw DecantError.launch("SteamSetup.exe is not a PE (missing MZ header)")
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
        let script = try requireLaunchScript()
        _ = try EngineManager.spawn("/bin/bash", [script.path, "steam"])
        DecantLog.line("launched steam client")
        return note
    }

    @discardableResult
    static func launchGame(appID: String, bottle: URL, engine: Engine) throws -> String? {
        guard !appID.isEmpty, appID.allSatisfy({ $0.isNumber }) else {
            throw DecantError.launch("invalid steam app id: \(appID)")
        }
        let note = try clearDumpsIfBig(bottle)
        let script = try requireLaunchScript()
        _ = try EngineManager.spawn("/bin/bash", [script.path, "play", appID])
        DecantLog.line("launched game appid=\(appID)")
        return note
    }

    static func uninstallGame(appID: String, bottle: URL, engine: Engine) throws {
        guard !appID.isEmpty, appID.allSatisfy({ $0.isNumber }) else {
            throw DecantError.launch("invalid steam app id: \(appID)")
        }
        let script = try requireLaunchScript()
        _ = try EngineManager.spawn("/bin/bash", [script.path, "uninstall", appID])
        DecantLog.line("uninstall requested appid=\(appID)")
    }

    // clear crash dumps before launching if they've grown past the cap.
    // returns a short note when bytes were freed.
    private static func clearDumpsIfBig(_ bottle: URL) throws -> String? {
        let report = Housekeeping.evaluateDumps(bottle)
        guard report.overCap else { return nil }
        let freed = Housekeeping.trimDumps(bottle)
        if freed > 0 {
            let note = "cleared \(Housekeeping.human(freed)) of crash dumps"
            DecantLog.line(note)
            return note
        }
        return nil
    }

    // games installed in the bottle, read from steam's appmanifest files.
    // covers the default library plus any extra library folders.
    static func installedGames(_ bottle: URL) -> [Game] {
        let fm = FileManager.default
        var roots = [steamDir(bottle).appendingPathComponent("steamapps", isDirectory: true)]
        roots.append(contentsOf: extraLibraryFolders(bottle))

        var games: [Game] = []
        var seen = Set<String>()
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for f in items
            where f.lastPathComponent.hasPrefix("appmanifest_") && f.pathExtension == "acf" {
                guard let txt = try? String(contentsOf: f, encoding: .utf8),
                      let appid = vdfValue(txt, "appid"),
                      let name = vdfValue(txt, "name"),
                      !seen.contains(appid),
                      !isSupportPackage(appID: appid, name: name)
                else { continue }
                seen.insert(appid)
                games.append(Game(appID: appid, name: name))
            }
        }
        return games.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // steam ships shared runtimes/redistributables as "apps" in steamapps;
    // they aren't games and shouldn't land on the shelf.
    static func isSupportPackage(appID: String, name: String) -> Bool {
        let junkIDs: Set<String> = ["228980", "1070560", "1391110", "1628350"]
        if junkIDs.contains(appID) { return true }
        let n = name.lowercased()
        for needle in ["redistributable", "steamworks common", "steam linux runtime",
                       "proton", "directx", "vcredist"] {
            if n.contains(needle) { return true }
        }
        return false
    }

    // additional steam library folders declared in libraryfolders.vdf, mapped
    // from windows paths back to the bottle's drive_c.
    static func extraLibraryFolders(_ bottle: URL) -> [URL] {
        let vdf = steamDir(bottle).appendingPathComponent("steamapps/libraryfolders.vdf")
        guard let txt = try? String(contentsOf: vdf, encoding: .utf8) else { return [] }
        var out: [URL] = []
        for path in vdfValues(txt, "path") {
            // windows path like C:\Games\SteamLibrary -> bottle drive_c
            if let drive = path.first.map({ String($0).lowercased() }) {
                let rest = path.dropFirst(2) // strip "C:"
                    .replacingOccurrences(of: "\\", with: "/")
                let url = bottle
                    .appendingPathComponent("drive_\(drive)")
                    .appendingPathComponent(rest)
                    .appendingPathComponent("steamapps", isDirectory: true)
                out.append(url)
            }
        }
        return out
    }

    // first value for a key in a vdf blob: "key"   "value".
    static func vdfValue(_ s: String, _ key: String) -> String? {
        vdfValues(s, key).first
    }
    static func vdfValues(_ s: String, _ key: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s*\"([^\"]*)\"") else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }
}
