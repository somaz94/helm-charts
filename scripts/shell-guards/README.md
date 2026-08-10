# scripts/shell-guards

<br/>

The runtime half of `make shell-lint` — three checks for bash/zsh divergences
that a syntax check cannot see.

<br/>

## Purpose

Every shell script in this repo must behave identically under bash and zsh.
`make shell-lint` enforces that with `bash -n` and `zsh -n`, plus `shellcheck`
on `scripts/`.

None of those three look at runtime semantics. `-n` **parses**; a construct that
parses cleanly in both shells and then does two different things is invisible to
it. Shellcheck targets POSIX/bash and has no opinion on zsh at all.

Three such constructs shipped in `charts/*/upgrade.sh` and survived every CI run
until someone happened to invoke the script under zsh:

| Construct | zsh behaviour | Damage |
|---|---|---|
| `read -rp "prompt" var` | `-p` means "read from the coprocess" | `read: -p: no coprocess`, then `set -e` kills the script. `--rollback` was impossible under zsh; every major-version bump aborted. |
| bare `local NAME` inside a loop | prints `NAME=<value>` on **stdout** once the parameter is set | A paginating fetch loop injected 200KB of HTTP response into its own output. The caller read the first line back as a version number and picked a version the major pin was supposed to exclude. |
| `<shell function> \| head -N` | reader exits first, producer takes SIGPIPE, `pipefail` promotes it | Silent `exit 141` with no message. Only lost the race when the producer had a lot left to write, so it looked chart-specific. |

Each check is deliberately narrow — it matches the exact shape that broke, not
the general construct — so ordinary code like `cat f | head -1` stays quiet. The
current tree is clean; the guards exist to keep it that way.

<br/>

## Usage

```bash
scripts/shell-guards/shell-guards.sh <file> [<file> ...]
```

Runs automatically as the last stage of `make shell-lint`, over the same file
set as `bash -n` (`scripts/**/*.sh` plus `charts/*/upgrade.sh`), and therefore
on every push through [`shell-lint.yml`](../../.github/workflows/shell-lint.yml).

Exit codes: `0` no findings, `1` at least one finding. Findings print as
`file:line: message` on stderr.

<br/>

## Fixing a finding

| Finding | Fix |
|---|---|
| `-p` flag on `read` | Use the canonical body's `prompt_confirm` / `prompt_read` helpers. They print with `printf`, honour `--yes`, and refuse to block when stdin is not a terminal. |
| bare `local NAME` in a loop | Move the declaration above the loop. Assigning in the same statement (`local x=$(…)`) is also safe — only the bare re-declaration prints. |
| `fn \| head -N` | Capture, then slice: `all=$(fn); printf '%s\n' "${all%%$'\n'*}"`. |

For a `\| head -N` that is genuinely safe, appending `\|\| true` marks it as
tolerated and the check skips it.

<br/>

## Scope

Pure `awk` and `grep`. No network, no shellcheck dependency, reads nothing
outside the files it is given, and never writes. Editing a chart's `upgrade.sh`
directly is still wrong — fix the template under
[`../upgrade-sync/templates/`](../upgrade-sync/templates/) and run
`make sync-apply`.
