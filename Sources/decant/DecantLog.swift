import Foundation
import Darwin

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

    private static func ensureFile() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(fd)
        try rotateIfNeeded(url)
        return url
    }

    static func line(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let row = "[\(stamp)] \(message)\n"
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let lock = open(directory.appendingPathComponent(".lock").path,
                            O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
            guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { flock(lock, LOCK_UN); close(lock) }
            guard flock(lock, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
            let url = try ensureFile()
            let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data(row.utf8))
        } catch {
            FileHandle.standardError.write(Data("decant log failed: \(error)\n".utf8))
        }
        FileHandle.standardError.write(Data(row.utf8))
    }

    private static func rotateIfNeeded(_ url: URL) throws {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes
        else { return }
        let bak = url.deletingLastPathComponent().appendingPathComponent("decant.log.1")
        if fm.fileExists(atPath: bak.path) { try fm.removeItem(at: bak) }
        try fm.moveItem(at: url, to: bak)
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
