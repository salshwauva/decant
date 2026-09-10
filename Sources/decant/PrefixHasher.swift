import Foundation
import CryptoKit

// a content fingerprint for a wine prefix. the engine fault tests use it to
// prove a failed engine install left the game data alone.
//
// this walks every file, so it is for the small fake prefix in the
// self-test. do not run it over a real bottle in the doctor path.
enum PrefixHasher {
    // paths that change on their own and say nothing about game data.
    static let defaultSkips = [
        "drive_c/Program Files (x86)/Steam/dumps",
        "**/CrashDumps",
    ]

    // sha256 over sorted relative paths and the bytes of each file, so both
    // a renamed file and an edited file change the digest.
    static func sha256(of directory: URL, skipping: [String] = defaultSkips) -> String {
        var hasher = SHA256()
        let files = (try? EngineStore.relativeFiles(of: directory)) ?? []
        for path in files where !skips(path, skipping) {
            hasher.update(data: Data(path.utf8))
            if let bytes = try? Data(contentsOf: directory.appendingPathComponent(path),
                                     options: .mappedIfSafe) {
                hasher.update(data: bytes)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // a pattern that starts with **/ matches any path component. every other
    // pattern matches a path prefix.
    private static func skips(_ path: String, _ patterns: [String]) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        for pattern in patterns {
            if pattern.hasPrefix("**/") {
                let name = String(pattern.dropFirst(3))
                if parts.contains(name) { return true }
            } else if path == pattern || path.hasPrefix(pattern + "/") {
                return true
            }
        }
        return false
    }
}
