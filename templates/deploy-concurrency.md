# Queued deploys: `concurrency` for a workflow that deploys on merge

Merging several PRs in a row (a Dependabot sweep does exactly this) starts several deploys.
A deploy that replaces one still running can be reported as failed by the platform (ECS:
"not found after stabilization") although nothing is wrong. Serialise them with a
`concurrency` group and `cancel-in-progress: false`: one run executes, at most one waits,
and an older waiting run is dropped in favour of the newer one. The newer one deploys
everything the older one would have.

Put the block at the top level of the workflow that builds and deploys the image.

## Push-triggered workflow

```yaml
# Deploys from the default branch queue behind each other; a running deploy is never
# cancelled. Everything else (branches, tags) gets its own group, so it never waits.
concurrency:
  group: ${{ github.ref == 'refs/heads/master' && 'production-deploy' || format('build-{0}', github.run_id) }}
  cancel-in-progress: false
```

Replace `master` with the default branch.

## `workflow_run`-triggered workflow (build runs after the test workflow)

`github.ref` is the default branch for every `workflow_run`, so key on the triggering
run instead. Runs that will skip the deploy (failed tests, a fork's run) get a group of
their own, so they cannot take the single waiting slot from a run that deploys.

```yaml
concurrency:
  group: ${{ github.event.workflow_run.event == 'push' && github.event.workflow_run.head_repository.full_name == github.repository && (github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'skipped') && 'production-deploy' || format('production-deploy-noop-{0}', github.run_id) }}
  cancel-in-progress: false
```

The three conditions mirror the guard a `workflow_run` job that holds deploy credentials
should have anyway (push event, same repository, tests passed or were skipped). Keep the
group expression and the job-level `if` in step: exactly the runs that deploy must land
in `production-deploy`.

## Notes

- Dropping a waiting run is fine only because every run builds the branch head, not its
  own commit. If a run deploys a specific SHA, keep one group per SHA instead.
- Merging a PR that edits `.github/workflows/*` needs a token with the `workflow` scope
  (`gh auth refresh -h github.com -s workflow -c`); without it `gh pr merge` fails with a
  bare HTTP 403.
