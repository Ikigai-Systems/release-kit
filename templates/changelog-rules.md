# Changelog and versioning

Every pull request carries its own changelog entry. There is no separate changelog step
and no release-time editing pass.

## How it works

1. The PR **title** is a conventional commit — it becomes the squash commit subject.
2. The PR **description** becomes the squash commit body. Additional entries live inside
   the `<!-- changelog:start -->` / `<!-- changelog:end -->` block, each wrapped in
   `BEGIN_NESTED_COMMIT` / `END_NESTED_COMMIT` — a bare conventional line only splits out
   for release-please's built-in types, so custom ones like `ops` would vanish silently.
   Keep each entry under 70 characters; GitHub wraps the body at ~72 when squashing.
3. `release-please` reads those commits on `master` and keeps an open
   `chore(main): release X.Y.Z` PR with the computed version and the `CHANGELOG.md` diff.
   Merging it tags the release and publishes the GitHub Release.

## Writing the entry

Use the `changelog-entry` skill (`/changelog`) rather than guessing. In short:

- Types: `feat` (minor), `fix` / `perf` / `security` (patch), `ops` (patch — self-hosted
  operators must act), and `chore` / `refactor` / `test` / `ci` / `docs` / `deps` (hidden).
- Breaking changes: `feat!:` plus a `BREAKING CHANGE:` footer explaining the migration.
- Write for the person affected, in present tense, naming things users see rather than
  classes and files.

## Rules

- **Never hand-edit the release PR.** release-please regenerates it on every push to
  `master` and force-pushes over manual changes. Corrections go into the source PR, or a
  follow-up commit after the release.
- **Never hand-edit the version file** — release-please owns it.
- Apply the `no-changelog` label to skip the automation on a PR.
- Merges are squash-only. Merge commits break the one-PR-one-entry model.
