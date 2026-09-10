# decant

a cozy launcher for windows-only steam games on apple silicon. one project:
the **engine** (wine 11 + dxmt install and launch scripts) and the **ui**
(swiftui shelf that drives it).

decant does not emulate a cpu. the hard work is done by tools that already
exist:

- rosetta 2 translates the x86-64 instructions (built into macos)
- wine provides the windows api and loads the program
- dxmt turns the game's directx calls into metal

on macos 26, off-the-shelf stacks (game porting toolkit, whisky, crossover,
mythic) fell over. the engine half of this repo builds a working free path:
wine 11 with a rebuilt winemac driver and dxmt, under
`~/Library/Application Support/decant`. the ui detects that stack, installs
windows steam into a bottle, lists your games, and launches them.

## layout

```
decant/
  engine/           # one-time wine + dxmt + steam bottle setup (scripts)
  Sources/decant/   # swiftui app
  scripts/          # bundle.sh, decant-launch.sh
  Resources/        # fonts, pour frames, icons
```

the engine scripts started from
[notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) (MIT,
base `540037e`) and live here as the owned recipe. attribution:
`engine/NOTICE`.

## setup

### 1. build the engine (once, ~1 hour first run)

```bash
bash engine/install.sh
```

that installs wine, creates the bottle, wires steam + dxmt, and deploys the
recipe under Application Support. `--minimal` stops before the long dxmt/wine
rebuilds if you only need the steam ui.

### 2. build the ui

needs the swift toolchain from the command line tools. no full xcode project.

```bash
./scripts/bundle.sh        # builds build/decant.app, deploys launch scripts
open build/decant.app
```

if the engine is missing, the app reports it as not ready and points at the
setup guide (`engine/install.sh`).

## scope and honesty

works: single-player and many online titles run through this stack.

does not work, ever, on macos: games with kernel level anti cheat (a lot of
competitive multiplayer). no launcher can change that.

confirmed running: fields of mistria, kynseed, travellers rest. cozy, 2d,
single player, no anti cheat.

## checks

```bash
./scripts/smoke.sh          # paths, pins, --self-test, --doctor
decant --self-test          # pure logic only
decant --doctor             # engine / bottle / dumps / launch script
decant --log                # print log path + tail
decant --gc                 # report / trim crash dumps
```

logs land in `~/Library/Application Support/decant/logs/decant.log`.
the ui ledger has a **log** link; launch errors show as a banner.

pins: `engine/PINS.md`.

## engine updates

each engine version lives in its own directory. `current` names the active
one, `previous` names the one it replaced.

```
engines/
  versions/<id>/                one engine version
  versions/<id>/manifest.json   pins plus a sha256 per artifact
  versions/<id>.partial/        in-flight work
  current   -> versions/<id>
  previous  -> versions/<id>
```

an install runs five steps. `Sources/decant/EngineStore.swift` and
`engine/scripts/lib/engine-store.sh` both follow them:

1. copy the new engine into `versions/<id>.partial`
2. hash every artifact the manifest lists (sha256)
3. validate the staged directory: manifest id, artifacts present, hashes
4. rename `versions/<id>.partial` onto `versions/<id>`
5. write `current.new`, rename it onto `current`, then point `previous` at the old id

a failure at any step leaves `current` on the old version and leaves the
bottle untouched. `decant --rollback-engine` swaps back to `previous`.

the self-test installs a fake engine, fingerprints a fake prefix, then fails
one install per fault case and checks that the old engine is still active and
the prefix still hashes the same:

```bash
swift build -c release && .build/release/decant --self-test
```

that run prints one `FAULT <name> recovered` line per case, then the count:

```
N=6
```

`./scripts/smoke.sh` fails when the count and the number of `FAULT` lines
disagree.

## launch lifecycle

pressing play runs a state machine. the states, the evidence each transition
needs, the timeouts, and what "process detected" can and cannot prove are in
[docs/launch-lifecycle.md](docs/launch-lifecycle.md).

every launch gets an id and a stage log. a finished or failed launch writes a
redacted report:

```bash
decant --export-launch      # print the newest logs/launch-<id>.txt
```

the state machine is a pure swift type, so the self-test drives it with a
fake clock, a fake probe and a fake spawner. no wine, no bottle:

```bash
swift build -c release && .build/release/decant --self-test
```

that run prints 15 launch cases:

```
ok   launch happy
ok   launch reset to idle
ok   launch illegal detect from idle
ok   launch duplicate play rejected
ok   launch duplicate leaves phase
ok   launch duplicate does not spawn again
ok   launch timeout preparing
ok   launch timeout offers recovery
ok   launch request sent on warm steam
ok   launch timeout request sent
ok   launch process detected
ok   redact hides the home path
ok   redact drops identity lines
ok   redact keeps the rest
ok   launch report is under DECANT_HOME
```

count them with:

```bash
.build/release/decant --self-test 2>/dev/null | grep -c '^ok   launch\|^ok   redact'
```

`./scripts/smoke.sh` fails when any of those cases goes missing.

## status

- engine recipe in-repo, install defaults to Application Support/decant (done)
- cozy pixel swiftui library ui (done)
- engine manager: detect wine 11 + dxmt bottle (done)
- install windows steam, scan the library, find owned games (done)
- launch a game by steam app id, with the directx-to-metal env (done)
- add and uninstall games through steam, themed desktop icons, pour animation (done)
- gui launch errors, honest status, prefix-scoped kills, structured logs (done)
- launch lifecycle: phases, launch ids, stage log, timeouts, redacted report (done)

this is the opposite end from [wisp](../wisp): wisp emulates a cpu from
scratch for a toy program; decant runs real games on a mature stack.
