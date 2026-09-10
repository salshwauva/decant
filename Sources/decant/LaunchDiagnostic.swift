import Foundation

// a launch report you can paste into a bug thread. it names the stages and
// their durations, then the tail of the log with the private parts removed.
enum LaunchDiagnostic {
    // lines that carry a steam identity never reach the report.
    private static let secretMarkers = ["loginusers", "accountname", "password", "steamid"]

    // replace the home directory with ~ and drop identity lines.
    static func redact(_ text: String, home: String, user: String) -> String {
        var kept: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lower = line.lowercased()
            if secretMarkers.contains(where: { lower.contains($0) }) { continue }
            var row = String(line)
            if !home.isEmpty { row = row.replacingOccurrences(of: home, with: "~") }
            if !user.isEmpty {
                row = row.replacingOccurrences(of: "/Users/\(user)", with: "~")
            }
            kept.append(row)
        }
        return kept.joined(separator: "\n")
    }

    static func export(session: LaunchSession, logTail: String, engineVersion: String) -> String {
        var out: [String] = []
        out.append("decant launch report")
        out.append("launch id:   \(session.id)")
        out.append("app id:      \(session.appID)")
        out.append("engine:      \(engineVersion)")
        out.append("final phase: \(session.phase.label)")
        out.append("why:         \(session.phase.explanation)")
        out.append("")
        out.append("stages")
        for stage in session.stages {
            let seconds = stage.duration.map { String(format: "%.1fs", $0) } ?? "open"
            let code = stage.exitCode.map { " exit=\($0)" } ?? ""
            out.append("  \(stage.phase.label)\t\(seconds)\(code)\t\(stage.evidence)")
        }
        out.append("")
        out.append("log tail (redacted)")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        out.append(redact(logTail, home: home, user: NSUserName()))
        return out.joined(separator: "\n") + "\n"
    }

    static func reportURL(id: String) -> URL {
        DecantLog.directory.appendingPathComponent("launch-\(id).txt")
    }

    @discardableResult
    static func write(session: LaunchSession, logTail: String) throws -> URL {
        let text = export(session: session, logTail: logTail,
                          engineVersion: session.engineVersion)
        try FileManager.default.createDirectory(at: DecantLog.directory,
                                                withIntermediateDirectories: true)
        let url = reportURL(id: session.id)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    // newest launch report on disk, for `decant --export-launch`.
    static func latestReport() -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: DecantLog.directory,
            includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        return items
            .filter { $0.lastPathComponent.hasPrefix("launch-") && $0.pathExtension == "txt" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return da > db
            }
            .first
    }
}
