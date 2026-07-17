# decant

a cozy launcher for windows-only steam games on apple silicon. it installs
and launches the games you already own, wrapped in a warm pixel ui.

decant does not emulate anything. the hard work (running x86-64, the windows
api, directx) is done by tools that already exist:

- rosetta 2 translates the x86-64 instructions (built into macos)
- wine provides the windows api and loads the program
- dxmt turns the game's directx calls into metal

the catch on macos 26: the off-the-shelf versions of this stack (game
porting toolkit, whisky, crossover, mythic) all fell over. so decant runs on
a home-built engine: wine 11 with a rebuilt winemac driver and the dxmt
fork's dlls, kept in `~/Library/Application Support/hearth`. that engine is a
one-time setup done by hand; the app just detects and drives it.

decant drives that stack: it sets up a bottle (an isolated windows world),
installs windows steam into it, finds the games you own, and launches them.
think of it as a cozy front end over your own wine engine, the same kind of
engine whisky and crossover wrap.

this is the opposite end from wisp. wisp emulates a cpu from scratch to run a
toy program. decant leans on mature engines to run real games. different
goals, same household.

## scope and honesty

works: single-player and many online titles run through this stack.

does not work, ever, on macos: games with kernel level anti cheat (a lot of
competitive multiplayer). no launcher can change that.

confirmed running: fields of mistria, kynseed, travellers rest. cozy, 2d,
single player, no anti cheat.

## build

needs the swift toolchain from the command line tools. no full xcode project.

    ./scripts/bundle.sh        # builds build/decant.app
    open build/decant.app

the app assumes the wine 11 + dxmt engine is already set up in
`~/Library/Application Support/hearth`. if it is missing, decant reports the
engine as not ready rather than trying to build it. setting up that engine is
a separate, one-time job, based on the recipe at
github.com/notpop/steam-on-m1-wine plus a rebuilt winemac driver and the dxmt
fork.

## status

- cozy pixel swiftui library ui (done)
- engine manager: detect the wine 11 + dxmt engine and its bottle (done)
- install windows steam, scan the library, find owned games (done)
- launch a game by its steam app id, with the directx-to-metal env (done)
- add and uninstall games through steam, themed desktop game icons, and a
  pour-on-launch animation (done)
