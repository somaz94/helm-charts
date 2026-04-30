# upgrade-sync

Canonical-body propagation for per-chart `upgrade.sh` scripts.

Inspired by the same `# upgrade-template:` convention used in
`somaz94/kuberntes-infra/scripts/upgrade-sync/`, but **simplified for chart
publishing** rather than infrastructure component management. Each chart keeps
a tiny Configuration block at the top of `upgrade.sh`, and the long common
body is sourced from a single template. Drifted bodies are a bug;
`sync.sh --check` catches them.

### How this differs from `kuberntes-infra/scripts/upgrade-sync/`

| Aspect | This repo (publisher) | kuberntes-infra (consumer) |
|---|---|---|
| Domain | Helm chart publishing — bumps `Chart.yaml.appVersion` (file-only, no cluster) | Infrastructure components — drives `helmfile apply` against live clusters |
| Marker scheme | **2-marker**: `# === BEGIN CANONICAL BODY ===` / `# === END CANONICAL BODY ===` | **3-marker**: three `# ===` lines surrounding the CONFIG block |
| Templates | `chart-appversion.sh`, `helm-charts/external-tracked.sh` (and growing) | 8 templates (`external-standard`, `external-oci`, `external-oci-with-mirror`, `external-oci-cr-version`, `local-with-templates`, `local-cr-version`, `external-with-image-tag`, `ansible-github-release`) |
| Commands | `--list`, `--check`, `--apply`, `--status` | `--check`, `--apply [--force]`, `--status`, `--print-expected`, `--insert-headers`, `--no-header` |
| Auto-PR | Yes — `scripts/check-version/check-version.sh --apply` opens one PR per drifted chart | No — infrastructure changes are always reviewed manually |
| Sister scripts | `scripts/check-version/`, `scripts/changelog/` | `check-versions.sh`, `manage-backups.sh` (in same directory) |

The two systems are **not** code-shared and intentionally so — they live in
different repos and serve opposite ends of the chart lifecycle (publish vs
consume). They are linked only by the OCI artifact at
`ghcr.io/somaz94/charts/<name>` (see "Publisher-Consumer flow" below).

### Publisher-Consumer flow

Charts in this repo are consumed by `kuberntes-infra` via OCI. When a chart's
`Chart.yaml.version` is bumped here and merged to `main`,
`chart-releaser-action` publishes a new artifact to
`ghcr.io/somaz94/charts/<name>` with a GitHub Release tag `<chart>-<version>`.
The consumer side then picks it up on its next `check-versions.sh` run:

```
[Stage 1: Publisher — this repo]
  charts/ghost/upgrade.sh             tracks Docker Hub library/ghost
    -> Chart.yaml.appVersion = 5.140.1
    -> check-version.sh --apply opens PR (chore/auto-bump/ghost-5.140.1)
    -> maintainer reviews & merges to main
                                       v
  chart-releaser-action publishes ghcr.io/somaz94/charts/ghost:0.5.4
  GitHub Release tag: ghost-0.5.4

[Stage 2: Consumer — kuberntes-infra]
  tools/ghost/upgrade.sh              tracks somaz94/helm-charts releases
                                       (GITHUB_TAG_PREFIX=ghost-)
    -> detects ghost-0.5.4
    -> rewrites helmfile.yaml.gotmpl chart version to 0.5.4
    -> mirror Ghost+MySQL images to Harbor
    -> manual `helmfile apply`
```

Charts wired into this flow today (each has both a publisher-side
`upgrade.sh` here and a consumer-side `upgrade.sh` in kuberntes-infra):

| Publisher (this repo) | Publisher source | Consumer (kuberntes-infra) | Consumer template |
|---|---|---|---|
| `charts/ghost` | Docker Hub `library/ghost` | `tools/ghost` | `external-oci-with-mirror` |
| `charts/unity-mcp-server` | GitHub `CoplayDev/unity-mcp` | `tools/unity-mcp-server` | `external-oci-with-mirror` |
| `charts/keycloak-operator` | GitHub `keycloak/keycloak-k8s-resources` | `security/keycloak-operator` | `external-oci` |
| `charts/elasticsearch-eck` | Elastic artifacts API | `observability/logging/elasticsearch` | `external-oci-cr-version` |
| `charts/kibana-eck` | Elastic artifacts API | `observability/logging/kibana` | `external-oci-cr-version` |

Pure CR-wrapper charts (`certmanager-letsencrypt`, `keycloak-cr`,
`nginx-gateway-cr`) and simple wrapper charts (`mysql`, `postgresql`, `redis`)
do **not** ship `upgrade.sh` — see "Authoring a new chart's upgrade.sh" below.

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

## Dry-run output contract

`scripts/check-version/check-version.sh` parses `upgrade.sh --dry-run`
output via fixed string matches. Treat the following lines emitted by
templates under `templates/` as the **API surface** consumed by
`check-version.sh` — when you change either side, change both in the same PR
and re-run `make version-check` to verify.

Strings consumed by `check-version.sh`:

| Pattern | Emitted by | Consumed in `check-version.sh` | Drift status |
|---|---|---|---|
| `Already up to date` | `chart-appversion.sh` happy-path uptodate | `detect_drift` | `uptodate` |
| `Latest available: <X.Y.Z>` | `chart-appversion.sh` upstream feed result | `parse_latest_from_dry_run`, `detect_drift` | `drift` |
| `Using explicit target: <X.Y.Z>` | `chart-appversion.sh` when `--version` is given | `parse_latest_from_dry_run` | `drift` (forced) |
| `Latest available (with published image): <X.Y.Z>` | `chart-appversion.sh` image-fallback path | `detect_drift` | `drift` (fallback target) |
| `Newest available matches current. Nothing to bump.` | `chart-appversion.sh` image-fallback returns current | `detect_drift` | `no-image` |
| `no GA version with a published image found` | `chart-appversion.sh` image-fallback exhausted | `detect_drift` | `no-image` |
| `is HIGHER than <sibling> version` | `chart-appversion.sh` sibling constraint | `detect_drift` | `blocked` |

Two ways to break the contract silently:

1. **Renaming/punctuation drift.** `check-version.sh` uses `grep -F` (fixed
   string) for the simple cases and tolerant regexes for sibling/fallback.
   Even a comma or capitalization change can cause a chart to be misclassified
   as `error` or always `uptodate`.
2. **New status added to the template without updating
   `detect_drift`.** A new branch in `chart-appversion.sh` that emits
   neither "Already up to date" nor "Latest available:" parses as `error`.

Future-proofing: a `--dry-run --json` mode is planned (will replace the
text grep). Until then, treat this section as the contract.
