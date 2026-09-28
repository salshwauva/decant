import AppKit
import ImageIO

// one small macOS app per installed game, so every game has an icon that
// launches it. steam under wine drops linux .desktop/.url shortcuts on the
// desktop instead: macOS can't run those, and a custom icon stamped onto them
// lives in the resource fork, which anything that rewrites the file drops.
//
// a launcher carries its icon as icon.icns inside the bundle. its only job is
// to open decant://play/<appid>, which decant turns into the same request the
// play button sends. launchers go in ~/Applications/decant and on the desktop.
// once a game's launchers exist, its steam shortcuts are removed.
enum GameLaunchers {
    static let scheme = "decant"
    // bump when the bundle layout changes so existing launchers get rebuilt.
    static let format = 1

    private static let icnsSizes = [16, 32, 128, 256, 512]

    static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    static var defaultTargets: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Applications/decant", isDirectory: true), desktop]
    }

    // steam's .ico for each game, copied out the first time it's found. the
    // only record of which .ico belongs to which game is the shortcut this
    // file removes, so the copy is what keeps the icon after that.
    static var iconCache: URL {
        EnginePaths.support.appendingPathComponent("icons", isDirectory: true)
    }

    static func playURL(_ appID: String) -> URL? {
        guard SteamManager.validAppID(appID) else { return nil }
        return URL(string: "\(scheme)://play/\(appID)")
    }

    // the app id in decant://play/<appid>, nil for anything else.
    static func appID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "play" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, SteamManager.validAppID(parts[0]) else { return nil }
        return parts[0]
    }

    // writes each game's launcher into every target that lacks a current one,
    // removes the steam shortcuts of games whose launchers all exist, and
    // removes launchers decant made for games no longer installed. returns one
    // line per failure (also logged) so one bad game never stops the rest.
    @discardableResult
    static func sync(_ games: [Game], bottle: URL,
                     desktop: URL = desktop, targets: [URL] = defaultTargets) -> [String] {
        var failures: [String] = []
        var keep = Set<String>()
        for game in games {
            guard SteamManager.validAppID(game.appID), !game.name.contains("/"),
                  game.name != ".", game.name != ".." else { continue }
            let name = "\(game.name).app"
            keep.insert(name)
            do {
                let icon = try icon(for: game, bottle: bottle, desktop: desktop)
                for dir in targets {
                    let app = dir.appendingPathComponent(name, isDirectory: true)
                    if needsWrite(app, appID: game.appID, source: icon.source) {
                        try write(app, game: game, icon: icon)
                    }
                }
                for file in steamShortcuts(for: game, desktop: desktop) {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                failures.append("launcher \(game.name): \(error)")
            }
        }
        failures += prune(targets, keeping: keep)
        for line in failures { DecantLog.line(line) }
        return failures
    }

    // steam's own shortcuts for this game on the desktop, matched by their
    // steam://rungameid/<appid> line so an unrelated file with the same name
    // stays put.
    static func steamShortcuts(for game: Game, desktop: URL) -> [URL] {
        ["desktop", "url"].map { desktop.appendingPathComponent("\(game.name).\($0)") }
            .filter { file in
                let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info?.isRegularFile == true, info?.isSymbolicLink != true,
                      let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
                let pattern = "steam://(?:rungameid|run)/" + game.appID + "(?:[^0-9]|$)"
                return text.range(of: pattern, options: .regularExpression) != nil
            }
    }

    // the official steam icon when one is known, else the themed medallion.
    // "source" is recorded in the launcher so a medallion launcher gets
    // rebuilt once the real icon turns up.
    private struct Icon {
        let image: NSImage
        let source: String
    }

    private static func icon(for game: Game, bottle: URL, desktop: URL) throws -> Icon {
        let fm = FileManager.default
        let cached = iconCache.appendingPathComponent("\(game.appID).ico")
        if !fm.fileExists(atPath: cached.path),
           let found = GameIcon.officialIcoPath(for: game, bottle: bottle, desktop: desktop),
           fm.fileExists(atPath: found) {
            try fm.createDirectory(at: iconCache, withIntermediateDirectories: true)
            try fm.copyItem(atPath: found, toPath: cached.path)
        }
        if let src = NSImage(contentsOf: cached) {
            return Icon(image: GameIcon.crisp(src), source: "steam")
        }
        return Icon(image: GameIconTheme.icon(for: game), source: "medallion")
    }

    private static func info(_ app: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func isLauncher(_ app: URL) -> Bool {
        (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
            && info(app)?["DecantAppID"] is String
    }

    private static func needsWrite(_ app: URL, appID: String, source: String) -> Bool {
        let fm = FileManager.default
        guard let info = info(app),
              fm.fileExists(atPath: app.appendingPathComponent("Contents/Resources/icon.icns").path),
              fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/launch").path)
        else { return true }
        // never trade a real steam icon down for the medallion.
        let upgrade = source == "steam" && info["DecantIcon"] as? String != source
        return info["DecantAppID"] as? String != appID || info["DecantFormat"] as? Int != format || upgrade
    }

    // builds the bundle in a staging folder on the same volume, then swaps it
    // in, so finder never sees a half-written launcher. refuses to replace
    // anything at that path that decant didn't make.
    private static func write(_ app: URL, game: Game, icon: Icon) throws {
        let fm = FileManager.default
        let exists = (try? app.checkResourceIsReachable()) == true
            || (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        if exists && !isLauncher(app) {
            throw DecantError.launcher("\(app.path) exists and is not a decant launcher")
        }
        guard let url = playURL(game.appID) else { throw DecantError.launcher("bad app id \(game.appID)") }

        try fm.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: app.deletingLastPathComponent(), create: true)
        defer { try? fm.removeItem(at: staging) }
        let built = staging.appendingPathComponent(app.lastPathComponent, isDirectory: true)
        let contents = built.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundleIdentifier": "com.sophia.decant.game.\(game.appID)",
            "CFBundleExecutable": "launch",
            "CFBundleIconFile": "icon",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "\(format)",
            // the launcher only hands off to decant, so it never takes a dock slot.
            "LSUIElement": true,
            "DecantAppID": game.appID,
            "DecantFormat": format,
            "DecantIcon": icon.source,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let launch = macos.appendingPathComponent("launch")
        try "#!/bin/sh\nexec /usr/bin/open \"\(url.absoluteString)\"\n"
            .write(to: launch, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launch.path)
        try icns(icon.image).write(to: resources.appendingPathComponent("icon.icns"))

        if exists {
            _ = try fm.replaceItemAt(app, withItemAt: built)
        } else {
            try fm.moveItem(at: built, to: app)
        }
        NSWorkspace.shared.noteFileSystemChanged(app.path)
    }

    // encodes the image's square bitmap reps at the sizes an .icns holds.
    // both icon sources already carry exact-size reps, so nothing is rescaled.
    static func icns(_ image: NSImage) throws -> Data {
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            .filter { $0.pixelsWide == $0.pixelsHigh && icnsSizes.contains($0.pixelsWide) }
        let data = NSMutableData()
        guard !reps.isEmpty,
              let dest = CGImageDestinationCreateWithData(data, "com.apple.icns" as CFString, reps.count, nil)
        else { throw DecantError.launcher("no icon sizes to encode") }
        for rep in reps {
            guard let cg = rep.cgImage else { throw DecantError.launcher("icon rep has no bitmap") }
            CGImageDestinationAddImage(dest, cg, nil)
        }
        guard CGImageDestinationFinalize(dest) else { throw DecantError.launcher("icns encoding failed") }
        return data as Data
    }

    // decant-made launchers whose game is gone (uninstalled or renamed).
    // anything without decant's marker is left alone. a missing folder has
    // nothing to prune.
    private static func prune(_ targets: [URL], keeping keep: Set<String>) -> [String] {
        var failures: [String] = []
        for dir in targets {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            for app in items where app.pathExtension == "app"
                && !keep.contains(app.lastPathComponent) && isLauncher(app) {
                do { try FileManager.default.removeItem(at: app) }
                catch { failures.append("remove \(app.path): \(error)") }
            }
        }
        return failures
    }
}
