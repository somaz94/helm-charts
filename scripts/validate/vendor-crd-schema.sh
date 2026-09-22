#!/usr/bin/env bash
# vendor-crd-schema.sh — convert an upstream CRD into a kubeconform JSON schema.
#
# The datree CRDs-catalog lags upstream, so a valid CR can have no schema and be
# silently skipped (see check-skips.sh). This closes that hole one kind at a time:
# it extracts each version's `spec.versions[].schema.openAPIV3Schema` from a CRD
# verbatim and writes it to the tree `make validate` searches first:
#
#   schemas/<group>/<kind-lowercased>_<version>.json
#
# Same layout as the datree catalog: a drop-in until the catalog catches up.
#
# Usage:
#   scripts/validate/vendor-crd-schema.sh <crd-url-or-path> [<schemas-dir>]
#
#   <crd-url-or-path>  http(s) URL or local path to a CustomResourceDefinition
#                      YAML. Multi-document files are accepted; every
#                      CustomResourceDefinition document in them is converted.
#   <schemas-dir>      output root. Defaults to `schemas/` at the repo root.
#
# Example — vendor the NGINX Gateway Fabric ProxySettingsPolicy schema:
#   scripts/validate/vendor-crd-schema.sh \
#     https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/config/crd/bases/gateway.nginx.org_proxysettingspolicies.yaml
#
# After vendoring, drop the matching line from scripts/validate/allowed-skips.txt
# so the gate starts requiring the kind to validate.
#
# Maintainer-only — this never runs in CI. It needs PyYAML (`pip install pyyaml`);
# the CI gate itself (check-skips.sh) parses kubeconform JSON and has no such
# dependency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "$REPO_ROOT/scripts/lib/common.sh"

SOURCE="${1:-}"
SCHEMAS_DIR="${2:-$REPO_ROOT/schemas}"

[ -n "$SOURCE" ] || die "usage: vendor-crd-schema.sh <crd-url-or-path> [<schemas-dir>]"

require_command python3
python3 -c 'import yaml' 2>/dev/null \
    || die "PyYAML required for CRD parsing: pip install pyyaml"

init_tmp_cleanup
crd_file="$(mktemp_tracked)"

case "$SOURCE" in
    http://*|https://*)
        require_command curl
        info "==> fetching $SOURCE"
        curl -sSfL "$SOURCE" -o "$crd_file" || die "fetch failed: $SOURCE"
        ;;
    *)
        [ -f "$SOURCE" ] || die "no such file: $SOURCE"
        cp "$SOURCE" "$crd_file"
        ;;
esac

python3 - "$crd_file" "$SCHEMAS_DIR" "$SOURCE" <<'PYEOF'
import json
import pathlib
import sys

import yaml

crd_path, schemas_dir, provenance = sys.argv[1], sys.argv[2], sys.argv[3]

docs = [d for d in yaml.safe_load_all(pathlib.Path(crd_path).read_text())
        if isinstance(d, dict) and d.get("kind") == "CustomResourceDefinition"]
if not docs:
    sys.exit(f"ERROR: no CustomResourceDefinition document found in {provenance}")

written = 0
for doc in docs:
    spec = doc.get("spec") or {}
    group = spec.get("group")
    kind = ((spec.get("names") or {}).get("kind"))
    if not group or not kind:
        sys.exit(f"ERROR: CRD is missing spec.group or spec.names.kind in {provenance}")

    for version in spec.get("versions") or []:
        name = version.get("name")
        schema = (version.get("schema") or {}).get("openAPIV3Schema")
        if not name or not schema:
            print(f"    skip {kind}/{name or '?'} — no openAPIV3Schema", file=sys.stderr)
            continue

        # datree CRDs-catalog layout: <group>/<kind lowercased>_<version>.json,
        # holding the openAPIV3Schema verbatim. kubeconform lowercases
        # {{.ResourceKind}} when expanding a -schema-location template, so the
        # filename must be lowercase for the lookup to hit.
        out = pathlib.Path(schemas_dir) / group / f"{kind.lower()}_{name}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(schema, indent=2, sort_keys=False) + "\n")
        print(f"    wrote {out.relative_to(pathlib.Path(schemas_dir).parent)} "
              f"({out.stat().st_size} bytes)", file=sys.stderr)
        written += 1

if written == 0:
    sys.exit("ERROR: no schema written — CRD had no version carrying an openAPIV3Schema")
PYEOF

info "==> done"
