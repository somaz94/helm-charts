#!/usr/bin/env bash
# detect-bumped-charts.sh — list charts that need a CHANGELOG.md sync.
#
# Reads the diff between two git refs and prints the names of charts whose
# Chart.yaml `version:` line changed without a matching CHANGELOG.md change
# in the same diff. One chart name per line on stdout.
#
# Usage:
#   detect-bumped-charts.sh <ref-a> <ref-b>
#
# Both refs must be resolvable in the current repo (commit SHAs, branch
# refs, tags, etc.). The diff is computed as `git diff <ref-a>...<ref-b>`
# (three-dot — symmetric merge-base diff, same form used by
# .github/workflows/lint.yml's changelog-check job).
#
# Special-case: an all-zeros SHA or empty <ref-a> is treated as "initial
# branch push" and the script exits 0 without output (nothing to detect
# against).
#
# This script is shared between:
#   - .github/workflows/changelog-auto.yml (PR flow — auto-commit sync)
#   - .github/workflows/release.yml        (push-to-main flow — fallback)
#
# .github/workflows/lint.yml's changelog-check intentionally keeps its own
# inline awk copy of this logic as an independent safeguard, so do NOT
# replace it with a call to this script.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <ref-a> <ref-b>" >&2
    exit 2
fi

REF_A="$1"
REF_B="$2"

# Initial-branch push (push event sends 0000... as the parent SHA) — there
# is no prior state to diff against, so emit nothing.
if [ -z "$REF_A" ] || [ "$REF_A" = "0000000000000000000000000000000000000000" ]; then
    exit 0
fi

# Charts whose Chart.yaml `version:` line changed in <ref-a>...<ref-b>.
changed_charts=$(git diff "${REF_A}...${REF_B}" -- 'charts/*/Chart.yaml' \
    | awk '/^\+\+\+ b\/charts\// { sub(/^\+\+\+ b\/charts\//, ""); split($0, a, "/"); chart=a[1] } \
           /^[+-]version:/ && $0 !~ /^[+-]{3}/ { print chart }' \
    | sort -u)

[ -z "$changed_charts" ] && exit 0

# All paths touched by the diff — we use this to check whether each chart's
# CHANGELOG.md was also updated.
diff_files=$(git diff --name-only "${REF_A}...${REF_B}")

while IFS= read -r c; do
    [ -n "$c" ] || continue
    # Defense in depth: reject anything that isn't a sane chart-dir name
    # before downstream consumers (workflow shells) word-split this output.
    if ! printf '%s' "$c" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        echo "warning: skipping chart with unexpected name: $c" >&2
        continue
    fi
    if ! printf '%s\n' "$diff_files" | grep -qx "charts/${c}/CHANGELOG.md"; then
        printf '%s\n' "$c"
    fi
done <<< "$changed_charts"
