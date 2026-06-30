# hearth

a cozy launcher for windows-only steam games on apple silicon. it installs
and launches the games you already own, wrapped in a warm pixel ui.

hearth does not emulate anything. the hard work (running x86-64, the windows
api, directx) is done by tools that already exist:

- rosetta 2 translates the x86-64 instructions (built into macos)
- wine provides the windows api and loads the program
- apple's game porting toolkit (d3dmetal) turns directx into metal

hearth drives that stack: it sets up a bottle, installs windows steam into
it, finds the games you own, and launches them. think of it as your own
cozy front end over the same engine whisky and crossover use.

this is the opposite end from wisp. wisp emulates a cpu from scratch to run a
toy program. hearth leans on mature engines to run real games. different
goals, same household.

## scope and honesty

works: single-player and many online titles run through this stack.

does not work, ever, on macos: games with kernel level anti cheat (a lot of
competitive multiplayer). no launcher can change that.

first target: fields of mistria. cozy, 2d, single player, no anti cheat.

## build

needs the swift toolchain from the command line tools. no full xcode project.

    ./scripts/bundle.sh        # builds build/hearth.app
    open build/hearth.app

## roadmap

- phase 0: cozy swiftui shell (done)
- phase 1: engine manager, set up wine + game porting toolkit, create a bottle
- phase 2: install windows steam, scan the library, find owned games
- phase 3: launch a game by its steam app id
- phase 4: the full cozy library ui
