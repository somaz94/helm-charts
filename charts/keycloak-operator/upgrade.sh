#!/bin/bash
# upgrade-template: helm-charts/external-tracked
#
# Purpose: as a chart maintainer, track new keycloak-k8s-resources releases
# (https://github.com/keycloak/keycloak-k8s-resources) and refresh:
#   - templates/crd-keycloaks.yaml
#   - templates/crd-realmimports.yaml
#   - Chart.yaml `appVersion`
#   - values.yaml `version`
#   - artifacthub.io/changes annotation
#
# Chart's own SemVer (Chart.yaml `version`) is NOT mirrored — bump manually
# with `make bump CHART=keycloak-operator LEVEL=patch|minor|major` after
# reviewing the diff. No cluster-side operations are performed; rollback
# restores files from backup/<timestamp>/ only.
set -euo pipefail

# ============================================================
# Configuration — keycloak-operator specific
# ============================================================
SCRIPT_NAME="keycloak-operator Helm Chart upgrade"
COMPONENT_LABEL="keycloak"
GITHUB_REPO="keycloak/keycloak-k8s-resources"
CHANGELOG_URL="https://www.keycloak.org/docs/latest/release_notes/index.html"
CONTAINER_IMAGE="quay.io/keycloak/keycloak-operator"
CHART_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CHART_DIR/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"

# Helm template gate header injected at the very top of each downloaded CRD.
GATE_OPEN='{{- if .Values.crds.install }}'
GATE_CLOSE='{{- end }}'
LABELS_ANN_BLOCK=$(cat <<'EOF'
  labels:
    {{- include "keycloak-operator.labels" . | nindent 4 }}
  {{- $crdAnn := include "keycloak-operator.crdAnnotations" . }}
  {{- if $crdAnn }}
  annotations:
    {{- $crdAnn | nindent 4 }}
  {{- end }}
EOF
)

CRD_FILES=(
  "keycloaks.k8s.keycloak.org-v1.yml:templates/crd-keycloaks.yaml"
  "keycloakrealmimports.k8s.keycloak.org-v1.yml:templates/crd-realmimports.yaml"
)

# ============================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

$SCRIPT_NAME
Tracks the upstream $GITHUB_REPO releases feed and refreshes the chart's CRD
templates and Chart.yaml/values.yaml versions. Does NOT touch any cluster.

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
  $(basename "$0") --version 26.6.1               # Pin to a specific version
  $(basename "$0") --rollback                     # Restore files from backup

After a successful bump, next steps are:
  1. git diff (review Chart.yaml, values.yaml, templates/crd-*.yaml)
  2. make bump CHART=$(basename "$CHART_DIR") LEVEL=patch
  3. make ci CHART=$(basename "$CHART_DIR")
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
    local dirname app_ver files
    dirname=$(basename "$dir")
    app_ver="unknown"
    [ -f "$dir/Chart.yaml" ] && app_ver=$(grep '^appVersion:' "$dir/Chart.yaml" | awk '{print $2}' | tr -d '"')
    files=$(find "$dir" -type f -printf '%P\n' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
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
  local dirname
  dirname=$(basename "$selected")
  echo ""
  echo "Restoring from backup/$dirname..."
  [ -f "$selected/Chart.yaml" ] && cp "$selected/Chart.yaml" "$CHART_DIR/Chart.yaml" && echo "  Restored Chart.yaml"
  [ -f "$selected/values.yaml" ] && cp "$selected/values.yaml" "$CHART_DIR/values.yaml" && echo "  Restored values.yaml"
  for entry in "${CRD_FILES[@]}"; do
    local dest="${entry#*:}"
    local backup_path="$selected/$dest"
    if [ -f "$backup_path" ]; then
      mkdir -p "$(dirname "$CHART_DIR/$dest")"
      cp "$backup_path" "$CHART_DIR/$dest"
      echo "  Restored $dest"
    fi
  done
  echo ""
  echo "Rollback complete. Run 'git diff' to review."
}

cleanup_backups() {
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -d "$BACKUP_DIR"/2* 2>/dev/null)" ]; then
    echo "No backups found."
    exit 0
  fi
  local total
  total=$(ls -d "$BACKUP_DIR"/2*/ 2>/dev/null | wc -l | tr -d ' ')
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
  local desc="Bump appVersion from ${from} to ${to} (refresh templates/crd-*.yaml from upstream)"
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

fetch_latest_release() {
  # keycloak-k8s-resources publishes tags, not GitHub Releases — query the
  # tags endpoint and filter to GA-style "X.Y.Z" entries.
  local url="https://api.github.com/repos/${GITHUB_REPO}/tags?per_page=100"
  curl -sSfL \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' \
    "$url" 2>/dev/null \
    | python3 -c "
import json, sys, re
try:
    tags = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ga = []
for t in tags:
    name = t.get('name') or ''
    if re.fullmatch(r'\d+\.\d+\.\d+', name):
        ga.append(name)
ga.sort(key=lambda v: tuple(int(p) for p in v.split('.')), reverse=True)
print(ga[0] if ga else '')
"
}

# Verify that the operator container image tag exists in the registry.
verify_image_exists() {
  local tag="$1"
  [ -z "$tag" ] && return 1
  local manifest_url="https://${CONTAINER_IMAGE%%/*}/v2/${CONTAINER_IMAGE#*/}/manifests/${tag}"
  local auth_header
  auth_header=$(curl -sSL -I "$manifest_url" 2>/dev/null \
    | grep -i '^www-authenticate:' | head -1) || true
  local http_code
  if [ -n "$auth_header" ]; then
    local realm service scope token_url token
    realm=$(echo "$auth_header" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
    service=$(echo "$auth_header" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    scope=$(echo "$auth_header" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')
    if [ -n "$realm" ]; then
      token_url="${realm}?service=${service}&scope=${scope}"
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

# Download a CRD file from upstream and inject the helm gate + labels/annotations block.
fetch_and_patch_crd() {
  local upstream_name="$1"
  local local_path="$2"
  local version="$3"
  local url="https://raw.githubusercontent.com/${GITHUB_REPO}/${version}/kubernetes/${upstream_name}"
  local tmp
  tmp=$(mktemp)
  if ! curl -sSfL -o "$tmp" "$url"; then
    echo "  ERROR: failed to fetch $url" >&2
    rm -f "$tmp"
    return 1
  fi
  python3 - "$tmp" "$local_path" <<'PYEOF'
import re, sys, pathlib

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
LABELS_ANN_BLOCK = (
    "  labels:\n"
    '    {{- include "keycloak-operator.labels" . | nindent 4 }}\n'
    '  {{- $crdAnn := include "keycloak-operator.crdAnnotations" . }}\n'
    "  {{- if $crdAnn }}\n"
    "  annotations:\n"
    "    {{- $crdAnn | nindent 4 }}\n"
    "  {{- end }}\n"
)
new_text, n = re.subn(
    r"^metadata:\n",
    "metadata:\n" + LABELS_ANN_BLOCK,
    text,
    count=1,
    flags=re.MULTILINE,
)
if n != 1:
    sys.stderr.write(f"failed to inject metadata block into {src}\n")
    sys.exit(1)
new_text = "{{- if .Values.crds.install }}\n" + new_text.rstrip() + "\n{{- end }}\n"
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(new_text)
PYEOF
  rm -f "$tmp"
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
echo "================================================"

# Step 1: read current versions
echo ""
echo "[Step 1/5] Reading current version..."
CURRENT_VERSION=$(grep '^version:' "$CHART_DIR/values.yaml" | awk '{print $2}' | tr -d '"')
[ -z "$CURRENT_VERSION" ] && { echo "  ERROR: could not read 'version' from values.yaml"; exit 1; }
CURRENT_APP_VERSION=$(grep '^appVersion:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
echo "  values.yaml version:    $CURRENT_VERSION"
echo "  Chart.yaml appVersion:  $CURRENT_APP_VERSION"

# Step 2: latest release
echo ""
echo "[Step 2/5] Checking latest upstream release ($GITHUB_REPO)..."
if [ -n "$TARGET_VERSION" ]; then
  LATEST_VERSION="$TARGET_VERSION"
  echo "  Using explicit target: $TARGET_VERSION"
else
  LATEST_VERSION=$(fetch_latest_release)
  [ -z "$LATEST_VERSION" ] && { echo "  ERROR: failed to fetch latest release"; exit 1; }
  echo "  Latest available:      $LATEST_VERSION"
fi

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ] && [ "$CURRENT_APP_VERSION" = "$LATEST_VERSION" ]; then
  echo ""
  echo "  Already up to date! Nothing to do."
  exit 0
fi

# Step 3: verify image exists
echo ""
echo "[Step 3/5] Verifying operator image..."
echo "  Checking: ${CONTAINER_IMAGE}:${LATEST_VERSION}"
if verify_image_exists "$LATEST_VERSION"; then
  echo "  Image verified OK."
else
  echo "  ERROR: ${CONTAINER_IMAGE}:${LATEST_VERSION} not found in registry."
  echo "  Refusing to bump. Retry once the image is published or pick another version."
  exit 1
fi

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

# Step 4: dry-run or apply
if $DRY_RUN; then
  echo ""
  echo "[Step 4/5] DRY-RUN. Would refresh:"
  for entry in "${CRD_FILES[@]}"; do
    echo "  - ${entry#*:}    (from ${entry%%:*}@${LATEST_VERSION})"
  done
  echo "  - values.yaml.version       ($CURRENT_VERSION -> $LATEST_VERSION)"
  echo "  - Chart.yaml.appVersion     ($CURRENT_APP_VERSION -> $LATEST_VERSION)"
  echo ""
  echo "  To apply: $(basename "$0")${TARGET_VERSION:+ --version $TARGET_VERSION}"
  exit 0
fi

# Step 4: backup & apply
echo ""
echo "[Step 4/5] Applying bump..."
mkdir -p "$BACKUP_DIR/$TIMESTAMP"
cp "$CHART_DIR/Chart.yaml" "$BACKUP_DIR/$TIMESTAMP/Chart.yaml"
cp "$CHART_DIR/values.yaml" "$BACKUP_DIR/$TIMESTAMP/values.yaml"
for entry in "${CRD_FILES[@]}"; do
  local_path="${entry#*:}"
  if [ -f "$CHART_DIR/$local_path" ]; then
    mkdir -p "$BACKUP_DIR/$TIMESTAMP/$(dirname "$local_path")"
    cp "$CHART_DIR/$local_path" "$BACKUP_DIR/$TIMESTAMP/$local_path"
  fi
done
echo "  Backed up to: backup/$TIMESTAMP/"

echo ""
echo "[Step 5/5] Refreshing CRD templates..."
for entry in "${CRD_FILES[@]}"; do
  upstream_name="${entry%%:*}"
  local_path="${entry#*:}"
  echo "  Fetching $upstream_name @ $LATEST_VERSION -> $local_path"
  fetch_and_patch_crd "$upstream_name" "$CHART_DIR/$local_path" "$LATEST_VERSION"
done

update_yaml_value "$CHART_DIR/values.yaml" "version" "$LATEST_VERSION"
echo "  Updated values.yaml (version: $CURRENT_VERSION -> $LATEST_VERSION)"

update_yaml_value "$CHART_DIR/Chart.yaml" "appVersion" "$LATEST_VERSION"
echo "  Updated Chart.yaml (appVersion: ${CURRENT_APP_VERSION:-unset} -> $LATEST_VERSION)"

update_artifacthub_changes "$CHART_DIR/Chart.yaml" "$CURRENT_APP_VERSION" "$LATEST_VERSION"

auto_prune_backups

echo ""
echo "================================================"
echo " Bump complete! ($CURRENT_VERSION -> $LATEST_VERSION)"
echo ""
echo " Changelog: $CHANGELOG_URL"
echo ""
echo " Next steps:"
echo "   1. git diff (review Chart.yaml, values.yaml, templates/crd-*.yaml)"
echo "   2. make bump CHART=$(basename "$CHART_DIR") LEVEL=patch"
echo "   3. make ci CHART=$(basename "$CHART_DIR")"
echo "   4. git add $(basename "$CHART_DIR") && git commit"
echo ""
echo " To rollback:"
echo "   $(basename "$0") --rollback"
echo "================================================"
