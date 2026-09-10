# launch lifecycle

pressing play used to be a shell script and a boolean that cleared after six
seconds. this note describes what replaced it.

## states

five phases plus idle, listed as `LaunchPhase` in
`Sources/decant/LaunchLifecycle.swift`.

| phase | meaning |
| --- | --- |
| idle | nothing is launching |
| preparing | decant asked for steam and waits for it inside the bottle |
| steamReady | steam processes are up in this prefix |
| requestSent | the play request went out to steam |
| processDetected | a game process runs in this prefix |
| failed | the launch stopped, with a reason |

## evidence

a phase never changes on a hope. each edge needs one named fact:

| edge | evidence |
| --- | --- |
| idle to preparing | the user pressed play on an app id |
| preparing to steamReady | the probe found steam processes in this prefix |
| steamReady to requestSent | the launch script started, and decant has its pid |
| requestSent to processDetected | the probe found a non steam windows process in this prefix |
| any in flight phase to failed | the phase ran out of time, or the spawn failed |
| failed or processDetected to idle | reset |

`LaunchMachine.apply` accepts those edges and throws on everything else. it
holds no `Process`, so the self-test drives it directly.

## timeouts

`preparing` waits 90 seconds, because steam inside wine is slow on a cold
prefix and a login prompt can sit there. `requestSent` waits 60 seconds.
`steamReady` has no timeout: decant sends the play request the moment it sees
steam. a timeout produces `failed(.timeout(from:))`, which names the phase
decant gave up in, so "gave up while preparing" and "gave up while request
sent" stay different problems.

## what process detected can and cannot prove

the probe runs `pgrep` for candidates, then `ps eww` on each one and keeps
only the processes whose environment carries this `WINEPREFIX`. a machine wide
`pgrep` would count crossover, whisky and every other bottle as ours.

so `processDetected` proves one thing: a windows process that is not one of
steam's own helpers runs inside decant's bottle. it does not prove the game
reached a title screen, drew a frame, or is playable. a game that crashes two
seconds in still passes through this phase. `requestSent` is weaker still: it
means decant started the wrapper, not that wine got anywhere. that is why the
ui says "a game process is running in this bottle" and no more.

## failures covered

- steam never comes up: `preparing` times out at 90 seconds.
- the game never appears: `requestSent` times out at 60 seconds.
- play is pressed twice: the second press is refused as a duplicate, the
  phase does not move, and nothing is spawned again.
- the launch script will not start: `spawn` failure with the exit code.
- no bottle at the path: `probe` failure that names the path.
- no engine on disk: `engineMissing`, which points at engine/install.sh.

## ids, stage log and the report

every launch has an id, and every phase it entered is one row in a stage log:
the duration, an exit code when a process reported one, and the evidence that
ended it. when a launch finishes or fails, decant writes `logs/launch-<id>.txt`
with the id, the engine version, the stage log, and the tail of the log. the
home path becomes `~`, and every line naming `loginusers`, `AccountName`,
`Password` or `steamid` is dropped. `decant --export-launch` prints the newest
report.

`LaunchController` owns the session and is the only place that starts a launch
process. views read `LaunchSnapshot` and nothing else.
