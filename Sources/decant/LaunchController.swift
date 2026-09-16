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
    // the engine gate. play and retry both run it, so neither can start a
    // launch on an engine that is not ready. production passes requireReady.
    private let ready: () throws -> Void
    private var session: LaunchSession?
    private var prefix: URL?
    private var lastRejection: LaunchFailure?
    private var timer: Timer?
    // every launcher this session started that has not reported an exit. a
    // launch starts the steam wrapper and then the game wrapper, and the
    // first can still be running when the second starts, so this holds both.
    // a pid leaves this list the moment its exit arrives, because the kernel
    // is free to give that number to an unrelated process afterwards.
    private var liveLaunchers: [Int32] = []

    // how often production polls the probe and the timeouts.
    private let pollSeconds: TimeInterval = 2

    init(clock: LaunchClock, probe: ProcessProbe, spawner: LaunchSpawner,
         ready: @escaping () throws -> Void = {}) {
        self.clock = clock
        self.probe = probe
        self.spawner = spawner
        self.ready = ready
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

        // the same gate play uses. retry comes back through here, so a
        // not-ready engine stops both.
        do {
            try ready()
        } catch {
            switch error {
            case DecantError.noEngine, DecantError.noBottle:
                fail(.engineMissing)
            default:
                fail(.notReady(String(describing: error)))
            }
            return
        }

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
        liveLaunchers = []
        publish()
    }

    func retry() {
        guard let live = session, let prefix else { return }
        let appID = live.appID
        let engineVersion = live.engineVersion
        reset()
        requestPlay(appID: appID, engineVersion: engineVersion, prefix: prefix)
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

        guard let limit = LaunchTimeout.limit(for: live.phase) else {
            publish()
            return
        }
        if live.elapsedInPhase(now: now) >= limit {
            advance(.timedOut, at: now)
            finish()
            return
        }
        // no new evidence, but the clock moved, so the ui still gets the time.
        publish()
    }

    // the launch script exited. a nonzero status is the failure the old
    // spawn path used to lose. every exit is logged with its launch id. a
    // callback from an earlier launch is stale and changes nothing, and an
    // exit that lands after the launch already ended only gets a log line.
    func deliverExit(launchID: String, pid: Int32, result: RunResult) {
        let apply = { [weak self] in
            guard let self else { return }
            guard let live = self.session, live.id == launchID else {
                self.forget(pid: pid)
                DecantLog.line("launch_id=\(launchID) stale exit \(result.code) from pid=\(pid) ignored")
                return
            }
            // this launcher is gone, so drop its pid before anything else can
            // decide to signal it.
            self.forget(pid: pid)
            DecantLog.line("launch_id=\(launchID) launch script pid=\(pid) exited \(result.code)")
            guard result.code != 0 else { return }
            guard live.phase.isInFlight else {
                DecantLog.line("launch_id=\(launchID) exit \(result.code) arrived after the "
                    + "launch ended in \(live.phase.label)")
                return
            }
            self.advance(.spawnFailed(result.code), at: self.clock.now(), exitCode: result.code)
            self.finish()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    // MARK: internals

    private func startSteam() {
        guard let live = session else { return }
        do {
            let id = live.id
            let pid = try spawner.startSteam(launchID: id) { [weak self] pid, result in
                self?.deliverExit(launchID: id, pid: pid, result: result)
            }
            liveLaunchers.append(pid)
            DecantLog.line("launch_id=\(live.id) steam wrapper pid=\(pid)")
        } catch {
            spawnFailed(error)
        }
    }

    private func sendPlayRequest() {
        guard let live = session else { return }
        do {
            let id = live.id
            // the steam wrapper can still be running, so this pid joins it
            // instead of replacing it.
            let pid = try spawner.startGame(appID: live.appID, launchID: id) { [weak self] pid, result in
                self?.deliverExit(launchID: id, pid: pid, result: result)
            }
            liveLaunchers.append(pid)
            advance(.requestSpawned(pid: pid), at: clock.now(), exitCode: nil)
            DecantLog.line("launch_id=\(live.id) phase=request_sent pid=\(pid)")
        } catch {
            spawnFailed(error)
        }
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
        stopLauncher()
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

    // a launch is over: log the stages and write a redacted report. a launch
    // that failed also stops the launcher it started, so the process ends,
    // its handles close and its output files stop growing. this signals the
    // launch script only. wine and steam keep running on purpose, because
    // one of those descendants can be a game the user is playing.
    private func finish() {
        guard let live = session else { return }
        DecantLog.line("launch_id=\(live.id) phase=\(live.phase.label) stages=\(live.stages.count)")
        if live.phase.isFailed { stopLauncher() }
        writeDiagnostic()
    }

    // stop every launcher this session still has running. a pid that already
    // reported its exit is not in the list, so it never gets signalled.
    private func stopLauncher() {
        let pids = liveLaunchers
        liveLaunchers = []
        for pid in pids {
            guard let code = spawner.terminate(pid: pid) else { continue }
            // ESRCH only means the launcher exited between the list and the
            // signal. anything else is worth the line. the pid is dropped
            // either way, and nothing is retried.
            let reason = String(cString: strerror(code))
            DecantLog.line("could not stop launcher pid=\(pid): \(reason)")
        }
    }

    private func forget(pid: Int32) {
        liveLaunchers.removeAll { $0 == pid }
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
            spawner: SteamLaunchSpawner(bottle: bottle, engine: engine),
            ready: { _ = try EngineManager.requireReady() }
        )
    }
}
