# Decant

Decant is a macOS launcher for Windows-only Steam games on Apple Silicon. It pairs a SwiftUI game library with an install recipe for Wine, DXMT, and Windows Steam.

The app finds installed games, launches them by Steam app ID, and shows engine status and launch errors.

## Features

- Detects the installed Wine and DXMT engine and reports its status.
- Lists owned Steam games and launches them by app ID.
- Installs Steam inside a dedicated Wine bottle and tracks setup progress.
- Re-icons and renames desktop shortcuts to match each game's Steam art.
- Caps and trims crash dumps through a `--gc` command.
- Logs to a single append-only file for diagnostics.

## How it works

Rosetta 2 translates x86-64 instructions. Wine provides the Windows APIs. DXMT translates supported Direct3D calls to Metal. Decant installs this stack and connects it to the game library.

The engine and Steam bottle live under `~/Library/Application Support/decant`. The repository contains the install recipe and the SwiftUI app.

## Prerequisites

- An Apple Silicon Mac running macOS 26. The engine recipe targets macOS 26; older releases are untested.
- Rosetta 2.
- Homebrew at `/opt/homebrew` and the Xcode Command Line Tools.
- Swift 6.3 or later (SwiftPM, macOS platform 13 minimum in `Package.swift`).
- At least 10 GB of free space for setup, plus space for games.

## Quick start

Clone the repository, then install the engine from the repository root:

```sh
git clone https://github.com/salshwauva/decant.git
cd decant
bash engine/install.sh
```

The first install includes Wine and DXMT builds and takes about an hour. The `--minimal` flag skips those rebuilds and installs the Steam UI only.

Build the app bundle and run it:

```sh
./scripts/bundle.sh
open build/decant.app
```

`bundle.sh` also deploys the launch scripts into `~/Library/Application Support/decant`. The app reports a missing engine until the engine install completes.

## Usage

Check engine and Wine status without opening the app:

```sh
BIN="$(swift build --show-bin-path)/decant"
"$BIN" --doctor
```

Expected output:

```
decant doctor
  support: /Users/<user>/Library/Application Support/decant
  wine:    .../engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine
  script:  ok
```

Other CLI flags on the same binary: `--self-test` runs the pure-logic checks with no Wine dependency, `--games` lists owned games, `--gc` reports and trims crash dumps, `--theme-icons` re-icons desktop shortcuts, `--play <app-id>` launches a game, `--log` prints the log path.

Opening the app (`open build/decant.app`, or running the binary with no flags) re-icons every installed game's real desktop shortcut on appear. Use the CLI flags above to check state without touching the desktop.

Logs live at `~/Library/Application Support/decant/logs/decant.log`.

## Compatibility

The project records successful runs of Fields of Mistria, Kynseed, and Travellers Rest. These results do not establish compatibility with other games.

Games that require Windows kernel anti-cheat are outside the supported scope. Compatibility depends on the game and the Wine and DXMT versions in `engine/PINS.md`.

## Tests and checks

```sh
swift build
swift test
python3 -B -m unittest discover -s Tests/EngineTests -v
```

`swift test` runs 18 cases against temp fixtures: argument parsing, process handling, and engine readiness. It does not exercise the installed engine, graphics, or a real game launch. The Python suite runs 7 cases against the shell install scripts.

Both suites, plus a release build, `--self-test`, and `--doctor`, run together through:

```sh
./scripts/smoke.sh
```

## Project structure

```
Sources/decant/   SwiftUI app, game library, and engine control
engine/           Wine, DXMT, and Steam install recipe
scripts/          App bundle, launch, and benchmark scripts
Tests/            Swift tests and engine tests
Resources/        Fonts, icons, and animation frames
docs/             Review guide and security and test plan
```

`Sources/decant/DecantApp.swift` is the entry point and CLI flag dispatch. `ContentView.swift` renders the shelf. `Engine.swift` detects the Wine and DXMT stack. `SteamManager.swift` installs and drives Steam inside the bottle. `GameIconTheme.swift` re-icons desktop shortcuts. `SelfTest.swift` holds the pure-logic checks behind `--self-test`.

`engine/install.sh` runs `engine/scripts/00` through `08` in order. `engine/PINS.md` records the exact pinned versions of Wine, DXMT, and their build tools.

## Status

Active development. The recorded compatibility list covers three games; the engine has not been validated against titles with kernel anti-cheat.

## Dependencies and credits

The engine scripts derive from [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine), under the MIT license, at base commit `540037e`. The [engine notice](engine/NOTICE) preserves that credit. [Engine pins](engine/PINS.md) records dependency versions.
