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

The target updates `Chart.yaml` and prints the next steps (annotation, README, commit, push).

<br/>

### Upstream version tracking (`upgrade.sh`)

Some charts wrap a third-party component whose image tag evolves on its own release cadence (e.g. `elasticsearch-eck`, `kibana-eck`). These charts ship a local `upgrade.sh` that queries the component's upstream version feed (e.g. `artifacts-api.elastic.co`), verifies the container image is published, backs up the current state, and rewrites the chart's `Chart.yaml` `appVersion` plus `values.yaml` `version` in one shot.

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

## PR Process

1. **Bump the chart version** in `Chart.yaml` for any change to chart contents (`templates/`, `values.yaml`, `values.schema.json`, `Chart.yaml` itself).
   - Use [SemVer](https://semver.org/): patch for fixes, minor for additive features, major for breaking changes.
2. **Add an entry to `artifacthub.io/changes`** annotation in `Chart.yaml` describing the change. Format:
   ```yaml
   artifacthub.io/changes: |
     - kind: added | changed | deprecated | removed | fixed | security
       description: One-line summary of the change
   ```
3. **Update the chart's `README.md`** if values, behavior, or install instructions change.
4. **Verify locally** with the commands above.
5. **Open a PR**. CI runs `helm lint`, `ct lint`, `helm template`, and `kubeconform` on changed charts.
6. After review and merge, [chart-releaser-action](https://github.com/helm/chart-releaser-action) automatically packages the chart, creates a GitHub Release tagged `<chart-name>-<version>`, updates the gh-pages index, and pushes the OCI artifact to GHCR.

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
