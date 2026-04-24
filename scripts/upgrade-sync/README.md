# upgrade-sync

Canonical-body propagation for per-chart `upgrade.sh` scripts.

Mirrors the pattern used by `~/gitlab-project/kuberntes-infra/scripts/upgrade-sync/`: each chart keeps a tiny Configuration block at the top of `upgrade.sh`, and the long common body is sourced from a single template. Drifted bodies are a bug; `sync.sh --check` catches them.

## How it works

Each chart's `upgrade.sh` declares its template on the second line:

```bash
#!/bin/bash
# upgrade-template: chart-appversion
#
# Purpose: ...
set -euo pipefail

# ============================================================
# Configuration — per chart
# ============================================================
SCRIPT_NAME="ghost Helm Chart appVersion Bump"
COMPONENT_LABEL="ghost"
VERSION_SOURCE="docker-hub"
VERSION_SOURCE_ARG="library/ghost"
# ... etc ...
# ============================================================

# === BEGIN CANONICAL BODY ===
# Everything between BEGIN/END is overwritten by sync.sh.
# === END CANONICAL BODY ===
```

`sync.sh` only rewrites the region between `# === BEGIN CANONICAL BODY ===` and `# === END CANONICAL BODY ===`. The Configuration block is untouched.

## Available templates

| Template | Use case | Required `VERSION_SOURCE` | `VERSION_SOURCE_ARG` |
|---|---|---|---|
| `chart-appversion.sh` | Chart maintainers tracking an upstream GA version to bump `Chart.yaml.appVersion` (and optionally `values.yaml.<key>`) | one of: `elastic-artifacts`, `docker-hub`, `github-release` | source-specific (see below) |

### `VERSION_SOURCE` options (inside `chart-appversion.sh`)

| Source | `VERSION_SOURCE_ARG` | Notes |
|---|---|---|
| `elastic-artifacts` | _(empty)_ | Queries `https://artifacts-api.elastic.co/v1/versions` — Elastic Stack products (elasticsearch, kibana, logstash, beats). |
| `docker-hub` | `"library/ghost"`, `"bitnami/redis"`, … | Docker Hub Registry API. Pulls paginated tag list, filters to plain `X.Y.Z` tags. |
| `github-release` | `"owner/repo"` (e.g. `"CoplayDev/unity-mcp"`) | GitHub Releases API. `GITHUB_TAG_PREFIX` env (default `v`) is stripped. Set `GITHUB_TOKEN` to avoid rate limits. |

## Commands

```bash
# From repo root:
scripts/upgrade-sync/sync.sh --list    # every chart and its template + sync status
scripts/upgrade-sync/sync.sh --check   # exits 1 if any canonical-body drifts
scripts/upgrade-sync/sync.sh --apply   # overwrite canonical bodies to match template
```

CI should run `--check` on every PR that touches `charts/*/upgrade.sh` or `scripts/upgrade-sync/templates/`.

## Authoring a new chart's `upgrade.sh`

1. Copy a sibling chart's `upgrade.sh` (e.g. `charts/ghost/upgrade.sh`) as a starting point.
2. Rewrite the Configuration block at the top (keep the `# upgrade-template:` line untouched).
3. Run `scripts/upgrade-sync/sync.sh --apply` to drop in the canonical body verbatim.
4. Make it executable: `chmod +x charts/<name>/upgrade.sh`.
5. Smoke-test: `./charts/<name>/upgrade.sh --dry-run`.

## Authoring a new template

1. Add `scripts/upgrade-sync/templates/<name>.sh` with the full script shape: shebang, per-chart CONFIG placeholders, `# === BEGIN CANONICAL BODY ===` … `# === END CANONICAL BODY ===`.
2. Update charts to reference it via `# upgrade-template: <name>` on line 2.
3. Run `sync.sh --apply` and commit.

## What the template does NOT do

- It does not touch a live cluster. `upgrade.sh` is file-level only.
- It does not bump the chart's own SemVer (`Chart.yaml.version`). That's a maintainer decision — use `make bump CHART=<name> LEVEL=patch|minor|major`.
- It does not push to a registry or trigger a release. `Chart.yaml.version` bumps drive `chart-releaser-action`.

## Backup directory

Each successful bump writes `backup/<timestamp>/` inside the chart's directory. These are **tracked in git** (rollback trail) — do not add them to `.gitignore`. Old backups are auto-pruned to `KEEP_BACKUPS` (default 5).
