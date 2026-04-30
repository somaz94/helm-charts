# Contributing

Thank you for your interest in contributing to this Helm chart collection!

<br/>

## Repository Layout

```
helm-charts/
├── charts/
│   └── <chart-name>/          # one directory per chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json
│       ├── README.md
│       └── templates/
└── .github/workflows/         # CI / release automation
```

Each chart is independently versioned via its own `Chart.yaml` and is released to both:
- **Helm repo**: `https://charts.somaz.blog`
- **OCI registry**: `oci://ghcr.io/somaz94/charts/<chart-name>`

<br/>

## Prerequisites

- [Helm](https://helm.sh/) **3.16+**
- [chart-testing](https://github.com/helm/chart-testing) (`ct`) — `brew install chart-testing`
- [kubeconform](https://github.com/yannh/kubeconform) (optional, matches CI) — `brew install kubeconform`

<br/>

## Local Development

The repository ships a `Makefile` that wraps the common operations. Run `make help` to see all targets.

### Verify a chart

```bash
# Run everything CI runs (lint + ct lint + template + kubeconform)
make ci

# Or individually (CHART=<name> limits to one chart, otherwise all)
make lint                              # helm lint
make ct-lint                           # chart-testing lint
make template                          # helm template smoke render
make validate                          # kubeconform schema validation
make lint CHART=nginx-gateway-cr       # limit to one chart
```

Raw equivalents (without the Makefile):

```bash
helm lint charts/<chart-name>
helm template ci charts/<chart-name> > /dev/null
helm template ci charts/<chart-name> | kubeconform -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

### Add a new chart

The fastest path is to copy an existing chart and adapt it:

```bash
make scaffold CHART=<new-chart> FROM=<existing-chart>
# Copies charts/<existing-chart>/ -> charts/<new-chart>/, renames in Chart.yaml,
# resets version to 0.1.0. Then edit description/keywords/values/templates.
```

Or scaffold manually:

```bash
mkdir -p charts/<new-chart>/templates
# Create Chart.yaml, values.yaml, values.schema.json, README.md, templates/...
make lint CHART=<new-chart>
```

Required files:
- `Chart.yaml` — `apiVersion: v2`, `version`, `appVersion`, `description`, `keywords`, `maintainers`, ArtifactHub annotations
- `values.yaml` — sensible defaults; default install should be a safe no-op when applicable
- `values.schema.json` — JSON Schema (draft-07) for input validation
- `README.md` — purpose, prerequisites, install, values reference table

### Bump a chart's version

```bash
make bump CHART=<chart-name> LEVEL=patch    # 0.1.0 -> 0.1.1
make bump CHART=<chart-name> LEVEL=minor    # 0.1.0 -> 0.2.0
make bump CHART=<chart-name> LEVEL=major    # 0.1.0 -> 1.0.0
```

The target updates `Chart.yaml` and prints the next steps (annotation, changelog, README, commit, push).

<br/>

### Sync the chart's `CHANGELOG.md`

After bumping `version` and adding the new `artifacthub.io/changes` entry to `Chart.yaml`, regenerate the chart's `CHANGELOG.md`:

```bash
make changelog CHART=<chart-name>            # prepend a new version section
make changelog CHART=<chart-name> DRY_RUN=1  # preview without writing
make changelog-all                           # sync every chart (backfill / sanity)
```

The script reads `Chart.yaml` `version` + `annotations.artifacthub.io/changes`, maps each entry's `kind` (`added` / `changed` / `deprecated` / `removed` / `fixed` / `security`) to a [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) section, and prepends a `## [vX.Y.Z] - YYYY-MM-DD` block to `charts/<chart-name>/CHANGELOG.md`. The annotation in `Chart.yaml` remains the source of truth — `CHANGELOG.md` is a regenerable mirror, never edit it directly. See [`scripts/changelog/README.md`](scripts/changelog/README.md) for details.

A CI guard (`.github/workflows/lint.yml`, job `changelog-check`) fails any PR that bumps a chart's `version:` line without also updating that chart's `CHANGELOG.md`.

<br/>

### Upstream version tracking (`upgrade.sh`)

Some charts wrap a third-party component whose image tag evolves on its own release cadence (e.g. `elasticsearch-eck`, `kibana-eck`, `ghost`, `unity-mcp-server`). These charts ship a local `upgrade.sh` that queries the component's upstream version feed (Elastic Artifacts API, Docker Hub, GitHub Releases), verifies the container image is published, backs up the current state, and rewrites the chart's `Chart.yaml` `appVersion` (plus `values.yaml.<VERSION_KEY>` when set).

```bash
cd charts/<chart-name>
./upgrade.sh --dry-run              # preview without changes
./upgrade.sh                        # bump to latest GA
./upgrade.sh --version 9.1.2        # pin to a specific version
./upgrade.sh --rollback             # restore files from backup/
./upgrade.sh --list-backups
./upgrade.sh --cleanup-backups      # keep last 5 (override via KEEP_BACKUPS=N)
```

`upgrade.sh` **does not touch any cluster**. It only rewrites local files and places the previous versions in `backup/<timestamp>/`. The chart's own SemVer (`Chart.yaml` `version`) is **not** auto-mirrored — bump it afterwards via `make bump CHART=<chart-name> LEVEL=minor`.

Charts with sibling-version constraints (e.g. `kibana-eck` requires version ≤ `elasticsearch-eck`) enforce that by reading the sibling's `values.yaml` directly — no kubectl access is needed.

<br/>

### `upgrade.sh` canonical template

All `upgrade.sh` scripts are **thin wrappers** around a single canonical body in [`scripts/upgrade-sync/templates/chart-appversion.sh`](scripts/upgrade-sync/templates/chart-appversion.sh). Each chart keeps only its Configuration block (script name, VERSION_SOURCE, CONTAINER_IMAGE, MAJOR_PIN, …) at the top of `upgrade.sh`; everything between `# === BEGIN CANONICAL BODY ===` and `# === END CANONICAL BODY ===` is synced from the template.

```bash
scripts/upgrade-sync/sync.sh --list     # show every chart and its template + sync status
scripts/upgrade-sync/sync.sh --check    # exits 1 if any chart drifts
scripts/upgrade-sync/sync.sh --apply    # overwrite canonical bodies to match templates
```

Supported `VERSION_SOURCE` values: `elastic-artifacts` (ES/Kibana), `docker-hub` (Ghost), `github-release` (Unity MCP, generic OSS). See [`scripts/upgrade-sync/README.md`](scripts/upgrade-sync/README.md) for the full list of config knobs.

<br/>

### Automated upstream version checks (`check-version.sh`)

A scheduled GitHub Actions workflow ([`.github/workflows/check-versions.yml`](.github/workflows/check-versions.yml)) sweeps every chart's `upgrade.sh` once a week, bumps any drifted chart, runs `make ci` to validate, and opens **one PR per chart**. Triggered locally via the same script:

```bash
./scripts/check-version/check-version.sh                   # drift report (default)
./scripts/check-version/check-version.sh --apply           # bump + PR for every drifted chart
./scripts/check-version/check-version.sh --apply --chart ghost --no-pr   # local-only test bump
```

Major-version bumps are **skipped by default** (the report flags them as `drift-major`); opt in with `--include-major` after reviewing breaking changes. Sibling-blocked charts (e.g. `kibana-eck` waiting on `elasticsearch-eck`) are reported as `blocked` and unblock automatically once the sibling PR lands.

See [`scripts/check-version/README.md`](scripts/check-version/README.md) for the full status matrix, branch-protection notes, and `GITHUB_TOKEN` PR-trigger caveats.

<br/>

### HA rolling-upgrade verification (stateful charts)

Charts that claim zero-downtime rolling upgrade support (currently `elasticsearch-eck` and `kibana-eck`) **must re-run the HA verification** before a **major** chart bump (e.g. `0.x` → `1.0.0`). Procedure, load generator, and success criteria are documented in [`docs/ha-rolling-verification.md`](docs/ha-rolling-verification.md).

Not required for:
- patch bumps (0.1.1 → 0.1.2) that only touch `README.md` or `artifacthub.io/changes`
- Stack image version bumps via `upgrade.sh` (image-only changes inherit the previously verified chart behavior)

Required for:
- major chart bumps
- changes to `podTemplate.spec`, StatefulSet / Deployment definitions, or PDB defaults
- ECK operator major-version bump

<br/>

## PR Process

1. **Bump the chart version** in `Chart.yaml` for any change to chart contents (`templates/`, `values.yaml`, `values.schema.json`, `Chart.yaml` itself).
   - Use [SemVer](https://semver.org/): patch for fixes, minor for additive features, major for breaking changes.
2. **Add an entry to `artifacthub.io/changes`** annotation in `Chart.yaml` describing the change. Format:
   ```yaml
   artifacthub.io/changes: |
     - kind: added | changed | deprecated | removed | fixed | security
       description: One-line summary of the change
   ```
3. **Run `make changelog CHART=<name>`** to update `charts/<chart>/CHANGELOG.md`. The new section is prepended automatically; commit the file alongside `Chart.yaml`. CI fails any version bump that does not include a `CHANGELOG.md` update.
4. **Update the chart's `README.md`** if values, behavior, or install instructions change.
5. **Verify locally** with the commands above.
6. **Open a PR**. CI runs `helm lint`, `ct lint`, `helm template`, and `kubeconform` on changed charts.
7. After review and merge, [chart-releaser-action](https://github.com/helm/chart-releaser-action) automatically packages the chart, creates a GitHub Release tagged `<chart-name>-<version>`, updates the gh-pages index, and pushes the OCI artifact to GHCR.

<br/>

## Commit Convention

[Conventional Commits](https://www.conventionalcommits.org/), e.g.:

- `feat(<chart>): add <feature>`
- `fix(<chart>): correct <issue>`
- `docs(<chart>): clarify <topic>`
- `chore: update workflow <name>`
- `ci: <change>`

<br/>

## Reporting Bugs / Requesting Features

Please use the [issue templates](https://github.com/somaz94/helm-charts/issues/new/choose). For security issues, see [SECURITY.md](SECURITY.md) instead.

<br/>

## License

By contributing, you agree that your contributions will be licensed under [Apache-2.0](LICENSE).
