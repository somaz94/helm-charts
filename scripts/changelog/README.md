# scripts/changelog

Per-chart `CHANGELOG.md` automation for the helm-charts mono-repo.

<br/>

## Purpose

Each chart under `charts/` is released independently (one Git tag and one chart-releaser GitHub Release per `<chart>-<X.Y.Z>`). Every release records its changes in two places:

1. **`Chart.yaml` `annotations.artifacthub.io/changes`** — the source of truth, surfaced in the Artifact Hub UI.
2. **`charts/<chart>/CHANGELOG.md`** — a human-readable mirror, regenerated from (1) by `make changelog`.

The annotation is what consumers and Artifact Hub read; `CHANGELOG.md` is what humans browsing the repo or a Git tag read. Keeping the two in sync would be tedious by hand, so `sync-changelog.sh` does it from a single command at PR time.

<br/>

## Usage

```bash
# Single chart — prepend a section for the chart's current version.
make changelog CHART=<name>

# Preview without writing.
make changelog CHART=<name> DRY_RUN=1

# Backfill / sanity-check every chart at once.
make changelog-all
make changelog-all DRY_RUN=1
```

The script can also be invoked directly:

```bash
./scripts/changelog/sync-changelog.sh charts/<name>
./scripts/changelog/sync-changelog.sh --dry-run charts/<name>
./scripts/changelog/sync-changelog.sh --all
./scripts/changelog/sync-changelog.sh --help
```

<br/>

## How it works

1. Parse `Chart.yaml` with `yq`:
   - `.version` → the new section's version.
   - `.annotations."artifacthub.io/changes"` → a YAML list of `{kind, description}` entries.
2. Group entries by `kind`. Each `kind` maps to one Keep a Changelog section header:

   | `kind` (Chart.yaml) | Section heading |
   | --- | --- |
   | `added` | `### Added` |
   | `changed` | `### Changed` |
   | `deprecated` | `### Deprecated` |
   | `removed` | `### Removed` |
   | `fixed` | `### Fixed` |
   | `security` | `### Security` |

   Sections are emitted in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) standard order shown above. Empty sections are omitted. Unmapped `kind:` values trigger a warning and are skipped (so they don't get silently dropped).
3. Format the new block as `## [vX.Y.Z] - YYYY-MM-DD` using today's date.
4. Prepend the block to `charts/<chart>/CHANGELOG.md`:
   - **No file yet** → create one with the standard Keep a Changelog header + the block.
   - **File exists** → insert the block immediately above the topmost prior `## [...]` heading.
   - **Section for the same version already exists** → log a warning and exit `0` (idempotent — safe to re-run).

<br/>

## Source of truth

`Chart.yaml` `artifacthub.io/changes` **always** wins. Never edit `CHANGELOG.md` directly — your edits will be overwritten or duplicated the next time `make changelog` runs. The flow is:

1. Edit `Chart.yaml` — bump `version`, add new `kind:`/`description:` entries to `artifacthub.io/changes`.
2. Run `make changelog CHART=<name>`.
3. `git add` both files.

This keeps Artifact Hub, the Git tag changelog, and the per-chart `CHANGELOG.md` consistent without divergence.

<br/>

## Format consistency

The output matches the [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) layout used by other PrivateWork repos (`bash-pilot`, `kube-diff`, etc.) — `## [vX.Y.Z] - YYYY-MM-DD`, the six standard subsection headings, version prefix `v`. This script does not emit `git-cliff`-style commit hash links because each entry is hand-curated in `artifacthub.io/changes` (one description per change, not one per commit).

<br/>

## CI guard

The `changelog-check` job in [`.github/workflows/lint.yml`](../../.github/workflows/lint.yml) fails any PR that bumps a chart's `Chart.yaml` `version:` line without also updating that chart's `CHANGELOG.md`. PRs that touch only `README.md`, `backup/`, or `CHANGELOG.md` itself (no version bump) pass through.

<br/>

## Requirements

- `yq` v4 (mikefarah/yq, Go binary). Install with `brew install yq`. The script aborts with a clear message if `yq` is missing or not v4.
- `bash`, `grep`, `head`, `tail`, `mktemp`, `date` — all standard on macOS and Ubuntu CI runners.
