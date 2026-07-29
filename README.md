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

## status

- engine recipe in-repo, install defaults to Application Support/decant (done)
- cozy pixel swiftui library ui (done)
- engine manager: detect wine 11 + dxmt bottle (done)
- install windows steam, scan the library, find owned games (done)
- launch a game by steam app id, with the directx-to-metal env (done)
- add and uninstall games through steam, themed desktop icons, pour animation (done)
- gui launch errors, honest status, prefix-scoped kills, structured logs (done)

this is the opposite end from [wisp](../wisp): wisp emulates a cpu from
scratch for a toy program; decant runs real games on a mature stack.
