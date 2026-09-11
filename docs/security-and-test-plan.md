# Decant: fixes, security, and demanding program tests

Prepared for Sophia on September 9, 2026. This document describes changes and their limits. It is not a claim of broad game compatibility.

## Review fixes

| Finding | Change | Evidence |
| --- | --- | --- |
| Engine reinstall deleted the launcher | Deployment preserves and refreshes the UI entry point | Repeated deployment in a temporary fixture |
| Shell errors disappeared after process creation | Swift waits for the request command and returns its error | A fake launcher exits with an error that reaches the Swift caller |
| Another bottle or old login log could satisfy readiness | Process checks match the selected prefix; login-log polling was removed | Similar prefix names fail the session check |
| Opening Steam stopped an active session | Normal opens reuse an existing Steam session in the bottle | The active-session fixture never calls session setup |
| Ready state only checked a directory | The doctor checks Wine 11.0, required files, driver exports, and a marker from the DXMT patch | A partial engine fails; the installed engine passes |
| Minimal setup lost its Steam-only purpose | Steam readiness and graphics readiness have separate checks | The minimal fixture permits Steam but rejects game readiness |
| Dependency versions could drift | The DXMT commit is fixed; the driver requires Wine 11.0; a toolchain archive checksum is enforced | Remote commit inspected; archive downloaded and hashed |
| Cached installer validation could be skipped | Read errors now stop the install; both routes validate PE structure | Invalid headers and hash mismatches fail |
| Library reads could hide errors | Read and parse errors now reach the caller | Malformed manifest fixture throws |
| External libraries and quoted names broke parsing | A KeyValues parser handles objects and escaped quotes; drive resolution uses Wine mappings | Nested-key and external-drive fixtures |
| Cleanup reported space that it did not free | Removal errors propagate; the return value counts successful removals | Successful cleanup and failed-removal fixtures |

The pinned DXMT commit is `924a607e3eee06fad5be6f176d8510bb08bc418d`. Its commit message describes the v0.6 window fix.

The local build scripts now use that exact commit. This pass did not rebuild the installed Wine and DXMT binaries.

The driver check establishes expected exports. The DXMT marker establishes the expected patch family. Neither check proves that a particular game renders correctly.

## Security issues

### Changes that reduce risk

- The Swift logger uses an exclusive file lock and atomic append. It rejects a symbolic link at the log filename.
- Dump discovery excludes paths that resolve outside the bottle. Desktop icon updates reject symbolic links and require a matching Steam game ID.
- Both Steam installer paths validate the PE signature and honor the optional SHA-256 pin. The shell download uses a private temporary directory.
- The DXMT source revision and Wine toolchain archive now have fixed content identifiers. Archive downloads no longer leave a partial file at the final filename.
- The driver copy no longer requests administrator access. The runtime belongs in Decant's writable application directory.

The Wine toolchain checksum is `289c7f19e270a3d3d0a6fdb07691b176c70a0795f6811e5255cba82425de4f10`.

GitHub did not publish a digest for that older asset. I calculated this value from the complete archive fetched over HTTPS.

That pin detects later content changes. It is not an independent publisher signature. Existing extracted toolchains still require separate provenance verification.

### Compatibility choices that remain

| Issue | Why it matters | Next validation |
| --- | --- | --- |
| CEF sandbox disabled and single-process mode enabled | A browser fault has less process isolation | Compare one removed flag at a time, including login and store pages |
| Steam receives `-noverifyfiles` | Steam's normal executable verification is reduced to preserve the wrapper | Test wrapper recovery with verification enabled before removing the flag |
| Steam installer hash remains optional | HTTPS and PE structure checks do not prove publisher identity | Maintain a trusted installer digest or add publisher-signature verification |
| Wine exposes host files through its mappings | A bottle is not a sandbox for hostile software | Use trusted software; inspect drive mappings before a new executable test |
| Long-lived runtime logs and crash dumps can grow during a session | Prelaunch cleanup does not impose a continuous disk limit | Measure growth during the long test before selecting a retention policy |

I retained the compatibility flags. Removing them without a game and Steam regression test could restore the original blank-window failures.

The C helper compiled with the existing warning flags. This pass did not execute it under Wine or fuzz Windows argument parsing.

The process runner bounds captured text in memory and imposes a command deadline. Temporary output files can still grow until that deadline.

A timeout stops the direct command. It does not claim to stop every Wine descendant, because those descendants can include an active game.

These limits mean the application is not ready for a claim of sandboxed execution or a complete security audit.

## Performance changes and measurements

Library discovery, engine checks, and dump scans now run outside the UI callback. The main queue receives the result and updates presentation state.

The launcher no longer regenerates an icon for a game with no desktop shortcut. It caches successful icon updates against input file metadata.

Game names convert to lowercase once before the sort. KeyValues parsing replaces repeated regular-expression compilation and supports more of Steam's file format.

The process runner reads only the last 64 KiB of each output file into memory. This avoids unbounded captured strings and inherited-pipe EOF waits.

A debug fixture with 5,000 manifests produced medians of 0.213 seconds before the parser change and 0.203 seconds afterward.

Those samples include process startup and filesystem effects. The small difference is within plausible run variation, so it does not establish a speed gain.

The strongest performance claim is removal of synchronous file scans from the main queue. A rendered UI trace remains necessary to quantify responsiveness.

No game FPS improvement was measured. These changes target launcher behavior and reliability.

The repeatable library benchmark creates isolated fixtures for 1,000 and 5,000 games:

```bash
swift build -c release
python3 -B scripts/benchmark-library.py .build/release/decant
```

This workload measures discovery of many games. It does not stress Wine or the graphics driver.

## What counts as the biggest test

There is no known largest compatible program for this engine. Compatibility is not ordered by download size or graphical detail.

A small game can require an unsupported API. A large D3D11 game can use a graphics path that the engine already handles.

Three different workloads answer different questions:

| Workload | Question |
| --- | --- |
| Thousands of manifest files | Does the launcher remain responsive with a large library? |
| A demanding graphics benchmark | Does the Wine and DXMT path handle sustained GPU work and complex shaders? |
| A large real game with saves and transitions | Do graphics, audio, input, asset loads, and state changes work together? |

The inspected Mac has an Apple M4 with 24 GB of memory and 10 GPU cores. This is a hardware inventory, not a performance rating.

The installed games are Fields of Mistria, Kynseed, and Travellers Rest. None establishes the upper limit of the engine.

## Recommended test sequence

### 1. Establish the existing-game baseline

Run one installed game through the rebuilt Decant app. Use a copied save or a new test save.

Check the path from Play to a visible game window. Check keyboard input and audio. Exit normally and launch again.

Open Steam while the game is active. Confirm that the normal open action preserves the game process.

The automated fixture covers the intended branch. This hardware check verifies that real process detection identifies the installed Steam version correctly.

### 2. Use a controlled graphics workload

[UNIGINE Superposition](https://benchmark.unigine.com/superposition) is a candidate for a demanding Windows graphics test. Compatibility with this particular engine remains unverified.

Use its DirectX mode and confirm D3D11 use in the DXMT diagnostics. An OpenGL run would measure a different graphics path.

Start with 720p Low, then increase to 1080p Medium and High. The publisher defines these presets in its [user manual](https://benchmark.unigine.com/docs/superposition/Superposition_Benchmark_User_Manual.pdf).

The free edition supports single benchmark runs. Timed stress mode and command-line automation belong to paid editions. Repeated manual runs avoid that requirement.

The Windows download is about 1.3 GB, and the publisher lists 5 GB of disk space. No benchmark download or installation occurred in this pass.

A standalone benchmark tests the engine directly. It does not establish that the Decant Steam-library workflow works.

A separate test bottle would keep its installer and settings apart from the current Steam library. It still shares the host and Wine runtime.

### 3. Compare cold and warm runs

Keep the engine revision, program version, resolution, and quality preset fixed. Connect power and disable Low Power Mode for a consistent comparison.

Record the first run separately. Initial shader work and filesystem caches can make it slower.

Run the same scene three more times without changing settings. Compare those results with each other before changing the preset.

Use the same camera route or built-in benchmark every time. Random play sessions create too much variation for a useful comparison.

### 4. Run a longer real-game session

Choose a Windows D3D11 game from the owned library after the baseline passes. A built-in benchmark provides a useful repeatable scene.

A demanding test should include a dense scene, a level transition, and a save followed by reload. Alt-tab and window changes also exercise the Metal view path.

Start with 30 minutes. Inspect memory and disk growth before extending the duration.

DX12-only or Vulkan-only programs do not test the graphics path configured in this recipe. Kernel anti-cheat can introduce a separate compatibility barrier.

### 5. Record evidence, not only average FPS

| Measurement | Meaning |
| --- | --- |
| Time from Play to the first usable frame | User-visible startup cost |
| Average FPS and available frame-time percentiles | Sustained speed and uneven frame delivery |
| Memory pressure, swap, and process memory | Whether the workload exceeds practical memory limits |
| Crashes, freezes, missing graphics, audio faults | Compatibility and stability failures |
| Log and dump growth before and after the session | Whether the runtime creates a disk-growth problem |

Activity Monitor provides process CPU, memory, and system memory pressure. GPU History adds host GPU activity, but it does not provide per-game frame timing.

Use the game's benchmark report when it supplies frame timings. A minimum-FPS value is not the same measurement as a 1% low.

Metal and CPU traces can help isolate a slow stage. Capture them during a separate diagnostic run because instrumentation can change performance.

Suggested acceptance targets are ten successful launches and a 30-minute session with no freeze, visual corruption, or sustained memory growth.

These are proposed test criteria. They are not measured results from this pass.

## Verification commands

```bash
swift test
python3 -B -m unittest discover -s Tests/EngineTests -v
bash scripts/smoke.sh
```

The smoke script now builds current source. The doctor returns a failure exit status when required engine checks fail.

Final results: 18 Swift regression tests, seven shell regression tests, the release build, and the installed-engine doctor all passed.

The release benchmark returned medians of 0.025 seconds for 1,000 games and 0.115 seconds for 5,000 games across five later processes.

These figures measure synthetic manifest discovery, including process startup. They exclude the UI, cover downloads, and actual game startup.

The packaged app resides at [build/decant.app](/Users/sophia/projects/decant/build/decant.app).

The previous deployed recipe was copied to `/private/tmp/decant-engine-before-fixes/` before deployment. That temporary copy is not durable backup storage.
