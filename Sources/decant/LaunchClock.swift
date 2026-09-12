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

// onExit fires when the wrapper decant started exits. the fakes call it by
// hand, so the self-test drives an early shell failure without wine.
protocol LaunchSpawner {
    func startSteam(launchID: String, onExit: @escaping (Int32, String) -> Void) throws -> Int32
    func startGame(appID: String, launchID: String,
                   onExit: @escaping (Int32, String) -> Void) throws -> Int32
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
        let needle = "WINEPREFIX=\(prefix.path)"
        var out: [String] = []
        for pid in pids.out.split(whereSeparator: \.isNewline) {
            guard let listing = try? EngineManager.run("/bin/ps", ["eww", "-p", String(pid)]),
                  listing.out.contains(needle)
            else { continue }
            out.append(listing.out)
        }
        return out
    }
}

// runs the real launch scripts through SteamManager and hands back the pid
// of the wrapper it started.
struct SteamLaunchSpawner: LaunchSpawner {
    let bottle: URL
    let engine: Engine

    func startSteam(launchID: String, onExit: @escaping (Int32, String) -> Void) throws -> Int32 {
        try SteamManager.launchClient(bottle, engine: engine, launchID: launchID,
                                      onExit: onExit).pid
    }

    func startGame(appID: String, launchID: String,
                   onExit: @escaping (Int32, String) -> Void) throws -> Int32 {
        try SteamManager.launchGame(appID: appID, bottle: bottle, engine: engine,
                                    launchID: launchID, onExit: onExit).pid
    }
}
