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

"$BIN" --self-test && pass "--self-test" || bad "--self-test"
"$BIN" --doctor && pass "--doctor" || bad "--doctor"

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
