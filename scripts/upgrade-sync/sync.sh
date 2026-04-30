#!/usr/bin/env bash
# Propagate the canonical upgrade.sh body from templates/ to each chart's
# upgrade.sh. Inspired by (but not code-shared with) the
# `# upgrade-template: <name>` convention in
# `somaz94/kuberntes-infra/scripts/upgrade-sync/`. See README.md for the
# differences between the two systems.
#
# Each chart's upgrade.sh declares its template on the second line:
#   #!/bin/bash
#   # upgrade-template: chart-appversion
#   ...
#   # === BEGIN CANONICAL BODY ===
#   (body — synced)
#   # === END CANONICAL BODY ===
#
# This script only touches the region between BEGIN/END markers. The
# per-chart Configuration block above BEGIN is left untouched.
#
# Usage:
#   sync.sh --check         report charts that drift from their template (exit 1 on drift)
#   sync.sh --apply [--force]
#                           overwrite canonical-body regions to match templates;
#                           refuses to run when the working tree is dirty
#                           (use --force to override at your own risk)
#   sync.sh --list          list every chart and its template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
CHARTS_DIR="$REPO_ROOT/charts"
BEGIN_MARKER="# === BEGIN CANONICAL BODY ==="
END_MARKER="# === END CANONICAL BODY ==="

# All temp files allocated by this run; cleaned up on EXIT (success or error).
TMP_FILES=()
cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [ -n "$f" ] && rm -f "$f"
  done
  return 0
}
trap cleanup_tmp EXIT

mktemp_tracked() {
  local f
  f=$(mktemp)
  TMP_FILES+=("$f")
  printf '%s' "$f"
}

# Refuse `--apply` when the working tree contains uncommitted changes that
# touch files this script will rewrite (charts/*/upgrade.sh). `--force`
# overrides; intended only for `make sync-apply` invocations following a
# clean checkout in CI.
ensure_clean_tree() {
  local force="$1"
  [ "$force" = "1" ] && return 0
  if ! command -v git >/dev/null 2>&1; then
    return 0  # Not a git checkout, nothing to guard.
  fi
  local dirty
  dirty=$(git -C "$REPO_ROOT" status --porcelain -- 'charts/*/upgrade.sh' 2>/dev/null || true)
  if [ -n "$dirty" ]; then
    echo "ERROR: working tree has uncommitted changes to charts/*/upgrade.sh:" >&2
    printf '%s\n' "$dirty" >&2
    echo "" >&2
    echo "Commit or stash before --apply, or pass --force to override." >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check|--apply [--force]|--list]

Propagates the canonical upgrade.sh body from
  scripts/upgrade-sync/templates/<NAME>.sh
to every chart whose upgrade.sh declares
  # upgrade-template: <NAME>

Commands:
  --check    Report drift; exits 1 when any chart body differs from template
  --apply    Rewrite canonical-body region of each chart's upgrade.sh to match.
             Refuses to run when the working tree is dirty.
    --force  Skip the dirty-tree guard (CI / clean-checkout use only)
  --list     List detected charts, their template, and whether they are in sync
  -h, --help Show this help
EOF
  exit 0
}

find_charts_with_template() {
  while IFS= read -r script; do
    local tmpl
    tmpl=$(grep -m1 '^# upgrade-template:' "$script" | awk -F': ' '{print $2}' | awk '{print $1}')
    if [ -n "$tmpl" ] && [ -f "$TEMPLATES_DIR/$tmpl.sh" ]; then
      printf '%s\t%s\n' "$script" "$tmpl"
    fi
  done < <(find "$CHARTS_DIR" -mindepth 2 -maxdepth 2 -name 'upgrade.sh' | sort)
}

extract_body() {
  # Stdin: whole file. Stdout: lines strictly between BEGIN and END markers.
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 ~ begin { inside=1; next }
    $0 ~ end   { inside=0; next }
    inside     { print }
  '
}

replace_body() {
  local script="$1"
  local body_file="$2"
  local tmp
  tmp=$(mktemp_tracked)
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v bodyfile="$body_file" '
    BEGIN { inside=0; injected=0 }
    {
      if ($0 ~ begin) {
        print
        while ((getline line < bodyfile) > 0) print line
        close(bodyfile)
        inside=1
        injected=1
        next
      }
      if ($0 ~ end) {
        print
        inside=0
        next
      }
      if (!inside) print
    }
    END { if (!injected) exit 2 }
  ' "$script" > "$tmp" || { echo "  ERROR: BEGIN/END markers not found in $script"; return 1; }
  mv "$tmp" "$script"
  chmod +x "$script"
}

check_or_apply() {
  local mode="$1"     # check | apply | list
  local drift=0
  local applied=0
  local count=0

  while IFS=$'\t' read -r script tmpl; do
    count=$((count + 1))
    local tmpl_file="$TEMPLATES_DIR/$tmpl.sh"
    local script_body_tmp tmpl_body_tmp
    script_body_tmp=$(mktemp_tracked)
    tmpl_body_tmp=$(mktemp_tracked)
    extract_body < "$script" > "$script_body_tmp"
    extract_body < "$tmpl_file" > "$tmpl_body_tmp"

    local status="in sync"
    if ! diff -q "$script_body_tmp" "$tmpl_body_tmp" >/dev/null 2>&1; then
      status="DRIFT"
      drift=$((drift + 1))
    fi

    case "$mode" in
      list)
        printf "  %-50s template=%-20s %s\n" "${script#$REPO_ROOT/}" "$tmpl" "$status"
        ;;
      check)
        if [ "$status" = "DRIFT" ]; then
          echo "DRIFT: ${script#$REPO_ROOT/}"
          diff -u "$script_body_tmp" "$tmpl_body_tmp" | head -40 || true
          echo ""
        fi
        ;;
      apply)
        if [ "$status" = "DRIFT" ]; then
          echo "Applying canonical body to ${script#$REPO_ROOT/} (template: $tmpl)"
          replace_body "$script" "$tmpl_body_tmp"
          applied=$((applied + 1))
        fi
        ;;
    esac
  done < <(find_charts_with_template)

  echo ""
  case "$mode" in
    list|check) echo "Summary: $count chart(s) using templates, $drift drift." ;;
    apply)      echo "Summary: $count chart(s) using templates, $applied body/bodies updated." ;;
  esac

  if [ "$mode" = "check" ] && [ "$drift" -gt 0 ]; then
    echo "Run: scripts/upgrade-sync/sync.sh --apply"
    return 1
  fi
  return 0
}

FORCE=0
MODE="list"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --list)    MODE="list"; shift ;;
    --check)   MODE="check"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --force)   FORCE=1; shift ;;
    *) echo "Unknown option: $1"; echo; usage ;;
  esac
done

if [ "$MODE" = "apply" ]; then
  ensure_clean_tree "$FORCE"
fi

check_or_apply "$MODE"
