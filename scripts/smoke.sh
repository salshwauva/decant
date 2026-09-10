#!/bin/bash
# thin smoke checks: paths, pure logic self-test, doctor. no game launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
pass() { echo "ok  - $*"; }
bad()  { echo "FAIL- $*"; fail=1; }

echo "== decant smoke =="

# monorepo layout
[ -f engine/install.sh ] && pass "engine/install.sh" || bad "engine/install.sh missing"
[ -f engine/PINS.md ] && pass "engine/PINS.md" || bad "engine/PINS.md missing"
[ -f engine/scripts/launch-steam.sh ] && pass "launch-steam.sh" || bad "launch-steam.sh missing"
[ -f scripts/decant-launch.sh ] && pass "decant-launch.sh" || bad "decant-launch.sh missing"
[ -f engine/scripts/lib/engine-store.sh ] && pass "lib/engine-store.sh" || bad "lib/engine-store.sh missing"
[ -f scripts/bundle.sh ] && pass "bundle.sh" || bad "bundle.sh missing"

# launch script must not use machine-wide kill patterns alone
if grep -q 'wineserver -k' engine/scripts/launch-steam.sh \
   && ! grep -q "kill -9 \$to_kill" engine/scripts/launch-steam.sh; then
  pass "prefix-scoped kill (wineserver -k)"
else
  bad "launch-steam kill path still looks machine-wide"
fi

# dxmt release pin present
if grep -q 'DXMT_SHA256=' engine/scripts/04-install-dxmt.sh; then
  pass "DXMT_SHA256 pin in 04-install-dxmt.sh"
else
  bad "DXMT_SHA256 missing"
fi

# build binary if needed
if [ ! -x .build/release/decant ] && [ ! -x build/decant.app/Contents/MacOS/decant ]; then
  echo "(building release binary for self-test)"
  swift build -c release
fi

BIN=""
if [ -x build/decant.app/Contents/MacOS/decant ]; then
  BIN=build/decant.app/Contents/MacOS/decant
elif [ -x .build/release/decant ]; then
  BIN=.build/release/decant
else
  BIN="$(swift build -c release --show-bin-path)/decant"
fi

[ -x "$BIN" ] && pass "binary $BIN" || bad "no decant binary"

SELF_OUT="$("$BIN" --self-test)" && pass "--self-test" || bad "--self-test"
printf '%s\n' "$SELF_OUT"

# the fault suite must recover from every fault it counts: one
# "FAULT <name> recovered" line per case, and N= the same number.
n=$(printf '%s\n' "$SELF_OUT" | sed -n 's/^N=//p' | tail -1)
faults=$(printf '%s\n' "$SELF_OUT" | grep -c '^FAULT ' | tr -d ' ')
if [ -n "$n" ] && [ "$n" = "$faults" ] && [ "$n" -gt 0 ]; then
  pass "engine fault suite: $faults recovered, N=$n"
else
  bad "engine fault count $faults does not match N=${n:-unset}"
fi

"$BIN" --doctor && pass "--doctor" || bad "--doctor"

# the shell half of the engine store must leave current as a symlink after an
# activate. temp directory only, never the real engine home.
STORE_TMP="$(mktemp -d)"
if (
  set -euo pipefail
  export DECANT_HOME="$STORE_TMP"
  export ENGINE_STORE_ROOT="$STORE_TMP/engines"
  # shellcheck source=../engine/scripts/lib/common.sh
  source engine/scripts/lib/common.sh
  # shellcheck source=../engine/scripts/lib/engine-store.sh
  source engine/scripts/lib/engine-store.sh
  mkdir -p "$ENGINE_STORE_ROOT/versions/v-fake/bin"
  printf 'fake wine\n' > "$ENGINE_STORE_ROOT/versions/v-fake/bin/wine"
  engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-fake" \
    v-fake wine-11.0 self-test v0.74 self-test
  engine_store_activate v-fake
  [ -L "$ENGINE_STORE_ROOT/current" ]
  [ "$(basename "$(readlink "$ENGINE_STORE_ROOT/current")")" = "v-fake" ]
) >/dev/null 2>&1; then
  pass "engine-store activate leaves current -> v-fake"
else
  bad "engine-store activate did not leave a current symlink"
fi
rm -rf "$STORE_TMP"

# support dir paths
SUP="${DECANT_HOME:-$HOME/Library/Application Support/decant}"
if [ -x "$SUP/engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine" ]; then
  pass "wine binary under Application Support"
else
  echo "skip- wine not installed yet (run bash engine/install.sh)"
fi
if [ -f "$SUP/engine/decant-launch.sh" ]; then
  pass "deployed launch script"
else
  echo "skip- launch script not deployed (run ./scripts/bundle.sh)"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "smoke FAILED"
  exit 1
fi
echo "smoke OK"
