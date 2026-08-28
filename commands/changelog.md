---
description: Classify the current branch or a PR for the changelog and apply a conventional title and changelog block
argument-hint: "[PR number | branch | nothing for current branch]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr edit:*), Bash(gh pr list:*)
---

Use the `changelog-entry` skill to classify this change and apply the result.

Target: $ARGUMENTS (empty means the current branch's open PR, or the diff against the
default branch when no PR exists yet).

1. Read the diff. For a PR use `gh pr diff <n>`; otherwise `git diff $(git merge-base HEAD origin/HEAD)...HEAD`.
   Read the surrounding code where the diff alone doesn't reveal user impact.
2. Apply the `changelog-entry` skill: worthy or not, type, scope, semver impact, wording.
3. Report your reasoning to the user in two or three lines — what a user would notice,
   and why the bump is what it is — then show the proposed title and block.
4. If a PR exists, apply it:
   - `gh pr edit <n> --title "<conventional title>"`
   - rewrite only the region between `<!-- changelog:start -->` and `<!-- changelog:end -->`
     in the description, creating the markers at the end of the body if absent, and
     leaving every other line of the description untouched.
   If no PR exists, print the title and block for the user to use when opening one.

Never modify code, tests or configuration in this command — PR metadata only.
