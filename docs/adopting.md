# Adopting release-kit in a repo

Roughly 20 minutes per repo. Steps 1 and 2 are one-time account/repo settings; the rest
is a single pull request.

## 1. Repo settings

The squash commit is what `release-please` reads, and by default GitHub builds its body
from the branch's commit messages rather than the PR description. Fix that first:

```bash
gh api -X PATCH repos/<owner>/<repo> \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true
```

Merge commits must be off — one PR must produce exactly one commit on the default branch.

## 2. Claude GitHub App + secret

Both are required, and the app is easy to miss — without it the workflow starts, runs,
and dies with `401 ... Claude Code is not installed on this repository`. The action
exchanges an OIDC token for an app token before it does anything else, and passing
`github_token` does **not** skip that step.

Install it on the repo (repo-admin only) — `/install-github-app` from a Claude Code
session in the repo, or https://github.com/apps/claude — then add the token:

```bash
claude setup-token                      # prints an OAuth token
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
```

## 3. Version of record

Decide where the version lives and make sure exactly one place holds it.

| Stack | `release-type` | File release-please owns |
|---|---|---|
| Rails / generic | `simple` | `version.txt` |
| Node | `node` | `package.json` |

Anything else that displays a version (a `--version` flag, a `/version` endpoint, a
Sentry release) must *read* that file rather than hardcode a copy. A second hardcoded
version will drift — that is the bug this replaces.

## 4. Files to add

Copy from `templates/`:

| Template | Destination |
|---|---|
| `release-please-config.{rails,node}.json` | `release-please-config.json` |
| `caller-changelog.yml` | `.github/workflows/changelog.yml` |
| `caller-release.yml` | `.github/workflows/release.yml` |

Keep the `permissions:` blocks in those callers. A reusable workflow can only *narrow*
the caller's token, never widen it, and GitHub's default for a repo is often read-only —
so a caller without them fails immediately with `startup_failure` and no readable log.
| `changelog-rules.md` | `.claude/rules/changelog.md` |

Then create `.release-please-manifest.json` seeded with the version you are starting
from — the last released version, *not* the next one:

```json
{ ".": "1.0.0" }
```

Set `packages['.']['package-name']` in the config for non-Node repos, and adjust
`target-branch` in the release workflow if the default branch is not `master`.

## 5. Dependabot

Give bumps a hidden type so they never reach the changelog:

```yaml
updates:
  - package-ecosystem: npm
    commit-message:
      prefix: deps
```

Bot pull requests are skipped by the changelog workflow, so they cost nothing to run.

## 6. Make the version reach your artifacts

release-please tags each release and creates a GitHub Release, but **a tag pushed with
`GITHUB_TOKEN` does not start any workflow** — GitHub suppresses that to prevent
recursion. So do not hang artifact builds off `on: push: tags:`; they will never fire.

Build from master instead. The release is just another commit on master, and it is the
only commit that touches the version file — so a build can detect it and tag that image
with the version:

```bash
git fetch --deepen=1 --quiet 2>/dev/null || true
if git diff --name-only HEAD~1 HEAD | grep -qx 'version.txt'; then
  echo "version=$(tr -d '[:space:]' < version.txt)" >> "$GITHUB_OUTPUT"
fi
```

Gate the semver image tag on that value being non-empty. Tagging *every* master build
with the current version would make `:1.2.0` a moving target for anyone pinning it.

(For reference, `fundamento-cloud` does this in `.github/actions/docker-build-setup`,
which already fans out to every packaging job.)

While you are in there, check for a second latent trap: a workflow triggered by
`workflow_run` with a `tags:` filter. **`workflow_run` does not support `tags:`** —
GitHub ignores the key silently, so those builds never ran for tags either.

Verify the release side before the first release:

```bash
npx release-please release-pr --dry-run \
  --repo-url=<owner>/<repo> \
  --config-file=release-please-config.json \
  --manifest-file=.release-please-manifest.json
```

## 7. Backfill (optional)

Seed `CHANGELOG.md` from history *below* the point release-please inserts at, with a note
saying where reconstruction ends and automation begins. Future releases prepend above it.
