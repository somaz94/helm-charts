#!/usr/bin/env bash
# Print charts whose Chart.yaml `version:` changed in <ref-a>...<ref-b> (three-dot) with
# no matching CHANGELOG.md change. Empty/all-zeros <ref-a> (first push) prints nothing.
# Shared by changelog-auto.yml and release.yml. lint.yml's changelog-check keeps its own
# inline awk copy on purpose as an independent safeguard — do NOT replace it with this.

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
