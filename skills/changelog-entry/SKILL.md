---
name: changelog-entry
description: Decide whether a change belongs in the product changelog, what its semver impact is, and how to describe it to users. Use when reviewing a pull request, preparing a PR title and description, or reconstructing changelog history from git. Triggers include "changelog", "release notes", "what version bump", "is this worth mentioning", "conventional commit title".
---

# Changelog Entry

Turn a diff into the changelog entry a *reader* wants, or decide there isn't one.

Downstream, `release-please` reads the squash commit — its subject comes from the PR
title, its body from the PR description — and builds `CHANGELOG.md`, the version number,
the git tag and the GitHub Release from those lines. So the text written here is the
text a customer eventually reads. There is no later polish step: release-please
regenerates its release PR on every push and overwrites hand edits.

## The decision, in order

1. **Who would notice this if it shipped?** If the honest answer is "nobody outside the
   team", it is not changelog-worthy. Stop and emit `chore:`.
2. **What kind of change is it?** Pick the type from the table below.
3. **What is the semver impact?** Derived from the type plus whether anything a user
   depends on was removed or altered.
4. **How would that person describe what changed?** Write one line in their vocabulary.

## Worthy vs not

**Worthy — someone outside the team notices:**

- A capability that didn't exist before, or one that now works differently
- A bug a user could plausibly have hit
- A performance change big enough to feel
- A security fix
- Any change to a public surface: HTTP API, CLI command or flag, MCP tool, formula
  function, webhook payload, keyboard shortcut
- Anything a self-hosted operator must act on: new or changed configuration, a data
  migration with a caveat, a new required service, changed resource requirements
- A deprecation, and the removal that eventually follows it

**Not worthy — invisible outside the repo:**

- Tests, fixtures, seeds, CI, build tooling, developer scripts
- Refactors, renames and reorganisation with no behavioural change
- Formatting, linting, type annotations
- Internal documentation, comments, plans and specs
- Dependency bumps — *unless* the bump is the fix for a user-visible bug or a security
  advisory, in which case describe the effect, not the bump

**When in doubt, ask whether you could write the line without naming a class, file or
internal concept.** If you can't, it is probably internal.

A single PR often contains both. Emit an entry for the visible part and let the rest go
unmentioned — do not pad the changelog to make a PR look bigger.

## Types

| Type | Section in CHANGELOG | Bump | Use for |
|---|---|---|---|
| `feat` | Features | minor | A new capability |
| `fix` | Bug Fixes | patch | Behaviour that was wrong is now right |
| `perf` | Performance | patch | Measurably faster, lighter, or cheaper |
| `security` | Security | patch | Closes a vulnerability or hardens a surface |
| `ops` | Upgrade Notes | patch | Self-hosted operators must do or know something |
| `deps` | *hidden* | patch | Dependency bumps |
| `chore` `refactor` `test` `ci` `docs` `style` `build` | *hidden* | patch | Everything internal |

`ops` is a custom type carried by the shared release-please config. Use it for the
self-hosted audience: "Requires `FOO_URL` to be set", "Adds an index; expect a longer
migration on large tables". If a change is both a user-facing feature *and* an operator
concern, emit two lines — a `feat` and an `ops`.

Add a scope when it locates the change for a reader: `feat(tables):`, `fix(editor):`.
Scopes are product areas, not directories. Omit rather than invent one.

## Semver

- **major** — a user's working setup breaks: a removed or renamed API endpoint, CLI
  command or flag, config key, or response field; a changed default that alters existing
  behaviour; a migration that is not backwards compatible with the previous release.
  Mark it `feat!:` / `fix!:` and add a `BREAKING CHANGE:` footer explaining what to do.
- **minor** — new capability, nothing existing broken.
- **patch** — fix, performance, security, or anything hidden.

Additive changes to a public surface are minor, not major, even when they are large.
Deprecating something is minor; removing it is major.

**Below 1.0.0** the repo config decides whether breaking changes fall back to a minor
bump. Do not compensate for it by hand — mark breaking changes honestly and let the
config apply the policy.

## Voice

Write for the person affected, not the person who wrote the code.

- Present tense, active, describing the shipped state: "Documents open in tabs", not
  "Added tab support" or "This PR adds".
- Lead with what changed for them, not with the mechanism. `fix(editor): documents no
  longer lose the last edit when the connection drops` beats `fix: correct Y.js provider
  teardown ordering`.
- One line per user-visible change. No trailing period. No PR or issue numbers —
  release-please appends the links.
- Name the thing users see. "Space sidebar", "the import command", "table formulas" —
  not `SpaceSidebarController`, `DirectoryImporter`, `FormulaEvaluator`.
- Keep it under roughly 100 characters. If it needs more, it is probably two entries.
- Never say "various", "several improvements", "misc" or "cleanup".

## Output

Produce a conventional-commit **title** and, when the PR carries more than one
user-visible change or a breaking note, a **body block** of further conventional-commit
lines. release-please parses every conventional line in the body as its own entry.

```
feat(spaces): group documents and tables into sidebar tabs

fix(spaces): keep the sidebar scroll position when switching tabs
ops: run `rails db:migrate` — adds an index on documents.space_id
```

A PR with nothing worth mentioning still needs a well-formed title so release-please can
classify it:

```
chore: extract editor connection lifecycle into a hook
```

When applying this to a live PR, keep the body block inside these markers so re-runs
replace it and leave everything else in the description alone:

```
<!-- changelog:start -->
...conventional lines...
<!-- changelog:end -->
```

## Worked examples

| Change | Entry |
|---|---|
| Editor kept a second ActionCable connection open per document, leaking sockets | `fix(editor): stop leaking realtime connections when documents are closed` — patch |
| Added `funcli spaces archive` / `unarchive` | `feat(cli): archive and unarchive spaces from the command line` — minor |
| Uploads failed against a host on a non-standard port | `fix(cli): upload to hosts on non-standard ports` — patch |
| Stabilised flaky E2E specs | `chore(ci): stabilise flaky end-to-end specs` — hidden |
| Bumped `activestorage` to pick up a security advisory | `security: update Active Storage for CVE-2026-XXXX` — patch |
| Renamed the `--url` flag to `--base-url` | `feat(cli)!: rename --url to --base-url` + `BREAKING CHANGE: use --base-url; --url is no longer accepted` — major |
| Dependabot bumps eslint | Not reached — bot PRs are skipped and land as `deps:` |

## Red flags

| Thought | Reality |
|---|---|
| "The PR title is close enough" | Close enough ships to customers verbatim. Rewrite it. |
| "I'll describe both the fix and the refactor" | The refactor is invisible. One entry. |
| "This touches config, so it's breaking" | Breaking means an existing setup stops working. New optional config is `minor`, or an `ops` note. |
| "Big diff, so minor at least" | Size is not impact. A 2000-line refactor is `chore`. |
| "I'll polish the wording at release time" | There is no release-time edit. release-please overwrites it. |
