# release-kit

Shared changelog and release automation for Ikigai Systems products.

Two halves:

- **Judgment** — a Claude Code plugin (`changelog`) holding the rules for whether a change
  belongs in a changelog, what its semver impact is, and how to word it. Used identically
  by CI and by `/changelog` in a local session, so there is one source of truth.
- **Mechanics** — reusable GitHub workflows wrapping
  [release-please](https://github.com/googleapis/release-please), which owns versions,
  `CHANGELOG.md`, tags and GitHub Releases. No custom aggregation code.

```
PR opened/updated
  └─ changelog-pr.yml → Claude reads the diff, sets a conventional PR title
                        and maintains a changelog block in the description
  ↓  reviewed as part of normal PR review
squash-merge → the commit carries the entries
  ↓
release.yml → release-please keeps an open "chore(main): release X.Y.Z" PR
  ↓  merged when you want a release
tag vX.Y.Z + GitHub Release → existing packaging pipelines take over
```

## Using it

See [docs/adopting.md](docs/adopting.md). A consuming repo needs two ~10-line workflow
files, a `release-please-config.json`, a manifest, and one secret.

Locally, add the marketplace once:

```bash
claude plugin marketplace add Ikigai-Systems/release-kit
claude plugin install changelog@release-kit
```

Then `/changelog` classifies the current branch or a given PR and applies the result.

## Contents

| Path | What |
|---|---|
| `skills/changelog-entry/SKILL.md` | The judgment rules — the thing worth reading |
| `commands/changelog.md` | `/changelog` slash command |
| `.github/workflows/changelog-pr.yml` | Reusable PR classification workflow |
| `.github/workflows/release.yml` | Reusable release-please wrapper |
| `templates/` | Starter configs to copy into a consuming repo |
| `docs/adopting.md` | Onboarding checklist |
