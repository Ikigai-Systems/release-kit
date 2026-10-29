#!/usr/bin/env bash
# Print only the diagnostic lines from a failing GitHub Actions job.
#
# `gh run view --job <id> --log-failed` emits a few hundred lines of runner
# provisioning, checkout and credential-cleanup noise around the handful that
# say what actually broke. This strips the "job\tstep\ttimestamp" prefix and
# keeps the lines worth reading.
#
# Usage: why-failed.sh <job-id|job-url> [extra-grep-pattern]
set -euo pipefail

target=${1:?usage: why-failed.sh <job-id|job-url> [extra-grep-pattern]}
extra=${2:-}

# Accept a full job URL as printed by `gh pr checks`.
job_id=${target##*/job/}

patterns='npm error|error TS[0-9]|ERESOLVE|##\[error\]|FAILED|Failure/Error|^\s+[0-9]+\) |rspec \./spec|Timed out retrying|AssertionError|SyntaxError|Cannot find module'
[ -n "$extra" ] && patterns="$patterns|$extra"

# Each line is "job<TAB>step<TAB>timestamp message". Keep the step (useful
# context) and drop the job name and the ISO timestamp. BSD sed does not
# understand \t, so do the splitting in perl.
gh run view --job "$job_id" --log-failed \
  | perl -pe 's/^[^\t]*\t([^\t]*)\t\S+\s/$1 | /' \
  | grep -E "$patterns" \
  | head -60
