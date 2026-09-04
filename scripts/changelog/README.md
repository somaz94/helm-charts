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

## CI automation

Three GitHub Actions cooperate so that no chart ever ships with an unsynced `CHANGELOG.md`, regardless of how the version bump landed on `main`.

<br/>

### Shared detection — `scripts/changelog/detect-bumped-charts.sh`

Both `changelog-auto.yml` (PR flow) and `release.yml` (push-to-main fallback) call `detect-bumped-charts.sh <ref-a> <ref-b>` to find charts that need a sync. It prints one chart name per line on stdout — the names of charts whose `Chart.yaml` `version:` line changed in the diff without a matching `CHANGELOG.md` change.

`lint.yml`'s `changelog-check` job intentionally keeps its own inline copy of the same `awk` logic. That duplication is the independent safeguard — if `detect-bumped-charts.sh` ever has a bug, lint.yml still catches unsynced PRs.

<br/>

### `changelog-auto.yml` — auto-generate and commit on PRs

[`.github/workflows/changelog-auto.yml`](../../.github/workflows/changelog-auto.yml) runs on every PR `synchronize` / `opened` / `reopened` event. It:

1. Calls `detect-bumped-charts.sh "origin/${BASE_REF}" HEAD` to find charts whose `Chart.yaml` `version:` was bumped without a matching `CHANGELOG.md` update.
2. Runs `bash scripts/changelog/sync-changelog.sh charts/<name>` for each.
3. If `git diff` shows changes, commits them as `chore(changelog): sync from Chart.yaml` (author: `github-actions[bot]`) and pushes to the PR branch.

Result: PR authors who only bump `Chart.yaml` `version` + `artifacthub.io/changes` get the matching `CHANGELOG.md` commit appended automatically. The `Lint / changelog-check` job re-runs against the updated branch and passes.

Token: the workflow checks out and pushes with `secrets.PAT_TOKEN`. `GITHUB_TOKEN` is not used here because pushes made with `GITHUB_TOKEN` do not retrigger other workflows (a documented GitHub Actions limitation), so `lint.yml` would never re-run after the sync commit.

Loop guard: the job is gated on `github.actor != 'github-actions[bot]'`, so the bot's own follow-up `synchronize` event is a no-op.

Fork PRs: `secrets.PAT_TOKEN` is sanitized away on fork PRs and the workflow's `GITHUB_TOKEN` is read-only against the fork's head ref. The job exits early in that case (gated on `github.event.pull_request.head.repo.full_name == github.repository`). Fork contributors fall through to `lint.yml`'s `changelog-check` job, whose error message instructs them to run `make changelog CHART=<name>` and push the result.

<br/>

### `release.yml` — release-time fallback for direct pushes

[`.github/workflows/release.yml`](../../.github/workflows/release.yml) covers the case where a `Chart.yaml` `version:` bump lands on `main` without going through `changelog-auto.yml` — e.g. an admin merge that bypassed PR review, a direct push, a hotfix, or a PR that pre-dated the auto-sync workflow.

Before chart-releaser packages the new tarballs, the workflow:

1. Calls `detect-bumped-charts.sh` against the push delta (`github.event.before...github.event.after`, or `HEAD~1...HEAD` for `workflow_dispatch`).
2. Runs `sync-changelog.sh` for each detected chart, producing the missing `CHANGELOG.md` updates in the working tree.
3. Commits and pushes the sync to `main` (author: `github-actions[bot]`, message: `chore(changelog): sync from Chart.yaml`).
4. Then proceeds to chart-releaser, so the `.tgz` published to GitHub Releases and OCI already contains the synced `CHANGELOG.md`.

Sync failure aborts the release. This is intentional fail-safe behavior — better to block a release than ship a tarball whose `CHANGELOG.md` doesn't match `Chart.yaml`'s `artifacthub.io/changes`.

The PAT_TOKEN-driven sync push retriggers `release.yml` once. The follow-up run is a no-op: `detect-bumped-charts.sh` finds no version bumps in the sync commit's delta, and chart-releaser's `skip_existing: true` short-circuits already-released versions. ~30s of CI lost, but no double-publish.

<br/>

### `dry_run` mode for safe verification

`release.yml` exposes a `workflow_dispatch.inputs.dry_run` boolean. When `true`:

- Detection and `sync-changelog.sh` still run (so the operator sees what *would* be synced in the workflow log).
- The sync commit/push is skipped — synced files stay in the runner's working tree only, never reach `main`.
- chart-releaser is skipped — no GitHub Release, no `index.yaml` update.
- OCI push is skipped.

Use this to verify the release-time sync logic safely on `main` without publishing anything:

```bash
gh workflow run release.yml -f dry_run=true
```

<br/>

### `changelog-check` job in `lint.yml` — independent safeguard

The `changelog-check` job in [`.github/workflows/lint.yml`](../../.github/workflows/lint.yml) fails any PR that bumps a chart's `Chart.yaml` `version:` line without also updating that chart's `CHANGELOG.md`. PRs that touch only `README.md`, `backup/`, or `CHANGELOG.md` itself (no version bump) pass through.

This job is intentionally kept as an independent safeguard — its detection logic mirrors `detect-bumped-charts.sh` but is duplicated on purpose so that disabling or breaking the auto-sync workflow does not silently let unsynced PRs merge. It is also the only feedback fork-PR contributors get (since `changelog-auto.yml` cannot push to a fork).

<br/>

## Integration with `check-version` (auto-bump PRs)

[`scripts/check-version/check-version.sh`](../check-version/) runs `make changelog CHART=<name>` automatically after `make ci` so the auto-PRs it opens already include a generated `CHANGELOG.md` and pass the `changelog-check` guard without any human follow-up. See [`scripts/check-version/README.md`](../check-version/README.md#changelogmd-generation) for the end-to-end flow.

<br/>

## Requirements

- `yq` v4 (mikefarah/yq, Go binary). Install with `brew install yq`. The script aborts with a clear message if `yq` is missing or not v4.
- `bash`, `grep`, `head`, `tail`, `mktemp`, `date` — all standard on macOS and Ubuntu CI runners.
