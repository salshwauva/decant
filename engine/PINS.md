# engine pins

record the exact versions this monorepo expects. bump deliberately after
an end-to-end game test.

| component | pin | notes |
|-----------|-----|--------|
| recipe base | `notpop/steam-on-m1-wine@540037e` | imported into `engine/` |
| Wine cask / app | **wine-stable 11.0** (Gcenx) | installed via brew, copied with `cp -RX` into `engines/wine11/` |
| Wine source (winemac rebuild) | tag **`wine-11.0`** | `WINE_BUILD_BRANCH` in `08-patch-wine-visibility.sh` |
| DXMT release tarball | **v0.74** | `04-install-dxmt.sh` |
| DXMT tarball SHA256 | `2598981a8b725653773e277470a95dda4253b8a14d36e0dc96dce0e3800f0ceb` | enforced in `04-install-dxmt.sh` |
| DXMT fork (full D3D11 path) | branch `debug/present-path-tracing` on `notpop/dxmt` | set `DXMT_FORK_SHA=<40-char>` for a fixed commit |
| LLVM (DXMT build) | tag **`llvmorg-15.0.7`** | `07-build-dxmt-fork.sh` |
| meson (DXMT build) | **1.10.x** (script pins 1.10.1 if host is 1.11+) | |
| SteamSetup.exe | MZ header required; optional env `DECANT_STEAMSETUP_SHA256` | app-side in `SteamManager` |

## after a known-good full install

```bash
# record the dxmt fork commit that rendered your titles
git -C "${DXMT_SRC:-$HOME/dev/dxmt}" rev-parse HEAD
# then either export for the next build:
#   export DXMT_FORK_SHA=<that-sha>
# or write it into this file under the DXMT fork row.
```

## wine binary check

```bash
arch -x86_64 "$HOME/Library/Application Support/decant/engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine" --version
# expect: wine-11.0
```
