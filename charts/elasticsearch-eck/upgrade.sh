#!/bin/bash
# upgrade-template: helm-charts/local-cr-version (adapted from
# kuberntes-infra/scripts/upgrade-sync/templates/local-cr-version.sh)
#
# Purpose: as a chart maintainer, track the latest Elasticsearch GA version
# and bump Chart.yaml `appVersion` + values.yaml `version` safely. Chart
# `version` (SemVer of the chart itself) is NOT mirrored — bump manually with
# `make bump CHART=elasticsearch-eck LEVEL=patch|minor|major` after reviewing
# the diff. No cluster-side operations are performed; rollback restores files
# from backup/<timestamp>/ only.
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
SCRIPT_NAME="elasticsearch-eck Helm Chart appVersion Bump"
COMPONENT_LABEL="elasticsearch"
VERSION_SOURCE="elastic-artifacts"
VERSION_SOURCE_ARG=""
VALUES_FILE="values.yaml"
VERSION_KEY="version"
MAJOR_PIN="9"
CHANGELOG_URL="https://www.elastic.co/guide/en/elasticsearch/reference/current/release-notes.html"
CONTAINER_IMAGE="docker.elastic.co/elasticsearch/elasticsearch"
# Chart version is not mirrored — maintainer bumps it via `make bump`.
MIRROR_CHART_VERSION="false"
# Append a changelog entry to Chart.yaml annotations on successful bump.
UPDATE_ARTIFACTHUB_CHANGES="true"
# ============================================================

CHART_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CHART_DIR/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

$SCRIPT_NAME
Tracks the upstream $COMPONENT_LABEL GA version and bumps Chart.yaml
appVersion + $VALUES_FILE.$VERSION_KEY. Does NOT touch any cluster.

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
  $(basename "$0") --version 9.1.2                # Pin to a specific version
  $(basename "$0") --rollback                     # Restore files from backup

After a successful bump, next steps are:
  1. git diff (review Chart.yaml, values.yaml)
  2. make bump CHART=$(basename "$CHART_DIR") LEVEL=minor   # bump chart SemVer
  3. make lint CHART=$(basename "$CHART_DIR") && make template CHART=$(basename "$CHART_DIR")
  4. git add $(basename "$CHART_DIR") && git commit -m "feat($(basename "$CHART_DIR")): bump appVersion to <VER>"
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
    local chart_ver="unknown"
    [ -f "$dir/Chart.yaml" ] && chart_ver=$(grep '^appVersion:' "$dir/Chart.yaml" | awk '{print $2}' | tr -d '"')
    local files=$(ls "$dir" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    printf "  [%d] %s (appVersion: %s) — %s\n" "$i" "$dirname" "$chart_ver" "$files"
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
  for dir in $(ls -dt "$BACKUP_DIR"/2*/); do
    backups+=("$dir")
  done

  read -rp "Select backup number to restore [1]: " choice
  choice=${choice:-1}

  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
    echo "Invalid selection."
    exit 1
  fi

  local selected="${backups[$((choice - 1))]}"
  local dirname=$(basename "$selected")

  echo ""
  echo "Restoring files from backup/$dirname..."

  [ -f "$selected/Chart.yaml" ] && cp "$selected/Chart.yaml" "$CHART_DIR/Chart.yaml" && echo "  Restored Chart.yaml"
  if [ -f "$selected/$(basename "$VALUES_FILE")" ]; then
    cp "$selected/$(basename "$VALUES_FILE")" "$CHART_DIR/$VALUES_FILE"
    echo "  Restored $VALUES_FILE"
  fi

  echo ""
  echo "File rollback complete. No cluster operations were performed."
  echo "Next: 'git diff' to review, then commit or discard."
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
    local dirname=$(basename "$dir")
    rm -rf "$dir"
    echo "  Removed: $dirname"
  done

  echo "Done."
}

auto_prune_backups() {
  [ -d "$BACKUP_DIR" ] || return 0
  local total
  total=$(ls -d "$BACKUP_DIR"/2*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$total" -le "$KEEP_BACKUPS" ] && return 0
  local to_delete=$((total - KEEP_BACKUPS))
  ls -dt "$BACKUP_DIR"/2*/ | tail -n "$to_delete" | while read -r dir; do
    rm -rf "$dir"
  done
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

# Append a `- kind: changed\n  description: ...` entry to the
# annotations.artifacthub.io/changes multi-line block in Chart.yaml.
# Idempotent: skipped when the exact description is already present.
update_artifacthub_changes() {
  local file="$1"
  local from="$2"
  local to="$3"
  [ "$UPDATE_ARTIFACTHUB_CHANGES" = "true" ] || return 0
  [ -f "$file" ] || return 0

  local desc="Bump appVersion from ${from} to ${to}"
  if grep -qF "$desc" "$file"; then
    echo "  artifacthub.io/changes entry already present. Skipped."
    return 0
  fi

  python3 - "$file" "$desc" <<'PYEOF'
import sys, re, pathlib

path = pathlib.Path(sys.argv[1])
desc = sys.argv[2]
text = path.read_text()

# Match the `  artifacthub.io/changes: |` literal-block and capture its body
# (all lines indented deeper than the key). Append a new entry at the end of
# the body, then write back.
pat = re.compile(
    r'(^(?P<indent>\s+)artifacthub\.io/changes:\s*\|\s*\n)'
    r'(?P<body>(?:(?P=indent)\s+.*\n?)*)',
    re.MULTILINE,
)
m = pat.search(text)
if not m:
    sys.stderr.write("WARN: artifacthub.io/changes block not found; skipping.\n")
    sys.exit(0)

indent = m.group('indent')
body = m.group('body')
entry_indent = indent + '  '
new_entry = f"{entry_indent}- kind: changed\n{entry_indent}  description: {desc}\n"

# Guarantee trailing newline on body before append.
if body and not body.endswith('\n'):
    body += '\n'
new_body = body + new_entry
text = text[:m.start('body')] + new_body + text[m.end('body'):]
path.write_text(text)
print("  Appended entry to artifacthub.io/changes.")
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
    *)
      ;;
  esac
}

fetch_latest_version() {
  fetch_ga_versions | head -1
}

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
  if [ "$a_tuple" -lt "$b_tuple" ]; then
    echo -1
  elif [ "$a_tuple" -gt "$b_tuple" ]; then
    echo 1
  else
    echo 0
  fi
}

# Verify that a container image tag exists in the registry.
verify_image_exists() {
  local tag="$1"
  if [ -z "$CONTAINER_IMAGE" ] || [ -z "$tag" ]; then
    return 0
  fi
  local registry="${CONTAINER_IMAGE%%/*}"
  local repo="${CONTAINER_IMAGE#*/}"
  local manifest_url="https://${registry}/v2/${repo}/manifests/${tag}"

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
      if [ -z "$TARGET_VERSION" ]; then
        echo "ERROR: --version requires a version number"
        exit 1
      fi
      shift 2
      ;;
    *)   echo "Unknown option: $1"; echo ""; usage ;;
  esac
done

# -----------------------------------------------
# Main
# -----------------------------------------------
echo "================================================"
echo " $SCRIPT_NAME"
if $DRY_RUN; then
  echo " Mode: DRY-RUN (no files will be changed)"
fi
if [ -n "$TARGET_VERSION" ]; then
  echo " Target: v$TARGET_VERSION"
fi
if [ -n "$MAJOR_PIN" ]; then
  echo " Major pin: $MAJOR_PIN.x"
fi
echo "================================================"

echo ""
echo "[Step 1/5] Reading current version from $VALUES_FILE..."
if [ ! -f "$CHART_DIR/$VALUES_FILE" ]; then
  echo "  ERROR: values file not found: $CHART_DIR/$VALUES_FILE"
  exit 1
fi
CURRENT_VERSION=$(read_yaml_value "$CHART_DIR/$VALUES_FILE" "$VERSION_KEY")
if [ -z "$CURRENT_VERSION" ]; then
  echo "  ERROR: could not read '$VERSION_KEY' from $VALUES_FILE"
  exit 1
fi
echo "  Current $COMPONENT_LABEL version: $CURRENT_VERSION"

CURRENT_APP_VERSION=""
if [ -f "$CHART_DIR/Chart.yaml" ]; then
  CURRENT_APP_VERSION=$(grep '^appVersion:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
  echo "  Chart.yaml appVersion:       $CURRENT_APP_VERSION"
fi

echo ""
echo "[Step 2/5] Checking latest upstream version (source: $VERSION_SOURCE)..."
if [ -n "$TARGET_VERSION" ]; then
  LATEST_VERSION="$TARGET_VERSION"
  echo "  Using explicit target: $TARGET_VERSION"
else
  LATEST_VERSION=$(MAJOR_PIN="$MAJOR_PIN" fetch_latest_version)
  if [ -z "$LATEST_VERSION" ]; then
    echo "  ERROR: failed to fetch latest version from '$VERSION_SOURCE'."
    exit 1
  fi
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

echo ""
echo "[Step 3/5] Verifying container image..."
if [ -n "$CONTAINER_IMAGE" ]; then
  echo "  Checking: $CONTAINER_IMAGE:$LATEST_VERSION"
  if verify_image_exists "$LATEST_VERSION"; then
    echo "  Image verified OK."
  else
    echo ""
    echo "  WARNING: Container image not found in registry."
    echo "    Image: $CONTAINER_IMAGE:$LATEST_VERSION"

    if [ -n "$TARGET_VERSION" ]; then
      echo ""
      echo "  Options:"
      echo "    - Wait for the image to be published and retry."
      echo "    - Choose a different version."
      exit 1
    fi

    echo ""
    echo "  Searching for the newest GA version with a published image..."
    AVAILABLE_VERSION=$(find_latest_available_version) || true

    if [ -z "$AVAILABLE_VERSION" ]; then
      echo ""
      echo "  ERROR: No GA version with a published image found within search limit."
      exit 1
    fi

    if [ "$AVAILABLE_VERSION" = "$CURRENT_VERSION" ]; then
      echo ""
      echo "  Newest available version matches current. Nothing to bump."
      exit 0
    fi

    echo ""
    echo "  Latest available (with published image): $AVAILABLE_VERSION"
    if $DRY_RUN; then
      LATEST_VERSION="$AVAILABLE_VERSION"
    else
      echo ""
      read -rp "  Use $AVAILABLE_VERSION instead of $LATEST_VERSION? [y/N]: " use_alt
      if [[ ! "$use_alt" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
      fi
      LATEST_VERSION="$AVAILABLE_VERSION"
    fi
  fi
else
  echo "  Skipped (CONTAINER_IMAGE not configured)."
fi

# Major version bump warning
CURRENT_MAJOR="${CURRENT_VERSION%%.*}"
LATEST_MAJOR="${LATEST_VERSION%%.*}"
if [ -n "$CURRENT_MAJOR" ] && [ -n "$LATEST_MAJOR" ] && [ "$CURRENT_MAJOR" != "$LATEST_MAJOR" ]; then
  echo ""
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "  !! MAJOR VERSION BUMP: $CURRENT_MAJOR.x -> $LATEST_MAJOR.x"
  echo "  !! Review breaking changes: $CHANGELOG_URL"
  echo "  !! Downstream consumers may need to update ECK Operator."
  echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  if ! $DRY_RUN; then
    echo ""
    read -rp "  Continue with major version bump? [y/N]: " major_confirm
    if [[ ! "$major_confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi
  fi
fi

echo ""
if $DRY_RUN; then
  echo "[Step 4/5] DRY-RUN complete. No files were changed."
  echo ""
  echo "  To apply: ./upgrade.sh"
  [ -n "$TARGET_VERSION" ] && echo "  To apply: ./upgrade.sh --version $TARGET_VERSION"
  exit 0
fi

echo "[Step 4/5] Backing up current files..."
mkdir -p "$BACKUP_DIR/$TIMESTAMP"
cp "$CHART_DIR/$VALUES_FILE" "$BACKUP_DIR/$TIMESTAMP/$(basename "$VALUES_FILE")"
[ -f "$CHART_DIR/Chart.yaml" ] && cp "$CHART_DIR/Chart.yaml" "$BACKUP_DIR/$TIMESTAMP/Chart.yaml"
echo "  Backed up to: backup/$TIMESTAMP/"
ls "$BACKUP_DIR/$TIMESTAMP/" | while read -r f; do echo "    - $f"; done

echo ""
echo "[Step 5/5] Applying version update..."

update_yaml_value "$CHART_DIR/$VALUES_FILE" "$VERSION_KEY" "$LATEST_VERSION"
echo "  Updated $VALUES_FILE ($VERSION_KEY: $CURRENT_VERSION -> $LATEST_VERSION)"

if [ -f "$CHART_DIR/Chart.yaml" ]; then
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
fi

auto_prune_backups

echo ""
echo "================================================"
echo " Bump complete! ($CURRENT_VERSION -> $LATEST_VERSION)"
echo ""
echo " Changelog: $CHANGELOG_URL"
echo ""
echo " Next steps:"
echo "   1. Review diff: git diff $(basename "$CHART_DIR")"
echo "   2. Bump chart SemVer: make bump CHART=$(basename "$CHART_DIR") LEVEL=minor"
echo "   3. Validate locally: make lint CHART=$(basename "$CHART_DIR") && make template CHART=$(basename "$CHART_DIR")"
echo "   4. Commit: git add $(basename "$CHART_DIR") && git commit -m \"feat($(basename "$CHART_DIR")): bump appVersion to $LATEST_VERSION\""
echo ""
echo " To rollback files:"
echo "   ./upgrade.sh --rollback"
echo "================================================"
