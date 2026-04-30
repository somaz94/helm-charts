# scripts/check-version

<br/>

Automate upstream-version drift detection and chart bumping for every chart
under `charts/` that ships an `upgrade.sh`.

This is a thin orchestrator on top of each chart's `upgrade.sh`. It does **not**
duplicate the per-chart logic for fetching upstream versions, verifying images,
or rewriting `Chart.yaml`/`values.yaml` — it just composes the existing pieces:

```
check-version.sh
  └─ for each chart:
       ./upgrade.sh --dry-run         (drift detection)
       ./upgrade.sh --version <new>   (bump files + append artifacthub.io/changes entry)
       make bump CHART=<name>         (chart SemVer +1)
       make ci CHART=<name>           (lint / template / validate)
       make changelog CHART=<name>    (prepend new section to charts/<name>/CHANGELOG.md)
       git commit + branch + push + gh pr create
```

<br/>

## Quick start

```bash
# Drift report only (safe, no file or branch changes)
./scripts/check-version/check-version.sh

# Drift report for one chart
./scripts/check-version/check-version.sh --check --chart ghost

# Bump a single chart locally (commit only, no push, no PR)
./scripts/check-version/check-version.sh --apply --chart ghost --no-pr

# Bump every drifted chart and open one PR per chart
./scripts/check-version/check-version.sh --apply
```

<br/>

## Command reference

| Flag | Purpose |
|------|---------|
| `--check` | Drift-only report (default). No files or branches change. |
| `--apply` | Run bump + ci + branch + commit + push + PR for each drifted chart. |
| `--chart <name>` | Limit to one chart. Repeatable. |
| `--skip-chart <name>` | Exclude one chart. Repeatable. |
| `--include-major` | Include major-version bumps in `--apply` (default: skip). |
| `--no-pr` | Stop after local commit (no `git push`, no `gh pr create`). |
| `--no-ci` | Skip `make ci` (debug only). |
| `--output <text\|github>` | `text` (default) or `github` (markdown for `$GITHUB_STEP_SUMMARY`). |

Environment variables:

- `BRANCH_PREFIX` — branch name prefix (default `chore/auto-bump`)
- `BASE_BRANCH` — base branch (default `main`)
- `GITHUB_TOKEN` — used by `gh` and by `upgrade.sh` for GitHub-based version sources

<br/>

## Status codes in the summary

| Status | Meaning |
|--------|---------|
| `uptodate` | Chart's `appVersion` already matches latest upstream GA. |
| `drift` | Newer GA exists; would bump on `--apply`. |
| `drift-major` | Newer GA crosses a major version. Skipped by default; opt in with `--include-major`. |
| `blocked` | A sibling-chart constraint (e.g. `kibana-eck` ≤ `elasticsearch-eck`) is preventing this bump until the sibling is bumped first. Re-run after the sibling PR merges. |
| `no-image` | Upstream feed advertises a newer GA, but the container image isn't published yet (and the script's image-fallback search couldn't find a newer published image either). Wait for the upstream registry push and re-run. Common for `elastic-artifacts` source where the artifacts API publishes the version slightly before the Docker image. |
| `pr-created` | `--apply` succeeded: branch pushed and PR opened. |
| `local-only` | `--apply --no-pr` succeeded: local branch + commit only. |
| `skipped` | Branch already exists on local or `origin`, or no diff after bump. |
| `error` | A step failed (dry-run, upgrade.sh, make bump, make ci, push, or PR). The chart is left clean — any partial work is reverted. |

<br/>

## Dry-run output contract (with `chart-appversion.sh`)

`detect_drift` and `parse_latest_from_dry_run` in `check-version.sh` parse
**fixed strings** emitted by `upgrade.sh --dry-run`. Treat the strings below
as the API surface between `templates/chart-appversion.sh` and this script —
when you change either side, change both in the same PR and re-run
`make version-check` to verify.

| Pattern in dry-run output | Emitted by | Mapped status |
|---|---|---|
| `Already up to date` | `chart-appversion.sh` happy-path uptodate | `uptodate` |
| `Latest available: <X.Y.Z>` | `chart-appversion.sh` upstream feed result | `drift` |
| `Using explicit target: <X.Y.Z>` | `chart-appversion.sh` `--version <V>` path | `drift` (forced) |
| `Latest available (with published image): <X.Y.Z>` | `chart-appversion.sh` image-fallback hit | `drift` (fallback) |
| `Newest available matches current. Nothing to bump.` | `chart-appversion.sh` image-fallback returns current | `no-image` |
| `no GA version with a published image found` | `chart-appversion.sh` image-fallback exhausted | `no-image` |
| `is HIGHER than <sibling> version` | `chart-appversion.sh` sibling constraint | `blocked` |

Two ways to break the contract silently:

1. **Renaming/punctuation drift.** Even capitalization or comma changes can
   misclassify charts as `error` or `uptodate`.
2. **New status added to the template without updating `detect_drift`.**
   A new branch in `chart-appversion.sh` that emits neither
   `Already up to date` nor `Latest available:` parses as `error`.

A `--dry-run --json` mode is planned to eliminate the text grep. Until then,
this section is the contract.

<br/>

## Failure handling

- **Working tree must be clean** before `--apply` runs. The script aborts otherwise.
- **`make ci` failure** → the chart's working copy is reset (`git checkout -- charts/<name>`), the per-chart branch is deleted, and the script moves on to the next chart with an `error` status.
- **`gh pr create` failure** → the branch stays pushed so a human can open the PR manually; only the PR step is marked `error`.
- Errors in any chart cause the script to exit with code `2` so CI surfaces the failure.

<br/>

## CHANGELOG.md generation

Each automated PR includes an updated `charts/<name>/CHANGELOG.md` so the auto-bump satisfies the `changelog-check` job in [`.github/workflows/lint.yml`](../../.github/workflows/lint.yml) without any human follow-up. Two pieces collaborate:

1. **`upgrade.sh` appends a new entry** to `Chart.yaml`'s `annotations.artifacthub.io/changes`:
   ```yaml
   - kind: changed
     description: Bump appVersion from <OLD> to <NEW>
   ```
   The append is idempotent (skipped if the same description text is already present), so a second `--apply` run for the same drift does not duplicate.

2. **`make changelog CHART=<name>` renders the mirror.** [`scripts/changelog/sync-changelog.sh`](../changelog/) reads `Chart.yaml`'s `version` + `annotations.artifacthub.io/changes` and prepends a `## [vX.Y.Z] - YYYY-MM-DD` section to `charts/<name>/CHANGELOG.md`. The sync step runs after `make ci` and is itself idempotent — re-runs with the same chart version warn and skip.

If a chart maintainer wants a more descriptive entry than the generic `Bump appVersion ...`, they can edit `Chart.yaml`'s annotation on the auto-PR branch and re-run `make changelog CHART=<name>` locally; the CHANGELOG.md will be regenerated against the edited annotation (the existing same-version section is replaced because `make changelog` skips on idempotency, so the cleaner path is to delete the auto-generated section first or amend it directly).

The auto-PR's checklist marks both rows checked so reviewers can see at a glance that no human touch-up is required:

```
- [x] Added an entry under `artifacthub.io/changes` in `Chart.yaml` (handled by upgrade.sh)
- [x] Updated `charts/<chart>/CHANGELOG.md` (handled by `make changelog`)
```

<br/>

## Backups

`upgrade.sh` writes a snapshot to `charts/<name>/backup/<timestamp>/` before
mutating files. These backups are **tracked in git** as a rollback trail and are
preserved across PRs — do not gitignore them. Rolling back manually:

```bash
cd charts/<name> && ./upgrade.sh --rollback
```

<br/>

## GitHub Actions

`.github/workflows/check-versions.yml` runs:

- **Schedule:** every Monday 00:00 UTC (09:00 KST) in `apply` mode.
- **Manual:** `workflow_dispatch` with a chart filter and an opt-in for major bumps.

The workflow installs `helm`, `chart-testing`, and `kubeconform`, then invokes
this script with `--apply --output github`.

### Required repo setting: allow GitHub Actions to create PRs

For the workflow to call `gh pr create` with the default `GITHUB_TOKEN`, the repo must have **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create and approve pull requests"** turned **on**. The setting defaults to OFF on new repos, and the resulting `gh pr create` failure looks like:

```
ERROR: gh pr create failed: GitHub Actions is not permitted to create or approve pull requests
```

The branches are still pushed in this state, so you can recover by either toggling the setting and re-running the workflow (after deleting the orphan branches), or by opening the PRs manually with `gh pr create --head chore/auto-bump/<chart>-<version>`.

Toggle the setting from the CLI (alternative to the UI checkbox):

```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -F default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true
```

### Why the workflow runs `make ci` itself

PRs created by the default `GITHUB_TOKEN` do **not** re-trigger other workflows
(such as `lint.yml`). To keep auto-PRs validated end-to-end, this workflow runs
`make ci` (the same `helm lint`, `chart-testing`, `helm template`, and
`kubeconform` checks the lint workflow runs) **before** opening the PR.

If the repo's branch protection on `main` requires a green check from
`lint.yml`, you have a few options:

1. **Add a check exception** for PRs labeled `auto-bump` (recommended for low-friction merges).
2. **Re-trigger lint** by closing and reopening the auto-PR, or by pushing an empty commit (lint runs because the closer event came from a user, not a bot).
3. **Switch to a PAT or GitHub App token** in the workflow so PRs are authored as a regular identity and trigger downstream workflows. This requires storing a secret and is left as an explicit upgrade path rather than the default.

<br/>

## Sibling-chart ordering

`kibana-eck` carries a sibling constraint (`appVersion` must be ≤
`elasticsearch-eck`'s `appVersion`). When both charts have new upstream versions
in the same week, `check-version.sh` will:

1. Bump `elasticsearch-eck` and open its PR.
2. Mark `kibana-eck` as `blocked` (the working tree off `main` still has the
   old elasticsearch-eck version).
3. Once the elasticsearch-eck PR merges, the next workflow run unblocks
   `kibana-eck` and opens its PR.

So a "tied" version pair takes two workflow ticks (or one extra manual run via
`workflow_dispatch`) to reach `main`.

<br/>

## Local prerequisites

- `bash` ≥ 4 (Homebrew bash on macOS)
- `helm` ≥ 3.16
- `chart-testing` (`brew install chart-testing`) — needed for `make ci` (`ct-lint`)
- `kubeconform` (`brew install kubeconform`) — needed for `make ci` (`validate`)
- `gh` — needed for `--apply` without `--no-pr`
- `python3` — used by `upgrade.sh` for JSON parsing
