import Foundation

// the three seams the launch controller talks to. production uses the real
// clock, a prefix-scoped process probe, and the steam launch scripts. the
// self-test injects fakes, so the lifecycle runs without wine.

protocol LaunchClock {
    func now() -> Date
}

protocol ProcessProbe {
    func steamReady(prefix: URL) -> Bool
    func gameDetected(appID: String, prefix: URL) -> Bool
}

// onExit carries the script's exit status back after the process ends, so
// a shell that fails later still reaches the controller.
protocol LaunchSpawner {
    func startSteam(launchID: String, onExit: @escaping (RunResult) -> Void) throws -> Int32
    func startGame(appID: String, launchID: String,
                   onExit: @escaping (RunResult) -> Void) throws -> Int32
}

struct SystemClock: LaunchClock {
    func now() -> Date { Date() }
}

// process detection scoped to one bottle. pgrep only proposes candidates;
// the answer comes from `ps eww`, which shows each process environment, so
// a match must carry this WINEPREFIX. a machine-wide pgrep would count
// crossover, whisky and every other prefix as ours.
struct SystemProcessProbe: ProcessProbe {
    // steam's own processes inside the bottle.
    private let steamPattern = "steamwebhelper|steam\\.exe|steamservice"
    // anything wine loads. the game is whichever one is not steam.
    private let winePattern = "wine64-preloader|wine-preloader|\\.exe"
    private let steamOwned = [
        "steam.exe", "steamwebhelper", "steamservice", "steamerrorreporter",
        "winedevice.exe", "wineserver", "explorer.exe", "services.exe",
        "plugplay.exe", "rpcss.exe", "svchost.exe",
    ]

    func steamReady(prefix: URL) -> Bool {
        !commandsInPrefix(matching: steamPattern, prefix: prefix).isEmpty
    }

    // "detected" means a windows process other than steam's own runs in this
    // prefix. it does not prove the game reached its title screen.
    func gameDetected(appID: String, prefix: URL) -> Bool {
        for command in commandsInPrefix(matching: winePattern, prefix: prefix) {
            let lower = command.lowercased()
            if lower.contains("-applaunch") { continue }
            if steamOwned.contains(where: { lower.contains($0) }) { continue }
            if lower.contains(".exe") { return true }
        }
        return false
    }

    // command lines of processes whose environment names this prefix.
    private func commandsInPrefix(matching pattern: String, prefix: URL) -> [String] {
        guard let pids = try? EngineManager.run("/usr/bin/pgrep", ["-f", pattern]),
              pids.code == 0
        else { return [] }
        var out: [String] = []
        for pid in pids.out.split(whereSeparator: \.isNewline) {
            guard let listing = try? EngineManager.run("/bin/ps", ["eww", "-p", String(pid)]),
                  Self.matchesPrefix(listing.out, prefix: prefix)
            else { continue }
            out.append(listing.out)
        }
        return out
    }

    // the same boundary rule the shell helper uses: WINEPREFIX must hold this
    // exact path, and the next thing must be another VAR= or the end of the
    // line. a substring test would count steam11-old as steam11.
    static func matchesPrefix(_ listing: String, prefix: URL) -> Bool {
        let needle = "WINEPREFIX=" + prefix.path
        for line in listing.split(whereSeparator: \.isNewline) {
            let text = String(line)
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: needle, range: search) {
                let startsClean = found.lowerBound == text.startIndex
                    || text[text.index(before: found.lowerBound)] == " "
                if startsClean && isAssignmentBoundary(text, after: found.upperBound) { return true }
                search = found.upperBound..<text.endIndex
            }
        }
        return false
    }

    // end of line, or a space followed by NAME= for the next variable.
    private static func isAssignmentBoundary(_ text: String, after index: String.Index) -> Bool {
        if index == text.endIndex { return true }
        guard text[index] == " " else { return false }
        var cursor = text.index(after: index)
        var first = true
        while cursor < text.endIndex {
            let ch = text[cursor]
            if ch == "=" { return !first }
            let ok = ch.isLetter || ch == "_" || (!first && ch.isNumber)
            if !ok { return false }
            first = false
            cursor = text.index(after: cursor)
        }
        return false
    }
}

// runs the real launch scripts through SteamManager and hands back the pid
// of the wrapper it started.
struct SteamLaunchSpawner: LaunchSpawner {
    let bottle: URL
    let engine: Engine

    func startSteam(launchID: String, onExit: @escaping (RunResult) -> Void) throws -> Int32 {
        try SteamManager.launchClient(bottle, engine: engine, launchID: launchID,
                                      onExit: onExit).pid
    }

    func startGame(appID: String, launchID: String,
                   onExit: @escaping (RunResult) -> Void) throws -> Int32 {
        try SteamManager.launchGame(appID: appID, bottle: bottle, engine: engine,
                                    launchID: launchID, onExit: onExit).pid
    }
}
