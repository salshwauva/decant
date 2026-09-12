# Decant

Decant is a macOS launcher for Windows Steam games on Apple Silicon. It pairs a SwiftUI game library with scripts that install Wine, DXMT, and Windows Steam.

The app finds installed games, launches them by Steam app ID, and shows engine status and launch errors. A pixel-art shelf presents the library.

## How it works

Rosetta 2 translates x86-64 instructions. Wine provides the Windows APIs. DXMT translates supported Direct3D calls to Metal. Decant installs this stack and connects it to the game library.

The engine and Steam bottle live under `~/Library/Application Support/decant`. The repository contains the install recipe and the SwiftUI app.

## Requirements

- An Apple Silicon Mac. The engine recipe targets macOS 26; older releases are untested.
- Rosetta 2.
- Homebrew at `/opt/homebrew` and the Xcode Command Line Tools.
- At least 10 GB of free space for setup, plus space for games.

## Build and run

From the repository root, install the engine:

```sh
bash engine/install.sh
```

The first install includes Wine and DXMT builds and can take about an hour. The `--minimal` option skips those rebuilds.

Build the app bundle:

```sh
./scripts/bundle.sh
open build/decant.app
```

The bundle script also deploys the launch scripts. The app reports a missing engine until the engine install completes.

## Compatibility

The project records successful runs of Fields of Mistria, Kynseed, and Travellers Rest. These results do not establish compatibility with other games.

Games that require Windows kernel anti-cheat are outside the supported scope. Compatibility depends on the game and the Wine and DXMT versions.

## Checks and diagnostics

Run the Swift and engine tests without a game launch:

```sh
swift test
python3 -B -m unittest discover -s Tests/EngineTests -v
```

After engine setup, run the smoke checks:

```sh
./scripts/smoke.sh
```

The executable also supports `--self-test`, `--doctor`, and `--log`. Logs live at `~/Library/Application Support/decant/logs/decant.log`.

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/decant/` | SwiftUI app, game library, and engine control |
| `engine/` | Wine, DXMT, and Steam install recipe |
| `scripts/` | App bundle and launch scripts |
| `Tests/` | Swift tests and engine tests |
| `Resources/` | Fonts, icons, and animation frames |

## Dependencies and credits

The engine scripts derive from [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine), under the MIT license, at base commit `540037e`.

The [engine notice](engine/NOTICE) preserves that credit. [Engine pins](engine/PINS.md) records dependency versions.
