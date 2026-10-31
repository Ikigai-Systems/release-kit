#!/bin/bash
# Merge PRs one at a time, waiting for each merge to finish deploying before the next.
#
# usage: [DEPLOY_WORKFLOW="<workflow name>"] [DEPLOY_TIMEOUT=5400] merge-and-wait.sh <pr>...
#
# Run from inside the repository. For each PR, in order:
#   1. skip it if it is no longer open;
#   2. wait for mergeStateStatus CLEAN, asking for a rebase / branch update if it is
#      DIRTY or BEHIND (Dependabot PRs are rebased with `@dependabot rebase`);
#   3. without DEPLOY_WORKFLOW, wait for the PR's checks; with it, trust the repo's gate;
#   4. squash-merge;
#   5. with DEPLOY_WORKFLOW, wait for that workflow's run on the merge commit and stop on
#      anything but success.
# Any failure stops the whole batch with a non-zero exit, so a broken deploy is never
# stacked under the next merge. Use it for Dependabot PRs only: a classifier that blocks
# agents from merging their own PRs is doing its job.
#
# Why serialise: when merges trigger deploys, a second deploy that replaces a running one
# can be reported as failed by the platform ("not found after stabilization") even though
# nothing is wrong. A `concurrency` group queues them (see templates/deploy-concurrency.md);
# this script keeps a batch from relying on that alone.
wf=${DEPLOY_WORKFLOW:-}
timeout=${DEPLOY_TIMEOUT:-5400}

for n in "$@"; do
  st=$(gh pr view "$n" --json state --jq .state)
  [ "$st" = OPEN ] || { echo "#$n: $st, skipping"; continue; }

  ok=0
  for i in $(seq 1 60); do
    m=$(gh pr view "$n" --json mergeStateStatus --jq .mergeStateStatus)
    [ "$m" = CLEAN ] && { ok=1; break; }
    if [ "$i" = 1 ] && { [ "$m" = DIRTY ] || [ "$m" = BEHIND ]; }; then
      gh pr update-branch "$n" >/dev/null 2>&1 || gh pr comment "$n" --body "@dependabot rebase" >/dev/null
    fi
    sleep 10
  done
  [ "$ok" = 1 ] || { echo "#$n: never CLEAN ($m), stopping"; exit 2; }

  if [ -z "$wf" ]; then
    sleep 40 # checks register late; a premature "nothing pending" passes too soon
    gh pr checks "$n" --watch >/dev/null 2>&1 || { echo "#$n: checks not green, stopping"; exit 2; }
  fi

  gh pr merge "$n" --squash >/dev/null 2>&1 || { echo "#$n: merge refused, stopping"; exit 2; }
  sha=$(gh pr view "$n" --json mergeCommit --jq .mergeCommit.oid)
  echo "#$n merged ($sha)"
  [ -z "$wf" ] && continue

  r=""
  for i in $(seq 1 $((timeout / 20))); do
    r=$(gh run list --workflow "$wf" --limit 15 --json headSha,status,conclusion \
      --jq "[.[]|select(.headSha==\"$sha\")][0]|(.status+\" \"+(.conclusion//\"\"))" 2>/dev/null)
    case "$r" in
      "completed success") echo "#$n deploy success"; break ;;
      completed*) echo "#$n deploy FAILED: $r, stopping"; exit 3 ;;
    esac
    sleep 20
  done
  [ "$r" = "completed success" ] || { echo "#$n deploy not finished ($r), stopping"; exit 3; }
done
echo "all done"
