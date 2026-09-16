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

python3 -B -m unittest discover -s Tests/EngineTests -v
swift test

# dxmt release pin present
if grep -q 'DXMT_SHA256=' engine/scripts/04-install-dxmt.sh; then
  pass "DXMT_SHA256 pin in 04-install-dxmt.sh"
else
  bad "DXMT_SHA256 missing"
fi

# build the current source before any binary check.
swift build -c release
BIN="$(swift build -c release --show-bin-path)/decant"

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

# the launch lifecycle cases must all be present and passing.
launch_missing=""
for name in "launch happy" "launch duplicate play rejected" \
            "launch timeout preparing" "launch timeout request sent" \
            "launch illegal detect from idle" "redact drops identity lines" \
            "launch shell failure reaches the controller" "launch ignores a stale exit" \
            "probe rejects a prefix with a suffix"; do
  printf '%s\n' "$SELF_OUT" | grep -Fq "ok   $name" || launch_missing="$launch_missing $name;"
done
if [ -z "$launch_missing" ]; then
  pass "launch lifecycle cases"
else
  bad "launch lifecycle cases missing or failing:$launch_missing"
fi

# the launcher must fail with a nonzero status when the engine is missing,
# and its log must carry the launch id decant passed in. temp home only.
LAUNCH_TMP="$(mktemp -d)"
if DECANT_HOME="$LAUNCH_TMP" DECANT_LAUNCH_ID=smoke-1 \
   bash scripts/decant-launch.sh play 2432860 >/dev/null 2>&1; then
  bad "decant-launch.sh reported success with no engine"
else
  pass "decant-launch.sh fails with a nonzero status when wine is missing"
fi
if grep -q 'launch_id=smoke-1' "$LAUNCH_TMP/logs/decant-launch.log" 2>/dev/null; then
  pass "decant-launch.sh logs the launch id"
else
  bad "decant-launch.sh dropped the launch id"
fi
rm -rf "$LAUNCH_TMP"

# doctor against an isolated home with no engine must fail.
DOCTOR_TMP="$(mktemp -d)"
if DECANT_HOME="$DOCTOR_TMP" "$BIN" --doctor >/dev/null 2>&1; then
  bad "--doctor passed with no engine in an empty home"
else
  pass "--doctor fails on a missing engine"
fi
rm -rf "$DOCTOR_TMP"

# the real engine, when one is installed here.
SUP="${DECANT_HOME:-$HOME/Library/Application Support/decant}"
if [ -x "$SUP/engines/current/Wine Stable.app/Contents/Resources/wine/bin/wine" ] \
   || [ -x "$SUP/engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine" ]; then
  "$BIN" --doctor && pass "--doctor on the installed engine" || bad "--doctor"
else
  echo "skip- no engine installed here (run bash engine/install.sh)"
fi

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

# a staged version with a bad artifact hash must not replace anything: the
# promote fails, versions/<id> is never created, and current stays put.
STORE_TMP="$(mktemp -d)"
if (
  set -euo pipefail
  export DECANT_HOME="$STORE_TMP"
  export ENGINE_STORE_ROOT="$STORE_TMP/engines"
  # shellcheck source=../engine/scripts/lib/common.sh
  source engine/scripts/lib/common.sh
  # shellcheck source=../engine/scripts/lib/engine-store.sh
  source engine/scripts/lib/engine-store.sh

  # a good version is active first.
  mkdir -p "$ENGINE_STORE_ROOT/versions/v-good/bin"
  printf 'good wine\n' > "$ENGINE_STORE_ROOT/versions/v-good/bin/wine"
  engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-good" \
    v-good wine-11.0 self-test v0.74 self-test
  engine_store_activate v-good

  # stage v-bad, then change the artifact so the manifest hash is wrong.
  STAGING="$ENGINE_STORE_ROOT/versions/v-bad.partial"
  mkdir -p "$STAGING/bin"
  printf 'staged wine\n' > "$STAGING/bin/wine"
  engine_store_write_manifest "$STAGING" v-bad wine-11.0 self-test v0.74 self-test
  printf 'tampered wine\n' > "$STAGING/bin/wine"

  ! engine_store_promote v-bad
  [ ! -e "$ENGINE_STORE_ROOT/versions/v-bad" ]
  [ ! -e "$STAGING" ]
  [ "$(basename "$(readlink "$ENGINE_STORE_ROOT/current")")" = "v-good" ]
) >/dev/null 2>&1; then
  pass "engine-store rejects a bad staged version and leaves current -> v-good"
else
  bad "engine-store promoted a bad staged version"
fi
rm -rf "$STORE_TMP"

# support dir paths. engines/current is the engine store; engines/wine11 is
# what an install made before the store left behind.
if [ -x "$SUP/engines/current/Wine Stable.app/Contents/Resources/wine/bin/wine" ] \
   || [ -x "$SUP/engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine" ]; then
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
