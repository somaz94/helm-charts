# scripts

<br/>

Maintainer automation for the helm-charts mono-repo. Three independent
sub-systems collaborate through a small set of file-level contracts; nothing
in here touches a live cluster.

```
scripts/
├─ upgrade-sync/    # canonical-body propagation for charts/*/upgrade.sh
├─ check-version/   # drift detection + auto-bump PR orchestration
└─ changelog/       # Chart.yaml annotation -> charts/*/CHANGELOG.md mirror
```

<br/>

## Overview

| Sub-system | Entry point | What it does | When it runs |
|---|---|---|---|
| [`upgrade-sync/`](upgrade-sync/) | `sync.sh` | Propagates the canonical body of each per-chart `upgrade.sh` from a single template under `templates/`. Catches body drift between charts. | On every PR that touches `charts/*/upgrade.sh` or `templates/`. Run via `make sync-check`. |
| [`check-version/`](check-version/) | `check-version.sh` | Iterates every chart's `upgrade.sh --dry-run --json`, classifies drift (`uptodate` / `drift` / `blocked` / `no-image` / `error`), and (with `--apply`) opens one PR per drifted chart. | Weekly via `.github/workflows/check-versions.yml`, or manual `make version-check` / `make version-apply`. |
| [`changelog/`](changelog/) | `sync-changelog.sh` | Renders per-chart `CHANGELOG.md` from `Chart.yaml`'s `annotations.artifacthub.io/changes` (Keep a Changelog format). Idempotent. | After `upgrade.sh` resets the annotation; via `make changelog CHART=<name>` or `make changelog-all`. |

<br/>

## How the pieces fit together

```
  upstream registry                           ┌──────────────────────────────────┐
  (Docker Hub / GHCR / Elastic API / GitHub)  │ scripts/check-version/           │
            │                                 │   for chart in charts/*:         │
            │ tracked by                      │     run upgrade.sh --dry-run     │
            ▼                                 │                  --json          │
  charts/<name>/upgrade.sh                    │     classify drift               │
   ▲                                          │   on --apply: open one auto-PR   │
   │ canonical body                           │              per drifted chart   │
   │ propagated by                            └──────────────────────────────────┘
  scripts/upgrade-sync/sync.sh                                  │
   │                                                            │ runs as part of --apply
   │                                                            ▼
  scripts/upgrade-sync/templates/             ┌──────────────────────────────────┐
   ├─ chart-appversion.sh                     │ charts/<name>/upgrade.sh:        │
   └─ helm-charts/external-tracked.sh         │   reset Chart.yaml annotation    │
                                              │     artifacthub.io/changes       │
                                              └──────────────────────────────────┘
                                                                │
                                                                │ rendered by
                                                                ▼
                                              ┌──────────────────────────────────┐
                                              │ scripts/changelog/               │
                                              │   prepend section to             │
                                              │   charts/<name>/CHANGELOG.md     │
                                              └──────────────────────────────────┘
```

<br/>

## Contracts between sub-systems

| Producer | Artifact | Consumer | Documented in |
|---|---|---|---|
| `templates/*.sh` | `# === BEGIN/END CANONICAL BODY ===` markers | `scripts/upgrade-sync/sync.sh` | [`upgrade-sync/README.md`](upgrade-sync/README.md) |
| `charts/<name>/upgrade.sh --dry-run --json` | JSON record (schema `helm-charts.upgrade.dryrun.v1`) | `scripts/check-version/check-version.sh` | [`upgrade-sync/README.md` § Dry-run JSON contract](upgrade-sync/README.md#dry-run-json-contract) |
| `charts/<name>/upgrade.sh` | `Chart.yaml.annotations."artifacthub.io/changes"` (RESET semantics) | `scripts/changelog/sync-changelog.sh` | [`changelog/README.md`](changelog/README.md) |

When changing one side of any of these contracts, change the other side in the
same PR and re-run `make sync-check` + `make version-check` to verify.

<br/>

## Makefile entry points

All three sub-systems are exposed through the top-level `Makefile`:

| Target | Wraps |
|---|---|
| `make sync-check` | `scripts/upgrade-sync/sync.sh --check` |
| `make sync-apply` | `scripts/upgrade-sync/sync.sh --apply` |
| `make sync-list` | `scripts/upgrade-sync/sync.sh --list` |
| `make sync-status` | `scripts/upgrade-sync/sync.sh --status` |
| `make version-check` | `scripts/check-version/check-version.sh --check` |
| `make version-apply` | `scripts/check-version/check-version.sh --apply` |
| `make changelog CHART=<name>` | `scripts/changelog/sync-changelog.sh charts/<name>` |
| `make changelog-all` | `scripts/changelog/sync-changelog.sh --all` |
| `make shell-lint` | `bash -n` + `zsh -n` + `shellcheck` (if installed) over every `scripts/**/*.sh` and `charts/*/upgrade.sh`. `STRICT=1 make shell-lint` requires `shellcheck`. |

<br/>

## Local prerequisites

Shared by all three sub-systems:

- `bash` ≥ 4 (Homebrew bash on macOS) **or** `zsh` ≥ 5 — scripts are written
  for both shells; the shebang is `#!/usr/bin/env bash`, so direct execution
  uses bash, but `zsh path/to/script.sh` works equivalently
- `python3` (used by every script for JSON / YAML manipulation)
- `git`

Additional, per sub-system:

- `helm` ≥ 3.16 (`upgrade-sync` template smoke-test, `check-version` indirectly via `make ci`)
- `chart-testing` + `kubeconform` (`check-version --apply` runs `make ci` per chart)
- `gh` (`check-version --apply` without `--no-pr`)
- `shellcheck` (optional; `make shell-lint` runs it when available, and
  `STRICT=1 make shell-lint` requires it for CI)
- `yq` is **not** required — every YAML touch goes through inline `python3` to
  avoid an extra dependency.

<br/>

## Per-system details

- [upgrade-sync/README.md](upgrade-sync/README.md) — canonical-body markers, available templates, the publisher↔consumer flow with `kuberntes-infra`, and the `--dry-run --json` schema.
- [check-version/README.md](check-version/README.md) — drift status codes, GitHub Actions wiring, sibling-chart ordering, and PR creation.
- [changelog/README.md](changelog/README.md) — Chart.yaml annotation RESET semantics and the Keep a Changelog mapping.
