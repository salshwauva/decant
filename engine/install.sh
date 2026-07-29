#!/usr/bin/env bash
#
# install.sh — build decant's wine 11 + dxmt engine (one-time, ~1 hour first run).
#
# this is the engine half of the decant monorepo. after it finishes, the
# swiftui app (build/decant.app) detects the stack under
# ~/Library/Application Support/decant and launches games.
#
# Default mode (no arguments)
# ---------------------------
# Wine 11 into the decant home, Steam bottle, steamwebhelper wrapper,
# DXMT fork build, winemac.so -fvisibility=default rebuild.
#
# --minimal
# ---------
# Stops after scripts/06. Steam UI works; D3D11 games don't.
#
# Every step is idempotent; safe to re-run at any point.
#
# Env overrides (all optional)
# ----------------------------
#   DECANT_HOME        runtime root (default: ~/Library/Application Support/decant)
#   WINEPREFIX         bottle path (default: $DECANT_HOME/bottles/steam11)
#   WINE_APP           writable Wine.app (default: $DECANT_HOME/engines/wine11/Wine Stable.app)
#   DXMT_SRC           DXMT fork checkout (default: ~/dev/dxmt)
#   LLVM_PREFIX        x86_64 LLVM 15 (default: $DXMT_SRC/toolchains/llvm)
#   WINE_BUILD_SRC     Wine 11.0 source (default: ~/dev/wine-build/wine)

set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=scripts/lib/common.sh
source "scripts/lib/common.sh"
require_macos_arm64

MODE="full"
if [[ "${1:-}" == "--minimal" ]]; then
    MODE="minimal"
elif [[ -n "${1:-}" ]]; then
    die "Unknown argument: $1 (use --minimal, or no arguments for full)"
fi

log_step "decant engine installer ($MODE mode)"
log_info "DECANT_HOME  : $DECANT_HOME"
log_info "WINEPREFIX   : $WINEPREFIX"
log_info "WINE_APP     : $WINE_APP"
log_info ""
if [[ "$MODE" == "full" ]]; then
    log_info "Full mode runs scripts/00 through 08. First run is ~1 hour"
    log_info "(LLVM 15 x86_64 self-build + Wine winemac rebuild). Each step"
    log_info "is idempotent; re-run after a failure to continue."
    log_info ""
    log_info "Steam UI only (skip long builds):  bash install.sh --minimal"
else
    log_info "Minimal mode: scripts/00 through 06. Steam boots; D3D11 games"
    log_info "need a later full run for DXMT + winemac visibility."
fi

core_steps=(
    scripts/00-prereqs.sh
    scripts/01-install-wine.sh
    scripts/02-setup-prefix.sh
    scripts/03-install-steam.sh
    scripts/04-install-dxmt.sh
    scripts/05-fix-ssl.sh
    scripts/06-install-wrapper.sh
)

d3d11_steps=(
    scripts/07-build-dxmt-fork.sh
    scripts/08-patch-wine-visibility.sh
)

# 09/10 install a separate "Steam on M1 Wine.app" dock icon. decant's own
# swiftui app is the front end, so those steps are skipped on purpose.

if [[ "$MODE" == "full" ]]; then
    steps=("${core_steps[@]}" "${d3d11_steps[@]}")
else
    steps=("${core_steps[@]}")
fi

for step in "${steps[@]}"; do
    log_step "$(basename "$step")"
    bash "$step" || die "$step failed; fix the error above and re-run install.sh"
done

# keep a deployed recipe copy next to the runtime so launch-steam.sh and
# the app always find scripts even if this git tree moves.
DEPLOY="$DECANT_HOME/engine"
log_step "Deploy recipe scripts to $DEPLOY"
mkdir -p "$DEPLOY"
rsync -a --delete \
    --exclude 'vendor' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    ./ "$DEPLOY/"
log_ok "Recipe deployed"

log_step "Done"
log_info ""
log_info "Engine is under $DECANT_HOME"
log_info "Next:"
log_info "  1. Build the UI:  ./scripts/bundle.sh && open build/decant.app"
log_info "  2. Or open Steam in the bottle:  bash scripts/launch-steam.sh --detach"
log_info "  3. Sign in, install a game, play from the decant shelf."
log_info ""
if [[ "$MODE" == "minimal" ]]; then
    log_info "You ran --minimal. For D3D11 games, re-run:"
    log_info "  bash install.sh"
    log_info ""
fi
