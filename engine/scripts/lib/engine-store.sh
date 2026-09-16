#!/usr/bin/env bash
# Per-version engine store, shell half.
#
# Source this file after lib/common.sh:
#   source "$(dirname "$0")/lib/engine-store.sh"
#
# The install scripts run before `decant` exists, so the same layout and the
# same activation steps live here and in Sources/decant/EngineStore.swift.
# Keep the two in step.
#
# Layout under ENGINE_STORE_ROOT (default $DECANT_HOME/engines):
#   versions/<id>/                one engine version
#   versions/<id>/manifest.json   pins plus sha256 per artifact
#   versions/<id>.partial/        in-flight work
#   current                       symlink to versions/<id>
#   previous                      symlink to the version current replaced
#
# The five activation steps, same as the Swift side:
#   1. copy the new engine into versions/<id>.partial
#   2. hash every artifact the manifest lists (sha256)
#   3. validate the staged directory: manifest id, artifacts present, hashes
#   4. rename versions/<id>.partial onto versions/<id>
#   5. write current.new, rename it onto current, then point previous at the old id
#
# A failure at any step leaves current on the old version.
#
# shellcheck shell=bash

: "${ENGINE_STORE_ROOT:=$DECANT_HOME/engines}"
export ENGINE_STORE_ROOT

# print the id current points at, or nothing when no version is active.
engine_store_active_id() {
    local link="$ENGINE_STORE_ROOT/current"
    [[ -L "$link" ]] || return 0
    basename "$(readlink "$link")"
}

engine_store_previous_id() {
    local link="$ENGINE_STORE_ROOT/previous"
    [[ -L "$link" ]] || return 0
    basename "$(readlink "$link")"
}

# step 2 and 3: manifest id matches the expected id, every artifact the
# manifest lists is present, and every sha256 matches. this half takes a
# directory, so the same check runs on a staging directory before step 4.
engine_store_validate_dir() {
    local dir=$1
    local id=$2
    local manifest="$dir/manifest.json"

    [[ -d "$dir" ]] || { log_error "no engine version at $dir"; return 1; }
    [[ -f "$manifest" ]] || { log_error "no manifest at $manifest"; return 1; }

    local declared
    declared=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$manifest") \
        || { log_error "manifest does not parse: $manifest"; return 1; }
    [[ "$declared" == "$id" ]] \
        || { log_error "manifest id $declared does not match $id"; return 1; }

    local count=0 rel expected actual
    while IFS=$'\t' read -r expected rel; do
        [[ -n "$rel" ]] || continue
        count=$((count + 1))
        if [[ ! -f "$dir/$rel" ]]; then
            log_error "artifact missing: $rel"
            return 1
        fi
        actual=$(shasum -a 256 "$dir/$rel" | awk '{print $1}')
        if [[ "$actual" != "$expected" ]]; then
            log_error "checksum mismatch: $rel is $actual, manifest says $expected"
            return 1
        fi
    done < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for path, digest in sorted(m["artifacts"].items()):
    print(digest + "\t" + path)
' "$manifest")

    [[ "$count" -gt 0 ]] || { log_error "manifest lists no artifacts"; return 1; }
    return 0
}

# do two version directories list the same artifacts and digests?
engine_store_same_artifacts() {
    python3 -c '
import json, sys
def artifacts(path):
    with open(path) as fh:
        return json.load(fh)["artifacts"]
sys.exit(0 if artifacts(sys.argv[1]) == artifacts(sys.argv[2]) else 1)
' "$1/manifest.json" "$2/manifest.json"
}

# the same check against an installed version directory.
engine_store_validate() {
    local id=$1
    engine_store_validate_dir "$ENGINE_STORE_ROOT/versions/$id" "$id"
}

# write manifest.json for a staged or installed version directory.
# usage: engine_store_write_manifest <dir> <id> <wine-tag> <wine-commit> <dxmt-tag> <dxmt-commit>
engine_store_write_manifest() {
    local dir=$1 id=$2 wine_tag=$3 wine_commit=$4 dxmt_tag=$5 dxmt_commit=$6
    python3 - "$dir" "$id" "$wine_tag" "$wine_commit" "$dxmt_tag" "$dxmt_commit" <<'PY'
import datetime, hashlib, json, os, sys

directory, ident, wine_tag, wine_commit, dxmt_tag, dxmt_commit = sys.argv[1:7]

artifacts = {}
for base, _dirs, files in os.walk(directory):
    for name in files:
        full = os.path.join(base, name)
        rel = os.path.relpath(full, directory)
        if rel == "manifest.json" or os.path.islink(full):
            continue
        h = hashlib.sha256()
        with open(full, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        artifacts[rel] = h.hexdigest()

manifest = {
    "id": ident,
    "wineTag": wine_tag,
    "wineSourceCommit": wine_commit,
    "dxmtTag": dxmt_tag,
    "dxmtCommit": dxmt_commit,
    "patches": [],
    "build": {"host": os.uname().sysname, "arch": os.uname().machine},
    "artifacts": artifacts,
    "createdAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
with open(os.path.join(directory, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
PY
}

# steps 3, 4 and 5: validate versions/<id>.partial, rename it onto
# versions/<id>, then switch current. the staging directory is the only thing
# a bad version can lose. current and any installed version stay as they are
# until validation passes.
engine_store_promote() {
    local id=$1
    local staging="$ENGINE_STORE_ROOT/versions/$id.partial"
    local dir="$ENGINE_STORE_ROOT/versions/$id"

    # step 3: validate the staged directory on its own terms.
    if ! engine_store_validate_dir "$staging" "$id"; then
        rm -rf "$staging"
        log_error "staged engine $id did not validate, nothing was replaced"
        return 1
    fi

    # step 4: rename the partial directory into place. an id names one set of
    # bytes, so a version that is already there is reused when it matches and
    # refused when it does not. the swift half applies the same rule.
    if [[ -d "$dir" ]]; then
        if engine_store_validate_dir "$dir" "$id" 2>/dev/null; then
            if engine_store_same_artifacts "$dir" "$staging"; then
                rm -rf "$staging"
                log_info "engine $id is already installed with the same contents"
                engine_store_activate "$id"
                return
            fi
            rm -rf "$staging"
            log_error "engine $id is already installed with different contents"
            return 1
        fi
        # it does not validate, so it is a leftover from an install that did
        # not finish. never remove the version current still names.
        if [[ "$(engine_store_active_id)" == "$id" ]]; then
            rm -rf "$staging"
            log_error "engine $id is active but does not validate; roll back first"
            return 1
        fi
        log_warn "replacing incomplete engine $id"
        rm -rf "$dir"
    fi
    mkdir -p "$(dirname "$dir")"
    mv "$staging" "$dir"

    # step 5: switch current and record previous.
    engine_store_activate "$id"
}

# step 5: point current at id, then record the id it replaced.
# mv -h keeps mv from following the current symlink into its target directory.
engine_store_activate() {
    local id=$1
    engine_store_validate "$id" || return 1

    local old
    old=$(engine_store_active_id)

    ln -sfn "versions/$id" "$ENGINE_STORE_ROOT/current.new"
    mv -fh "$ENGINE_STORE_ROOT/current.new" "$ENGINE_STORE_ROOT/current"

    if [[ -n "$old" && "$old" != "$id" ]]; then
        # if previous cannot be written, put current back on the old version,
        # so the two links never disagree about which version ran last.
        if ! { ln -sfn "versions/$old" "$ENGINE_STORE_ROOT/previous.new" \
            && mv -fh "$ENGINE_STORE_ROOT/previous.new" "$ENGINE_STORE_ROOT/previous"; }; then
            rm -f "$ENGINE_STORE_ROOT/previous.new"
            ln -sfn "versions/$old" "$ENGINE_STORE_ROOT/current.new"
            mv -fh "$ENGINE_STORE_ROOT/current.new" "$ENGINE_STORE_ROOT/current"
            log_error "could not record previous; current stays on $old"
            return 1
        fi
    fi

    [[ -L "$ENGINE_STORE_ROOT/current" ]] \
        || { log_error "current is not a symlink after activate"; return 1; }
    log_ok "engine current -> $id"
}

# swap back to the version current replaced.
engine_store_rollback() {
    local prev
    prev=$(engine_store_previous_id)
    [[ -n "$prev" ]] || { log_error "no previous engine version to roll back to"; return 1; }
    engine_store_activate "$prev"
}
