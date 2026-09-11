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
        check("support ends with decant",
              EnginePaths.support.path.hasSuffix("Application Support/decant")
                || EnginePaths.support.path.contains("Application Support/decant"))
        check("wine path under engines/wine11",
              EnginePaths.wineBinary.contains("engines/wine11"))

        // status enum headlines distinct
        check("headline noEngine", EngineStatus.noEngine.headline.contains("not installed"))
        if let e = Engine.detect() {
            check("headline noBottle",
                  EngineStatus.engineNoBottle(e).headline.contains("no bottle"))
        } else {
            print("skip headline noBottle (no wine on disk)")
        }

        if failed == 0 {
            print("self-test: all passed")
            return true
        }
        print("self-test: \(failed) failure(s)")
        return false
    }
}
