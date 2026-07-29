#!/bin/bash
# decant-launch.sh — entry point the UI calls to drive the wine 11 + dxmt
# stack. all env the engine needs is baked in here so swift only runs
# "decant-launch.sh steam" or "decant-launch.sh play <appid>".
set -euo pipefail

SUP="${DECANT_HOME:-$HOME/Library/Application Support/decant}"
export DECANT_HOME="$SUP"
mkdir -p "$SUP/logs"
LOG="$SUP/logs/decant-launch.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG" >&2; }

# prefer the git tree engine (monorepo) when this script lives there;
# otherwise the deployed copy under Application Support.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/../engine/scripts" ]; then
    REPO="$(cd "$SCRIPT_DIR/../engine" && pwd)"
elif [ -d "$SUP/engine/scripts" ]; then
    REPO="$SUP/engine"
else
    log "error: decant engine not found (looked next to this script and under $SUP/engine)"
    exit 1
fi

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
        if grep -q "Logged On" "$STEAM_DIR/logs/connection_log.txt" 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    log "warn: steam login wait timed out (continuing)"
    return 0
}

open_steam() {
    log "open_steam via $REPO/scripts/launch-steam.sh"
    bash "$REPO/scripts/launch-steam.sh" --detach
}

play_game() {
    local appid="$1"
    log "play_game appid=$appid"
    if [ ! -x "$WINE_BIN" ]; then
        log "error: wine missing at $WINE_BIN"
        exit 1
    fi
    if [ ! -f "$STEAM_EXE" ]; then
        log "error: steam.exe missing at $STEAM_EXE"
        exit 1
    fi
    if ! steam_running; then
        open_steam
        wait_for_login
        sleep 3
    fi
    WINEDEBUG=-all WINEDLLOVERRIDES="$GAME_OVERRIDES" \
        nohup arch -x86_64 "$WINE_BIN" "$STEAM_EXE" \
        -applaunch "$appid" -force-d3d11-no-singlethreaded -screen-fullscreen 0 \
        >>"$LOG" 2>&1 &
    log "launching app $appid"
    echo "launching app $appid"
}

uninstall_game() {
    local appid="$1"
    log "uninstall_game appid=$appid"
    if ! steam_running; then
        open_steam
        wait_for_login
        sleep 3
    fi
    WINEDEBUG=-all nohup arch -x86_64 "$WINE_BIN" "$STEAM_EXE" \
        "steam://uninstall/$appid" >>"$LOG" 2>&1 &
    log "uninstalling app $appid"
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
