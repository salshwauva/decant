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
require_macos_arm64
require_homebrew

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

if [[ "$WINE_APP" != "$BREW_WINE_APP" ]]; then
    if [[ ! -x "$WINE_BIN" ]]; then
        log_info "Copying Wine into decant home: $WINE_APP"
        mkdir -p "$(dirname "$WINE_APP")"
        # -R recursive, -X drop xattrs including com.apple.provenance
        rm -rf "$WINE_APP"
        cp -RX "$BREW_WINE_APP" "$WINE_APP"
        log_ok "Writable Wine copy at $WINE_APP"
    else
        log_ok "Writable Wine already at $WINE_APP"
    fi
fi

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
