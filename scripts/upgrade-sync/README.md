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

| Template | Use case | Required CONFIG |
|---|---|---|
| `chart-appversion` | Chart maintainers tracking an upstream GA version to bump `Chart.yaml.appVersion` (and optionally `values.yaml.<key>`). Used by `ghost`, `unity-mcp-server`, `elasticsearch-eck`, `kibana-eck`. | `VERSION_SOURCE` ∈ {`elastic-artifacts`, `docker-hub`, `github-release`}, plus source-specific args (see below). |
| `helm-charts/external-tracked` | Chart maintainers tracking an upstream GitHub repo that ships **both** a versioned image **and** companion CRD manifests. Refreshes `Chart.yaml.appVersion`, `values.yaml.version`, and `templates/crd-*.yaml`. Used by `keycloak-operator`. | `GITHUB_REPO`, `CONTAINER_IMAGE`, `CRD_FILES` (array), plus the helm-template gate vars (`GATE_OPEN`/`GATE_CLOSE`/`LABELS_ANN_BLOCK`). |

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

## Dry-run JSON contract

`scripts/check-version/check-version.sh` consumes the `--dry-run --json`
output of each chart's `upgrade.sh`. This is the **API surface** between the
templates and the orchestrator — when you change either side, change both in
the same PR and re-run `make version-check` to verify.

### Schema

`helm-charts.upgrade.dryrun.v1` — a single-line JSON object on stdout when
`upgrade.sh` is invoked with `--dry-run --json`. All human progress output is
redirected to stderr in this mode.

| Field | Type | When | Meaning |
|---|---|---|---|
| `schema` | string | always | Contract version. Must start with `helm-charts.upgrade.dryrun.`. Bump suffix on shape changes. |
| `chart` | string | always | Basename of `CHART_DIR` (e.g. `ghost`). |
| `status` | enum | always | One of `uptodate`, `drift`, `blocked`, `no-image`, `error`. |
| `current` | string\|null | always | Current version read from `Chart.yaml` / `values.yaml`. |
| `latest` | string\|null | `uptodate`/`drift`/`no-image` only | Version that would be applied. `null` for `blocked` (sibling forbids any bump) and exhausted `no-image`. For `drift` after image-fallback, this is the fallback target (older than `upstream_latest`). |
| `upstream_latest` | string\|null | always | Raw upstream feed result before any image-fallback decision. For `drift` without fallback, equals `latest`. |
| `major_bump` | bool | always | `true` only for `status=drift` when `current.major != latest.major`. |
| `sibling` | object\|null | `blocked` only | `{"name": "<sibling-chart>", "version": "<sibling-current>"}` — the constraint that's holding the bump. |
| `error` | string\|null | `error` and some `no-image` | Human-readable reason. `null` for happy-path states. |

### Status transitions

| `status` | `latest` | `upstream_latest` | Notes |
|---|---|---|---|
| `uptodate` | = `current` | = `current` | Upstream feed itself is at the current version. |
| `drift` | new version | = `latest` (or older if image-fallback hit) | Bump candidate. Check `major_bump` for review escalation. |
| `blocked` | `null` | the version that was attempted | Sibling check rejected the target. `sibling.name` and `sibling.version` describe the constraint. |
| `no-image` | `null` (exhausted) or `current` (matches-current) | upstream feed value | Newer GA exists upstream but the container image isn't published yet. Re-run later. |
| `error` | `null` | maybe `null` | Fetch failed, `Chart.yaml`/`values.yaml` unreadable, etc. See `error`. |

### Two ways to break the contract silently

1. **New status added to a template without bumping `schema`.** Add a new
   `status` enum value (e.g. `manual-review`) and update `detect_drift` in
   `check-version.sh` to handle it; the schema string stays `v1` because the
   shape is additive. If you change a field name or remove one, bump to
   `v2` and update both sides.
2. **Field renamed.** `check-version.sh` reads fields by exact name. Renaming
   `upstream_latest` -> `feed_latest` without updating the parser silently
   misclassifies every chart.

Use `bash charts/<name>/upgrade.sh --dry-run --json | python3 -m json.tool`
to eyeball the record before merging template changes.
