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
              SteamManager.isSupportPackage(appID: "1", name: "DirectX Redistributable"))
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

            let store = EngineStore(root: tmp.appendingPathComponent("engines", isDirectory: true))
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

                var thrown: Error?
                do {
                    try store.install(from: srcNew, manifest: newManifest, fault: fault)
                } catch {
                    thrown = error
                }
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
}
