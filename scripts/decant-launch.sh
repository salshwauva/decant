#!/bin/bash
# decant-launch.sh — the single entry point hearth's ui calls to drive the
# working wine 11 + dxmt stack. all the env the recipe needs is baked in here
# so the swift side just runs "decant-launch.sh steam" or
# "decant-launch.sh play <appid>".
set -o pipefail

SUP="$HOME/Library/Application Support/hearth"
REPO="$SUP/engine/steam-on-m1-wine"

export WINE_APP="$SUP/engines/wine11/Wine Stable.app"
export WINE_BIN="$WINE_APP/Contents/Resources/wine/bin/wine"
export WINESERVER_BIN="$WINE_APP/Contents/Resources/wine/bin/wineserver"
export WINEPREFIX="$SUP/bottles/steam11"
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"

STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/steam.exe"
GAME_OVERRIDES="dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

steam_running() { pgrep -f "steamwebhelper.exe" >/dev/null 2>&1; }

wait_for_login() {
    local i
    for i in $(seq 1 30); do
        grep -q "Logged On" "$STEAM_DIR/logs/connection_log.txt" 2>/dev/null && return 0
        sleep 2
    done
    return 0
}

open_steam() {
    # the notpop launcher handles process cleanup, singleton locks, the
    # webhelper wrapper redeploy, the virtual desktop, and the flag set.
    bash "$REPO/scripts/launch-steam.sh" --detach
}

play_game() {
    local appid="$1"
    if ! steam_running; then
        open_steam
        wait_for_login
        sleep 3
    fi
    WINEDEBUG=-all WINEDLLOVERRIDES="$GAME_OVERRIDES" \
        nohup arch -x86_64 "$WINE_BIN" "$STEAM_EXE" \
        -applaunch "$appid" -force-d3d11-no-singlethreaded -screen-fullscreen 0 \
        >/dev/null 2>&1 &
    echo "launching app $appid"
}

uninstall_game() {
    local appid="$1"
    if ! steam_running; then
        open_steam
        wait_for_login
        sleep 3
    fi
    # steam://uninstall/<appid> opens steam's own uninstall confirmation.
    WINEDEBUG=-all nohup arch -x86_64 "$WINE_BIN" "$STEAM_EXE" \
        "steam://uninstall/$appid" >/dev/null 2>&1 &
    echo "uninstalling app $appid"
}

case "${1:-}" in
    steam)     open_steam ;;
    play)      [ -n "${2:-}" ] || { echo "usage: decant-launch.sh play <appid>" >&2; exit 2; }
               play_game "$2" ;;
    uninstall) [ -n "${2:-}" ] || { echo "usage: decant-launch.sh uninstall <appid>" >&2; exit 2; }
               uninstall_game "$2" ;;
    *)         echo "usage: decant-launch.sh {steam|play <appid>|uninstall <appid>}" >&2; exit 2 ;;
esac
