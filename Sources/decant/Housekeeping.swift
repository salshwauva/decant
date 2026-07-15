import Foundation

// keeps a bottle from ballooning the way a steam webhelper crash-loop can.
// when the client crashes repeatedly under wine it writes a minidump per
// crash; left unchecked that reached 100+ GB and filled the disk. before any
// launch, if accumulated crash dumps cross a cap, clear them. dumps are pure
// crash fallout, steam recreates the folder on demand, so deleting is safe.
enum Housekeeping {
    // clear dumps once their total crosses this. 10 GiB by default (the size
    // that prompted this guard); override with DECANT_DUMP_CAP_GB.
    static var dumpCapBytes: UInt64 {
        let gib: UInt64 = 1024 * 1024 * 1024
        if let s = ProcessInfo.processInfo.environment["DECANT_DUMP_CAP_GB"],
           let g = Double(s), g > 0 {
            return UInt64(g * Double(gib))
        }
        return 10 * gib
    }

    // crash-dump locations inside a bottle: steam's own dumps folder plus any
    // per-user temp/crashdump folders wine hands out.
    static func dumpDirs(_ bottle: URL) -> [URL] {
        let fm = FileManager.default
        var dirs = [
            bottle.appendingPathComponent(
                "drive_c/Program Files (x86)/Steam/dumps", isDirectory: true)
        ]
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        if let names = try? fm.contentsOfDirectory(atPath: users.path) {
            for u in names {
                dirs.append(users.appendingPathComponent(
                    "\(u)/AppData/Local/CrashDumps", isDirectory: true))
                dirs.append(users.appendingPathComponent("\(u)/Temp/dumps", isDirectory: true))
            }
        }
        return dirs.filter { fm.fileExists(atPath: $0.path) }
    }

    // recursive byte size of a directory, counting regular files only.
    static func dirSize(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let it = fm.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in it {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true, let s = v?.fileSize { total += UInt64(s) }
        }
        return total
    }

    // total dump bytes across all known locations in the bottle.
    static func dumpBytes(_ bottle: URL) -> UInt64 {
        dumpDirs(bottle).reduce(0) { $0 + dirSize($1) }
    }

    // if dumps have crossed the cap, delete them. returns bytes freed (0 if
    // under the cap or nothing to clear).
    @discardableResult
    static func trimDumps(_ bottle: URL, cap: UInt64 = dumpCapBytes) -> UInt64 {
        let dirs = dumpDirs(bottle)
        let total = dirs.reduce(0) { $0 + dirSize($1) }
        guard total >= cap else { return 0 }
        let fm = FileManager.default
        for d in dirs { try? fm.removeItem(at: d) }
        return total
    }

    static func human(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
}
