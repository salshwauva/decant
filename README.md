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

The executable also supports `--self-test`, `--doctor`, `--log`, `--gc`, `--export-launch`, and `--rollback-engine`. Logs live at `~/Library/Application Support/decant/logs/decant.log`.

## Engine updates

Each engine version lives in its own directory. `current` names the active version. `previous` names the version it replaced.

```
engines/
  versions/<id>/                one engine version
  versions/<id>/manifest.json   pins plus a sha256 per artifact
  versions/<id>.partial/        in-flight work
  current   -> versions/<id>
  previous  -> versions/<id>
```

An install runs five steps. `Sources/decant/EngineStore.swift` and `engine/scripts/lib/engine-store.sh` follow the same five:

1. Copy the new engine into `versions/<id>.partial`.
2. Hash every artifact the manifest lists.
3. Validate the staged directory: manifest ID, artifacts present, hashes match.
4. Rename `versions/<id>.partial` onto `versions/<id>`.
5. Write `current.new`, rename it onto `current`, then point `previous` at the old ID.

A failure at any step leaves `current` on the old version and leaves the bottle untouched. `decant --rollback-engine` swaps back to `previous`.

The self-test installs a fake engine, fingerprints a fake prefix, then fails one install per fault case. It checks that the old engine is still active and that the prefix still hashes the same:

```sh
swift build -c release && .build/release/decant --self-test
```

That run prints one `FAULT <name> recovered` line per case, then the count as `N=`. The smoke script fails when the count and the number of `FAULT` lines disagree.

## Launch lifecycle

Pressing Play runs a state machine. [The lifecycle note](docs/launch-lifecycle.md) records the states, the evidence each transition needs, the timeouts, and what a detected process does and does not prove.

Every launch carries an ID and a stage log. A finished or failed launch writes a redacted report:

```sh
decant --export-launch
```

Two things can end a launch early. A phase can run out of time. The launch script can also exit non-zero, and Decant reports that exit instead of waiting for the timeout.

The state machine is a plain Swift type, so the self-test drives it with a fake clock, a fake probe, and a fake spawner. No Wine and no bottle are involved:

```sh
.build/release/decant --self-test 2>/dev/null | grep -c '^ok   launch\|^ok   redact'
```

The smoke script fails when any named lifecycle case goes missing.

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
