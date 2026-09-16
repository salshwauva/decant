import XCTest
import Foundation
@testable import decant

final class DecantTests: XCTestCase {
    private var root: URL!
    private var previousHome: String?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("decant-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        previousHome = ProcessInfo.processInfo.environment["DECANT_HOME"]
        setenv("DECANT_HOME", root.path, 1)
    }

    override func tearDownWithError() throws {
        if let previousHome { setenv("DECANT_HOME", previousHome, 1) } else { unsetenv("DECANT_HOME") }
        try FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ relative: String, _ content: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testKeyValuesEscapesAndNestedKeys() {
        let source = #"""
        // a nested key must not replace the app name
        "AppState" {
            "name" "A \"quoted\" game"
            "path" "C:\\Games\\Library"
            "nested" { "name" "other" }
        }
        """#
        let app = ValveKeyValues.parse(source)?["AppState"]?.object
        XCTAssertEqual(app?["name"]?.text, "A \"quoted\" game")
        XCTAssertEqual(app?["path"]?.text, #"C:\Games\Library"#)
        XCTAssertEqual(app?["nested"]?.object?["name"]?.text, "other")
    }

    func testMalformedKeyValues() {
        for input in ["{", "}", "\"key\"", "\"root\" { \"a\" \"b\"", "\"a\" \"unterminated"] {
            XCTAssertNil(ValveKeyValues.parse(input), input)
        }
    }

    func testExternalDriveMapping() throws {
        let drive = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let devices = root.appendingPathComponent("bottle/dosdevices")
        try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: devices.appendingPathComponent("d:"), withDestinationURL: drive)
        let bottle = root.appendingPathComponent("bottle")
        XCTAssertEqual(SteamManager.libraryURL(#"D:\SteamLibrary"#, bottle: bottle)?.path, drive.appendingPathComponent("SteamLibrary").path)
        XCTAssertNil(SteamManager.libraryURL(#"E:\Library"#, bottle: bottle))
        XCTAssertNil(SteamManager.libraryURL(#"C:\..\outside"#, bottle: bottle))
        XCTAssertNil(SteamManager.libraryURL("invalid", bottle: bottle))
    }

    func testLibraryDeduplicationAndInstallState() throws {
        let folder = "bottle/drive_c/Program Files (x86)/Steam/steamapps/"
        try write(folder + "appmanifest_100.acf", #"""
        "AppState" { "appid" "100" "name" "Proton Adventure" "StateFlags" "4" }
        """#)
        try write(folder + "appmanifest_duplicate.acf", #"""
        "AppState" { "appid" "100" "name" "Proton Adventure" "StateFlags" "4" }
        """#)
        try write(folder + "appmanifest_101.acf", #"""
        "AppState" { "appid" "101" "name" "partial" "StateFlags" "2" }
        """#)
        try write(folder + "appmanifest_228980.acf", #"""
        "AppState" { "appid" "228980" "name" "Shared runtime" "StateFlags" "4" }
        """#)
        XCTAssertEqual(try SteamManager.installedGames(root.appendingPathComponent("bottle")), [Game(appID: "100", name: "Proton Adventure")])
    }

    func testMalformedManifestReportsFailure() throws {
        try write("bottle/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_100.acf", "unfinished")
        XCTAssertThrowsError(try SteamManager.installedGames(root.appendingPathComponent("bottle")))
    }

    func testMinimalEngineCanOpenSteamWithoutGraphics() throws {
        let wine = try write("engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine", "#!/bin/sh\necho wine-11.0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try write("bottles/steam11/drive_c/Program Files (x86)/Steam/steam.exe", "fixture")
        try write("engine/decant-launch.sh", "fixture")
        try write("engine/scripts/launch-steam.sh", "fixture")
        try write("engine/wrapper/steamwebhelper.exe", "fixture")
        try FileManager.default.createDirectory(at: EnginePaths.bottle("steam11").appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)
        XCTAssertNoThrow(try EngineManager.requireSteam())
        XCTAssertThrowsError(try EngineManager.requireReady())
    }

    func testAppIDRejectsUnicodeAndShellSyntax() {
        XCTAssertTrue(SteamManager.validAppID("12345"))
        for id in ["", "１２", "١٢", "1;touch x", "-1", "1/2", "1\n"] {
            XCTAssertFalse(SteamManager.validAppID(id))
        }
    }

    func testBothProcessStreamsAndExitStatus() throws {
        let result = try EngineManager.run("/bin/bash", ["-c", "printf output; printf failure >&2; exit 7"])
        XCTAssertEqual(result.code, 7)
        XCTAssertEqual(result.out, "output")
        XCTAssertEqual(result.err, "failure")
    }

    func testOutputCaptureIsBounded() throws {
        let result = try EngineManager.run("/bin/bash", ["-c", "head -c 1000000 /dev/zero; head -c 1000000 /dev/zero >&2"])
        XCTAssertEqual(result.out.utf8.count, 65536)
        XCTAssertEqual(result.err.utf8.count, 65536)
    }

    func testProcessTimeout() {
        let start = Date()
        XCTAssertThrowsError(try EngineManager.run("/bin/sleep", ["5"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testShellFailureReachesCaller() throws {
        try write("engine/decant-launch.sh", "echo missing-steam >&2\nexit 9\n")
        XCTAssertThrowsError(try SteamManager.launchGame(appID: "100", bottle: root, engine: Engine(wine: "/unused/wine"))) {
            XCTAssertTrue(String(describing: $0).contains("missing-steam"))
        }
    }

    func testLaunchUsesSelectedBottleAndEngine() throws {
        try write("engine/decant-launch.sh", "printf '%s\\n' \"$WINEPREFIX\" \"$WINE_BIN\" \"$WINE_APP\" \"$@\" > \"$DECANT_HOME/request\"\n")
        let wine = root.appendingPathComponent("engine/Wine Stable.app/Contents/Resources/wine/bin/wine").path
        let bottle = root.appendingPathComponent("other bottle")
        try SteamManager.launchGame(appID: "100", bottle: bottle, engine: Engine(wine: wine))
        let fields = try String(contentsOf: root.appendingPathComponent("request")).split(separator: "\n").map(String.init)
        XCTAssertEqual(fields, [bottle.path, wine, root.appendingPathComponent("engine/Wine Stable.app").path, "play", "100"])
    }

    // the merge kept main's checked request and added the lifecycle path.
    // both build their environment in one place, so both name the bottle,
    // the engine, and the launch id.
    func testLaunchEnvironmentIncludesID() {
        let wine = root.appendingPathComponent("engines/current/Wine Stable.app/Contents/Resources/wine/bin/wine").path
        let bottle = root.appendingPathComponent("bottles/steam11")
        let env = SteamManager.launchEnvironment(bottle: bottle, engine: Engine(wine: wine), launchID: "id-1")
        XCTAssertEqual(env["WINEPREFIX"], bottle.path)
        XCTAssertEqual(env["WINE_BIN"], wine)
        XCTAssertEqual(env["WINE_APP"], root.appendingPathComponent("engines/current/Wine Stable.app").path)
        XCTAssertEqual(env["DECANT_LAUNCH_ID"], "id-1")
        let plain = SteamManager.launchEnvironment(bottle: bottle, engine: Engine(wine: wine))
        XCTAssertNil(plain["DECANT_LAUNCH_ID"])
    }

    // the lifecycle path does not wait for the script, so the exit status
    // arrives later. the spawn must carry that status back.
    func testSpawnDeliversExitStatus() throws {
        try write("engine/decant-launch.sh", "echo missing-steam >&2\nexit 9\n")
        let done = expectation(description: "exit")
        var seen: RunResult?
        let spawn = try SteamManager.launchGame(appID: "100", bottle: root,
                                                engine: Engine(wine: "/unused/wine"),
                                                launchID: "id-2") { pid, result in
            XCTAssertGreaterThan(pid, 0)
            seen = result
            done.fulfill()
        }
        XCTAssertGreaterThan(spawn.pid, 0)
        wait(for: [done], timeout: 10)
        XCTAssertEqual(seen?.code, 9)
        XCTAssertTrue(seen?.err.contains("missing-steam") == true)
    }

    // and the controller must turn that late status into a failed launch,
    // then stop the launcher it started.
    func testAsyncShellFailureReachesController() throws {
        let prefix = EnginePaths.bottle("steam11")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let probe = FakeProcessProbe()
        probe.steam = true
        let spawner = FakeLaunchSpawner()
        let controller = LaunchController(clock: FakeLaunchClock(Date(timeIntervalSince1970: 0)),
                                          probe: probe, spawner: spawner)
        controller.requestPlay(appID: "100", engineVersion: "test", prefix: prefix)
        XCTAssertEqual(controller.phase, .requestSent)
        XCTAssertEqual(spawner.gameStarts, 1)

        spawner.reportGameExit(9, err: "missing-steam")
        XCTAssertEqual(controller.phase, .failed(.spawn(9)))
        XCTAssertEqual(controller.snapshot?.phase, .failed(.spawn(9)))
        // the launcher reported its own exit, so its pid is gone and must
        // not be signalled afterwards.
        XCTAssertTrue(spawner.terminated.isEmpty)
    }

    // a launcher that reported its exit is never signalled later, and a
    // timeout stops every launcher that is still running.
    func testTimeoutStopsOnlyLiveLaunchers() throws {
        let prefix = EnginePaths.bottle("steam11")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        // steam comes up, exits, then the launch times out: nothing to stop.
        let goneClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let goneSpawner = FakeLaunchSpawner()
        let gone = LaunchController(clock: goneClock, probe: FakeProcessProbe(),
                                    spawner: goneSpawner)
        gone.requestPlay(appID: "100", engineVersion: "test", prefix: prefix)
        goneSpawner.reportSteamExit(0)
        goneClock.advance(LaunchTimeout.preparing + 1)
        gone.tick()
        XCTAssertEqual(gone.phase, .failed(.timeout(from: .preparing)))
        XCTAssertTrue(goneSpawner.terminated.isEmpty)

        // the steam wrapper is still running when the game request goes out,
        // so the timeout stops both.
        let bothClock = FakeLaunchClock(Date(timeIntervalSince1970: 0))
        let bothProbe = FakeProcessProbe()
        let bothSpawner = FakeLaunchSpawner()
        let both = LaunchController(clock: bothClock, probe: bothProbe, spawner: bothSpawner)
        both.requestPlay(appID: "100", engineVersion: "test", prefix: prefix)
        bothProbe.steam = true
        bothClock.advance(5)
        both.tick()
        XCTAssertEqual(both.phase, .requestSent)
        bothClock.advance(LaunchTimeout.requestSent + 1)
        both.tick()
        XCTAssertEqual(bothSpawner.terminated,
                       [FakeLaunchSpawner.steamPID, FakeLaunchSpawner.gamePID])
    }

    // play and retry pass the same engine gate, so neither starts a launch
    // on an engine that is not ready.
    func testRetryPassesTheEngineGate() throws {
        let prefix = EnginePaths.bottle("steam11")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let probe = FakeProcessProbe()
        probe.steam = true
        let spawner = FakeLaunchSpawner()
        let controller = LaunchController(clock: FakeLaunchClock(Date(timeIntervalSince1970: 0)),
                                          probe: probe, spawner: spawner,
                                          ready: { throw DecantError.noEngine })
        controller.requestPlay(appID: "100", engineVersion: "test", prefix: prefix)
        XCTAssertEqual(controller.phase, .failed(.engineMissing))
        controller.retry()
        XCTAssertEqual(controller.phase, .failed(.engineMissing))
        XCTAssertEqual(spawner.steamStarts, 0)
        XCTAssertEqual(spawner.gameStarts, 0)
    }

    // the swift probe uses the same boundary rule as the shell helper.
    func testProcessProbeRejectsPrefixSuffix() {
        let bottle = root.appendingPathComponent("bottles/steam11")
        let exact = "PID TTY WINEPREFIX=\(bottle.path) WINEDEBUG=-all wine steam.exe"
        let longer = "PID TTY WINEPREFIX=\(bottle.path)-old WINEDEBUG=-all wine steam.exe"
        XCTAssertTrue(SystemProcessProbe.matchesPrefix(exact, prefix: bottle))
        XCTAssertFalse(SystemProcessProbe.matchesPrefix(longer, prefix: bottle))
        let tail = "PID TTY WINEPREFIX=\(bottle.path)"
        XCTAssertTrue(SystemProcessProbe.matchesPrefix(tail, prefix: bottle))
    }

    // an id names one set of bytes. a second install under that id with
    // different contents is refused, and the installed version survives.
    func testEngineStoreRejectsExistingVersionReplacement() throws {
        let store = EngineStore(root: root.appendingPathComponent("engines"))
        let first = root.appendingPathComponent("build-first")
        let second = root.appendingPathComponent("build-second")
        try write("build-first/bin/wine", "first\n")
        try write("build-second/bin/wine", "second\n")
        func manifest(_ dir: URL) throws -> EngineManifest {
            EngineManifest(id: "v-1", wineTag: "wine-11.0", wineSourceCommit: "t",
                           dxmtTag: "v0.74", dxmtCommit: "t", patches: [], build: [:],
                           artifacts: try EngineStore.artifactHashes(of: dir),
                           createdAt: Date(timeIntervalSince1970: 0))
        }
        try store.install(from: first, manifest: try manifest(first), fault: nil)
        XCTAssertEqual(try store.activeID(), "v-1")
        XCTAssertThrowsError(try store.install(from: second, manifest: try manifest(second), fault: nil)) {
            XCTAssertTrue(String(describing: $0).contains("different contents"))
        }
        let kept = try String(contentsOf: store.versionURL(id: "v-1").appendingPathComponent("bin/wine"),
                              encoding: .utf8)
        XCTAssertEqual(kept, "first\n")
        XCTAssertEqual(try store.activeID(), "v-1")
    }

    // if the previous link cannot be written, current goes back to the
    // version that was active, so the two links never disagree.
    func testEngineStoreRestoresLinksAfterPreviousFailure() throws {
        var store = EngineStore(root: root.appendingPathComponent("engines"))
        for (id, text) in [("v-old", "old\n"), ("v-new", "new\n")] {
            let source = root.appendingPathComponent("build-\(id)")
            try write("build-\(id)/bin/wine", text)
            let manifest = EngineManifest(id: id, wineTag: "wine-11.0", wineSourceCommit: "t",
                                          dxmtTag: "v0.74", dxmtCommit: "t", patches: [], build: [:],
                                          artifacts: try EngineStore.artifactHashes(of: source),
                                          createdAt: Date(timeIntervalSince1970: 0))
            try store.install(from: source, manifest: manifest, fault: nil)
        }
        XCTAssertEqual(try store.activeID(), "v-new")
        // fail only the previous link, the way a crash between the two would.
        store.switchBarrier = { pending in
            if pending.lastPathComponent.hasPrefix("previous") {
                throw EngineStoreError.interrupted("stopped before previous")
            }
        }
        XCTAssertThrowsError(try store.activate(id: "v-old"))
        XCTAssertEqual(try store.activeID(), "v-new")
    }

    // when the restore fails too, the error names both versions and both
    // failures, so the state on disk is not a silent surprise.
    func testEngineStoreReportsAFailedRestore() throws {
        var store = EngineStore(root: root.appendingPathComponent("engines"))
        for (id, text) in [("v-old", "old\n"), ("v-new", "new\n")] {
            let source = root.appendingPathComponent("build-\(id)")
            try write("build-\(id)/bin/wine", text)
            let manifest = EngineManifest(id: id, wineTag: "wine-11.0", wineSourceCommit: "t",
                                          dxmtTag: "v0.74", dxmtCommit: "t", patches: [], build: [:],
                                          artifacts: try EngineStore.artifactHashes(of: source),
                                          createdAt: Date(timeIntervalSince1970: 0))
            try store.install(from: source, manifest: manifest, fault: nil)
        }
        // the previous link fails, and so does the attempt to put current back.
        var currentWrites = 0
        store.switchBarrier = { pending in
            if pending.lastPathComponent.hasPrefix("previous") {
                throw EngineStoreError.interrupted("stopped before previous")
            }
            currentWrites += 1
            if currentWrites > 1 {
                throw EngineStoreError.interrupted("stopped before the restore")
            }
        }
        XCTAssertThrowsError(try store.activate(id: "v-old")) { error in
            guard case EngineStoreError.restoreFailed(let text) = error else {
                return XCTFail("expected restoreFailed, got \(error)")
            }
            XCTAssertTrue(text.contains("v-old"))
            XCTAssertTrue(text.contains("v-new"))
            XCTAssertTrue(text.contains("stopped before previous"))
            XCTAssertTrue(text.contains("stopped before the restore"))
        }
    }

    func testPartialEngineIsNotReady() throws {
        let wine = try write("engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine", "#!/bin/sh\necho wine-11.0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try FileManager.default.createDirectory(at: EnginePaths.bottle("steam11").appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)
        XCTAssertFalse(EngineManager.status().isFullyReady)
    }

    func testDumpCleanupAndFailedRemoval() throws {
        let dump = try write("bottle/drive_c/Program Files (x86)/Steam/dumps/a.dmp", "12345")
        let bottle = root.appendingPathComponent("bottle")
        XCTAssertEqual(try Housekeeping.trimDumps(bottle, cap: 1), 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dump.path))
        let missing = Housekeeping.DumpReport(bytes: 10, cap: 1, dirs: [root.appendingPathComponent("missing")])
        XCTAssertThrowsError(try Housekeeping.trimDumps(missing))
    }

    func testDumpSymlinkCannotEscapeBottle() throws {
        let outside = try write("outside/a.dmp", "keep")
        let target = root.appendingPathComponent("bottle/drive_c/Program Files (x86)/Steam/dumps")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside.deletingLastPathComponent())
        XCTAssertEqual(try Housekeeping.trimDumps(root.appendingPathComponent("bottle"), cap: 1), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testInstallerRequiresPESignature() {
        var data = Data(repeating: 0, count: 128)
        data[0] = 0x4d; data[1] = 0x5a; data[60] = 64
        XCTAssertThrowsError(try SteamManager.validateSteamSetup(data))
        data[64] = 0x50; data[65] = 0x45
        XCTAssertNoThrow(try SteamManager.validateSteamSetup(data))
        data[63] = 0xff
        XCTAssertThrowsError(try SteamManager.validateSteamSetup(data))
    }

    func testConcurrentLogWrites() throws {
        DispatchQueue.concurrentPerform(iterations: 40) { DecantLog.line("row-\($0)") }
        let rows = try String(contentsOf: DecantLog.fileURL).split(separator: "\n")
        XCTAssertEqual(rows.count, 40)
        XCTAssertEqual(Set(rows.map { $0.split(separator: " ").last! }).count, 40)
    }

    func testLogRejectsSymlink() throws {
        let outside = try write("outside.txt", "keep")
        try FileManager.default.createDirectory(at: DecantLog.directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: DecantLog.fileURL, withDestinationURL: outside)
        DecantLog.line("must not overwrite")
        XCTAssertEqual(try String(contentsOf: outside), "keep")
    }
}
