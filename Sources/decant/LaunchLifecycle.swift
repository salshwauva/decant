import Foundation

// the launch lifecycle as pure data. no Process, no wine, no views.
// every phase change needs a named piece of evidence, so a launch that
// stalls can say which step it is on and what it was waiting for.

// where a launch is right now.
enum LaunchPhase: Equatable {
    case idle
    case preparing
    case steamReady
    case requestSent
    case processDetected
    case failed(LaunchFailure)

    // short label for the ui.
    var label: String {
        switch self {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .steamReady: return "steam ready"
        case .requestSent: return "request sent"
        case .processDetected: return "running"
        case .failed: return "failed"
        }
    }

    // one plain sentence about what decant is doing or what went wrong.
    var explanation: String {
        switch self {
        case .idle:
            return "nothing is launching"
        case .preparing:
            return "waiting for steam to come up inside the bottle"
        case .steamReady:
            return "steam is up, sending the play request"
        case .requestSent:
            return "the play request went out, watching for the game process"
        case .processDetected:
            return "a game process is running in this bottle"
        case .failed(let failure):
            return failure.explanation
        }
    }

    // preparing, steam ready and request sent are the in-flight phases: a
    // launch can still time out or fail from any of them.
    var isInFlight: Bool {
        switch self {
        case .preparing, .steamReady, .requestSent: return true
        case .idle, .processDetected, .failed: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

// why a launch stopped. indirect because timeout names the phase it left.
indirect enum LaunchFailure: Equatable {
    case timeout(from: LaunchPhase)
    case spawn(Int32)
    case engineMissing
    case duplicate
    case probe(String)

    var explanation: String {
        switch self {
        case .timeout(let from):
            return "gave up while \(from.label): no evidence arrived in time"
        case .spawn(let code):
            return "the launch script failed (exit \(code))"
        case .engineMissing:
            return "no engine on disk: run bash engine/install.sh"
        case .duplicate:
            return "a launch is already in flight, so this play was ignored"
        case .probe(let why):
            return "cannot watch for the game process: \(why)"
        }
    }
}

// the only facts that move a launch forward. each one is something decant
// saw, not something it hoped for.
enum LaunchEvidence: Equatable {
    case userPlay(appID: String)
    case steamReady
    case requestSpawned(pid: Int32)
    case gameDetected
    case timedOut
    case spawnFailed(Int32)
    case reset

    // what goes in the stage log.
    var label: String {
        switch self {
        case .userPlay(let appID): return "user pressed play (appid \(appID))"
        case .steamReady: return "steam processes found in this prefix"
        case .requestSpawned(let pid): return "launch script started (pid \(pid))"
        case .gameDetected: return "game process found in this prefix"
        case .timedOut: return "timed out"
        case .spawnFailed(let code): return "spawn failed (exit \(code))"
        case .reset: return "reset"
        }
    }
}

// evidence the current phase does not accept.
enum LaunchIllegal: Error, Equatable {
    case duplicate
    case badTransition(phase: String, evidence: String)
}

// how long a phase may wait for its evidence before decant calls it failed.
// steam ready is not listed: the controller sends the play request as soon
// as it sees steam, so nothing waits there.
enum LaunchTimeout {
    static let preparing: TimeInterval = 90
    static let requestSent: TimeInterval = 60

    static func limit(for phase: LaunchPhase) -> TimeInterval? {
        switch phase {
        case .preparing: return preparing
        case .requestSent: return requestSent
        default: return nil
        }
    }
}

// the state machine. legal edges only; everything else throws.
struct LaunchMachine: Equatable {
    private(set) var phase: LaunchPhase = .idle

    mutating func apply(_ evidence: LaunchEvidence) throws {
        switch (phase, evidence) {
        case (.idle, .userPlay):
            phase = .preparing
        case (.preparing, .steamReady):
            phase = .steamReady
        case (.steamReady, .requestSpawned):
            phase = .requestSent
        case (.requestSent, .gameDetected):
            phase = .processDetected
        case (_, .userPlay) where phase.isInFlight:
            throw LaunchIllegal.duplicate
        case (_, .timedOut) where phase.isInFlight:
            phase = .failed(.timeout(from: phase))
        case (_, .spawnFailed(let code)) where phase.isInFlight:
            phase = .failed(.spawn(code))
        case (.failed, .reset), (.processDetected, .reset):
            phase = .idle
        default:
            throw LaunchIllegal.badTransition(phase: phase.label, evidence: evidence.label)
        }
    }

    // failures that have no evidence of their own: decant never got far
    // enough to look. legal from an in-flight phase only.
    mutating func fail(_ failure: LaunchFailure) throws {
        guard phase.isInFlight else {
            throw LaunchIllegal.badTransition(phase: phase.label, evidence: "fail")
        }
        phase = .failed(failure)
    }
}

// one row of the stage log: which phase, when it started, how long it took,
// the exit code if a process reported one, and the evidence that ended it.
struct LaunchStage {
    let phase: LaunchPhase
    let enteredAt: Date
    var duration: TimeInterval?
    var exitCode: Int32?
    var evidence: String
}

// one launch attempt: an id, what it was launching, and its stage log.
struct LaunchSession {
    let id: String
    let appID: String
    let engineVersion: String
    var stages: [LaunchStage]
    var machine: LaunchMachine

    // a fresh session already holds the first evidence: the user pressed play.
    // the stage log opens on preparing so elapsed time counts from that press.
    static func make(appID: String, engineVersion: String, now: Date) throws -> LaunchSession {
        var session = LaunchSession(
            id: UUID().uuidString,
            appID: appID,
            engineVersion: engineVersion,
            stages: [],
            machine: LaunchMachine()
        )
        try session.machine.apply(.userPlay(appID: appID))
        session.stages = [LaunchStage(phase: session.machine.phase, enteredAt: now,
                                      duration: nil, exitCode: nil,
                                      evidence: "in progress")]
        return session
    }

    var phase: LaunchPhase { machine.phase }

    var startedAt: Date? { stages.first?.enteredAt }

    // close the open stage, then open one for the new phase.
    mutating func record(_ evidence: LaunchEvidence, at now: Date, exitCode: Int32? = nil) {
        record(label: evidence.label, at: now, exitCode: exitCode)
    }

    // same, for a failure that has no evidence of its own.
    mutating func record(label: String, at now: Date, exitCode: Int32? = nil) {
        closeLastStage(evidence: label, at: now, exitCode: exitCode)
        stages.append(LaunchStage(phase: machine.phase, enteredAt: now,
                                  duration: nil, exitCode: nil, evidence: "in progress"))
    }

    // a note that did not change the phase (a rejected duplicate, say).
    mutating func note(_ text: String, at now: Date) {
        guard var last = stages.popLast() else { return }
        last.evidence = last.evidence == "in progress" ? text : "\(last.evidence); \(text)"
        stages.append(last)
    }

    private mutating func closeLastStage(evidence: String, at now: Date, exitCode: Int32?) {
        guard var last = stages.popLast() else { return }
        last.duration = now.timeIntervalSince(last.enteredAt)
        last.evidence = evidence
        if let exitCode { last.exitCode = exitCode }
        stages.append(last)
    }

    // how long the current phase has been open.
    func elapsedInPhase(now: Date) -> TimeInterval {
        guard let last = stages.last else { return 0 }
        return now.timeIntervalSince(last.enteredAt)
    }

    func elapsed(now: Date) -> TimeInterval {
        guard let start = startedAt else { return 0 }
        return now.timeIntervalSince(start)
    }
}
