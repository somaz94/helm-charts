#!/usr/bin/env bash
# Shared helpers for scripts/ — sourced, never executed; bash 3.2+ and zsh 5+;
# safe to double-source. Sets no shell options and installs no trap unless the
# caller runs init_tmp_cleanup. Callers source it relative to their own path:
#   . "$SCRIPT_DIR/../lib/common.sh"

[ "${HELM_CHARTS_LIB_COMMON_LOADED:-}" = "1" ] && return 0
HELM_CHARTS_LIB_COMMON_LOADED=1

# ---------- Logging ----------
# All output goes to stderr so callers can keep stdout reserved for
# machine-readable data (TAB-separated records, JSON, file paths).

log()  { printf '%s\n' "$*" >&2; }
info() { log "$*"; }
warn() { log "WARNING: $*"; }
die()  { log "ERROR: $*"; exit 1; }

# ---------- Temp-file tracking ----------
# The array lives in this lib's namespace so multiple callers can share it
# without colliding with their own TMP_FILES variable.

LIB_COMMON_TMP_FILES=()

# Internal — the trap handler. Tolerates an empty array under `set -u` via
# the `[@]:-` default expansion.
_lib_common_cleanup_tmp() {
    local f
    for f in "${LIB_COMMON_TMP_FILES[@]:-}"; do
        [ -n "$f" ] && rm -f "$f"
    done
    return 0
}

# Install the EXIT trap. Idempotent — calling more than once is a no-op so
# scripts that source this lib indirectly (via another lib) don't blow away
# their own trap.
init_tmp_cleanup() {
    if [ "${LIB_COMMON_TRAP_INSTALLED:-}" = "1" ]; then
        return 0
    fi
    LIB_COMMON_TRAP_INSTALLED=1
    trap _lib_common_cleanup_tmp EXIT
}

# Allocate a tracked temp file. Prints the path on stdout so callers can do:
#   tmp=$(mktemp_tracked)
mktemp_tracked() {
    local f
    f=$(mktemp)
    LIB_COMMON_TMP_FILES+=("$f")
    printf '%s' "$f"
}

# ---------- Dependency guards ----------

# Abort if $1 is not on PATH. Optional $2 is an install hint shown in the
# error message.
require_command() {
    local cmd="$1" hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [ -n "$hint" ]; then
            die "$cmd is required ($hint)"
        else
            die "$cmd is required"
        fi
    fi
}

# Guard for mikefarah/yq v4 — the only yq dialect these scripts target.
# Aborts with a clear message if yq is missing or is the wrong major version.
require_yq_v4() {
    require_command yq "install: brew install yq"
    if ! yq --version 2>&1 | grep -qE 'version v?4\.'; then
        die "yq v4 is required (mikefarah/yq). Found: $(yq --version 2>&1)"
    fi
}
