# decant engine

Wine 11 + DXMT install and launch scripts for the **decant** monorepo.

The SwiftUI app is the front end. This directory is the one-time engine
build: a writable Wine 11, a Steam bottle, the steamwebhelper wrapper,
DXMT, and a winemac.so visibility rebuild so games draw on Metal.

## one-time setup

From the monorepo root (or this directory):

```bash
bash engine/install.sh          # full D3D11 path (~1 hour first run)
# bash engine/install.sh --minimal   # Steam UI only
```

Runtime lands under `~/Library/Application Support/decant/`:

| path | contents |
|------|----------|
| `engines/wine11/` | writable Wine Stable.app + patches |
| `bottles/steam11/` | Wine prefix with Steam |
| `engine/` | deployed copy of these scripts |

Then build the UI:

```bash
./scripts/bundle.sh
open build/decant.app
```

## provenance

Scripts are derived from [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine)
(MIT), base revision `540037e`, with decant path defaults and deploy
behavior. Full third-party list: `NOTICE`.

## what this is not

- Not a fork that reimplements Wine or DXMT.
- Not the old standalone "Steam on M1 Wine.app" dock wrapper; use
  `decant.app` instead (`scripts/09` / `10` are left in-tree for
  reference but are not run by `install.sh`).
