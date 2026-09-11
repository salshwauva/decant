# Decant: code review and interview guide

Reviewed September 9, 2026, at repository revision `bbb4e07`.

This document records the original review. The subsequent fixes and remaining limits appear in [the security and test plan](/Users/sophia/projects/decant/docs/security-and-test-plan.md).

This guide explains the code for Sophia to study. It does not attribute authorship of imported work to her.

## Overall assessment

Decant is a native macOS launcher with a local compatibility engine. Its strongest engineering work concerns the boundaries between applications, operating systems, and graphics libraries.

The repository assembles Wine, DXMT, and Windows Steam into a runtime that the SwiftUI application controls. Rosetta translates the x86 instructions in that runtime.

There is no application server, HTTP API, or database in this repository. The back end consists of Swift services, shell scripts, and a Windows helper executable.

The code supports a credible interview discussion about process control, dependency compatibility, diagnostics, and native application design. Reliability needs more work before broad distribution.

| Review area | Assessment | Main evidence |
| --- | --- | --- |
| Correctness | Needs work | Launch requests can appear successful after the shell fails. Readiness checks prove very little. |
| Security | Needs hardening | DXMT release checksum exists, but other inputs lack equivalent verification. CEF isolation and Steam verification are disabled. |
| Performance | Suitable for a small library, with clear limits | Simple scans and a lazy grid help. File scans and icon work execute in UI callbacks. |
| Maintainability | Reasonable separation, inconsistent contracts | Small service types and shared shell helpers help. Paths, setup behavior, and documentation diverge. |

### What I verified

- A fresh debug build passed with Apple Swift 6.3.3. It produced no compiler warnings in this run.
- All 14 checks in the current self-test passed. The doctor command found the local Wine executable, bottle, and launcher script.
- All 21 shell files passed Bash syntax checks.
- Temporary fixtures reproduced deletion of the deployed launcher during the installer copy, and acceptance of an old login record.
- I did not launch a game, rebuild Wine or DXMT, run the C wrapper, or perform a visual accessibility audit.

The first build attempt encountered sandbox restrictions on compiler caches. The approved build then passed. This was an environment restriction, not a source failure.

## Review findings, in priority order

### 1. P1: an engine reinstall removes the UI launcher

Source: [engine/install.sh:93](/Users/sophia/projects/decant/engine/install.sh:93).

The installer copies `engine/` into the deployed engine directory with `rsync --delete`. The deployed directory also contains `decant-launch.sh`.

That launcher originates from the repository's top-level `scripts/` directory. It does not exist in the installer's source directory, so the copy deletes it.

Trigger: a user builds the app, then reruns the engine installer. The existing app loses the script that handles every launch request.

The installer tells users to build the UI afterward, which restores the script. However, an engine repair should not require an unrelated UI rebuild.

An isolated reproduction with temporary source and destination directories confirmed this behavior.

Improvement: give one deployment step ownership of the complete runtime recipe, including the launcher. Verify that all required entry points exist afterward.

### 2. P1: the UI cannot report failures after the shell starts

Sources: [Engine.swift:175](/Users/sophia/projects/decant/Sources/decant/Engine.swift:175), [SteamManager.swift:104](/Users/sophia/projects/decant/Sources/decant/SteamManager.swift:104), [ContentView.swift:315](/Users/sophia/projects/decant/Sources/decant/ContentView.swift:315).

`spawn` returns a process identifier immediately after `Process.run()`. That proves Bash started. It does not prove the script completed or the game opened.

For example, the shell can exit because Steam is missing. Swift already returned success, so the error banner never receives that failure.

The UI clears its launch indicator after six seconds. This timer has no connection to Steam login, process health, or a visible game window.

Improvement: retain the launch process and observe its exit. Add an explicit acknowledgement for completion of launcher preparation.

Keep distinct states for request accepted, Steam ready, game launch requested, and failure. Only claim a running game when a separate observation supports that claim.

The shell also detaches Wine, so observing Bash alone cannot establish game health. This distinction matters in an interview.

### 3. P2: session checks can accept another bottle or an old login

Source: [scripts/decant-launch.sh:35](/Users/sophia/projects/decant/scripts/decant-launch.sh:35).

`steam_running` searches the whole machine for `steamwebhelper.exe`. A helper from another Wine prefix can cause Decant to skip its own Steam setup.

`wait_for_login` searches the complete connection log for any `Logged On` entry. A record from an earlier session satisfies the check.

A temporary log containing an old login followed by logout returned success immediately. No active Steam session existed in that fixture.

The function also reports success after its 60-second timeout. It therefore provides neither a reliable readiness signal nor a failure signal.

Improvement: scope process checks to the configured prefix. Inspect evidence from the current session and return a distinct timeout result.

The lower-level cleanup script already scopes its primary stop command through `WINEPREFIX`. Apply the same discipline to session detection.

### 4. P2: the ready state does not establish that the engine can launch

Source: [Engine.swift:98](/Users/sophia/projects/decant/Sources/decant/Engine.swift:98).

The ready state requires an executable at the Wine path and a `drive_c/windows/system32` directory. It does not require Steam, DXMT, or the patched driver.

A minimal install, partial install, or fresh Wine prefix can therefore receive a green ready indicator.

The doctor command checks the launcher file separately, but always exits successfully through the CLI path. It functions as a report, not a deployment gate.

Improvement: validate required artifacts and their versions. Separate basic Wine readiness from Steam readiness and D3D11 readiness.

### 5. P2: the documented dependency pins do not guarantee a matching build

Sources: [01-install-wine.sh:27](/Users/sophia/projects/decant/engine/scripts/01-install-wine.sh:27), [07-build-dxmt-fork.sh:131](/Users/sophia/projects/decant/engine/scripts/07-build-dxmt-fork.sh:131), [08-patch-wine-visibility.sh:25](/Users/sophia/projects/decant/engine/scripts/08-patch-wine-visibility.sh:25).

The Wine installer accepts the current `wine-stable` cask or an existing installation. Its version check only requires output that starts with `wine-`.

The driver build defaults to Wine 11.0 source. A different installed Wine version can therefore receive a driver from 11.0.

The DXMT build follows a mutable branch unless the caller supplies `DXMT_FORK_SHA`. Existing local edits can also remain in the build.

These choices weaken reproducibility at an ABI boundary where version mismatches already caused failures.

Improvement: require a matching Wine version and fixed DXMT commit. Record the build inputs and artifact hashes with each engine installation.

## Languages and tools

| Language or format | Role in this repository | Why it fits |
| --- | --- | --- |
| Swift | App entry point, UI, engine services, Steam metadata, logs, file maintenance | Native framework access and typed state |
| Bash and POSIX shell | Dependency installation, compiler invocation, runtime deployment, Wine launch | Direct control of external programs and environment variables |
| C | The Windows `steamwebhelper.exe` wrapper | Small executable with direct Win32 API access |
| Python | Short embedded scripts for registry edits and path calculation | Clearer text transformations than complex shell substitutions |
| XML plist, registry files, Makefile | App metadata, Wine configuration, wrapper build | Configuration and build formats, not additional application services |

SwiftUI and AppKit are frameworks. Wine and DXMT are external runtime components. LLVM, Meson, Ninja, and MinGW are build tools.

The Swift package declares tools version 5.9 and macOS 13 as its minimum platform. A newer compiler can still build the package in Swift 5 language mode.

The package contains one executable target and no declared third-party Swift package dependencies. There is no separate Swift test target.

DXMT and Wine contain substantial native code outside this repository. Do not describe their internal algorithms as algorithms implemented in Decant.

## The engine, from installation to a game window

### The three compatibility responsibilities

Rosetta translates x86 instructions for Apple Silicon. Wine supplies the Windows API environment and loads Windows programs.

DXMT supplies a Metal implementation of Direct3D 10 and 11. This scope also appears in the [upstream DXMT repository](https://github.com/3Shain/dxmt).

These components address different problems. A Windows program can execute instructions correctly while its graphics initialization still fails.

Decant's engine is the installation and launch recipe that makes those components cooperate.

### Installation is a sequence with dependencies

Source: [engine/install.sh](/Users/sophia/projects/decant/engine/install.sh).

The installer represents its steps as arrays of script paths. It executes them sequentially because later steps require earlier outputs.

The first group checks prerequisites, copies Wine into Decant's home, creates the Wine prefix, installs Steam, and deploys the helper wrapper.

It also stages a checksum-verified DXMT release and copies supporting fonts and certificates.

The full path then builds the DXMT fork and rebuilds Wine's macOS driver. The minimal path stops before these long builds.

The DXMT release is an intermediate setup state. It is not an automatic runtime fallback after a failed full build.

The scripts use file markers to skip work. Examples include an existing LLVM static library and a driver with at least 100 public symbols.

These checks reduce repeat work. However, they prove less than a complete, compatible installation. A file can exist after a partial build.

The intended rerun behavior resembles idempotence: repeating a step should preserve a usable result. Current deployment and mutable inputs prevent that guarantee across the whole installer.

### What a Wine bottle stores

The default bottle is a directory under `Application Support/decant/bottles/steam11`.

It holds a Windows-style filesystem, registry files, Steam, and game data. `WINEPREFIX` directs Wine to that directory.

This is configuration and filesystem separation. It is not a security sandbox for an untrusted Windows executable.

One shared bottle simplifies discovery and Steam login. It also shares registry changes and compatibility overrides across games.

The Swift API accepts bottle and engine parameters, but launch methods do not forward them. The shell selects the default Wine and `steam11` paths.

This is consistent with today's single-bottle product, but the API suggests broader support than it delivers. A future multi-bottle design must fix that contract.

### The launch path

1. `ContentView.play` requires the basic engine state and sets the selected game's launch indicator.
2. `SteamManager.launchGame` validates the app ID, checks crash dumps, and locates the launcher script.
3. `EngineManager.spawn` starts Bash with an argument array and directs output to a log.
4. `decant-launch.sh` selects the Wine runtime and bottle, prepares Steam when necessary, and sends `-applaunch` with the app ID.
5. Wine runs the Windows programs under Rosetta. Game Direct3D calls reach DXMT, which uses Metal.

The shell passes `-force-d3d11-no-singlethreaded` and `-screen-fullscreen 0` for every game. These are game-specific conventions, not universal Steam guarantees.

Per-game compatibility settings would be a reasonable extension after the current launch contract becomes reliable.

### Steam session preparation

Source: [launch-steam.sh](/Users/sophia/projects/decant/engine/scripts/launch-steam.sh).

The script stops the current bottle's Wine session, removes stale Chromium locks, and checks whether Steam replaced the helper wrapper.

It also edits compatibility settings and launches Steam within a Wine virtual desktop. That desktop contains related Windows windows inside one host window.

The primary cleanup uses `wineserver -k` with the bottle's prefix. This protects unrelated prefixes from that command.

The residual cleanup uses a substring match against a process environment. Similar prefix names can still match. Exact identity would strengthen this boundary.

Opening Steam always reaches the session-reset path. The UI's add-game action can therefore stop a game already active in the same bottle.

A normal open action should reuse a healthy session. Session repair should be a separate operation with a clear effect.

### The C wrapper is a process adapter

Source: [steamwebhelper-wrapper.c](/Users/sophia/projects/decant/engine/wrapper/src/steamwebhelper-wrapper.c).

Steam launches its web helper by filename. The installer puts Decant's wrapper at that filename and retains Valve's helper as `steamwebhelper_real.exe`.

The wrapper finds its own path, locates the real helper beside it, and reads the original command line.

It adds `--disable-gpu --single-process`, calls `CreateProcessW`, waits for the child, and returns the child's exit code.

Wide-character strings support Unicode paths. Dynamic allocation sizes the final command line from the inputs. The normal path frees allocations and closes process handles.

The original argument tail remains intact. That avoids reparsing and reconstructing every Chromium argument.

The first-token scanner remains simple: it recognizes quotes and spaces, but not the full range of Windows command-line edge cases.

The path buffer also retains the `MAX_PATH` limit. These are useful candidates for wrapper tests.

The wrapper changes Steam's browser behavior. It does not disable DXMT for games. The game processes still receive the graphics DLL overrides.

### Why the Wine and DXMT patches matter

Source: [dxmt-diagnosis.md:201](/Users/sophia/projects/decant/engine/docs/dxmt-diagnosis.md:201).

The repository's imported diagnosis records three separate failures. I reviewed the diagnosis and local build scripts, but could not inspect the external fork source.

**Symbol visibility:** DXMT uses `dlsym` to locate functions in Wine's macOS driver. Hidden functions cannot be found through that lookup.

The local recipe rebuilds `winemac.so` with `-fvisibility=default`. It then replaces that driver in Decant's Wine copy.

An ABI is the binary contract between separately compiled components. Symbol names and structure layouts form part of that contract.

**Structure layout and timing:** the diagnosis describes DXMT reading Wine's internal window structure. Wine 11 changed that structure.

Even a corrected field reference remained unavailable before the first GDI presentation. This combines a layout problem with an object-lifecycle problem.

The documented fork uses Wine's window accessor and the Cocoa window's content view. This reduces dependence on private structure offsets.

The accessor is still a Wine driver dependency. Calling it an accessor does not guarantee a permanent public ABI.

**Main-thread deadlock:** Cocoa work requires the main thread, but some Wine helper functions already dispatch there and wait.

The documented failure adds another synchronous dispatch around those helpers. The main thread waits for work that also needs the main thread.

The documented fix lets Wine's helpers manage their own dispatch. It separately dispatches only the direct Cocoa operation that needs it.

This is strong interview material about thread ownership and re-entrancy. It explains why adding another main-thread wrapper can make a program less correct.

## Front-end design and implementation

### State owns the presentation

`ContentView` stores the engine state, game array, selected game, launch app ID, and banner state with `@State`.

SwiftUI derives the visible interface from those values. Selecting a game presents a detail sheet. Changing the launch app ID changes the cover and button state.

`Game` conforms to `Identifiable` with its Steam app ID. Stable identity lets SwiftUI associate each row with the correct game across refreshes.

The detail view receives values and action closures. It does not execute Wine itself. This keeps that component reusable and easier to reason about.

The main view still owns action coordination. There is no separate observable application model, so describing the current design as full MVVM would overstate it.

### Layout choices

The library uses four fixed-width columns inside `LazyVGrid`. A geometry preference reports the content height to the parent.

The parent caps the shelf at 560 points and enables vertical scrolling. The window sizes itself to its content.

This produces a stable small-library layout. Fixed widths, small text, and a content-sized window limit adaptation to narrow screens and larger text needs.

These are code-level tradeoffs. I did not inspect the rendered interface or measure text contrast during this review.

### Shared components

`Theme.swift` centralizes colors, fonts, bevels, and button behavior. `ViewModifier` and `ButtonStyle` reuse presentation without a deep inheritance hierarchy.

`AsyncImage` requests Steam cover art. It substitutes a game initial when the image is unavailable.

The pour animation preloads up to 60 frames. A timer advances the array index every 0.1 seconds and uses modulo to wrap around.

Preload avoids repeated file reads during the animation. Its cost is memory for the decoded images.

AppKit supplies Finder icon changes and bitmap drawing. CoreText registers the bundled fonts before the UI needs them.

### Front-end improvements

- Move manifest and dump scans out of the UI callback. Keep published UI state on the main actor.
- Skip icon generation when no shortcut exists. Cache icon results and update only changed shortcuts.
- Replace the six-second launch timer with observed operation states.
- Add explicit accessible labels and keyboard actions where symbolic controls need them. Verify VoiceOver and reduced motion.
- Preserve the distinction between unavailable data and an empty library. Current `try?` paths often hide read failures.

## Back-end data structures and algorithms

### Game discovery

Source: [SteamManager.swift:140](/Users/sophia/projects/decant/Sources/decant/SteamManager.swift:140).

Steam's manifest files provide the installed app ID and name. The launcher scans the default library and paths from `libraryfolders.vdf`.

It uses a set to reject duplicate app IDs, filters support packages, appends accepted games to an array, and sorts by name.

Let B be the total manifest bytes read, N the directory entries inspected, and G the accepted games.

The expected work is approximately O(B + N + G log G), excluding string comparison length. The set uses O(G) additional space.

The file reads and regex extraction dominate small libraries. The sort becomes more visible with many games.

This code does not fetch every owned game from a Steam account. It lists local manifest entries and does not check manifest install-completion flags.

### Data structure map

| Structure | Concrete use | Tradeoff |
| --- | --- | --- |
| `[Game]` | Ordered library and SwiftUI iteration | Simple traversal; sorting costs O(G log G) comparisons |
| `Set<String>` | App ID deduplication and known support IDs | Expected constant-time membership; requires extra memory |
| `[String: String]` | Process environment overrides | Direct key replacement; duplicated sources can disagree |
| Enums with associated values | `EngineStatus` and `DecantError` | Carry state-specific data and support exhaustive switches |
| Structs | `Game`, `RunResult`, `DumpReport`, `Engine` | Small value models with explicit fields |
| `[NSImage]` | Animation frames | Constant-time indexing; memory grows with decoded image pixels |
| Tuples and arrays | Setup instructions, icon accents, script stages | Compact fixed records and explicit order |

### Parsing tradeoff

`vdfValues` uses a regular expression to extract quoted key-value pairs. It does not construct Valve's nested KeyValues tree.

That is compact for controlled fields, but escaped quotes can truncate values. Repeated keys in different sections also lack context.

Additional library paths map drive letters to `drive_c`, `drive_d`, and similar directories. Wine commonly maps other drives through `dosdevices` links.

External library support therefore needs real drive resolution. A small KeyValues parser plus Wine-aware path resolution would address both boundaries.

The support filter also rejects any title containing `proton` or `directx`. A real game with such a name can disappear.

Known app IDs provide a safer primary filter. Treat broad name matches as uncertain metadata.

### Other algorithms

| Algorithm | Location | Cost and meaning |
| --- | --- | --- |
| Recursive file enumeration and sum | `Housekeeping.dirSize` | O(F) metadata visits for F files; it does not read every dump byte |
| Regex extraction | `SteamManager.vdfValues` | Scans text for each requested key; no structural parse |
| SHA-256 | Steam installer validation and DXMT archive verification | O(B) byte processing; compares content against an expected digest |
| Hex-run scan | `GameIcon.firstSHA1` | Linear scan with a bounded 40-character candidate; extracts an existing hash string |
| Scalar sum modulo 360 | Fallback icon color | Linear in app ID length; deterministic with frequent collisions |
| Nearest-neighbor image resize | `GameIcon.crisp` | Work grows with output pixels; preserves hard pixel edges |
| Quote-state scan | C wrapper `args_tail` | Linear in the executable token length |
| Bounded polling | `wait_for_login` | Up to 30 checks, with two-second sleeps |

The icon color function is not a cryptographic hash. `firstSHA1` does not calculate SHA-1. It recognizes text already present in a shortcut.

No custom graph search, balanced tree, or machine-learning algorithm appears in the launcher. Ordinary algorithms suit its workload.

### Process output and concurrency

`EngineManager.run` creates separate stdout and stderr pipes. Two background tasks drain those pipes while the parent waits for the child.

This addresses a real deadlock: a child can block on a full pipe while the parent waits for that child to exit.

A dispatch group joins the reader tasks before the method returns their output. This is a useful example of coordinating independent I/O streams.

The method still waits synchronously and has no timeout or cancellation. It also stores all captured output in memory.

A descendant that retains a pipe's write handle can delay EOF after the direct child exits. Large output can consume substantial memory.

For long tasks, stream bounded output to logs and add a defined cancellation policy. Review captured mutable state before a Swift 6 strict-concurrency migration.

## Fallbacks and their costs

| Mechanism | Current behavior | Cost or limit |
| --- | --- | --- |
| Missing cover art | Show the game's initial | Shelf remains usable offline; no durable cover cache is defined here |
| Missing official icon | Generate a themed icon | More bitmap work, currently repeated on refresh |
| Missing logo or pour frames | Draw a seal, or omit the animation | Useful graceful degradation |
| Display-size detection fails | Use 1440 by 900 | May fit some displays poorly |
| Wrapper replaced by Steam | Detect a hash difference and redeploy | Depends on a build toolchain and a size-based binary classification |
| Targeted Wine driver build fails | Attempt a full Wine build | More time and disk use |
| Newer Meson detected | Install 1.10.1 with `pip --user` | Depends on the host Python configuration; this is not an isolated environment |
| Native graphics DLL unavailable | `n,b` permits Wine builtin lookup | Loader fallback does not prove equivalent game compatibility |
| Steam login wait expires | Continue and return success | Masks readiness failures |
| Some metadata or cleanup operations fail | Skip through `try?` or `|| true` | Can hide faults that deserve a visible warning |

Fallbacks should preserve an explicit guarantee. Missing artwork can safely preserve launch functionality. Missing login readiness cannot safely preserve a claim of readiness.

## Additional improvement areas

### Report actual cleanup results

`trimDumps` ignores each removal error, then returns the original total. The UI can report freed space even when deletion failed.

Return confirmed removal results and remaining bytes. The current cap is a prelaunch threshold, so an active crash loop can exceed it between launches.

### Treat downloaded code consistently

The DXMT release has a required default SHA-256 digest. Steam's Swift installer supports an optional digest, but otherwise checks only an MZ header.

An MZ header identifies a possible executable format. It does not authenticate the publisher or validate the complete PE structure.

The shell Steam installer does not enforce the Swift digest setting. The Wine toolchain archive also lacks a checksum check in its download path.

Use one documented verification policy across installation routes. Do not describe MD5 wrapper comparison as a security guarantee; it is a local change detector.

CEF runs with reduced process isolation, and Steam receives `-noverifyfiles`. These compatibility decisions deserve an explicit threat model before wider distribution.

### Make logs reliable under concurrent writers

The Swift logger opens a file and seeks to its end before each write. Spawned processes receive separate file handles.

Those handles do not use a shared atomic append protocol. Writes can race, and log rotation does not retarget handles that children already inherited.

The shell also writes separate logs with different retention behavior. `decant-launch.log` has no size cap in the reviewed script.

Centralize append and retention behavior. Preserve enough history to explain a failure across all launch stages.

### Strengthen verification

The existing self-test is a useful quick check, but it covers mostly small examples and path shapes.

The smoke script can reuse an existing app bundle without rebuilding current source. Its cleanup check searches source text, including comments.

High-value tests would cover launch failure propagation, deployment preservation, VDF escapes and external drives, and wrapper installation states.

A separate manual engine check should verify a visible rendered game frame on the intended hardware. A successful Swift build cannot establish graphics compatibility.

### Keep documentation aligned with executable behavior

Some architecture notes still describe older prefix paths, different CEF flags, and corefonts as a normal install step. Corefonts are currently opt-in.

The GUI guide mentions Meson 1.10.2 in a virtual environment. The script selects 1.10.1 through `pip --user` when it detects a newer version.

Use the scripts as evidence for current behavior. Keep historical diagnosis separate from the current operator guide.

## What the project does well

- **It delegates account and download functions to Steam.** Decant avoids a second login system and a duplicate source of library truth.
- **It exposes a small process boundary.** Swift passes explicit arguments to a shell entry point that owns compatibility setup.
- **It preserves repair evidence.** Logs, CLI diagnostics, driver backups, and detailed diagnosis notes support investigation.
- **It applies native UI composition.** Small views, value models, shared styles, and callbacks keep the interface understandable.
- **It recognizes compatibility as a layered problem.** Instruction translation, Windows APIs, browser behavior, and graphics setup receive separate treatment.

## How to discuss it in interviews

### Describe the project accurately

Present Decant as a native macOS game launcher that packages and controls a Wine and DXMT compatibility stack.

Explain that its local back end manages runtime setup, installed-game discovery, process launch, and maintenance.

The ownership boundary matters. [engine/NOTICE](/Users/sophia/projects/decant/engine/NOTICE) attributes the imported recipe to `notpop/steam-on-m1-wine` at `540037e`.

It lists local changes such as Decant paths, writable Wine deployment, recipe deployment, and prefix-scoped cleanup.

The graphics patch lives in an external DXMT fork. The repository alone does not establish who authored each diagnosis or patch.

Use your contribution history to state what you personally designed, adapted, diagnosed, and validated. Treat imported fixes as dependencies you understand.

### Five useful interview topics

| Likely question | Points to explain |
| --- | --- |
| What happens after Play? | Follow the UI, Swift service, shell entry point, Steam request, Wine, and DXMT boundary. Distinguish request acceptance from success. |
| What was technically difficult? | Explain symbol lookup, ABI drift, and the documented main-thread deadlock. State your actual contribution to that work. |
| Why use these technologies? | Swift for native state and UI; shell for external tools; C for a Windows-compatible process adapter. |
| Which data structures matter? | Array for ordered presentation, set for deduplication, dictionary for environment variables, enums for states and errors. |
| What would you change first? | Repair deployment, observe launch results, and verify engine capabilities. Connect each change to a concrete user failure. |

### Questions to rehearse aloud

- Why can a child process start successfully while the requested operation fails?
- Why does a private structure layout create a different compatibility risk from a function call?
- Why can a second synchronous main-thread dispatch cause deadlock?
- What does a Wine prefix isolate, and what does it leave shared with the host?
- Which project decisions did you make yourself, and what evidence demonstrates their effect?

Start with the complete Play path. Then explain one failure and its proposed correction without relying on the source code in front of you.
