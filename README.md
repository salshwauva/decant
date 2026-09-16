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

The executable also supports `--self-test`, `--doctor`, `--log`, `--export-launch`, and `--rollback-engine`. Logs live at `~/Library/Application Support/decant/logs/decant.log`.

## Engine versions and rollback

Each engine version lives in its own directory. The `current` link names the active version. The `previous` link names the version it replaced.

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
2. Hash every artifact the manifest lists (sha256).
3. Validate the staged directory: manifest id, artifacts present, hashes.
4. Rename `versions/<id>.partial` onto `versions/<id>`.
5. Write `current.new`, rename it onto `current`, then point `previous` at the old id.

A failure at any step leaves `current` on the version that was already active. One id names one set of bytes, so a second install under an id that is already there is refused unless the contents match.

Roll back to the version `current` replaced:

```sh
decant --rollback-engine
```

A rollback changes the engine only. It does not undo a Steam install or a change inside the bottle.

The self-test installs a fake engine into a temporary directory, fingerprints a fake prefix, then fails one install per fault case. It checks that the old engine is still active and that the prefix still hashes the same:

```sh
swift build -c release
"$(swift build -c release --show-bin-path)/decant" --self-test
```

That run prints one `FAULT <name> recovered` line per case, then the count. The count it printed here was `N=6`. The smoke script fails when the count and the number of `FAULT` lines disagree.

## Launch diagnostics

A play press runs a state machine. Each phase change needs a named piece of evidence. The phases, the evidence, the timeouts, and what a detected process does and does not prove are in [the launch lifecycle notes](docs/launch-lifecycle.md).

Every launch gets an id and a stage log. The id travels into the launch script and into the log, so one launch can be traced end to end. A finished or failed launch writes a redacted report:

```sh
decant --export-launch
```

The report hides the home path, the account name, and the Wine side user directories.

A detected process proves only that a Windows process other than Steam runs in this bottle. It does not prove that a game reached its title screen.

Count the launch cases the self-test ran:

```sh
"$(swift build -c release --show-bin-path)/decant" --self-test 2>/dev/null \
  | grep -c '^ok   launch\|^ok   redact\|^ok   probe'
```

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/decant/` | SwiftUI app, game library, and engine control |
| `engine/` | Wine, DXMT, and Steam install recipe |
| `scripts/` | App bundle and launch scripts |
| `Tests/` | Swift tests and engine tests |
| `docs/` | Launch lifecycle notes, the review guide, and the security and test plan |
| `Resources/` | Fonts, icons, and animation frames |

## Dependencies and credits

The engine scripts derive from [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine), under the MIT license, at base commit `540037e`.

The [engine notice](engine/NOTICE) preserves that credit. [Engine pins](engine/PINS.md) records dependency versions.
