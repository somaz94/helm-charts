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
#   sync.sh --list          list every managed chart and its template
#   sync.sh --status        list every chart, including charts that are
#                           unmanaged (no header) or whose declared template
#                           does not exist on disk

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
Usage: $(basename "$0") [--check|--apply [--force]|--list|--status]

Propagates the canonical upgrade.sh body from
  scripts/upgrade-sync/templates/<NAME>.sh
to every chart whose upgrade.sh declares
  # upgrade-template: <NAME>

Commands:
  --check    Report drift; exits 1 when any chart body differs from template
  --apply    Rewrite canonical-body region of each chart's upgrade.sh to match.
             Refuses to run when the working tree is dirty.
    --force  Skip the dirty-tree guard (CI / clean-checkout use only)
  --list     List managed charts (header present + template file exists)
  --status   List every chart with one of the following classifications:
               managed              header present, template file exists
               unmanaged-no-header  upgrade.sh exists, no header (intentional opt-out)
               missing-template     header references a template that does not
                                    exist on disk -> warning, exit 1 from --check
  -h, --help Show this help
EOF
  exit 0
}

# Read the "# upgrade-template: <name>" header. Stdout: template name, or
# empty string when no header is present.
read_template_header() {
  grep -m1 '^# upgrade-template:' "$1" 2>/dev/null \
    | awk -F': ' '{print $2}' \
    | awk '{print $1}'
}

# Yield every charts/*/upgrade.sh as one tab-separated record:
#   <script-path>\t<status>\t<tmpl-or-empty>
# where <status> is one of: managed, unmanaged-no-header, missing-template.
classify_all_charts() {
  while IFS= read -r script; do
    local tmpl
    tmpl=$(read_template_header "$script")
    if [ -z "$tmpl" ]; then
      printf '%s\t%s\t\n' "$script" "unmanaged-no-header"
    elif [ -f "$TEMPLATES_DIR/$tmpl.sh" ]; then
      printf '%s\t%s\t%s\n' "$script" "managed" "$tmpl"
    else
      printf '%s\t%s\t%s\n' "$script" "missing-template" "$tmpl"
    fi
  done < <(find "$CHARTS_DIR" -mindepth 2 -maxdepth 2 -name 'upgrade.sh' | sort)
}

# Yield only managed charts (legacy interface used by check_or_apply):
#   <script-path>\t<tmpl>
find_charts_with_template() {
  classify_all_charts | awk -F'\t' '$2 == "managed" { printf "%s\t%s\n", $1, $3 }'
}

# Print stderr warnings for charts whose declared template does not exist.
# Returns the count of such charts (via the global MISSING_TEMPLATE_COUNT).
MISSING_TEMPLATE_COUNT=0
warn_missing_templates() {
  MISSING_TEMPLATE_COUNT=0
  while IFS=$'\t' read -r script status tmpl; do
    if [ "$status" = "missing-template" ]; then
      MISSING_TEMPLATE_COUNT=$((MISSING_TEMPLATE_COUNT + 1))
      echo "WARNING: ${script#$REPO_ROOT/} declares template '$tmpl' but $TEMPLATES_DIR/$tmpl.sh does not exist." >&2
    fi
  done < <(classify_all_charts)
  if [ "$MISSING_TEMPLATE_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "These charts are silently skipped by --check/--apply. Either add the missing template, remove the header, or fix the typo." >&2
    echo "" >&2
  fi
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

# Wide listing covering every charts/*/upgrade.sh, including unmanaged ones.
# Used by --status. Body sameness is computed only for managed charts.
print_status() {
  local managed=0 unmanaged=0 missing=0 drift=0
  printf "  %-50s %-20s %s\n" "CHART" "STATUS" "TEMPLATE / NOTE"
  while IFS=$'\t' read -r script st tmpl; do
    case "$st" in
      managed)
        managed=$((managed + 1))
        local tmpl_file="$TEMPLATES_DIR/$tmpl.sh" body_tmp tmpl_tmp
        body_tmp=$(mktemp_tracked)
        tmpl_tmp=$(mktemp_tracked)
        extract_body < "$script" > "$body_tmp"
        extract_body < "$tmpl_file" > "$tmpl_tmp"
        local sub="in sync"
        if ! diff -q "$body_tmp" "$tmpl_tmp" >/dev/null 2>&1; then
          sub="DRIFT"
          drift=$((drift + 1))
        fi
        printf "  %-50s %-20s template=%s (%s)\n" "${script#$REPO_ROOT/}" "managed" "$tmpl" "$sub"
        ;;
      missing-template)
        missing=$((missing + 1))
        printf "  %-50s %-20s template=%s NOT FOUND\n" "${script#$REPO_ROOT/}" "missing-template" "$tmpl"
        ;;
      unmanaged-no-header)
        unmanaged=$((unmanaged + 1))
        printf "  %-50s %-20s %s\n" "${script#$REPO_ROOT/}" "unmanaged-no-header" "(no '# upgrade-template:' header)"
        ;;
    esac
  done < <(classify_all_charts)
  echo ""
  echo "Summary: $managed managed ($drift drift), $unmanaged unmanaged-no-header, $missing missing-template."
  if [ "$missing" -gt 0 ]; then
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
    --status)  MODE="status"; shift ;;
    --force)   FORCE=1; shift ;;
    *) echo "Unknown option: $1"; echo; usage ;;
  esac
done

if [ "$MODE" = "apply" ]; then
  ensure_clean_tree "$FORCE"
fi

# For --status, the dedicated wide listing both classifies and warns about
# missing templates inline. For other modes, surface the warnings before the
# regular run so silent skips become visible.
if [ "$MODE" != "status" ]; then
  warn_missing_templates
fi

case "$MODE" in
  status)
    print_status
    ;;
  *)
    rc=0
    check_or_apply "$MODE" || rc=$?
    # Missing-template warnings escalate --check to a non-zero exit so CI
    # surfaces the silent-skip case. --list / --apply only warn.
    if [ "$MODE" = "check" ] && [ "$MISSING_TEMPLATE_COUNT" -gt 0 ] && [ "$rc" -eq 0 ]; then
      rc=1
    fi
    exit "$rc"
    ;;
esac
