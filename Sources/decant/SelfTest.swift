import Foundation

// pure-logic smoke checks invoked by `decant --self-test` and scripts/smoke.sh.
// no wine required.
enum SelfTest {
    @discardableResult
    static func run() -> Bool {
        var failed = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
                failed += 1
            }
        }

        // VDF parse
        let sample = """
        "AppState"
        {
        \t"appid"\t\t"12345"
        \t"name"\t\t"Fields of Mistria"
        \t"path"\t\t"C:\\\\Games\\\\Lib"
        }
        """
        check("vdf appid", SteamManager.vdfValue(sample, "appid") == "12345")
        check("vdf name", SteamManager.vdfValue(sample, "name") == "Fields of Mistria")
        check("vdf path", SteamManager.vdfValues(sample, "path").first?.contains("Games") == true)

        // support package filter
        check("filter redistributable",
              SteamManager.isSupportPackage(appID: "228980", name: "DirectX Redistributable"))
        check("filter junk id",
              SteamManager.isSupportPackage(appID: "228980", name: "Anything"))
        check("keep real game",
              !SteamManager.isSupportPackage(appID: "2432860", name: "Fields of Mistria"))

        // housekeeping human units
        check("human bytes", Housekeeping.human(500) == "500 B")
        check("human kb", Housekeeping.human(2048).contains("KB"))
        check("human gb", Housekeeping.human(10 * 1024 * 1024 * 1024).contains("GB"))

        // dump report under empty temp bottle
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("decant-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let report = Housekeeping.evaluateDumps(tmp, cap: 100)
        check("empty dumps under cap", !report.overCap && report.bytes == 0)

        // engine path shape
        // DECANT_HOME moves the whole engine home, so the check follows it
        // instead of assuming the Application Support layout.
        if let home = ProcessInfo.processInfo.environment["DECANT_HOME"], !home.isEmpty {
            check("support follows DECANT_HOME", EnginePaths.support.path == home,
                  EnginePaths.support.path)
        } else {
            check("support ends with decant",
                  EnginePaths.support.path.hasSuffix("Application Support/decant"))
        }
        check("wine path under engines/current or the wine11 fallback",
              EnginePaths.wineBinary.contains("engines/current")
                || EnginePaths.wineBinary.contains("engines/wine11"))

        // status enum headlines distinct
        check("headline noEngine", EngineStatus.noEngine.headline.contains("not installed"))
        if let e = Engine.detect() {
            check("headline noBottle",
                  EngineStatus.engineNoBottle(e).headline.contains("no bottle"))
        } else {
            print("skip headline noBottle (no wine on disk)")
        }

        // engine update faults. temp directories only, never a real bottle.
        runEngineUpdateFaults { name, ok, detail in check(name, ok, detail) }

        // launch lifecycle. fake clock, fake probe, fake spawner, no wine.
        runLaunchLifecycle { name, ok, detail in check(name, ok, detail) }

        if failed == 0 {
            print("self-test: all passed")
            return true
        }
        print("self-test: \(failed) failure(s)")
        return false
    }

    // engine update fault suite. build a fake old engine and activate it,
    // fingerprint a fake game prefix, then fail one install per fault and
    // prove the old engine is still active and the prefix is byte for byte
    // the same. one "FAULT <name> recovered" line per case, then the count.
    static func runEngineUpdateFaults(_ record: (String, Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("decant-engine-faults-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        func writeFile(_ url: URL, _ text: String) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        }

        do {
            let srcOld = tmp.appendingPathComponent("build-old", isDirectory: true)
            let srcNew = tmp.appendingPathComponent("build-new", isDirectory: true)
            try writeFile(srcOld.appendingPathComponent("bin/wine"), "old engine bytes\n")
            try writeFile(srcNew.appendingPathComponent("bin/wine"), "new engine bytes\n")
            try writeFile(srcNew.appendingPathComponent("lib/dxmt.dll"), "new dxmt bytes\n")

            let prefix = tmp.appendingPathComponent("bottle", isDirectory: true)
            try writeFile(prefix.appendingPathComponent("drive_c/game/save.dat"), "save one\n")
            try writeFile(prefix.appendingPathComponent("drive_c/game/config.ini"), "res=1080\n")

            var store = EngineStore(root: tmp.appendingPathComponent("engines", isDirectory: true))
            let oldManifest = try fakeManifest(id: "v-old", from: srcOld)
            let newManifest = try fakeManifest(id: "v-new", from: srcNew)

            try store.install(from: srcOld, manifest: oldManifest, fault: nil)
            record("engine v-old active", try store.activeID() == "v-old", "")

            let before = PrefixHasher.sha256(of: prefix)

            for fault in EngineFault.allCases {
                var recovered = true
                func step(_ name: String, _ passed: Bool, _ detail: String = "") {
                    if !passed { recovered = false }
                    record("\(fault.rawValue) \(name)", passed, detail)
                }

                // interruptedSwitch stops the real switch path between
                // current.new and the rename onto current.
                store.switchBarrier = fault == .interruptedSwitch ? { _ in
                    throw EngineStoreError.interrupted("stopped between current.new and current")
                } : nil

                var thrown: Error?
                do {
                    try store.install(from: srcNew, manifest: newManifest, fault: fault)
                } catch {
                    thrown = error
                }
                store.switchBarrier = nil
                step("install throws", thrown != nil, "install returned without an error")

                let active = ((try? store.activeID()) ?? nil)
                step("current stays v-old", active == "v-old", "current is \(active ?? "nil")")

                var oldValid = true
                var oldDetail = ""
                do {
                    try store.validate(id: "v-old")
                } catch {
                    oldValid = false
                    oldDetail = "\(error)"
                }
                step("v-old still validates", oldValid, oldDetail)
                step("prefix unchanged", PrefixHasher.sha256(of: prefix) == before,
                     "prefix hash moved")

                // a half written switch link must not survive the failure.
                let pendingPath = store.root.appendingPathComponent("current.new").path
                let stale = (try? fm.destinationOfSymbolicLink(atPath: pendingPath)) != nil
                step("no stale current.new", !stale, "current.new is still there")

                if recovered { print("FAULT \(fault.rawValue) recovered") }
            }
            print("N=\(EngineFault.allCases.count)")

            // the happy path, then a rollback to the version it replaced.
            try store.install(from: srcNew, manifest: newManifest, fault: nil)
            record("clean install activates v-new", try store.activeID() == "v-new", "")
            try store.rollback()
            record("rollback restores v-old", try store.activeID() == "v-old", "")
            record("rollback leaves prefix unchanged",
                   PrefixHasher.sha256(of: prefix) == before, "")
        } catch {
            record("engine fault suite", false, "\(error)")
        }
    }

    private static func fakeManifest(id: String, from dir: URL) throws -> EngineManifest {
        EngineManifest(
            id: id,
            wineTag: "wine-11.0",
            wineSourceCommit: "self-test",
            dxmtTag: "v0.74",
            dxmtCommit: "self-test",
            patches: ["winemac-visibility"],
            build: ["host": "self-test"],
            artifacts: try EngineStore.artifactHashes(of: dir),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // launch lifecycle suite. the state machine is pure, so the four evidence
    // steps run with no process at all. the controller cases use a fake clock
    // and a fake probe, and DECANT_HOME points at a temp directory so no
    // report ever lands in the real support folder.
    static func runLaunchLifecycle(_ record: (String, Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("decant-launch-\(UUID().uuidString)", isDirectory: true)
        let previousHome = ProcessInfo.processInfo.environment["DECANT_HOME"]
        setenv("DECANT_HOME", tmp.path, 1)
        defer {
            if let previousHome { setenv("DECANT_HOME", previousHome, 1) } else { unsetenv("DECANT_HOME") }
            try? fm.removeItem(at: tmp)
        }

        let prefix = tmp.appendingPathComponent("bottles/steam11", isDirectory: true)
        try? fm.createDirectory(at: prefix, withIntermediateDirectories: true)

        // 1. the happy path, straight through the machine.
        var machine = LaunchMachine()
        var walked = true
        do {
            try machine.apply(.userPlay(appID: "2432860"))
            walked = walked && machine.phase == .preparing
            try machine.apply(.steamReady)
            walked = walked && machine.phase == .steamReady
            try machine.apply(.requestSpawned(pid: 4242))
            walked = walked && machine.phase == .requestSent
            try machine.apply(.gameDetected)
            walked = walked && machine.phase == .processDetected
        } catch {
            walked = false
        }
        record("launch happy", walked, "ended at \(machine.phase.label)")

        // 2. a finished launch resets back to idle.
        var afterReset = false
        if (try? machine.apply(.reset)) != nil { afterReset = machine.phase == .idle }
        record("launch reset to idle", afterReset, "phase is \(machine.phase.label)")

        // 3. evidence the phase does not accept.
        var idle = LaunchMachine()
        var refused = false
        do {
            try idle.apply(.gameDetected)
        } catch LaunchIllegal.badTransition {
            refused = idle.phase == .idle
        } catch {
            refused = false
        }
        record("launch illegal detect from idle", refused, "phase is \(idle.phase.label)")

        // 4. a second play while one is in flight changes nothing.
        let dupClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let dupProbe = FakeProcessProbe()
        let dupSpawner = FakeLaunchSpawner()
        let dup = LaunchController(clock: dupClock, probe: dupProbe, spawner: dupSpawner)
        dup.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        let phaseBefore = dup.phase
        dupClock.advance(5)
        dup.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        record("launch duplicate play rejected",
               dup.snapshot?.lastRejection == .duplicate, "rejection is \(String(describing: dup.snapshot?.lastRejection))")
        record("launch duplicate leaves phase", dup.phase == phaseBefore,
               "phase moved to \(dup.phase.label)")
        record("launch duplicate does not spawn again",
               dupSpawner.steamStarts == 1 && dupSpawner.gameStarts == 0,
               "steam=\(dupSpawner.steamStarts) game=\(dupSpawner.gameStarts)")

        // 5. steam never comes up: preparing times out at 90 seconds.
        dupClock.advance(LaunchTimeout.preparing + 1)
        dup.tick()
        record("launch timeout preparing",
               dup.phase == .failed(.timeout(from: .preparing)), "phase is \(dup.phase.label)")
        let recovery = dup.snapshot?.recovery ?? []
        record("launch timeout offers recovery",
               recovery.contains(.retry) && recovery.contains(.openLog),
               "recovery is \(recovery.map(\.rawValue))")

        // 6. steam is already up, the request goes out, the game never appears.
        let sentClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let sentProbe = FakeProcessProbe()
        sentProbe.steam = true
        let sentSpawner = FakeLaunchSpawner()
        let sent = LaunchController(clock: sentClock, probe: sentProbe, spawner: sentSpawner)
        sent.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        record("launch request sent on warm steam",
               sent.phase == .requestSent && sentSpawner.gameStarts == 1,
               "phase is \(sent.phase.label)")
        sentClock.advance(LaunchTimeout.requestSent + 1)
        sent.tick()
        record("launch timeout request sent",
               sent.phase == .failed(.timeout(from: .requestSent)), "phase is \(sent.phase.label)")
        record("launch timeout stops the launcher",
               sentSpawner.terminated == [4343], "terminated \(sentSpawner.terminated)")

        // 7. the game shows up in the prefix, so the launch completes.
        // the report carries the tail of the log, so write a real home path
        // into the log first. without it the report holds no home path and
        // the redaction check below could pass on text that was never
        // redacted at all.
        let realHome = fm.homeDirectoryForCurrentUser.path
        DecantLog.line("fixture opened \(realHome)/Library/Application Support/decant/logs")
        let liveClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let liveProbe = FakeProcessProbe()
        liveProbe.steam = true
        let liveController = LaunchController(clock: liveClock,
                                              probe: liveProbe,
                                              spawner: FakeLaunchSpawner())
        liveController.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        liveProbe.game = true
        liveClock.advance(4)
        liveController.tick()
        record("launch process detected", liveController.phase == .processDetected,
               "phase is \(liveController.phase.label)")

        // 7b. the script exits nonzero after the request went out. the old
        // spawn path lost that error; the exit callback carries it now.
        let lateClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let lateProbe = FakeProcessProbe()
        lateProbe.steam = true
        let lateSpawner = FakeLaunchSpawner()
        let late = LaunchController(clock: lateClock, probe: lateProbe, spawner: lateSpawner)
        late.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        let liveID = late.snapshot?.id ?? "none"
        lateClock.advance(3)
        lateSpawner.reportGameExit(3, err: "steam is not installed")
        record("launch shell failure reaches the controller",
               late.phase == .failed(.spawn(3)), "phase is \(late.phase.label)")

        // this failure came from the launcher's own exit, so there is nothing
        // left to signal. a stop here would reach a pid the kernel may have
        // handed to another process.
        record("an exited launcher is not signalled",
               lateSpawner.terminated.isEmpty, "terminated \(lateSpawner.terminated)")

        // 7c. the same controller retries, so the first launch is over. its
        // exit callback arrives late and must change nothing.
        let firstExit = lateSpawner.gameExit
        late.retry()
        let secondID = late.snapshot?.id ?? "none"
        let secondPhase = late.phase
        record("retry starts a new launch",
               secondID != liveID && secondPhase == .requestSent,
               "id \(secondID) phase \(secondPhase.label)")
        firstExit?(FakeLaunchSpawner.gamePID, RunResult(code: 9, out: "", err: "old launch"))
        record("launch ignores a stale exit", late.phase == secondPhase,
               "phase is \(late.phase.label)")

        // 7f. a launcher that already reported its exit is never signalled.
        // the kernel can hand that pid to something else, so a later timeout
        // must not reach for it.
        let goneClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let goneProbe = FakeProcessProbe()
        let goneSpawner = FakeLaunchSpawner()
        let gone = LaunchController(clock: goneClock, probe: goneProbe, spawner: goneSpawner)
        gone.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        goneSpawner.reportSteamExit(0)
        goneClock.advance(LaunchTimeout.preparing + 1)
        gone.tick()
        record("launch timeout skips a launcher that already exited",
               gone.phase == .failed(.timeout(from: .preparing))
                 && goneSpawner.terminated.isEmpty,
               "phase \(gone.phase.label) terminated \(goneSpawner.terminated)")

        // 7g. the steam wrapper can still be running when the game request
        // goes out, so a timeout stops both launchers, not just the last one.
        let bothClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let bothProbe = FakeProcessProbe()
        let bothSpawner = FakeLaunchSpawner()
        let both = LaunchController(clock: bothClock, probe: bothProbe, spawner: bothSpawner)
        both.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        bothProbe.steam = true
        bothClock.advance(5)
        both.tick()
        record("launch starts the game while the steam wrapper runs",
               both.phase == .requestSent && bothSpawner.steamStarts == 1
                 && bothSpawner.gameStarts == 1,
               "phase \(both.phase.label)")
        bothClock.advance(LaunchTimeout.requestSent + 1)
        both.tick()
        record("launch timeout stops every launcher still running",
               bothSpawner.terminated == [FakeLaunchSpawner.steamPID, FakeLaunchSpawner.gamePID],
               "terminated \(bothSpawner.terminated)")

        // 7h. a signal that fails still drops the pid, so nothing is
        // signalled twice and nothing is retried.
        let failClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let failProbe = FakeProcessProbe()
        failProbe.steam = true
        let failSpawner = FakeLaunchSpawner()
        failSpawner.terminateErrno = ESRCH
        let failing = LaunchController(clock: failClock, probe: failProbe, spawner: failSpawner)
        failing.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        failClock.advance(LaunchTimeout.requestSent + 1)
        failing.tick()
        let afterFirstStop = failSpawner.terminated
        failing.deliverExit(launchID: failing.snapshot?.id ?? "none",
                            pid: FakeLaunchSpawner.gamePID,
                            result: RunResult(code: 1, out: "", err: ""))
        record("a failed stop drops the pid anyway",
               afterFirstStop == [FakeLaunchSpawner.gamePID]
                 && failSpawner.terminated == afterFirstStop,
               "terminated \(failSpawner.terminated)")

        // 7e. play and retry pass the same engine gate. a not-ready engine
        // starts nothing, either way.
        let gateSpawner = FakeLaunchSpawner()
        let gateProbe = FakeProcessProbe()
        gateProbe.steam = true
        let gated = LaunchController(clock: FakeLaunchClock(Date(timeIntervalSince1970: 0)),
                                     probe: gateProbe, spawner: gateSpawner,
                                     ready: { throw DecantError.launch("Wine 11.0 is required") })
        gated.requestPlay(appID: "2432860", engineVersion: "self-test", prefix: prefix)
        record("play refuses a not-ready engine",
               gated.phase == .failed(.notReady("launch failed: Wine 11.0 is required")),
               "phase is \(gated.phase.label)")
        gated.retry()
        record("retry refuses a not-ready engine and spawns nothing",
               gateSpawner.steamStarts == 0 && gateSpawner.gameStarts == 0
                 && gated.phase.isFailed,
               "steam=\(gateSpawner.steamStarts) game=\(gateSpawner.gameStarts) "
                 + "phase=\(gated.phase.label)")

        // 7d. the prefix match uses the same boundary rule as the shell, so a
        // longer prefix name is not this bottle.
        let probeListing = "PID TTY  WINEPREFIX=\(prefix.path)-old WINEDEBUG=-all wine steam.exe"
        record("probe rejects a prefix with a suffix",
               !SystemProcessProbe.matchesPrefix(probeListing, prefix: prefix), probeListing)
        let exactListing = "PID TTY  WINEPREFIX=\(prefix.path) WINEDEBUG=-all wine steam.exe"
        record("probe accepts the exact prefix",
               SystemProcessProbe.matchesPrefix(exactListing, prefix: prefix), exactListing)

        // 8. the report on disk names the stages and hides the private parts.
        let home = fm.homeDirectoryForCurrentUser.path
        let user = NSUserName()
        let raw = """
        [t] opened \(home)/Library/Application Support/decant/logs
        AccountName=alice
        steamid=76561190000000000
        [t] play appid=2432860
        """
        let clean = LaunchDiagnostic.redact(raw, home: home, user: user)
        record("redact hides the home path", !clean.contains(home), clean)
        record("redact drops identity lines",
               !clean.contains("alice") && !clean.contains("AccountName")
                 && !clean.contains("steamid"), clean)
        record("redact keeps the rest", clean.contains("play appid=2432860"), clean)

        // 9. the wine side writes the same account name in three shapes. a
        // fake name keeps this case honest on any machine.
        let wineRaw = """
        [t] wine opened drive_c/users/zuzu/AppData/Local/Mistria
        [t] path Z:\\Users\\zuzu\\Documents\\save.dat
        [t] shell C:\\users\\zuzu\\Temp
        [t] theme zuzuberry loaded
        """
        let wineClean = LaunchDiagnostic.redact(wineRaw, home: "", user: "zuzu")
        record("redact masks the unix side user",
               wineClean.contains("drive_c/users/<user>/AppData"), wineClean)
        record("redact masks the z drive user",
               wineClean.contains("Z:\\Users\\<user>\\Documents"), wineClean)
        record("redact masks the c drive user",
               wineClean.contains("C:\\users\\<user>\\Temp"), wineClean)
        record("redact keeps a word that contains the user",
               wineClean.contains("zuzuberry"), wineClean)

        // 10. the report the finished launch wrote is on disk, not just a path
        // decant can compute.
        let launchID = liveController.snapshot?.id ?? "none"
        let reportPath = LaunchDiagnostic.reportURL(id: launchID)
        record("launch report is under DECANT_HOME",
               reportPath.path.hasPrefix(tmp.path), reportPath.path)
        record("launch report exists on disk",
               fm.fileExists(atPath: reportPath.path), reportPath.path)
        let reportText = (try? String(contentsOf: reportPath, encoding: .utf8)) ?? ""
        record("launch report names the launch id",
               reportText.contains(launchID), reportText)
        record("launch report carries the fixture log line",
               reportText.contains("fixture opened"), reportText)
        record("launch report hides the home path",
               !reportText.isEmpty && !reportText.contains(home), reportText)
        record("launch report masks the home path it carried",
               reportText.contains("~/Library/Application Support/decant/logs"), reportText)
    }
}

// MARK: launch fakes. test-only seams, never used by the app.

final class FakeLaunchClock: LaunchClock {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

final class FakeProcessProbe: ProcessProbe {
    var steam = false
    var game = false
    func steamReady(prefix: URL) -> Bool { steam }
    func gameDetected(appID: String, prefix: URL) -> Bool { game }
}

// the fake keeps the exit callbacks so a test can fire one by hand, the way
// a real launch script reports its status after it ends.
final class FakeLaunchSpawner: LaunchSpawner {
    static let steamPID: Int32 = 4242
    static let gamePID: Int32 = 4343

    private(set) var steamStarts = 0
    private(set) var gameStarts = 0
    private(set) var steamExit: ((Int32, RunResult) -> Void)?
    private(set) var gameExit: ((Int32, RunResult) -> Void)?
    private(set) var terminated: [Int32] = []
    // when set, terminate reports this errno instead of success.
    var terminateErrno: Int32?

    func startSteam(launchID: String,
                    onExit: @escaping (Int32, RunResult) -> Void) throws -> Int32 {
        steamStarts += 1
        steamExit = onExit
        return Self.steamPID
    }

    func startGame(appID: String, launchID: String,
                   onExit: @escaping (Int32, RunResult) -> Void) throws -> Int32 {
        gameStarts += 1
        gameExit = onExit
        return Self.gamePID
    }

    func terminate(pid: Int32) -> Int32? {
        terminated.append(pid)
        return terminateErrno
    }

    // fire the exit a real launcher would report.
    func reportSteamExit(_ code: Int32) { steamExit?(Self.steamPID, RunResult(code: code, out: "", err: "")) }
    func reportGameExit(_ code: Int32, err: String = "") {
        gameExit?(Self.gamePID, RunResult(code: code, out: "", err: err))
    }
}
