# CLAUDE.md — helm-charts

Repo-specific guidance for this Helm chart collection. Assume global `~/.claude/CLAUDE.md` rules (commit style, push safety, language) already apply — this file only adds conventions unique to this repo.

<br/>

## When adding a new chart

Adding a chart under `charts/<name>/` **requires updating three index files in the same PR**. This is the most frequently missed step:

| File | What to update |
|---|---|
| `README.md` | Append a row to the "Charts" table with name, version, and one-line description. |
| `SECURITY.md` | Append a row to the "Supported Versions" table. Every chart the repo owner commits to patching must be listed, otherwise the new chart is silently out of security policy scope. |
| `CONTRIBUTING.md` | Only update if the chart introduces a new pattern (e.g. `upgrade.sh` tooling, new helper script). No change needed for plain wrapper charts. |

Run `git status` before every chart-adding commit and confirm `SECURITY.md` and `README.md` are both modified.

<br/>

## Chart conventions

### File layout (required)

```
charts/<chart-name>/
├── Chart.yaml                      # apiVersion: v2, kubeVersion: ">=1.25.0-0"
├── values.yaml                     # heavy comments, safe defaults
├── values.schema.json              # JSON Schema draft-07, additionalProperties: false at top level
├── README.md                       # English only (no Korean, no *-en.md siblings)
├── .helmignore                     # add `upgrade.sh` and `backup/` if shipping upgrade.sh
└── templates/
    ├── NOTES.txt                   # post-install instructions
    ├── _helpers.tpl                # defines <chart>.labels and <chart>.annotations
    └── *.yaml                      # one file per resource kind
```

### Chart.yaml required annotations

```yaml
annotations:
  artifacthub.io/category: <category>     # networking | monitoring | security | storage | database
  artifacthub.io/license: Apache-2.0
  artifacthub.io/links: |
    - name: Source
      url: https://github.com/somaz94/helm-charts
    # plus upstream doc / source links
  artifacthub.io/prerelease: "false"
  artifacthub.io/changes: |
    - kind: added | changed | deprecated | removed | fixed | security
      description: <one-line change summary>
```

`artifacthub.io/changes` must gain a new entry every time `Chart.yaml` `version` is bumped.

### values.schema.json conventions

- `additionalProperties: false` at the **top level only** — blocks unknown keys at root, forces callers to use declared paths.
- Escape-hatch blocks (`specExtra`, `podTemplateExtra`, `containerExtra`, `nodeSetExtra`, `<resource>Extra`) must use `additionalProperties: true` so arbitrary YAML passes through.
- Use `$defs` for reusable shapes (`resources`, `metadataBlock`, etc.).

### Template conventions

- `_helpers.tpl` defines `<chart>.labels` (includes standard `app.kubernetes.io/*` labels + `.Values.commonLabels`) and `<chart>.annotations` (merges `.Values.commonAnnotations` with a per-resource extras dict).
- Per-resource metadata override via `.Values.resourceMetadata.<resource>.{labels,annotations}` — consumer can annotate only the ServiceMonitor without polluting the primary CR.
- Every template file is gated by a `.Values.<feature>.enabled` boolean (except the primary CR and `NOTES.txt`).

### README structure

```markdown
# <chart-name>

<one-sentence summary>

## What it deploys         # resource table
## Versioning              # only if appVersion has semantic meaning
## Prerequisites           # k8s version, required operators/CRDs, storageclass notes
## Install                 # OCI registry + Classic Helm repo
## Quick examples          # 3–5 complete, paste-ready examples
## Values reference        # tables by block
## Maintaining this chart  # only if upgrade.sh / make bump flow exists
## License
```

Add `<br/>` between every `##` and `###` heading. English only — this repo does not have Korean `README.md` siblings.

<br/>

## `upgrade.sh` pattern

Include a chart-local `upgrade.sh` **only** when the chart wraps a third-party component with its own release cadence (e.g. `elasticsearch-eck`, `kibana-eck`). Skip for pure CR-wrapper charts (`nginx-gateway-cr`, `certmanager-letsencrypt`).

`upgrade.sh` must:

- Live at `charts/<chart>/upgrade.sh`, marked executable, gitignored-from-packaging via `.helmignore` (add `upgrade.sh` and `backup/`).
- Have a `# upgrade-template: helm-charts/<template-name>` header on line 2 for future aggregator (`check-versions.sh`) discovery.
- Be **file-only**: rewrite `Chart.yaml` `appVersion` and `values.yaml` `version`. **Never** call `kubectl`, `helm`, or `helmfile`.
- Ship `--dry-run`, `--version <v>`, `--rollback`, `--list-backups`, `--cleanup-backups`.
- Back up to `backup/<timestamp>/` before writing. Keep `KEEP_BACKUPS` (default 5).
- Append a `- kind: changed` entry to `annotations.artifacthub.io/changes` on successful bump.
- **Not** mirror `appVersion` into `Chart.yaml` `version` — chart SemVer stays under maintainer control via `make bump`.

For sibling-dependent charts (e.g. `kibana-eck` needs Kibana ≤ Elasticsearch), read the sibling's `values.yaml` directly — never query a cluster.

<br/>

## Versioning

- `Chart.yaml` **version** → chart's own SemVer. Bumped by maintainer via `make bump CHART=<name> LEVEL=patch|minor|major` for template or schema changes.
- `Chart.yaml` **appVersion** → the version of whatever the chart wraps. For pure CR-wrapper charts this is arbitrary (e.g. `"1.0.0"`); for charts wrapping a versioned component it tracks upstream and is bumped by `upgrade.sh`.
- `values.yaml` **version** (when present) → injected into the rendered CR's `spec.version`. Defaults to `appVersion`; consumer may override.

<br/>

## Validation before commit

```bash
make lint CHART=<name>           # helm lint
make template CHART=<name>       # helm template smoke render
make ci                          # full CI locally (helm lint + ct lint + helm template + kubeconform)
```

If you added a template that emits a new resource kind, also verify it renders with every flag enabled (all optional `*.enabled: true` features on) — that's the path most likely to break.

<br/>

## Release mechanics

Releases are fully automatic — merging a `Chart.yaml` `version` bump to `main` triggers `release.yml`, which:

1. Packages changed charts via `chart-releaser-action`
2. Creates a GitHub Release tagged `<chart>-<version>`
3. Updates the `gh-pages` `index.yaml` (serves `https://charts.somaz.blog`)
4. Pushes the OCI artifact to `ghcr.io/somaz94/charts/<chart>`

Never tag releases manually; never push to `gh-pages` manually.

<br/>

## Things that live elsewhere

- **Commit style, push safety, conventional commits** — global `~/.claude/CLAUDE.md`
- **Korean vs English rules** — this repo is English-only (README.md is the only doc, no `README-en.md` siblings)
- **Sensitive value sanitization** — this is a public repo; there should be nothing to sanitize. If you see a real internal domain/token in a PR, reject it.
