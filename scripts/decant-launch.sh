#!/bin/bash
# decant-launch.sh — entry point the UI calls to drive the wine 11 + dxmt
# stack. all env the engine needs is baked in here so swift only runs
# "decant-launch.sh steam" or "decant-launch.sh play <appid>".
set -euo pipefail

SUP="${DECANT_HOME:-$HOME/Library/Application Support/decant}"
export DECANT_HOME="$SUP"
# no wine virtual desktop by default: under the current steam client its login
# window lands off-screen and steam never signs in. set WINE_VIRTUAL_DESKTOP
# (a WxH size, or "auto") to bring it back.
export WINE_VIRTUAL_DESKTOP="${WINE_VIRTUAL_DESKTOP-}"
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

source "$REPO/scripts/lib/common.sh"

STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/steam.exe"
GAME_OVERRIDES="dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

open_steam() {
    if prefix_steam_running; then
        log "steam session already exists in this bottle"
    else
        bash "$REPO/scripts/launch-steam.sh" --detach
    fi
}

send_request() {
    require_wine_installed
    [[ -f "$STEAM_EXE" ]] || die "steam.exe missing at $STEAM_EXE"
    open_steam
    # Steam owns login and offline mode. Historical logs cannot prove readiness.
    WINEDLLOVERRIDES="$GAME_OVERRIDES" wine_run "$STEAM_EXE" "$@" >>"$LOG" 2>&1 \
        || { log "steam request failed; see $LOG"; return 1; }
    log "steam request command completed"
}

validate_appid() {
    [[ "$1" =~ ^[0-9]+$ ]] || die "invalid steam app id"
}

# exit status when a game already runs in this bottle. the running app id goes
# to stdout for the caller; nothing is started or stopped.
EXIT_GAME_RUNNING=3

play_game() {
    validate_appid "$1"
    local running
    running="$(prefix_running_appid)"
    if [ -n "$running" ]; then
        log "a game is already running from decant (app $running)"
        echo "$running"
        exit "$EXIT_GAME_RUNNING"
    fi
    send_request -applaunch "$1" -force-d3d11-no-singlethreaded -screen-fullscreen 0
}

uninstall_game() {
    validate_appid "$1"
    send_request "steam://uninstall/$1"
}

case "${1:-}" in
    steam)     send_request ;;
    play)      [ -n "${2:-}" ] || { echo "usage: decant-launch.sh play <appid>" >&2; exit 2; }
               play_game "$2" ;;
    uninstall) [ -n "${2:-}" ] || { echo "usage: decant-launch.sh uninstall <appid>" >&2; exit 2; }
               uninstall_game "$2" ;;
    *)         echo "usage: decant-launch.sh {steam|play <appid>|uninstall <appid>}" >&2; exit 2 ;;
esac
