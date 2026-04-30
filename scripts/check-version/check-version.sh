#!/usr/bin/env bash
# Discover upstream version drift across every chart's upgrade.sh and
# (optionally) bump, validate, and open a PR per chart.
#
# Modes:
#   --check   report drift only (default; safe, no file/branch/PR changes)
#   --apply   for each drifted chart, run upgrade.sh + make bump + make ci,
#             create a branch + commit + push + open a PR
#
# By design, this script treats each chart's upgrade.sh as a black box and
# only relies on the standard CLI contract documented in
# scripts/upgrade-sync/templates/chart-appversion.sh:
#   --dry-run, --dry-run --json, --version <X.Y.Z>, --rollback, --list-backups
#
# Drift detection consumes the `--dry-run --json` record (schema:
# helm-charts.upgrade.dryrun.v1). See the "Dry-run JSON contract" section of
# scripts/check-version/README.md for the schema.
#
# Major version bumps are skipped by default (drift-only report) because
# they typically require manual review of breaking changes. Use
# --include-major to opt in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHARTS_DIR="$REPO_ROOT/charts"

# Defaults
MODE="check"            # check | apply
INCLUDE_MAJOR=false
NO_PR=false             # when true: build branch+commit locally, skip push and gh pr create
NO_CI=false             # when true: skip make ci (debug only)
OUTPUT="text"           # text | github (markdown for $GITHUB_STEP_SUMMARY)
INCLUDE_CHARTS=()
EXCLUDE_CHARTS=()
BRANCH_PREFIX="${BRANCH_PREFIX:-chore/auto-bump}"
BASE_BRANCH="${BASE_BRANCH:-main}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Detect upstream version drift across charts/*/upgrade.sh and (optionally)
open one PR per chart with the bump.

Options:
  --check                Report drift only (default; no changes).
  --apply                For each drifted chart, run upgrade.sh + make bump +
                         make ci, then push branch and open a PR.
  --chart <name>         Only process this chart. Repeatable.
  --skip-chart <name>    Exclude this chart. Repeatable.
  --include-major        Include major-version bumps in --apply (default: skip).
  --no-pr                Stop after local commit (no push, no gh pr create).
  --no-ci                Skip make ci (debug only).
  --output <text|github> Output format (github = markdown table for
                         GitHub Actions step summary). Default: text.
  -h, --help             Show this help.

Environment:
  BRANCH_PREFIX          Branch name prefix. Default: chore/auto-bump
  BASE_BRANCH            Base branch to diff against. Default: main
  GITHUB_TOKEN           Used by gh for PR creation (and by upgrade.sh for
                         GitHub-based version sources).

Examples:
  $(basename "$0")                            # Drift report for all charts
  $(basename "$0") --check --chart ghost      # Drift for one chart
  $(basename "$0") --apply --chart ghost --no-pr   # Local bump (no push)
  $(basename "$0") --apply                    # Bump + PR for every drifted chart
  $(basename "$0") --apply --include-major    # Include major bumps
EOF
}

# -----------------------------------------------
# Argument parsing
# -----------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)          MODE="check"; shift ;;
    --apply)          MODE="apply"; shift ;;
    --chart)
      [ -z "${2:-}" ] && { echo "ERROR: --chart requires a name" >&2; exit 1; }
      INCLUDE_CHARTS+=("$2"); shift 2 ;;
    --skip-chart)
      [ -z "${2:-}" ] && { echo "ERROR: --skip-chart requires a name" >&2; exit 1; }
      EXCLUDE_CHARTS+=("$2"); shift 2 ;;
    --include-major)  INCLUDE_MAJOR=true; shift ;;
    --no-pr)          NO_PR=true; shift ;;
    --no-ci)          NO_CI=true; shift ;;
    --output)
      [ -z "${2:-}" ] && { echo "ERROR: --output requires a value" >&2; exit 1; }
      case "$2" in text|github) OUTPUT="$2" ;; *) echo "ERROR: --output must be text or github" >&2; exit 1 ;; esac
      shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# -----------------------------------------------
# Helpers
# -----------------------------------------------

# Check whether $1 is in the array passed via $2 (var name).
contains() {
  local needle="$1" arr_name="$2"
  local -n arr_ref="$arr_name"
  local x
  for x in "${arr_ref[@]:-}"; do
    [ "$x" = "$needle" ] && return 0
  done
  return 1
}

# List charts that have an upgrade.sh, sorted, then apply --chart / --skip-chart filters.
discover_charts() {
  local found=()
  local d
  for d in "$CHARTS_DIR"/*/; do
    [ -f "${d}upgrade.sh" ] || continue
    found+=("$(basename "$d")")
  done

  local c kept=()
  for c in "${found[@]}"; do
    if [ "${#INCLUDE_CHARTS[@]}" -gt 0 ]; then
      contains "$c" INCLUDE_CHARTS || continue
    fi
    if [ "${#EXCLUDE_CHARTS[@]}" -gt 0 ]; then
      contains "$c" EXCLUDE_CHARTS && continue
    fi
    kept+=("$c")
  done
  printf '%s\n' "${kept[@]}"
}

# Read top-level appVersion from a chart's Chart.yaml.
read_app_version() {
  local chart="$1"
  awk '/^appVersion:/ { gsub(/["\047]/, "", $2); print $2; exit }' "$CHARTS_DIR/$chart/Chart.yaml"
}

# Read top-level Chart.yaml `version` (chart SemVer, NOT appVersion).
read_chart_version() {
  local chart="$1"
  awk '/^version:/ { gsub(/["\047]/, "", $2); print $2; exit }' "$CHARTS_DIR/$chart/Chart.yaml"
}

# True if $1 (current) and $2 (latest) differ in major version.
is_major_bump() {
  local cur="$1" new="$2"
  [ -z "$cur" ] || [ -z "$new" ] && return 1
  [ "${cur%%.*}" != "${new%%.*}" ]
}

# Parse upgrade.sh --dry-run --json output (schema:
# helm-charts.upgrade.dryrun.v1) into a TAB-separated record:
#   <status>\t<current>\t<latest>\t<upstream>\t<major>\t<sibling>\t<error>
# where <major> is "yes" or "no", and any null/missing fields are empty
# strings. Emits nothing and exits non-zero on parse failure.
parse_dry_run_json() {
  # Pass the script via -c so python3's stdin stays attached to the pipe
  # (a here-doc would shadow the upstream JSON). Fields are joined with
  # \x01 (non-whitespace) so `IFS=$'\x01' read` preserves empty fields —
  # \t collapses consecutive empties when used as IFS.
  python3 -c '
import json, sys
try:
    doc = json.loads(sys.stdin.read())
except Exception as e:
    sys.stderr.write(f"JSON parse error: {e}\n")
    sys.exit(1)
schema = doc.get("schema", "")
if not schema.startswith("helm-charts.upgrade.dryrun."):
    sys.stderr.write(f"unexpected schema: {schema}\n")
    sys.exit(1)
sib = (doc.get("sibling") or {}).get("name") or ""
fields = [
    doc.get("status") or "",
    doc.get("current") or "",
    doc.get("latest") or "",
    doc.get("upstream_latest") or "",
    "yes" if doc.get("major_bump") else "no",
    sib,
    doc.get("error") or "",
]
print("\x01".join(fields))
'
}

# Working tree must be clean before --apply touches anything.
ensure_clean_tree() {
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
    echo "ERROR: working tree is dirty. Commit or stash before running --apply." >&2
    git -C "$REPO_ROOT" status --short >&2
    exit 1
  fi
}

# Reset a single chart directory to HEAD (used after a failed make ci).
restore_chart() {
  local chart="$1"
  git -C "$REPO_ROOT" checkout -- "charts/$chart" 2>/dev/null || true
  git -C "$REPO_ROOT" clean -fd "charts/$chart" 2>/dev/null || true
}

# Switch back to BASE_BRANCH (used between charts in --apply mode).
checkout_base() {
  git -C "$REPO_ROOT" checkout "$BASE_BRANCH" >/dev/null 2>&1 || {
    echo "ERROR: failed to checkout $BASE_BRANCH" >&2
    exit 1
  }
}

# -----------------------------------------------
# Per-chart processing
# -----------------------------------------------

# Globals populated per chart for reporting.
declare -a RESULTS=()  # one entry per processed chart, tab-separated:
                       # name<TAB>current<TAB>latest<TAB>major<TAB>status<TAB>detail

record_result() {
  RESULTS+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"$'\t'"$6")
}

# Run upgrade.sh --dry-run --json for a chart, print drift info (or
# "uptodate"). stdout: one of:
#   uptodate
#   drift <current> <latest>
#   blocked <current> <upstream-latest> <sibling-name>
#   no-image <current> <upstream-latest>
#   error <message>
#
# The output line format (legacy, consumed by process_chart) is preserved
# verbatim across the JSON migration. The semantic mapping is:
#   JSON status=uptodate          -> uptodate
#   JSON status=drift             -> drift current latest
#   JSON status=blocked           -> blocked current upstream_latest sibling.name
#   JSON status=no-image          -> no-image current upstream_latest
#   JSON status=error             -> error <upgrade.sh's error message>
detect_drift() {
  local chart="$1"
  local raw json_record status current latest upstream major sibling err

  # Capture the JSON line on stdout regardless of exit code — upgrade.sh
  # exits non-zero on `blocked` / `no-image-exhausted`, but the EXIT trap
  # has already emitted the JSON record. `|| true` shields us from
  # `set -euo pipefail` so the pipe-failure exit doesn't blow away the
  # captured payload.
  raw=$(cd "$CHARTS_DIR/$chart" && bash ./upgrade.sh --dry-run --json 2>/dev/null || true)
  if [ -z "$raw" ]; then
    echo "error empty stdout from upgrade.sh --dry-run --json"
    return 0
  fi
  json_record=$(printf '%s' "$raw" | parse_dry_run_json) || {
    echo "error could not parse upgrade.sh --dry-run --json output (schema mismatch)"
    return 0
  }

  IFS=$'\x01' read -r status current latest upstream major sibling err <<< "$json_record"

  case "$status" in
    uptodate)
      echo "uptodate"
      ;;
    drift)
      echo "drift ${current:-?} ${latest:-?}"
      ;;
    blocked)
      # `latest` is null in the JSON record (no bump can happen); the third
      # field of the legacy line is the version that was attempted, which is
      # what `upstream_latest` carries.
      echo "blocked ${current:-?} ${upstream:-?} ${sibling:-sibling}"
      ;;
    no-image)
      echo "no-image ${current:-?} ${upstream:-?}"
      ;;
    error|*)
      echo "error ${err:-unknown error from upgrade.sh}"
      ;;
  esac
  return 0
}

# Extract the topmost section from a chart's CHANGELOG.md (from the first
# `## [vX.Y.Z]` heading up to, but not including, the next `## [` heading).
# This is the section `make changelog` just prepended.
extract_changelog_top_section() {
  local changelog_path="$1"
  [ -f "$changelog_path" ] || return 0
  awk '/^## \[/ { n++; if (n > 1) exit } n == 1 { print }' "$changelog_path"
}

# Build a PR body for an auto-bump.
build_pr_body() {
  local chart="$1" current="$2" latest="$3" chart_ver_before="$4" chart_ver_after="$5"
  local changelog_section changelog_block=""
  changelog_section=$(extract_changelog_top_section "$CHARTS_DIR/$chart/CHANGELOG.md")
  if [ -n "$changelog_section" ]; then
    changelog_block="

## Changes (from CHANGELOG.md)

$changelog_section"
  fi

  cat <<EOF
## Summary

Automated upstream bump for \`$chart\`: \`appVersion\` $current -> $latest.

Generated by \`scripts/check-version/check-version.sh\`.

## Affected charts

- \`$chart\`$changelog_block

## Type of change

- [x] Chart update (templates, values, schema)

## Checklist

- [x] Bumped \`version\` in \`Chart.yaml\` per SemVer ($chart_ver_before -> $chart_ver_after)
- [x] Added an entry under \`artifacthub.io/changes\` in \`Chart.yaml\` (handled by upgrade.sh)
- [x] Updated \`charts/$chart/CHANGELOG.md\` (handled by \`make changelog\`)
- [x] \`make lint\`, \`make ct-lint\`, \`make template\`, \`make validate\` (\`make ci\`) ran in the workflow before this PR was opened
- [ ] Reviewer to verify the bump matches upstream release notes

## Additional context

- Source: \`charts/$chart/upgrade.sh --version $latest\`
- Branch will be deleted automatically when this PR is merged or closed.
EOF
}

process_chart() {
  local chart="$1" idx="$2" total="$3"
  local upgrade_sh="$CHARTS_DIR/$chart/upgrade.sh"
  local current latest line major

  echo ""
  echo "[$idx/$total] $chart"

  if [ ! -x "$upgrade_sh" ] && [ ! -f "$upgrade_sh" ]; then
    echo "  ERROR: upgrade.sh not found"
    record_result "$chart" "?" "?" "?" "error" "no upgrade.sh"
    return 0
  fi

  line=$(detect_drift "$chart")
  case "$line" in
    uptodate)
      current=$(read_app_version "$chart")
      echo "  Already up to date ($current)"
      record_result "$chart" "$current" "$current" "no" "uptodate" "-"
      return 0
      ;;
    error\ *)
      echo "  ERROR: ${line#error }"
      current=$(read_app_version "$chart")
      record_result "$chart" "$current" "?" "?" "error" "${line#error }"
      return 0
      ;;
    blocked\ *)
      # shellcheck disable=SC2086
      set -- $line
      current="$2"; latest="$3"; local sibling="$4"
      echo "  BLOCKED: bump $sibling to $latest first"
      record_result "$chart" "$current" "$latest" "no" "blocked" "waiting on $sibling"
      return 0
      ;;
    no-image\ *)
      # shellcheck disable=SC2086
      set -- $line
      current="$2"; latest="$3"
      echo "  NO-IMAGE: upstream feed shows $latest but no published container image yet"
      record_result "$chart" "$current" "$latest" "no" "no-image" "image not published yet"
      return 0
      ;;
    drift\ *)
      # shellcheck disable=SC2086
      set -- $line
      current="$2"; latest="$3"
      ;;
  esac

  if is_major_bump "$current" "$latest"; then
    major="yes"
  else
    major="no"
  fi

  echo "  Current: $current"
  echo "  Latest:  $latest"
  echo "  Major:   $major"

  if [ "$MODE" = "check" ]; then
    if [ "$major" = "yes" ]; then
      record_result "$chart" "$current" "$latest" "$major" "drift-major" "manual review needed"
    else
      record_result "$chart" "$current" "$latest" "$major" "drift" "would bump"
    fi
    return 0
  fi

  # MODE=apply
  if [ "$major" = "yes" ] && ! $INCLUDE_MAJOR; then
    echo "  SKIP: major bump (use --include-major to opt in)"
    record_result "$chart" "$current" "$latest" "$major" "drift-major" "skipped (major)"
    return 0
  fi

  apply_chart_bump "$chart" "$current" "$latest" "$major"
}

apply_chart_bump() {
  local chart="$1" current="$2" latest="$3" major="$4"
  local branch="$BRANCH_PREFIX/$chart-$latest"
  local chart_ver_before chart_ver_after

  # Preflight: branch already exists locally or on origin.
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "  SKIP: local branch $branch already exists"
    record_result "$chart" "$current" "$latest" "$major" "skipped" "branch exists locally"
    return 0
  fi
  if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "  SKIP: remote branch $branch already exists"
    record_result "$chart" "$current" "$latest" "$major" "skipped" "branch exists on origin"
    return 0
  fi

  # All work happens on the new branch off of BASE_BRANCH.
  if ! git -C "$REPO_ROOT" checkout -b "$branch" "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "  ERROR: failed to create branch $branch"
    record_result "$chart" "$current" "$latest" "$major" "error" "git checkout -b failed"
    return 0
  fi

  # Run upgrade.sh with explicit --version to avoid interactive image-not-found prompts.
  echo "  Running upgrade.sh --version $latest..."
  if ! (cd "$CHARTS_DIR/$chart" && bash ./upgrade.sh --version "$latest"); then
    echo "  ERROR: upgrade.sh failed"
    restore_chart "$chart"
    git -C "$REPO_ROOT" checkout "$BASE_BRANCH" >/dev/null 2>&1
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    record_result "$chart" "$current" "$latest" "$major" "error" "upgrade.sh failed"
    return 0
  fi

  chart_ver_before=$(read_chart_version "$chart")

  echo "  Running make bump CHART=$chart LEVEL=patch..."
  if ! make -C "$REPO_ROOT" bump CHART="$chart" LEVEL=patch >/dev/null; then
    echo "  ERROR: make bump failed"
    restore_chart "$chart"
    checkout_base
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    record_result "$chart" "$current" "$latest" "$major" "error" "make bump failed"
    return 0
  fi
  chart_ver_after=$(read_chart_version "$chart")

  if ! $NO_CI; then
    echo "  Running make ci CHART=$chart..."
    if ! make -C "$REPO_ROOT" ci CHART="$chart" >/dev/null 2>&1; then
      echo "  ERROR: make ci failed"
      restore_chart "$chart"
      checkout_base
      git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
      record_result "$chart" "$current" "$latest" "$major" "error" "make ci failed (rolled back)"
      return 0
    fi
  fi

  # Materialize the per-chart CHANGELOG.md from Chart.yaml's freshly-updated
  # artifacthub.io/changes annotation. upgrade.sh has already appended a
  # `Bump appVersion from <old> to <new>` entry, so make changelog is purely
  # a render step (and is idempotent — it skips if the new version section
  # already exists, which keeps re-runs safe).
  echo "  Running make changelog CHART=$chart..."
  if ! make -C "$REPO_ROOT" changelog CHART="$chart"; then
    echo "  ERROR: make changelog failed"
    restore_chart "$chart"
    checkout_base
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    record_result "$chart" "$current" "$latest" "$major" "error" "make changelog failed (rolled back)"
    return 0
  fi

  echo "  Committing..."
  git -C "$REPO_ROOT" add "charts/$chart"
  if ! git -C "$REPO_ROOT" diff --cached --quiet; then
    git -C "$REPO_ROOT" commit -m "feat($chart): bump appVersion to $latest" >/dev/null
  else
    echo "  WARNING: no staged changes after upgrade.sh + make bump (unexpected)"
    checkout_base
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    record_result "$chart" "$current" "$latest" "$major" "skipped" "no diff after bump"
    return 0
  fi

  if $NO_PR; then
    echo "  Stopped before push (--no-pr). Branch: $branch"
    checkout_base
    record_result "$chart" "$current" "$latest" "$major" "local-only" "branch=$branch (no push)"
    return 0
  fi

  echo "  Pushing branch $branch..."
  if ! git -C "$REPO_ROOT" push -u origin "$branch" >/dev/null 2>&1; then
    echo "  ERROR: git push failed"
    checkout_base
    record_result "$chart" "$current" "$latest" "$major" "error" "git push failed (branch kept locally)"
    return 0
  fi

  echo "  Opening PR..."
  local pr_body pr_url
  pr_body=$(build_pr_body "$chart" "$current" "$latest" "$chart_ver_before" "$chart_ver_after")
  # Best-effort label creation; ignore failures (label may already exist or perms missing).
  gh -R "$(gh_repo)" label create "auto-bump"  --color "ededed" --description "Automated upstream version bump"  >/dev/null 2>&1 || true
  gh -R "$(gh_repo)" label create "$chart"     --color "0e8a16" --description "Affects chart $chart"             >/dev/null 2>&1 || true
  if [ "$major" = "yes" ]; then
    gh -R "$(gh_repo)" label create "major-bump" --color "b60205" --description "Major version bump (review breaking changes)" >/dev/null 2>&1 || true
  fi

  local label_args=(--label "auto-bump" --label "$chart")
  [ "$major" = "yes" ] && label_args+=(--label "major-bump")

  if pr_url=$(gh pr create \
        --base "$BASE_BRANCH" \
        --head "$branch" \
        --title "feat($chart): bump appVersion to $latest" \
        --body "$pr_body" \
        "${label_args[@]}" 2>&1); then
    echo "  PR: $pr_url"
    record_result "$chart" "$current" "$latest" "$major" "pr-created" "$pr_url"
  else
    echo "  ERROR: gh pr create failed: $pr_url"
    record_result "$chart" "$current" "$latest" "$major" "error" "gh pr create failed (branch pushed)"
  fi

  checkout_base
}

# Best-effort detection of the GitHub repo (owner/name) for gh.
gh_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
    return
  fi
  git -C "$REPO_ROOT" config --get remote.origin.url \
    | sed -E 's#(git@[^:]+:|https://[^/]+/)([^/]+/[^/.]+)(\.git)?#\2#'
}

# -----------------------------------------------
# Reporting
# -----------------------------------------------
print_text_summary() {
  local total=0 uptodate=0 drift=0 drift_major=0 prs=0 local_only=0 errors=0 skipped=0 blocked=0 no_image=0
  echo ""
  echo "================================================"
  echo " Summary"
  echo "================================================"
  printf "  %-22s %-10s %-10s %-6s %-12s %s\n" "CHART" "CURRENT" "LATEST" "MAJOR" "STATUS" "DETAIL"
  printf "  %-22s %-10s %-10s %-6s %-12s %s\n" "----------------------" "----------" "----------" "------" "------------" "------"
  local row name cur lat maj st det
  for row in "${RESULTS[@]}"; do
    IFS=$'\t' read -r name cur lat maj st det <<< "$row"
    printf "  %-22s %-10s %-10s %-6s %-12s %s\n" "$name" "$cur" "$lat" "$maj" "$st" "$det"
    total=$((total+1))
    case "$st" in
      uptodate)    uptodate=$((uptodate+1)) ;;
      drift)       drift=$((drift+1)) ;;
      drift-major) drift_major=$((drift_major+1)) ;;
      pr-created)  prs=$((prs+1)) ;;
      local-only)  local_only=$((local_only+1)) ;;
      skipped)     skipped=$((skipped+1)) ;;
      blocked)     blocked=$((blocked+1)) ;;
      no-image)    no_image=$((no_image+1)) ;;
      error)       errors=$((errors+1)) ;;
    esac
  done
  echo ""
  printf "  Total: %d  |  up-to-date: %d  drift: %d  major-skipped: %d  PR: %d  local-only: %d  blocked: %d  no-image: %d  skipped: %d  errors: %d\n" \
    "$total" "$uptodate" "$drift" "$drift_major" "$prs" "$local_only" "$blocked" "$no_image" "$skipped" "$errors"
}

print_github_summary() {
  local out_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  {
    echo "## Helm Charts Auto-Version Check"
    echo ""
    echo "Mode: \`$MODE\` | Charts processed: ${#RESULTS[@]} | Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "| Chart | Current | Latest | Major | Status | Detail |"
    echo "|-------|---------|--------|-------|--------|--------|"
    local row name cur lat maj st det
    for row in "${RESULTS[@]}"; do
      IFS=$'\t' read -r name cur lat maj st det <<< "$row"
      echo "| \`$name\` | \`$cur\` | \`$lat\` | $maj | $st | $det |"
    done
  } >> "$out_file"
}

# -----------------------------------------------
# Main
# -----------------------------------------------
echo "================================================"
echo " Helm Charts Auto-Version Check"
echo " Mode: $MODE  |  Repo: $REPO_ROOT"
[ "${#INCLUDE_CHARTS[@]}" -gt 0 ] && echo " Filter: --chart ${INCLUDE_CHARTS[*]}"
[ "${#EXCLUDE_CHARTS[@]}" -gt 0 ] && echo " Filter: --skip-chart ${EXCLUDE_CHARTS[*]}"
$INCLUDE_MAJOR && echo " Major bumps: included"
$NO_PR && echo " --no-pr: stopping after local commit"
$NO_CI && echo " --no-ci: skipping make ci"
echo "================================================"

# Discover and validate charts list.
mapfile -t CHARTS < <(discover_charts)
if [ "${#CHARTS[@]}" -eq 0 ]; then
  echo ""
  echo "No charts to process (after filters). Exiting."
  exit 0
fi
echo ""
echo "Charts to process: ${CHARTS[*]}"

# Apply mode requires a clean tree and being on BASE_BRANCH.
if [ "$MODE" = "apply" ]; then
  ensure_clean_tree
  current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  if [ "$current_branch" != "$BASE_BRANCH" ]; then
    echo "ERROR: must be on $BASE_BRANCH to run --apply (currently on $current_branch)" >&2
    exit 1
  fi
  if ! $NO_PR && ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found; install it or use --no-pr" >&2
    exit 1
  fi
fi

# Process each chart sequentially.
total="${#CHARTS[@]}"
i=0
for chart in "${CHARTS[@]}"; do
  i=$((i+1))
  process_chart "$chart" "$i" "$total"
done

# Output summary in the requested format.
case "$OUTPUT" in
  text)   print_text_summary ;;
  github) print_text_summary; print_github_summary ;;
esac

# Exit non-zero if any chart errored, so CI surfaces the failure.
for row in "${RESULTS[@]}"; do
  IFS=$'\t' read -r _name _cur _lat _maj st _det <<< "$row"
  if [ "$st" = "error" ]; then
    exit 2
  fi
done
exit 0
