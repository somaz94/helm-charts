#!/usr/bin/env bash
# sync-changelog.sh — generate/update per-chart CHANGELOG.md from Chart.yaml.
#
# Reads `version` and `annotations."artifacthub.io/changes"` from a chart's
# Chart.yaml, maps each entry's `kind` to a Keep a Changelog section, and
# prepends a `## [vX.Y.Z] - YYYY-MM-DD` block to charts/<name>/CHANGELOG.md.
#
# Idempotent: skips when a section for the same version already exists.
#
# Usage:
#   sync-changelog.sh [--dry-run] <chart-dir>     # single chart
#   sync-changelog.sh [--dry-run] --all           # every chart under charts/
#   sync-changelog.sh --help

set -euo pipefail

# zsh compat: a zero-match glob is fatal under zsh's default NOMATCH. No-op in
# bash. Must run before any glob (e.g. "$CHARTS_DIR"/*/).
[ -n "${ZSH_VERSION:-}" ] && setopt nonomatch

# Resolve script path portably across bash and zsh.
# bash: ${BASH_SOURCE[0]}; zsh executed: $0 (these scripts are not sourced).
_SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_PATH")" && pwd)"
unset _SCRIPT_PATH
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHARTS_DIR="$REPO_ROOT/charts"

# Shared helpers: log/warn/die/info, mktemp_tracked, require_yq_v4.
# Installs an EXIT trap that removes every mktemp_tracked file — protects
# against SIGTERM / `set -e` exits between mktemp and the success-path mv.
. "$SCRIPT_DIR/../lib/common.sh"
init_tmp_cleanup

DRY_RUN=0
ALL=0
CHART_DIR=""

usage() {
    cat <<'EOF'
sync-changelog.sh — sync a chart's CHANGELOG.md from its Chart.yaml.

Usage:
  sync-changelog.sh [--dry-run] <chart-dir>
  sync-changelog.sh [--dry-run] --all
  sync-changelog.sh --help

Flags:
  --dry-run   Print the resulting CHANGELOG.md to stdout without writing.
  --all       Process every chart under charts/.
  --help      Show this help.

Behavior:
  - Reads `version` and `annotations.artifacthub.io/changes` from Chart.yaml.
  - Maps `kind` to Keep a Changelog sections in the order:
      Added, Changed, Deprecated, Removed, Fixed, Security.
  - Prepends a new `## [vX.Y.Z] - YYYY-MM-DD` block to charts/<name>/CHANGELOG.md.
  - If the file does not exist, creates it with a standard Keep a Changelog header.
  - If a section for the same version already exists, prints a warning and exits 0.

Requires: yq v4 (mikefarah/yq).
EOF
}

# log/info/warn/die provided by lib/common.sh.

# Map a Chart.yaml `kind:` value to a Keep a Changelog section header.
section_for_kind() {
    case "$1" in
        added)      echo "Added" ;;
        changed)    echo "Changed" ;;
        deprecated) echo "Deprecated" ;;
        removed)    echo "Removed" ;;
        fixed)      echo "Fixed" ;;
        security)   echo "Security" ;;
        *)          echo "" ;;
    esac
}

# Standard Keep a Changelog header used when creating a new CHANGELOG.md.
standard_header() {
    cat <<'EOF'
# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
EOF
}

# Render a single `## [vX.Y.Z] - YYYY-MM-DD` block from the chart's
# artifacthub.io/changes annotation. Stdout = the block (no trailing newline).
render_section() {
    local chart_yaml="$1" version="$2" today="$3"
    local inner kind label entries

    inner="$(yq -r '.annotations."artifacthub.io/changes" // ""' "$chart_yaml")"
    if [ -z "$inner" ] || [ "$inner" = "null" ]; then
        die "$chart_yaml has no annotations.\"artifacthub.io/changes\""
    fi

    printf '## [v%s] - %s\n' "$version" "$today"

    # Iterate kinds in Keep a Changelog order. For each kind, emit a section
    # only if at least one entry of that kind exists.
    for kind in added changed deprecated removed fixed security; do
        entries="$(printf '%s\n' "$inner" \
            | yq -r "[.[] | select(.kind == \"$kind\") | .description] | .[] | \"- \" + .")"
        if [ -n "$entries" ]; then
            label="$(section_for_kind "$kind")"
            printf '\n### %s\n%s\n' "$label" "$entries"
        fi
    done

    # Detect any unknown kinds and surface them so we don't silently drop entries.
    local unknown
    unknown="$(printf '%s\n' "$inner" \
        | yq -r '[.[].kind] | unique | .[]' \
        | grep -vE '^(added|changed|deprecated|removed|fixed|security)$' || true)"
    if [ -n "$unknown" ]; then
        warn "$chart_yaml has unmapped kind(s) — entries dropped:"
        printf '  - %s\n' $unknown >&2
    fi
}

# Process a single chart directory. Writes/updates charts/<name>/CHANGELOG.md
# unless --dry-run, in which case the rendered file is printed to stdout.
process_chart() {
    local chart_dir="$1"
    local chart_yaml="$chart_dir/Chart.yaml"
    local changelog="$chart_dir/CHANGELOG.md"
    local name version today section new_content tmp

    [ -f "$chart_yaml" ] || die "Chart.yaml not found: $chart_yaml"

    name="$(basename "$chart_dir")"
    version="$(yq -r '.version' "$chart_yaml")"
    [ -n "$version" ] && [ "$version" != "null" ] || die "$chart_yaml has no version"
    today="$(date +%Y-%m-%d)"

    # Idempotency: same-version section already present — skip.
    if [ -f "$changelog" ] && grep -qE "^## \[v${version}\] - " "$changelog"; then
        warn "$changelog already has a section for v$version, skipping"
        return 0
    fi

    section="$(render_section "$chart_yaml" "$version" "$today")"

    if [ -f "$changelog" ]; then
        # Existing file: insert the new section before the first `## [` line
        # (the topmost prior version block). If none exists yet, append at end.
        local first_version_line
        first_version_line="$(grep -nE '^## \[' "$changelog" | head -1 | cut -d: -f1 || true)"
        if [ -n "$first_version_line" ]; then
            new_content="$( \
                head -n $((first_version_line - 1)) "$changelog"; \
                printf '%s\n\n' "$section"; \
                tail -n +"$first_version_line" "$changelog" \
            )"
        else
            new_content="$(cat "$changelog"; printf '\n%s\n' "$section")"
        fi
    else
        # New file: standard header + first section.
        new_content="$(standard_header; printf '\n%s\n' "$section")"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '===== %s (v%s) — DRY RUN =====\n' "$name" "$version"
        printf '%s\n' "$new_content"
        printf '===== end %s =====\n\n' "$name"
        return 0
    fi

    tmp="$(mktemp_tracked)"
    printf '%s\n' "$new_content" > "$tmp"
    mv "$tmp" "$changelog"
    if [ -f "$changelog" ] && [ "$(wc -l < "$changelog")" -gt 0 ]; then
        log "updated: $changelog (v$version)"
    fi
}

# CLI parsing.
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --all)     ALL=1; shift ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        -*) die "unknown flag: $1" ;;
        *) CHART_DIR="$1"; shift ;;
    esac
done

require_yq_v4

if [ "$ALL" -eq 1 ]; then
    [ -z "$CHART_DIR" ] || die "--all and <chart-dir> are mutually exclusive"
    [ -d "$CHARTS_DIR" ] || die "charts dir not found: $CHARTS_DIR"
    # Guard against a zero-match glob: `setopt nonomatch` (top of file) keeps zsh
    # from aborting, and this [ -d ] check skips the literal pattern that both
    # shells then pass through. Avoids the bash-only `shopt -s nullglob`.
    for d in "$CHARTS_DIR"/*/; do
        [ -d "$d" ] || continue
        process_chart "${d%/}"
    done
else
    [ -n "$CHART_DIR" ] || { usage; die "missing <chart-dir> (or use --all)"; }
    [ -d "$CHART_DIR" ] || die "chart directory not found: $CHART_DIR"
    process_chart "$CHART_DIR"
fi
