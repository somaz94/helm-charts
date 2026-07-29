#!/usr/bin/env bash
# check-skips.sh — turn kubeconform's silent skips into a hard failure.
#
# `make validate` runs kubeconform with -ignore-missing-schemas so that a chart
# emitting a CR whose schema is not published does not break the whole run. The
# cost is that such a resource is reported `statusSkipped` and the exit code
# stays 0 — the CR ships unvalidated and the summary still reads green. As the
# collection's `-cr` charts grow, every new CR kind missing from the datree
# catalog would join that blind spot invisibly.
#
# This script reads kubeconform's `-output json -verbose` payload on stdin,
# prints the per-chart summary that `-summary` used to print, and fails when a
# resource is invalid OR skipped without a matching declaration in
# scripts/validate/allowed-skips.txt.
#
# Usage:
#   <kubeconform ... -output json -verbose> | check-skips.sh <chart> [<allowlist>]
#
#   <chart>      chart directory name, matched against the allowlist's first field
#   <allowlist>  defaults to scripts/validate/allowed-skips.txt
#
# Exit codes:
#   0  every resource valid, or skipped-and-declared
#   1  an invalid resource, or a skip with no declaration
#
# Parses only kubeconform JSON — no YAML, no PyYAML, no network. Safe for CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$REPO_ROOT/scripts/lib/common.sh"

CHART="${1:-}"
ALLOWLIST="${2:-$SCRIPT_DIR/allowed-skips.txt}"

[ -n "$CHART" ] || die "usage: check-skips.sh <chart> [<allowlist>]"
[ -f "$ALLOWLIST" ] || die "allowlist not found: $ALLOWLIST"

require_command python3

# Pass the script via -c so python3's stdin stays attached to the pipe
# (a here-doc would shadow the kubeconform JSON — same trap documented in
# scripts/check-version/check-version.sh). Arguments follow the -c body and
# arrive as sys.argv[1:]. The body therefore uses double quotes throughout.
python3 -c '
import json, sys

chart, allowlist_path = sys.argv[1], sys.argv[2]

# (chart, apiVersion, Kind) triples; chart may be "*" to cover every chart.
allowed = set()
with open(allowlist_path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) != 3:
            sys.exit("ERROR: {}:{}: expected 3 fields, got {}: {!r}".format(
                allowlist_path, lineno, len(fields), line))
        allowed.add(tuple(fields))

try:
    payload = json.loads(sys.stdin.read())
except Exception as exc:
    sys.exit("ERROR: {}: could not parse kubeconform JSON output: {}".format(chart, exc))

resources = payload.get("resources") or []
counts = {}
problems = []
undeclared = 0
# Group undeclared skips by (kind, apiVersion) -- a chart emitting N copies of
# one unschema-d kind is a single thing to fix, not N identical error blocks.
undeclared_kinds = {}

for res in resources:
    status = res.get("status") or "unknown"
    counts[status] = counts.get(status, 0) + 1
    kind = res.get("kind") or "?"
    version = res.get("version") or "?"

    if status == "statusSkipped":
        if (chart, version, kind) in allowed or ("*", version, kind) in allowed:
            continue
        undeclared += 1
        undeclared_kinds[(kind, version)] = undeclared_kinds.get((kind, version), 0) + 1
    elif status in ("statusInvalid", "statusError"):
        problems.append("{}: {} ({}) -- {}".format(
            status[len("status"):].lower(), kind, version, res.get("msg") or "no message"))

for (kind, version), n in sorted(undeclared_kinds.items()):
    tally = "" if n == 1 else " x{}".format(n)
    problems.append(
        "undeclared skip: {} ({}){}\n".format(kind, version, tally)
        + "      no schema resolved, so this resource was NOT validated.\n"
        + "      fix: scripts/validate/vendor-crd-schema.sh <upstream-crd-url>\n"
        + "      or, if no schema is obtainable, declare it in\n"
        + "      scripts/validate/allowed-skips.txt with a `# why:` note."
    )

valid = counts.get("statusValid", 0)
skipped = counts.get("statusSkipped", 0)
invalid = counts.get("statusInvalid", 0) + counts.get("statusError", 0)

summary = "    {} resources -- valid {}, invalid {}, skipped {}".format(
    len(resources), valid, invalid, skipped)
declared = skipped - undeclared
if declared:
    summary += " ({} declared)".format(declared)
print(summary, file=sys.stderr)

for p in problems:
    print("    ERROR: " + p, file=sys.stderr)
if problems:
    sys.exit(1)
' "$CHART" "$ALLOWLIST"
