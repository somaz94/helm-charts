#!/usr/bin/env bash
# CANONICAL TEMPLATE — do not run directly, and do not hand-edit the body
# of a per-chart upgrade.sh that uses this template.
#
# Purpose: as a chart maintainer, track the latest upstream GA version of
# a component (image / release) and bump Chart.yaml `appVersion`, plus
# optionally `values.yaml.<VERSION_KEY>`. File-level only — no cluster.
#
# The body below (everything between the BEGIN/END CANONICAL BODY markers)
# is the source of truth propagated to per-chart `upgrade.sh` files via
#   scripts/upgrade-sync/sync.sh --apply
# Each chart's upgrade.sh keeps its own Configuration block above the BEGIN
# marker and receives the same body.
#
# Supported VERSION_SOURCE values and the repo/owner fed through
# VERSION_SOURCE_ARG:
#   elastic-artifacts    (no arg; uses artifacts-api.elastic.co)
#   docker-hub           (arg: "library/ghost", "bitnami/redis", ...)
#   github-release       (arg: "owner/repo" — uses GitHub Releases API,
#                         tag_name stripped of GITHUB_TAG_PREFIX)
#
# Optional config:
#   MAJOR_PIN                 restrict to this major version, e.g. "5"
#   CONTAINER_IMAGE           if set, the script verifies the image tag
#                             exists in the registry before bumping
#   TAG_SUFFIX                suffix appended to the version when verifying
#                             image existence, e.g. "-alpine" for Ghost
#   VALUES_FILE / VERSION_KEY if VALUES_FILE is set, update
#                             <CHART_DIR>/<VALUES_FILE>.<VERSION_KEY>;
#                             empty VALUES_FILE means only Chart.yaml
#                             appVersion is rewritten
#   SIBLING_CHART_DIR         path (relative to CHART_DIR) to a sibling
#                             chart whose version acts as an upper bound
#   SIBLING_CHART_LABEL       human-readable name of that sibling
#   UPDATE_ARTIFACTHUB_CHANGES  when "true", append a
#                               `- kind: changed / description: Bump ...`
#                               entry to Chart.yaml annotations on success
#   MIRROR_CHART_VERSION      when "true", also bump Chart.yaml `version`
#                             (NOT recommended — prefer `make bump`)
#   GITHUB_TAG_PREFIX         defaults to "v"; stripped from github-release
#                             tag_name to derive the version
set -euo pipefail

# ============================================================
# Configuration (per-chart placeholders — replaced in real upgrade.sh)
# ============================================================
SCRIPT_NAME="__SCRIPT_NAME__"
COMPONENT_LABEL="__COMPONENT_LABEL__"
VERSION_SOURCE="__VERSION_SOURCE__"
VERSION_SOURCE_ARG="__VERSION_SOURCE_ARG__"
MAJOR_PIN="__MAJOR_PIN__"
CHANGELOG_URL="__CHANGELOG_URL__"
CONTAINER_IMAGE="__CONTAINER_IMAGE__"
TAG_SUFFIX="__TAG_SUFFIX__"
VALUES_FILE="__VALUES_FILE__"
VERSION_KEY="__VERSION_KEY__"
SIBLING_CHART_DIR="__SIBLING_CHART_DIR__"
SIBLING_CHART_LABEL="__SIBLING_CHART_LABEL__"
UPDATE_ARTIFACTHUB_CHANGES="__UPDATE_ARTIFACTHUB_CHANGES__"
MIRROR_CHART_VERSION="__MIRROR_CHART_VERSION__"
GITHUB_TAG_PREFIX="${GITHUB_TAG_PREFIX:-v}"
# ============================================================

# === BEGIN CANONICAL BODY ===
CHART_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CHART_DIR/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

$SCRIPT_NAME
Tracks the upstream $COMPONENT_LABEL GA version and bumps Chart.yaml
appVersion${VALUES_FILE:+ + $VALUES_FILE.$VERSION_KEY}. Does NOT touch any cluster.
${SIBLING_CHART_LABEL:+
Sibling check: target version must be <= $SIBLING_CHART_LABEL version.
}
Commands:
  (default)           Check latest version and bump
  --version <VER>     Bump to a specific version (skips upstream query)
  --dry-run           Preview changes only (no files will be modified)
  --rollback          Restore files from a previous backup
  --list-backups      List available backups
  --cleanup-backups   Keep only the last $KEEP_BACKUPS backups, remove older ones
  -h, --help          Show this help message

Examples:
  $(basename "$0")                                # Bump to latest GA
  $(basename "$0") --dry-run                      # Preview without changes
  $(basename "$0") --version X.Y.Z                # Pin to a specific version
  $(basename "$0") --rollback                     # Restore files from backup

After a successful bump, next steps are:
  1. git diff (review Chart.yaml${VALUES_FILE:+, $VALUES_FILE})
  2. make bump CHART=$(basename "$CHART_DIR") LEVEL=patch   # bump chart SemVer
  3. make ci CHART=$(basename "$CHART_DIR")                 # lint + template + validate
  4. git add $(basename "$CHART_DIR") && git commit -m "feat($(basename "$CHART_DIR")): bump appVersion"
EOF
  exit 0
}

list_backups() {
  echo "Available backups:"
  echo ""
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -d "$BACKUP_DIR"/2* 2>/dev/null)" ]; then
    echo "  No backups found."
    exit 0
  fi
  local i=1
  for dir in $(ls -dt "$BACKUP_DIR"/2*/); do
    local dirname=$(basename "$dir")
    local app_ver="unknown"
    [ -f "$dir/Chart.yaml" ] && app_ver=$(grep '^appVersion:' "$dir/Chart.yaml" | awk '{print $2}' | tr -d '"')
    local files=$(ls "$dir" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    printf "  [%d] %s (appVersion: %s) — %s\n" "$i" "$dirname" "$app_ver" "$files"
    i=$((i + 1))
  done
  echo ""
}

do_rollback() {
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -d "$BACKUP_DIR"/2* 2>/dev/null)" ]; then
    echo "No backups found."
    exit 1
  fi
  list_backups
  local backups=()
  for dir in $(ls -dt "$BACKUP_DIR"/2*/); do backups+=("$dir"); done
  read -rp "Select backup number to restore [1]: " choice
  choice=${choice:-1}
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
    echo "Invalid selection."
    exit 1
  fi
  local selected="${backups[$((choice - 1))]}"
  local dirname=$(basename "$selected")
  echo ""
  echo "Restoring from backup/$dirname..."
  [ -f "$selected/Chart.yaml" ] && cp "$selected/Chart.yaml" "$CHART_DIR/Chart.yaml" && echo "  Restored Chart.yaml"
  if [ -n "$VALUES_FILE" ] && [ -f "$selected/$(basename "$VALUES_FILE")" ]; then
    cp "$selected/$(basename "$VALUES_FILE")" "$CHART_DIR/$VALUES_FILE"
    echo "  Restored $VALUES_FILE"
  fi
  echo ""
  echo "Rollback complete. Run 'git diff' to review."
}

cleanup_backups() {
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -d "$BACKUP_DIR"/2* 2>/dev/null)" ]; then
    echo "No backups found."
    exit 0
  fi
  local total=$(ls -d "$BACKUP_DIR"/2*/ 2>/dev/null | wc -l | tr -d ' ')
  echo "Total backups: $total (keeping last $KEEP_BACKUPS)"
  if [ "$total" -le "$KEEP_BACKUPS" ]; then
    echo "Nothing to clean up."
    exit 0
  fi
  local to_delete=$((total - KEEP_BACKUPS))
  echo "Removing $to_delete old backup(s)..."
  ls -dt "$BACKUP_DIR"/2*/ | tail -n "$to_delete" | while read -r dir; do
    rm -rf "$dir"
    echo "  Removed: $(basename "$dir")"
  done
  echo "Done."
}

auto_prune_backups() {
  [ -d "$BACKUP_DIR" ] || return 0
  local total
  total=$(ls -d "$BACKUP_DIR"/2*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$total" -le "$KEEP_BACKUPS" ] && return 0
  local to_delete=$((total - KEEP_BACKUPS))
  ls -dt "$BACKUP_DIR"/2*/ | tail -n "$to_delete" | while read -r dir; do rm -rf "$dir"; done
  echo "  Auto-pruned $to_delete old backup(s) (KEEP_BACKUPS=$KEEP_BACKUPS)."
}

# Read a top-level YAML string value. Handles quoted and unquoted values.
read_yaml_value() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      gsub(/^["\x27]|["\x27]$/, "")
      sub(/[[:space:]]+#.*$/, "")
      print
      exit
    }
  ' "$file"
}

# Replace a top-level YAML string value (quotes preserved where possible).
update_yaml_value() {
  local file="$1"
  local key="$2"
  local new="$3"
  local tmp
  tmp=$(mktemp)
  awk -v k="$key" -v v="$new" '
    BEGIN { done = 0 }
    {
      if (!done && $0 ~ "^" k ":") {
        line = $0
        if (match(line, /: *"[^"]*"/)) {
          sub(/"[^"]*"/, "\"" v "\"", line)
        } else if (match(line, /: *\x27[^\x27]*\x27/)) {
          sub(/\x27[^\x27]*\x27/, "\x27" v "\x27", line)
        } else {
          sub(/:[[:space:]].*$/, ": " v, line)
        }
        print line
        done = 1
        next
      }
      print
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Reset the Chart.yaml artifacthub.io/changes literal block to a single
# `Bump appVersion ...` entry, replacing whatever was there. RESET semantics:
# the annotation only describes the changes for the release currently being
# cut, never an ever-growing accumulation of past entries. Manual entries
# added by humans during PR review are preserved across the same release
# cycle but are wiped out at the next bump (when this function runs).
update_artifacthub_changes() {
  local file="$1"
  local from="$2"
  local to="$3"
  [ "$UPDATE_ARTIFACTHUB_CHANGES" = "true" ] || return 0
  [ -f "$file" ] || return 0
  local desc="Bump appVersion from ${from} to ${to}"
  python3 - "$file" "$desc" <<'PYEOF'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
desc = sys.argv[2]
text = path.read_text()
pat = re.compile(
    r'(?P<head>^(?P<indent>\s+)artifacthub\.io/changes:\s*\|\s*\n)'
    r'(?P<body>(?:(?P=indent)\s+.*\n?)*)',
    re.MULTILINE,
)
m = pat.search(text)
if not m:
    sys.stderr.write("WARN: artifacthub.io/changes block not found; skipping.\n")
    sys.exit(0)
indent = m.group('indent')
entry_indent = indent + '  '
new_body = f"{entry_indent}- kind: changed\n{entry_indent}  description: {desc}\n"
if m.group('body') == new_body:
    print("  artifacthub.io/changes already at the target reset state. Skipped.")
    sys.exit(0)
new_text = text[:m.start('body')] + new_body + text[m.end('body'):]
path.write_text(new_text)
print("  Reset artifacthub.io/changes to single 'Bump appVersion ...' entry.")
PYEOF
}

# Fetch sorted list of GA versions (newest first, respecting MAJOR_PIN).
fetch_ga_versions() {
  case "$VERSION_SOURCE" in
    elastic-artifacts)
      local url="https://artifacts-api.elastic.co/v1/versions"
      curl -sSfL "$url" 2>/dev/null | python3 -c "
import json, sys, re, os
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
versions = d.get('versions', [])
ga = [v for v in versions if re.fullmatch(r'\d+\.\d+\.\d+', v)]
major = os.environ.get('MAJOR_PIN', '').strip()
if major:
    ga = [v for v in ga if v.startswith(major + '.')]
ga.sort(key=lambda v: tuple(int(p) for p in v.split('.')), reverse=True)
for v in ga:
    print(v)
" 2>/dev/null
      ;;
    docker-hub)
      local repo="${VERSION_SOURCE_ARG}"
      [ -z "$repo" ] && return 0
      local base="https://hub.docker.com/v2/repositories/${repo}/tags/?page_size=100"
      local url="$base"
      local page=1
      local all_tags=""
      while [ "$page" -le 5 ] && [ -n "$url" ]; do
        local resp
        resp=$(curl -sSfL "$url" 2>/dev/null) || break
        all_tags+="$(printf '%s' "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in d.get('results', []):
        print(r.get('name', ''))
except Exception:
    pass
" 2>/dev/null)
"
        url=$(printf '%s' "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('next') or '')
except Exception:
    print('')
" 2>/dev/null)
        page=$((page + 1))
      done
      printf '%s' "$all_tags" | python3 -c "
import sys, re, os
major = os.environ.get('MAJOR_PIN', '').strip()
ga = set()
for line in sys.stdin:
    t = line.strip()
    if re.fullmatch(r'\d+\.\d+\.\d+', t):
        if major and not t.startswith(major + '.'):
            continue
        ga.add(t)
ga = sorted(ga, key=lambda v: tuple(int(p) for p in v.split('.')), reverse=True)
for v in ga:
    print(v)
"
      ;;
    github-release)
      local repo="${VERSION_SOURCE_ARG}"
      [ -z "$repo" ] && return 0
      local url="https://api.github.com/repos/${repo}/releases?per_page=100"
      curl -sSfL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        -H 'Accept: application/vnd.github+json' \
        "$url" 2>/dev/null \
        | python3 -c "
import json, sys, re, os
try:
    releases = json.load(sys.stdin)
except Exception:
    sys.exit(0)
major = os.environ.get('MAJOR_PIN', '').strip()
prefix = os.environ.get('GITHUB_TAG_PREFIX', 'v')
ga = set()
for r in releases:
    if r.get('draft') or r.get('prerelease'):
        continue
    tag = r.get('tag_name') or ''
    if prefix and tag.startswith(prefix):
        tag = tag[len(prefix):]
    if re.fullmatch(r'\d+\.\d+\.\d+', tag):
        if major and not tag.startswith(major + '.'):
            continue
        ga.add(tag)
ga = sorted(ga, key=lambda v: tuple(int(p) for p in v.split('.')), reverse=True)
for v in ga:
    print(v)
" 2>/dev/null
      ;;
    *)
      echo "  ERROR: unknown VERSION_SOURCE: $VERSION_SOURCE" >&2
      return 1
      ;;
  esac
}

fetch_latest_version() { fetch_ga_versions | head -1; }

find_latest_available_version() {
  local max_attempts=15
  local attempt=0
  while IFS= read -r v; do
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$max_attempts" ]; then
      echo "    (stopped after $max_attempts attempts)" >&2
      break
    fi
    if verify_image_exists "$v"; then
      echo "    $v: available" >&2
      echo "$v"
      return 0
    fi
    echo "    $v: not found" >&2
  done < <(fetch_ga_versions)
  return 1
}

semver_compare() {
  local a_tuple b_tuple
  a_tuple=$(echo "$1" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
  b_tuple=$(echo "$2" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
  if [ "$a_tuple" -lt "$b_tuple" ]; then echo -1
  elif [ "$a_tuple" -gt "$b_tuple" ]; then echo 1
  else echo 0; fi
}

# File-based sibling check (no kubectl, no cluster access).
check_sibling_version() {
  local target="$1"
  [ -n "$SIBLING_CHART_DIR" ] || return 0
  local sibling_values="$CHART_DIR/$SIBLING_CHART_DIR/values.yaml"
  local sibling_chart="$CHART_DIR/$SIBLING_CHART_DIR/Chart.yaml"
  local sibling_ver=""
  if [ -n "$VERSION_KEY" ] && [ -f "$sibling_values" ]; then
    sibling_ver=$(read_yaml_value "$sibling_values" "$VERSION_KEY")
  fi
  if [ -z "$sibling_ver" ] && [ -f "$sibling_chart" ]; then
    sibling_ver=$(grep '^appVersion:' "$sibling_chart" | awk '{print $2}' | tr -d '"')
  fi
  if [ -z "$sibling_ver" ]; then
    echo "  WARN: could not determine sibling ($SIBLING_CHART_LABEL) version. Skipping check."
    return 0
  fi
  echo "  Sibling $SIBLING_CHART_LABEL version: $sibling_ver"
  local cmp
  cmp=$(semver_compare "$target" "$sibling_ver")
  if [ "$cmp" = "1" ]; then
    echo ""
    echo "  ERROR: target version $target is HIGHER than $SIBLING_CHART_LABEL version $sibling_ver."
    echo "  Bump $SIBLING_CHART_LABEL first:"
    echo "    cd $SIBLING_CHART_DIR && ./upgrade.sh --version $target"
    return 1
  fi
  echo "  OK ($target <= $sibling_ver)."
  return 0
}

# Verify that a container image tag exists in the registry.
verify_image_exists() {
  local tag="$1${TAG_SUFFIX}"
  if [ -z "$CONTAINER_IMAGE" ] || [ -z "$1" ]; then
    return 0
  fi
  local registry="${CONTAINER_IMAGE%%/*}"
  local repo="${CONTAINER_IMAGE#*/}"
  local manifest_url="https://${registry}/v2/${repo}/manifests/${tag}"
  # Docker Hub uses registry-1.docker.io as the actual registry host.
  if [ "$registry" = "docker.io" ]; then
    manifest_url="https://registry-1.docker.io/v2/${repo}/manifests/${tag}"
  fi
  local auth_header
  auth_header=$(curl -sSL -I "$manifest_url" 2>/dev/null \
    | grep -i '^www-authenticate:' | head -1) || true
  local http_code
  if [ -n "$auth_header" ]; then
    local realm service scope
    realm=$(echo "$auth_header" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
    service=$(echo "$auth_header" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    scope=$(echo "$auth_header" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')
    if [ -n "$realm" ]; then
      local token_url="${realm}?service=${service}&scope=${scope}"
      local token
      token=$(curl -sSL "$token_url" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null) || true
      if [ -n "$token" ]; then
        http_code=$(curl -sSL -o /dev/null -w '%{http_code}' \
          -H "Authorization: Bearer $token" \
          -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
          -H "Accept: application/vnd.oci.image.manifest.v1+json" \
          "$manifest_url" 2>/dev/null) || true
        [ "$http_code" = "200" ] && return 0
        return 1
      fi
    fi
  fi
  http_code=$(curl -sSL -o /dev/null -w '%{http_code}' \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "$manifest_url" 2>/dev/null) || true
  [ "$http_code" = "200" ]
}

# -----------------------------------------------
# Argument parsing
# -----------------------------------------------
DRY_RUN=false
TARGET_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)          usage ;;
    --list-backups)     list_backups; exit 0 ;;
    --rollback)         do_rollback; exit 0 ;;
    --cleanup-backups)  cleanup_backups; exit 0 ;;
    --dry-run)          DRY_RUN=true; shift ;;
    --version)
      TARGET_VERSION="${2:-}"
      [ -z "$TARGET_VERSION" ] && { echo "ERROR: --version requires a version number"; exit 1; }
      shift 2 ;;
    *) echo "Unknown option: $1"; echo ""; usage ;;
  esac
done

# -----------------------------------------------
# Main
# -----------------------------------------------
echo "================================================"
echo " $SCRIPT_NAME"
$DRY_RUN && echo " Mode: DRY-RUN (no files will be changed)"
[ -n "$TARGET_VERSION" ] && echo " Target: $TARGET_VERSION"
[ -n "$MAJOR_PIN" ] && echo " Major pin: $MAJOR_PIN.x"
echo "================================================"

# Step 1: read current version
echo ""
if [ -n "$VALUES_FILE" ]; then
  echo "[Step 1/N] Reading current version from $VALUES_FILE..."
  if [ ! -f "$CHART_DIR/$VALUES_FILE" ]; then
    echo "  ERROR: values file not found: $CHART_DIR/$VALUES_FILE"
    exit 1
  fi
  CURRENT_VERSION=$(read_yaml_value "$CHART_DIR/$VALUES_FILE" "$VERSION_KEY")
  [ -z "$CURRENT_VERSION" ] && { echo "  ERROR: could not read '$VERSION_KEY' from $VALUES_FILE"; exit 1; }
  echo "  Current $COMPONENT_LABEL version: $CURRENT_VERSION"
else
  echo "[Step 1/N] Reading current appVersion from Chart.yaml..."
  CURRENT_VERSION=$(grep '^appVersion:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
  [ -z "$CURRENT_VERSION" ] && { echo "  ERROR: could not read appVersion"; exit 1; }
  echo "  Current appVersion: $CURRENT_VERSION"
fi

CURRENT_APP_VERSION=""
if [ -f "$CHART_DIR/Chart.yaml" ]; then
  CURRENT_APP_VERSION=$(grep '^appVersion:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
  echo "  Chart.yaml appVersion:       $CURRENT_APP_VERSION"
fi

# Step 2: fetch latest upstream
echo ""
echo "[Step 2/N] Checking latest upstream version (source: $VERSION_SOURCE)..."
if [ -n "$TARGET_VERSION" ]; then
  LATEST_VERSION="$TARGET_VERSION"
  echo "  Using explicit target: $TARGET_VERSION"
else
  LATEST_VERSION=$(MAJOR_PIN="$MAJOR_PIN" fetch_latest_version)
  [ -z "$LATEST_VERSION" ] && { echo "  ERROR: failed to fetch latest version"; exit 1; }
  echo "  Latest available:      $LATEST_VERSION"
fi

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ] && { [ -z "$CURRENT_APP_VERSION" ] || [ "$CURRENT_APP_VERSION" = "$LATEST_VERSION" ]; }; then
  echo ""
  echo "  Already up to date! Nothing to do."
  exit 0
fi

echo ""
echo "  Bump: $CURRENT_VERSION -> $LATEST_VERSION"
echo "  Changelog: $CHANGELOG_URL"

# Step 3: optional sibling check
if [ -n "$SIBLING_CHART_DIR" ]; then
  echo ""
  echo "[Step 3/N] Sibling version check ($SIBLING_CHART_LABEL)..."
  if ! check_sibling_version "$LATEST_VERSION"; then
    exit 1
  fi
fi

# Step 4: verify image if configured
echo ""
echo "[Step 4/N] Verifying container image..."
if [ -n "$CONTAINER_IMAGE" ]; then
  echo "  Checking: $CONTAINER_IMAGE:${LATEST_VERSION}${TAG_SUFFIX}"
  if verify_image_exists "$LATEST_VERSION"; then
    echo "  Image verified OK."
  else
    echo ""
    echo "  WARNING: Container image not found in registry."
    if [ -n "$TARGET_VERSION" ]; then
      echo "  Refusing to bump. Retry once the image is published or choose another version."
      exit 1
    fi
    echo "  Searching for the newest GA version with a published image..."
    AVAILABLE_VERSION=$(find_latest_available_version) || true
    if [ -z "$AVAILABLE_VERSION" ]; then
      echo "  ERROR: no GA version with a published image found within search limit."
      exit 1
    fi
    if [ "$AVAILABLE_VERSION" = "$CURRENT_VERSION" ]; then
      echo "  Newest available matches current. Nothing to bump."
      exit 0
    fi
    echo "  Latest available (with published image): $AVAILABLE_VERSION"
    if $DRY_RUN; then
      LATEST_VERSION="$AVAILABLE_VERSION"
    else
      read -rp "  Use $AVAILABLE_VERSION instead of $LATEST_VERSION? [y/N]: " use_alt
      [[ ! "$use_alt" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }
      LATEST_VERSION="$AVAILABLE_VERSION"
    fi
  fi
else
  echo "  Skipped (CONTAINER_IMAGE not configured)."
fi

# Step 5: major bump warning
CURRENT_MAJOR="${CURRENT_VERSION%%.*}"
LATEST_MAJOR="${LATEST_VERSION%%.*}"
if [ -n "$CURRENT_MAJOR" ] && [ -n "$LATEST_MAJOR" ] && [ "$CURRENT_MAJOR" != "$LATEST_MAJOR" ]; then
  echo ""
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "  !! MAJOR VERSION BUMP: $CURRENT_MAJOR.x -> $LATEST_MAJOR.x"
  echo "  !! Review breaking changes: $CHANGELOG_URL"
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  if ! $DRY_RUN; then
    read -rp "  Continue with major version bump? [y/N]: " major_confirm
    [[ ! "$major_confirm" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }
  fi
fi

# Step 6: dry-run or apply
echo ""
if $DRY_RUN; then
  echo "[Step 6/N] DRY-RUN complete. No files were changed."
  echo "  To apply: $(basename "$0")${TARGET_VERSION:+ --version $TARGET_VERSION}"
  exit 0
fi

echo "[Step 6/N] Applying bump..."
mkdir -p "$BACKUP_DIR/$TIMESTAMP"
cp "$CHART_DIR/Chart.yaml" "$BACKUP_DIR/$TIMESTAMP/Chart.yaml"
if [ -n "$VALUES_FILE" ] && [ -f "$CHART_DIR/$VALUES_FILE" ]; then
  cp "$CHART_DIR/$VALUES_FILE" "$BACKUP_DIR/$TIMESTAMP/$(basename "$VALUES_FILE")"
fi
echo "  Backed up to: backup/$TIMESTAMP/"
ls "$BACKUP_DIR/$TIMESTAMP/" | while read -r f; do echo "    - $f"; done

if [ -n "$VALUES_FILE" ]; then
  update_yaml_value "$CHART_DIR/$VALUES_FILE" "$VERSION_KEY" "$LATEST_VERSION"
  echo "  Updated $VALUES_FILE ($VERSION_KEY: $CURRENT_VERSION -> $LATEST_VERSION)"
fi

update_yaml_value "$CHART_DIR/Chart.yaml" "appVersion" "$LATEST_VERSION"
echo "  Updated Chart.yaml (appVersion: ${CURRENT_APP_VERSION:-unset} -> $LATEST_VERSION)"

if [ "$MIRROR_CHART_VERSION" = "true" ]; then
  CURRENT_CHART_VERSION=$(grep '^version:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
  if [ "$CURRENT_CHART_VERSION" != "$LATEST_VERSION" ]; then
    update_yaml_value "$CHART_DIR/Chart.yaml" "version" "$LATEST_VERSION"
    echo "  Updated Chart.yaml (version: ${CURRENT_CHART_VERSION:-unset} -> $LATEST_VERSION) [mirrored]"
  fi
fi

update_artifacthub_changes "$CHART_DIR/Chart.yaml" "$CURRENT_APP_VERSION" "$LATEST_VERSION"

auto_prune_backups

echo ""
echo "================================================"
echo " Bump complete! ($CURRENT_VERSION -> $LATEST_VERSION)"
echo ""
echo " Changelog: $CHANGELOG_URL"
echo ""
echo " Next steps:"
echo "   1. git diff (review Chart.yaml${VALUES_FILE:+, $VALUES_FILE})"
echo "   2. make bump CHART=$(basename "$CHART_DIR") LEVEL=patch   # bump chart SemVer"
echo "   3. make ci CHART=$(basename "$CHART_DIR")"
echo "   4. git add $(basename "$CHART_DIR") && git commit"
echo ""
echo " To rollback:"
echo "   $(basename "$0") --rollback"
echo "================================================"
# === END CANONICAL BODY ===
