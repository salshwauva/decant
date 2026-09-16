#!/usr/bin/env bash
#
# 01-install-wine.sh — Install Wine + winetricks + GStreamer via Homebrew.
#
# Installs:
#   - wine-stable  (Gcenx cask, Wine 11.0_1 x86_64)
#   - gstreamer-runtime (dependency of wine-stable; needs sudo for .pkg)
#   - winetricks   (Homebrew formula)
#
# Removes the quarantine xattr from Wine Stable.app so macOS Gatekeeper
# doesn't SIGKILL the unsigned binary on exec.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/engine-store.sh
source "$(dirname "$0")/lib/engine-store.sh"
require_macos_arm64
require_homebrew
require_cmd python3

# one engine version per id. bump the id when a pin in PINS.md moves.
: "${ENGINE_ID:=wine-11.0-dxmt-v0.74}"
: "${ENGINE_WINE_TAG:=wine-11.0}"
: "${ENGINE_WINE_COMMIT:=${WINE_BUILD_BRANCH:-wine-11.0}}"
: "${ENGINE_DXMT_TAG:=v0.74}"
: "${ENGINE_DXMT_COMMIT:=${DXMT_FORK_SHA:-unset}}"

WINE_CASK="wine-stable"
WINETRICKS_FORMULA="winetricks"

log_step "Installing Wine + winetricks"

# -- Tap Gcenx (if not already) -----------------------------------------------
# wine-stable lives in the official Homebrew Cask repo, so no extra tap is
# strictly required. We keep this block explicit so the script documents
# the trust boundary.
if ! brew_arm64 list --cask | grep -q "^${WINE_CASK}$"; then
    log_info "Installing cask ${WINE_CASK}"
    # gstreamer-runtime (pulled in as a dependency) invokes the system
    # installer and will prompt for sudo in the interactive terminal.
    brew_arm64 install --cask "$WINE_CASK"
else
    log_ok "Cask ${WINE_CASK} already installed"
fi

# -- winetricks ---------------------------------------------------------------
if ! brew_arm64 list --formula | grep -q "^${WINETRICKS_FORMULA}$"; then
    log_info "Installing formula ${WINETRICKS_FORMULA}"
    brew_arm64 install "$WINETRICKS_FORMULA"
else
    log_ok "Formula ${WINETRICKS_FORMULA} already installed"
fi

# -- Deploy a writable Wine into decant's engine home --------------------------
# Brew puts Wine Stable.app under /Applications. decant needs a writable copy
# (for winemac.so + DXMT dlls). `cp -RX` drops com.apple.provenance so the
# copy is not read-only under macOS Tahoe.
BREW_WINE_APP="/Applications/Wine Stable.app"
if [[ ! -d "$BREW_WINE_APP" ]]; then
    # some installs land under ~/Applications
    BREW_WINE_APP="$HOME/Applications/Wine Stable.app"
fi
if [[ ! -d "$BREW_WINE_APP" ]]; then
    die "Wine Stable.app not found after brew install (looked in /Applications and ~/Applications)"
fi

# The engine store keeps each version in its own directory and points
# engines/current at the active one. The previous version stays on disk, so a
# bad install rolls back. The five steps below match engine_store_activate and
# Sources/decant/EngineStore.swift.
VERSION_DIR="$ENGINE_STORE_ROOT/versions/$ENGINE_ID"
STAGING="$ENGINE_STORE_ROOT/versions/$ENGINE_ID.partial"

if [[ -d "$VERSION_DIR" ]] && engine_store_validate "$ENGINE_ID"; then
    log_ok "Engine version $ENGINE_ID is already installed and validates"
else
    log_info "Installing engine version $ENGINE_ID"
    # step 1: copy into the partial directory. -R recursive, -X drop xattrs
    # including com.apple.provenance, which makes the copy read-only on Tahoe.
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -RX "$BREW_WINE_APP" "$STAGING/Wine Stable.app"

    # wine-stable is unsigned. Without this macOS kills wine with exit 137.
    if xattr -l "$STAGING/Wine Stable.app" 2>/dev/null | grep -q com.apple.quarantine; then
        log_info "Removing com.apple.quarantine from the staged copy"
        xattr -dr com.apple.quarantine "$STAGING/Wine Stable.app"
    fi

    # the patched driver needs this exact wine, so check the staged copy
    # before anything is promoted. a wrong version never reaches the store.
    staged_version=$(run_x86_64 "$STAGING/Wine Stable.app/Contents/Resources/wine/bin/wine" \
        --version 2>&1 || true)
    if [[ "$staged_version" != "wine-11.0" ]]; then
        rm -rf "$STAGING"
        die "Wine 11.0 is required for the patched driver. Found: $staged_version"
    fi
    log_ok "Staged Wine responds: $staged_version"

    # step 2: hash every artifact into the manifest.
    log_info "Hashing artifacts into manifest.json"
    engine_store_write_manifest "$STAGING" "$ENGINE_ID" \
        "$ENGINE_WINE_TAG" "$ENGINE_WINE_COMMIT" "$ENGINE_DXMT_TAG" "$ENGINE_DXMT_COMMIT"

    # steps 3, 4 and 5: validate the staged copy, rename it into place, then
    # switch current. A staged copy that does not validate is removed and
    # current keeps the version it already had.
    engine_store_promote "$ENGINE_ID" || die "Engine version $ENGINE_ID did not install"
fi

# activate the version this run asked for, whether it was installed now or
# reused. promote already activates a fresh install; this is what makes a
# reused version current too.
engine_store_activate "$ENGINE_ID" || die "Could not activate engine version $ENGINE_ID"

# point this shell at the version that is now active.
WINE_APP="$ENGINE_STORE_ROOT/current/Wine Stable.app"
WINE_BIN="$WINE_APP/Contents/Resources/wine/bin/wine"
WINESERVER_BIN="$WINE_APP/Contents/Resources/wine/bin/wineserver"
export WINE_APP WINE_BIN WINESERVER_BIN

if [[ ! -d "$WINE_APP" ]]; then
    die "Wine Stable.app not found at $WINE_APP"
fi

# -- Gatekeeper quarantine ----------------------------------------------------
# wine-stable is an unsigned/ad-hoc-signed x86_64 bundle. Without removing
# the quarantine xattr, macOS kills wine on launch with exit code 137.
if xattr -l "$WINE_APP" 2>/dev/null | grep -q com.apple.quarantine; then
    log_info "Removing com.apple.quarantine from $WINE_APP"
    xattr -dr com.apple.quarantine "$WINE_APP"
    log_ok "Quarantine xattr cleared"
else
    log_ok "No quarantine xattr on $WINE_APP"
fi

# -- Smoke test ---------------------------------------------------------------
log_info "Smoke-testing Wine binary"
wine_version=$(run_x86_64 "$WINE_BIN" --version 2>&1 || true)
if [[ "$wine_version" == "wine-11.0" ]]; then
    log_ok "Wine responds: $wine_version"
else
    die "Wine 11.0 is required for the patched driver. Found: $wine_version"
fi

log_ok "Wine + winetricks install complete"
