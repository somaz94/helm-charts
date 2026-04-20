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

### Verify a chart

```bash
# Lint
helm lint charts/<chart-name>
ct lint --target-branch main --check-version-increment=false

# Render templates (smoke test)
helm template ci charts/<chart-name>

# Render with example values
helm template ci charts/<chart-name> -f charts/<chart-name>/ci/example-values.yaml

# Validate generated manifests against k8s + CRD schemas
helm template ci charts/<chart-name> | kubeconform \
  -strict \
  -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

### Add a new chart

```bash
mkdir -p charts/<new-chart>/templates
# Create Chart.yaml, values.yaml, values.schema.json, README.md, templates/...
helm lint charts/<new-chart>
```

Required files:
- `Chart.yaml` — `apiVersion: v2`, `version`, `appVersion`, `description`, `keywords`, `maintainers`, ArtifactHub annotations
- `values.yaml` — sensible defaults; default install should be a safe no-op when applicable
- `values.schema.json` — JSON Schema (draft-07) for input validation
- `README.md` — purpose, prerequisites, install, values reference table

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
