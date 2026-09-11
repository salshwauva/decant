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
