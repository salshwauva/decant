import Foundation

// append-only structured log under Application Support/decant/logs.
// launch failures, dump trims, and doctor notes go here so the gui can
// show a path and a terminal user can tail the file.
enum DecantLog {
    static var directory: URL {
        EnginePaths.support.appendingPathComponent("logs", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("decant.log")
    }

    // rotate when past this size so the file stays readable.
    private static let maxBytes: UInt64 = 2 * 1024 * 1024

    static func ensureFile() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        rotateIfNeeded(url)
        return url
    }

    static func line(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let row = "[\(stamp)] \(message)\n"
        do {
            let url = try ensureFile()
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = row.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            FileHandle.standardError.write(Data("decant log failed: \(error)\n".utf8))
        }
        FileHandle.standardError.write(Data(row.utf8))
    }

    private static func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes
        else { return }
        let bak = url.deletingLastPathComponent().appendingPathComponent("decant.log.1")
        try? fm.removeItem(at: bak)
        try? fm.moveItem(at: url, to: bak)
        fm.createFile(atPath: url.path, contents: nil)
    }

    // last non-empty lines for gui banners (best-effort, small files).
    static func tail(lines n: Int = 12) -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        let parts = text.split(whereSeparator: \.isNewline).map(String.init)
        return parts.suffix(n).joined(separator: "\n")
    }
}
