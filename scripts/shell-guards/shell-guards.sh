#!/usr/bin/env bash
# shell-guards.sh — catch the bash/zsh divergences that `zsh -n` cannot see.
#
# Every shell script in this repo must behave identically under bash and zsh.
# `make shell-lint` already runs `bash -n` and `zsh -n`, but those only PARSE —
# they say nothing about runtime semantics. Three divergences slipped through
# that gate and shipped, each silently corrupting a different thing:
#
#   1. `read -rp`         zsh reads -p as "take input from the coprocess", so
#                         every prompt died with "read: -p: no coprocess" under
#                         `set -e`. Rollback was impossible under zsh for months.
#
#   2. bare `local NAME`  On the second pass through a loop the parameter is
#      inside a loop      already set, and zsh's `local` then PRINTS
#                         "NAME=<value>" on stdout. A paginating fetch loop
#                         dumped 200KB of HTTP response into its own output,
#                         which the caller then read back as a version number.
#
#   3. `<function> |      The reader exits after one line while the function is
#      head -N`           still writing, the function takes SIGPIPE, and
#                         `pipefail` + `set -e` turn that into a silent exit 141.
#
# Each check is deliberately narrow — it flags the exact shape that broke, not
# the general construct — so a legitimate `cat f | head -1` stays quiet.
#
# Usage:
#   shell-guards.sh <file> [<file> ...]
#
# Exit codes:
#   0  no findings
#   1  at least one finding (each printed as file:line: message)
#
# Pure awk + grep. No network, no shellcheck dependency.

set -euo pipefail

rc=0

for f in "$@"; do
  [ -f "$f" ] || continue

  # 1. `read -p` / `read -rp` in code (comments describing the trap are fine).
  if out=$(grep -nE '^[^#]*\bread[[:space:]]+-[A-Za-z]*p([[:space:]]|$)' "$f"); then
    printf '%s\n' "$out" | while IFS=: read -r line _; do
      # Worded to avoid the literal shape this very check greps for — otherwise
      # the guard reports itself on every run.
      echo "$f:$line: the -p flag on \`read\` is not portable; zsh reads it as \"from the coprocess\". Use prompt_confirm/prompt_read (printf, then a bare read)." >&2
    done
    rc=1
  fi

  # 2. A bare `local NAME` (no assignment) executed inside a loop body.
  #    Depth is tracked on `do`/`done` rather than on `while`/`for`, so a
  #    condition spanning several lines still lands on the right depth. Both
  #    keywords are anchored hard: `do` only counts at end of line (the shell
  #    loop form) or prose like "# do not hand-edit" inflates depth for the rest
  #    of the file, and `done` only at line start followed by a terminator or a
  #    redirect — `done < <(cmd)` has to close, while an embedded awk program's
  #    `done = 0` must not.
  if out=$(awk '
    { line = $0; sub(/^[[:space:]]*#.*$/, "", line) }
    line ~ /(^|[[:space:]]|;)do[[:space:]]*$/            { depth++ }
    line ~ /^[[:space:]]*done[[:space:]]*([;&|)<>#]|$)/  { if (depth > 0) depth-- }
    depth > 0 && line ~ /^[[:space:]]*local[[:space:]]+[A-Za-z_][A-Za-z0-9_]*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*$/ {
      sub(/^[[:space:]]+/, "", line); print NR ":" line
    }
  ' "$f"); [ -n "$out" ]; then
    printf '%s\n' "$out" | while IFS=: read -r line decl; do
      echo "$f:$line: \`$decl\` re-runs each iteration — zsh prints \"NAME=<value>\" to stdout when the parameter is already set. Declare it above the loop." >&2
    done
    rc=1
  fi

  # 3. A function defined in this file piped into an early-exiting `head`.
  #    Only fires when the file enables pipefail, which is what promotes the
  #    producer's SIGPIPE into a script-killing failure.
  if grep -qE '^[[:space:]]*set[[:space:]].*pipefail' "$f"; then
    if out=$(awk '
      /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/ {
        name = $0
        sub(/^[[:space:]]*(function[[:space:]]+)?/, "", name)
        sub(/[[:space:]]*\(\).*$/, "", name)
        fn[name] = 1
      }
      /\|[[:space:]]*head[[:space:]]+-/ {
        if ($0 ~ /\|\|[[:space:]]*true/) next          # explicitly tolerated
        if ($0 ~ /^[[:space:]]*#/) next
        line = $0
        sub(/[[:space:]]*\|[[:space:]]*head[[:space:]]+-.*$/, "", line)
        sub(/^.*[;&(){}][[:space:]]*/, "", line)
        sub(/^[[:space:]]+/, "", line)
        split(line, w, /[[:space:]]+/)
        if (w[1] in fn) print NR ":" w[1]
      }
    ' "$f"); [ -n "$out" ]; then
      printf '%s\n' "$out" | while IFS=: read -r line fn; do
        echo "$f:$line: \`$fn | head -N\` — head exits first, $fn takes SIGPIPE, pipefail turns it into exit 141. Capture the output, then slice it." >&2
      done
      rc=1
    fi
  fi
done

exit $rc
