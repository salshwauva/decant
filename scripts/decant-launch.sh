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
CONNECTION_LOG="$STEAM_DIR/logs/connection_log.txt"
CONSOLE_LOG="$STEAM_DIR/logs/console_log.txt"
GAME_OVERRIDES="dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"

open_steam() {
    if prefix_steam_running; then
        log "steam session already exists in this bottle"
    else
        bash "$REPO/scripts/launch-steam.sh" --detach
    fi
}

require_steam() {
    require_wine_installed
    [[ -f "$STEAM_EXE" ]] || die "steam.exe missing at $STEAM_EXE"
}

# runs steam.exe in the bottle. against a live steam it only forwards the
# request; its exit status is not reliable evidence of what steam did with it.
steam_exe() {
    WINEDLLOVERRIDES="$GAME_OVERRIDES" wine_run "$STEAM_EXE" "$@" >>"$LOG" 2>&1
}

send_request() {
    require_steam
    open_steam
    # Steam owns login and offline mode. Historical logs cannot prove readiness.
    steam_exe "$@" || { log "steam request failed; see $LOG"; return 1; }
    log "steam request command completed"
}

# a cold steam signs in 30 s to 2 min after it starts, and a request sent
# before that is dropped. so play waits for a new sign-in (or an existing one)
# and then for the game process. both waits poll once a second; the swift
# caller allows 300 s for play.
LOGON_WAIT=150
START_WAIT=60

# size of a steam log in bytes, 0 while the file does not exist yet.
log_offset() {
    local size
    size=$(wc -c 2>/dev/null <"$1") || size=0
    echo $(( size ))
}

# how many lines matching $3 steam appended to log $1 after byte offset $2.
# a log that shrank was rotated, so it is read whole. only counts leave here,
# the lines carry account ids.
new_matches() {
    local from=$2 count
    (( $(log_offset "$1") >= from )) || from=0
    count=$(tail -c +$(( from + 1 )) "$1" 2>/dev/null | grep -ac -- "$3") || true
    echo "${count:-0}"
}

# true when the last connection state steam logged is Logged On.
steam_logged_on() {
    local state
    state=$(tail -c 65536 "$CONNECTION_LOG" 2>/dev/null \
        | grep -aoE '^\[[0-9: -]+\] \[(Connecting|Connected|Logging On|Logged On|Logged Off),' \
        | tail -1) || true
    [[ "$state" == *"[Logged On," ]]
}

# waits for a new sign-in after connection log offset $1.
wait_signed_in() {
    local i from=$1 restarted=0
    for (( i = 0; i < LOGON_WAIT; i++ )); do
        if ! prefix_steam_running; then
            if (( restarted )); then
                log "steam exited again while signing in; see $LOG"
                return 1
            fi
            # one restart shares the original deadline and needs a fresh sign-in.
            from=$(log_offset "$CONNECTION_LOG")
            restarted=1
            log "steam exited while signing in; restarting once"
            open_steam || return 1
        fi
        if (( $(new_matches "$CONNECTION_LOG" "$from" "RecvMsgClientLogOnResponse.*'OK'") > 0 )); then
            return 0
        fi
        sleep 1
    done
    log "steam did not sign in within ${LOGON_WAIT}s; see $LOG"
    return 1
}

# waits for steam to log a game process for app $1 after console log offset $2.
wait_game_started() {
    local i
    for (( i = 0; i < START_WAIT; i++ )); do
        if (( $(new_matches "$CONSOLE_LOG" "$2" "Game process added : AppID $1[^0-9]") > 0 )); then
            return 0
        fi
        sleep 1
    done
    return 1
}

validate_appid() {
    [[ "$1" =~ ^[0-9]+$ ]] || die "invalid steam app id"
}

# a windows-side helper (engine/helpers/dismiss-dialog) presses one button on a
# startup dialog that a game raises and a button press skips. it only touches a
# dialog with the exact title owned by the exact program, and inside this
# bottle only. kynseed sets its window resizable before its graphics device
# exists, which raises a .net error that Continue gets past.
DIALOG_HELPER="$REPO/helpers/dismiss-dialog/dismiss-dialog.exe"
DIALOG_WAIT=90

start_dialog_helper() {
    local title program button
    case "$1" in
        758870) title="Microsoft .NET Framework"; program="Kynseed.exe"; button="Continue" ;;
        *)      return 0 ;;
    esac
    if [[ ! -f "$DIALOG_HELPER" ]]; then
        log "dialog helper missing at $DIALOG_HELPER; $program may need a manual Continue"
        return 0
    fi
    ( wine_run "$DIALOG_HELPER" "$title" "$program" "$button" "$DIALOG_WAIT" >>"$LOG" 2>&1 & )
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
    require_steam
    local signed_in_from started_from
    signed_in_from=$(log_offset "$CONNECTION_LOG")
    if prefix_steam_running && steam_logged_on; then
        log "steam is signed in"
    else
        open_steam
        log "waiting up to ${LOGON_WAIT}s for steam to sign in"
        wait_signed_in "$signed_in_from" || return 1
        log "steam signed in"
    fi
    started_from=$(log_offset "$CONSOLE_LOG")
    # the forwarder's exit status is ignored: it has returned 1 for launches
    # that worked. steam's own game process line decides.
    steam_exe -applaunch "$1" -force-d3d11-no-singlethreaded -screen-fullscreen 0 \
        || log "steam request command exited $?; checking whether the game started"
    wait_game_started "$1" "$started_from" \
        || { log "steam did not start app $1 within ${START_WAIT}s; see $LOG"; return 1; }
    log "steam started app $1"
    start_dialog_helper "$1"
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
