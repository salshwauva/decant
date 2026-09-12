import Foundation
import Combine

// what a user can do about a launch that is stuck or failed.
enum RecoveryAction: String, Identifiable {
    case retry
    case openLog
    case runDoctor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .retry: return "retry"
        case .openLog: return "open log"
        case .runDoctor: return "run doctor"
        }
    }
}

// the read-only view of a launch. views get this and nothing else, so no
// view can start, stop or probe a process.
struct LaunchSnapshot: Equatable {
    let id: String
    let appID: String
    let phase: LaunchPhase
    let elapsed: TimeInterval
    let explanation: String
    let recovery: [RecoveryAction]
    // set when decant refused a second play while one was in flight.
    let lastRejection: LaunchFailure?

    var isInFlight: Bool { phase.isInFlight }

    // m:ss, for the ui.
    var elapsedLabel: String {
        let total = Int(elapsed.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func recovery(for phase: LaunchPhase) -> [RecoveryAction] {
        switch phase {
        case .failed: return [.retry, .openLog, .runDoctor]
        case .preparing, .steamReady, .requestSent: return [.openLog]
        case .idle, .processDetected: return []
        }
    }
}

// owns one launch at a time and turns evidence into phases. this is the only
// place that starts a launch process.
final class LaunchController: ObservableObject {
    @Published private(set) var snapshot: LaunchSnapshot?

    private let clock: LaunchClock
    private let probe: ProcessProbe
    private let spawner: LaunchSpawner
    private var session: LaunchSession?
    private var prefix: URL?
    private var lastRejection: LaunchFailure?
    private var timer: Timer?

    // how often production polls the probe and the timeouts.
    private let pollSeconds: TimeInterval = 2

    init(clock: LaunchClock, probe: ProcessProbe, spawner: LaunchSpawner) {
        self.clock = clock
        self.probe = probe
        self.spawner = spawner
    }

    deinit { timer?.invalidate() }

    // production polling. the self-test calls tick() by hand instead.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    var phase: LaunchPhase { session?.phase ?? .idle }

    // the user pressed play. a second press while a launch is in flight is
    // recorded as a duplicate and changes nothing.
    func requestPlay(appID: String, engineVersion: String, prefix: URL) {
        let now = clock.now()

        if var live = session, live.phase.isInFlight {
            do {
                try live.machine.apply(.userPlay(appID: appID))
                session = live
            } catch {
                lastRejection = .duplicate
                live.note("duplicate play ignored", at: now)
                session = live
                DecantLog.line("launch_id=\(live.id) duplicate play appid=\(appID) phase=\(live.phase.label)")
            }
            publish()
            return
        }

        lastRejection = nil
        self.prefix = prefix
        guard let fresh = try? LaunchSession.make(appID: appID, engineVersion: engineVersion,
                                                  now: now) else { return }
        session = fresh
        DecantLog.line("launch_id=\(fresh.id) phase=preparing appid=\(appID) engine=\(engineVersion)")
        publish()

        guard FileManager.default.fileExists(atPath: prefix.path) else {
            fail(.probe("no bottle at \(prefix.path)"))
            return
        }

        if probe.steamReady(prefix: prefix) {
            advance(.steamReady, at: clock.now())
            sendPlayRequest()
        } else {
            startSteam()
        }
    }

    // clear a finished or failed launch so play works again.
    func reset() {
        session = nil
        lastRejection = nil
        publish()
    }

    func retry() {
        guard let live = session, let prefix else { return }
        let appID = live.appID
        let engineVersion = live.engineVersion
        reset()
        requestPlay(appID: appID, engineVersion: engineVersion, prefix: prefix)
    }

    // opening the steam client by itself has no game to watch for, so it gets
    // a launch id and a log line and no lifecycle. it lives here because the
    // controller is the only place that starts a launch process. returns the
    // dump trim note when there is one.
    func openSteamClient(bottle: URL, engine: Engine) throws -> String? {
        let id = UUID().uuidString
        let spawn = try SteamManager.launchClient(bottle, engine: engine, launchID: id)
        DecantLog.line("launch_id=\(id) steam client pid=\(spawn.pid)")
        return spawn.note
    }

    // one poll: look for evidence, then check the timeout for this phase.
    func tick() {
        guard let live = session, let prefix, live.phase.isInFlight else { return }
        let now = clock.now()

        switch live.phase {
        case .preparing:
            if probe.steamReady(prefix: prefix) {
                advance(.steamReady, at: now)
                sendPlayRequest()
                return
            }
        case .requestSent:
            if probe.gameDetected(appID: live.appID, prefix: prefix) {
                advance(.gameDetected, at: now)
                finish()
                return
            }
        default:
            break
        }

        guard let limit = LaunchTimeout.limit(for: live.phase) else { return }
        if live.elapsedInPhase(now: now) >= limit {
            advance(.timedOut, at: now)
            finish()
        }
    }

    // MARK: internals

    private func startSteam() {
        guard let live = session else { return }
        let id = live.id
        do {
            let pid = try spawner.startSteam(launchID: id) { [weak self] code, err in
                self?.wrapperExited(launchID: id, code: code, err: err)
            }
            DecantLog.line("launch_id=\(id) steam wrapper pid=\(pid)")
        } catch {
            spawnFailed(error)
        }
    }

    private func sendPlayRequest() {
        guard let live = session else { return }
        let id = live.id
        do {
            let pid = try spawner.startGame(appID: live.appID, launchID: id) { [weak self] code, err in
                self?.wrapperExited(launchID: id, code: code, err: err)
            }
            advance(.requestSpawned(pid: pid), at: clock.now(), exitCode: nil)
            DecantLog.line("launch_id=\(id) phase=request_sent pid=\(pid)")
        } catch {
            spawnFailed(error)
        }
    }

    // the wrapper exited. a zero exit is the normal case: the script hands the
    // request to steam and returns while wine keeps running, so the probe still
    // has to find the game. a non-zero exit is a launch that died early, and
    // saying so now beats waiting out the phase timeout.
    private func wrapperExited(launchID: String, code: Int32, err: String) {
        // the handler runs on a process-reaping thread. every phase change
        // belongs to the main queue, next to the published snapshot.
        DispatchQueue.main.async { [weak self] in
            self?.applyWrapperExit(launchID: launchID, code: code, err: err)
        }
    }

    // the self-test calls this directly, the same way it calls tick().
    func applyWrapperExit(launchID: String, code: Int32, err: String) {
        guard let live = session, live.id == launchID, live.phase.isInFlight else { return }
        guard code != 0 else {
            DecantLog.line("launch_id=\(launchID) wrapper exited 0, waiting for the game")
            return
        }
        let reason = err.isEmpty ? "launcher exited \(code)" : err
        DecantLog.line("launch_id=\(launchID) wrapper exited \(code): \(reason)")
        advance(.spawnFailed(code), at: clock.now(), exitCode: code)
        finish()
    }

    private func spawnFailed(_ error: Error) {
        guard let live = session else { return }
        if case DecantError.noEngine = error {
            fail(.engineMissing)
            return
        }
        if case DecantError.noBottle = error {
            fail(.engineMissing)
            return
        }
        let code = Int32(truncatingIfNeeded: (error as NSError).code)
        DecantLog.line("launch_id=\(live.id) spawn failed: \(error)")
        advance(.spawnFailed(code), at: clock.now(), exitCode: code)
        finish()
    }

    private func fail(_ failure: LaunchFailure) {
        guard var live = session else { return }
        let now = clock.now()
        try? live.machine.fail(failure)
        live.record(label: failure.explanation, at: now)
        session = live
        DecantLog.line("launch_id=\(live.id) phase=failed \(failure.explanation)")
        publish()
        writeDiagnostic()
    }

    private func advance(_ evidence: LaunchEvidence, at now: Date, exitCode: Int32? = nil) {
        guard var live = session else { return }
        do {
            try live.machine.apply(evidence)
        } catch {
            DecantLog.line("launch_id=\(live.id) refused \(evidence.label) in \(live.phase.label)")
            return
        }
        live.record(evidence, at: now, exitCode: exitCode)
        session = live
        publish()
    }

    // a launch is over: log the stages and write a redacted report.
    private func finish() {
        guard let live = session else { return }
        DecantLog.line("launch_id=\(live.id) phase=\(live.phase.label) stages=\(live.stages.count)")
        writeDiagnostic()
    }

    private func writeDiagnostic() {
        guard let live = session else { return }
        do {
            let url = try LaunchDiagnostic.write(session: live, logTail: DecantLog.tail(lines: 40))
            DecantLog.line("launch_id=\(live.id) report \(url.path)")
        } catch {
            DecantLog.line("launch_id=\(live.id) could not write report: \(error)")
        }
    }

    private func publish() {
        guard let live = session else {
            snapshot = nil
            return
        }
        let now = clock.now()
        snapshot = LaunchSnapshot(
            id: live.id,
            appID: live.appID,
            phase: live.phase,
            elapsed: live.elapsed(now: now),
            explanation: live.phase.explanation,
            recovery: LaunchSnapshot.recovery(for: live.phase),
            lastRejection: lastRejection
        )
    }
}

extension LaunchController {
    // the production wiring: real clock, prefix-scoped probe, real scripts.
    static func production(bottle: URL, engine: Engine) -> LaunchController {
        LaunchController(
            clock: SystemClock(),
            probe: SystemProcessProbe(),
            spawner: SteamLaunchSpawner(bottle: bottle, engine: engine)
        )
    }
}
