import Foundation

// a game hearth knows about: its steam app id and display name, read from
// the windows steam install inside the bottle.
struct Game: Identifiable {
    var id: String { appID }
    let appID: String
    let name: String
}

// installs and drives the windows steam client inside a bottle, and reads
// back which games are installed. login and the game downloads happen in
// steam's own window; hearth just sets the table.
enum SteamManager {
    static let steamSetupURL = "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

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
            guard let url = URL(string: steamSetupURL),
                  let data = try? Data(contentsOf: url)
            else { throw HearthError.launch("could not download SteamSetup.exe") }
            try data.write(to: dl)
        }
        let r = try EngineManager.run(engine.wine, [dl.path, "/S"], extraEnv: EngineManager.bottleEnv(bottle))
        if !isInstalled(bottle) {
            throw HearthError.launch("steam install did not produce steam.exe: \(r.err)")
        }
    }

    // open the steam client so the user can sign in and install games.
    static func launchClient(_ bottle: URL, engine: Engine) throws {
        try EngineManager.spawn(engine.wine, [steamExe(bottle).path],
                                extraEnv: EngineManager.bottleEnv(bottle))
    }

    // launch an owned, installed game by app id, through steam, with the
    // direct3d-to-metal env in place.
    static func launchGame(appID: String, bottle: URL, engine: Engine) throws {
        try EngineManager.spawn(engine.wine, [steamExe(bottle).path, "-applaunch", appID],
                                extraEnv: EngineManager.gameEnv(bottle))
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
                      !seen.contains(appid)
                else { continue }
                seen.insert(appid)
                games.append(Game(appID: appid, name: name))
            }
        }
        return games.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // additional steam library folders declared in libraryfolders.vdf, mapped
    // from windows paths back to the bottle's drive_c.
    private static func extraLibraryFolders(_ bottle: URL) -> [URL] {
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
