#!/usr/bin/env bash
# check-upstream-rbac.sh — fail when a chart's RBAC drifts from the upstream manifest it re-implements.
#
# A chart whose templates/rbac.yaml is a hand-kept copy of an upstream raw manifest cannot notice
# when upstream moves or adds a rule: lint, render and kubeconform all stay green. keycloak-operator
# missed the rules upstream moved into keycloakcontroller-cluster-role in 26.7.1 for five releases,
# until operator 26.8.0 failed every reconcile with a 403 (fixed in chart 0.2.6).
#
# Renders the chart with its defaults and compares every ClusterRole / Role against the same-named
# object in charts/<chart>/upstream/*.yml (written by the chart's upgrade.sh), rule for rule as
# (apiGroup, resource, resourceName, verb) tuples. A role on one side only, or a tuple on one side
# only, is drift.
#
# Usage:
#   check-upstream-rbac.sh <chart>
#
# Exit codes:
#   0  RBAC matches upstream, or the chart has no upstream/ snapshot (nothing to compare)
#   1  drift
#
# Needs helm, yq v4 and python3 (stdlib only). No network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$REPO_ROOT/scripts/lib/common.sh"

CHART="${1:-}"
[ -n "$CHART" ] || die "usage: check-upstream-rbac.sh <chart>"
CHART_DIR="$REPO_ROOT/charts/$CHART"
[ -d "$CHART_DIR" ] || die "chart not found: $CHART_DIR"

SNAPSHOTS=""
if [ -d "$CHART_DIR/upstream" ]; then
  SNAPSHOTS="$(find "$CHART_DIR/upstream" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)"
fi
[ -n "$SNAPSHOTS" ] || exit 0

require_command helm
require_command python3
require_yq_v4

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ROLES_EXPR='select(.kind == "ClusterRole" or .kind == "Role") | {"kind": .kind, "name": .metadata.name, "rules": (.rules // [])}'

helm template "$CHART" "$CHART_DIR" >"$WORK/chart.yaml"
yq -o=json -I=0 "$ROLES_EXPR" "$WORK/chart.yaml" >"$WORK/chart.jsonl"

: >"$WORK/upstream.jsonl"
while IFS= read -r snapshot; do
  yq -o=json -I=0 "$ROLES_EXPR" "$snapshot" >>"$WORK/upstream.jsonl"
done <<EOF
$SNAPSHOTS
EOF

python3 - "$CHART" "$WORK/upstream.jsonl" "$WORK/chart.jsonl" <<'PYEOF'
import json
import sys
from collections import defaultdict

chart, upstream_path, chart_path = sys.argv[1:4]


def load(path):
    roles = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line == "null":
                continue
            doc = json.loads(line)
            roles[(doc["kind"], doc["name"])] = doc["rules"] or []
    return roles


def tuples(rules):
    out = set()
    for rule in rules:
        verbs = rule.get("verbs") or []
        for url in rule.get("nonResourceURLs") or []:
            out.update(("nonResourceURL", url, "", v) for v in verbs)
        for group in rule.get("apiGroups") or []:
            for resource in rule.get("resources") or []:
                for name in rule.get("resourceNames") or ["*"]:
                    out.update((group, resource, name, v) for v in verbs)
    return out


def describe(items):
    by_target = defaultdict(list)
    for group, resource, name, verb in sorted(items):
        by_target[(group or "core", resource, name)].append(verb)
    lines = []
    for (group, resource, name), verbs in sorted(by_target.items()):
        target = resource if name == "*" else f"{resource}/{name}"
        lines.append(f"{group} {target} [{', '.join(verbs)}]")
    return lines


upstream, rendered = load(upstream_path), load(chart_path)
problems = []
for key in sorted(set(upstream) | set(rendered)):
    label = f"{key[0]}/{key[1]}"
    if key not in rendered:
        problems.append(f"  {label}: in upstream only — the chart does not render it")
        continue
    if key not in upstream:
        problems.append(f"  {label}: in the chart only — upstream has no such object")
        continue
    want, have = tuples(upstream[key]), tuples(rendered[key])
    if want == have:
        continue
    problems.append(f"  {label}:")
    problems += [f"    missing in chart: {line}" for line in describe(want - have)]
    problems += [f"    extra in chart:   {line}" for line in describe(have - want)]

if problems:
    print(f"check-upstream-rbac: {chart} RBAC drifts from upstream/ — update templates/rbac.yaml")
    print("\n".join(problems))
    sys.exit(1)
print(f"check-upstream-rbac: {chart} RBAC matches upstream/ ({len(upstream)} roles)")
PYEOF
