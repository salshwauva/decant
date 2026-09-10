import Foundation
import CryptoKit

// per-version engine installs. every engine version lives in its own
// directory under versions/<id>. a `current` symlink names the active
// version and a `previous` symlink names the one before it, so a broken
// install rolls back without a rebuild and without touching a bottle.
//
// activation is the same five steps here and in
// engine/scripts/lib/engine-store.sh. keep both in step:
//   1. copy the new engine into versions/<id>.partial
//   2. hash every artifact the manifest lists (sha256)
//   3. validate the staged directory: manifest id, artifacts present, hashes
//   4. rename versions/<id>.partial onto versions/<id>
//   5. write current.new, rename it onto current, then point previous at the old id
//
// a failure at any step leaves current on the old version. the partial
// directory and the half written symlink go away with it.

// what an engine version is made of. artifacts maps a path relative to the
// version directory to its sha256 hex digest.
struct EngineManifest: Codable, Equatable {
    var id: String
    var wineTag: String
    var wineSourceCommit: String
    var dxmtTag: String
    var dxmtCommit: String
    var patches: [String]
    var build: [String: String]
    var artifacts: [String: String]
    var createdAt: Date
}

// the failure points an install can hit. the self-test drives one install
// per case and proves the old engine survives each one.
enum EngineFault: String, CaseIterable {
    case interruptedDownload
    case diskFullDuringCopy
    case badChecksum
    case failedValidation
    case manifestIdMismatch
    case interruptedSwitch
}

enum EngineStoreError: Error, CustomStringConvertible {
    case checksumMismatch(String)
    case validationFailed(String)
    case interrupted(String)
    case noPrevious

    var description: String {
        switch self {
        case .checksumMismatch(let s): return "checksum mismatch: \(s)"
        case .validationFailed(let s): return "validation failed: \(s)"
        case .interrupted(let s): return "interrupted: \(s)"
        case .noPrevious: return "no previous engine version to roll back to"
        }
    }
}

struct EngineStore {
    let root: URL

    private var fm: FileManager { FileManager.default }

    var versionsURL: URL { root.appendingPathComponent("versions", isDirectory: true) }
    var currentURL: URL { root.appendingPathComponent("current") }
    var previousURL: URL { root.appendingPathComponent("previous") }

    func versionURL(id: String) -> URL {
        versionsURL.appendingPathComponent(id, isDirectory: true)
    }

    func stagingURL(id: String) -> URL {
        versionsURL.appendingPathComponent("\(id).partial", isDirectory: true)
    }

    func manifestURL(id: String) -> URL {
        versionURL(id: id).appendingPathComponent("manifest.json")
    }

    // the id current points at, or nil when nothing is active yet.
    func activeID() throws -> String? {
        linkTarget(currentURL)
    }

    func previousID() throws -> String? {
        linkTarget(previousURL)
    }

    func writeManifest(_ manifest: EngineManifest, to directory: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    func readManifest(in directory: URL) throws -> EngineManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw EngineStoreError.validationFailed("no manifest at \(url.path)")
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(EngineManifest.self, from: data)
        } catch {
            throw EngineStoreError.validationFailed("manifest does not parse: \(error)")
        }
    }

    // hash every artifact the manifest lists and compare with the digest it
    // records. a missing file is a validation failure, a different digest is
    // a checksum mismatch.
    func checksumVerify(dir: URL, manifest: EngineManifest) throws {
        if manifest.artifacts.isEmpty {
            throw EngineStoreError.validationFailed("manifest lists no artifacts")
        }
        for path in manifest.artifacts.keys.sorted() {
            let expected = manifest.artifacts[path] ?? ""
            let file = dir.appendingPathComponent(path)
            guard fm.fileExists(atPath: file.path) else {
                throw EngineStoreError.validationFailed("artifact missing: \(path)")
            }
            let actual = try Self.sha256(ofFile: file)
            if actual != expected {
                throw EngineStoreError.checksumMismatch("\(path) is \(actual), manifest says \(expected)")
            }
        }
    }

    // a version directory is good when its manifest parses, its id matches
    // the directory name, and every artifact it lists is present and hashes
    // to the recorded digest.
    func validate(id: String) throws {
        try validate(directory: versionURL(id: id), expectedID: id)
    }

    func validate(directory: URL, expectedID: String) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw EngineStoreError.validationFailed("no version directory at \(directory.path)")
        }
        let manifest = try readManifest(in: directory)
        if manifest.id != expectedID {
            throw EngineStoreError.validationFailed(
                "manifest id \(manifest.id) does not match \(expectedID)")
        }
        try checksumVerify(dir: directory, manifest: manifest)
    }

    // step 5. point current at id and record the id it replaced.
    func activate(id: String) throws {
        try validate(id: id)
        let old = try activeID()
        try link(currentURL, to: "versions/\(id)")
        if let old, old != id {
            try link(previousURL, to: "versions/\(old)")
        }
    }

    // swap back to the version current replaced. activate records the id it
    // displaces, so a rollback after a rollback returns where it started.
    func rollback() throws {
        guard let prev = try previousID() else { throw EngineStoreError.noPrevious }
        try activate(id: prev)
    }

    // install a new version from a built engine directory. fault names a
    // barrier to fail at, for the self-test. on any failure current keeps
    // pointing at the version that was already active.
    func install(from source: URL, manifest: EngineManifest, fault: EngineFault?) throws {
        let staging = stagingURL(id: manifest.id)
        let installed = versionURL(id: manifest.id)
        let pending = root.appendingPathComponent("current.new")
        var renamed = false

        try fm.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        try? fm.removeItem(at: staging)

        do {
            // step 1: copy into the partial directory.
            if fault == .interruptedDownload {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                throw EngineStoreError.interrupted("download stopped before the engine arrived")
            }
            try copyTree(from: source, to: staging, stopAfterFirstFile: fault == .diskFullDuringCopy)

            var staged = manifest
            if fault == .manifestIdMismatch {
                staged.id = manifest.id + "-mismatch"
            }
            try writeManifest(staged, to: staging)

            if fault == .badChecksum, let first = manifest.artifacts.keys.sorted().first {
                let file = staging.appendingPathComponent(first)
                var bytes = try Data(contentsOf: file)
                bytes.append(0x21)
                try bytes.write(to: file, options: .atomic)
            }
            if fault == .failedValidation, let first = manifest.artifacts.keys.sorted().first {
                try fm.removeItem(at: staging.appendingPathComponent(first))
            }

            // step 2: hash what the download claimed to deliver.
            try checksumVerify(dir: staging, manifest: manifest)

            // step 3: validate the staged directory on its own terms.
            try validate(directory: staging, expectedID: manifest.id)

            // step 4: rename the partial directory into place.
            try? fm.removeItem(at: installed)
            guard rename(staging.path, installed.path) == 0 else {
                throw EngineStoreError.interrupted("could not rename \(staging.path)")
            }
            renamed = true

            // step 5: switch current.
            if fault == .interruptedSwitch {
                try? fm.removeItem(at: pending)
                try fm.createSymbolicLink(atPath: pending.path,
                                          withDestinationPath: "versions/\(manifest.id)")
                throw EngineStoreError.interrupted("stopped between current.new and current")
            }
            try activate(id: manifest.id)
        } catch {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: pending)
            if renamed { try? fm.removeItem(at: installed) }
            throw error
        }
    }

    // -- helpers --------------------------------------------------------------

    static func sha256(ofFile url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // hash every regular file under directory, so a caller can fill
    // manifest.artifacts from a freshly built engine.
    static func artifactHashes(of directory: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        for path in try relativeFiles(of: directory) {
            out[path] = try sha256(ofFile: directory.appendingPathComponent(path))
        }
        return out
    }

    static func relativeFiles(of directory: URL) throws -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        let base = directory.standardizedFileURL.path
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            out.append(String(full.dropFirst(base.count + 1)))
        }
        return out.sorted()
    }

    private func copyTree(from source: URL, to destination: URL, stopAfterFirstFile: Bool) throws {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var copied = 0
        for path in try Self.relativeFiles(of: source) {
            let target = destination.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.copyItem(at: source.appendingPathComponent(path), to: target)
            copied += 1
            if stopAfterFirstFile {
                throw EngineStoreError.interrupted("no space left after \(copied) file(s)")
            }
        }
    }

    private func linkTarget(_ link: URL) -> String? {
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        return (dest as NSString).lastPathComponent
    }

    // write a symlink the way step 5 does: a fresh .new link, renamed onto
    // the real name so a reader never sees a missing link.
    private func link(_ link: URL, to relativeTarget: String) throws {
        let pending = link.appendingPathExtension("new")
        try? fm.removeItem(at: pending)
        try fm.createSymbolicLink(atPath: pending.path, withDestinationPath: relativeTarget)
        guard rename(pending.path, link.path) == 0 else {
            try? fm.removeItem(at: pending)
            throw EngineStoreError.interrupted("could not rename onto \(link.path)")
        }
    }
}
