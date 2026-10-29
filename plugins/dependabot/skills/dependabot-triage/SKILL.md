---
name: dependabot-triage
description: Triage the weekly batch of Dependabot pull requests in a repository - inventory the open bot PRs, read why each one is red, sort them into merge / recombine / reject / fix, and act. Use on a dependency sweep, or whenever the user says "dependabot", "dependency PRs", "bump PRs", "deps PRs", or asks why a dependency bump is failing CI.
---

# Dependabot triage

Dependabot opens PRs on a schedule across the ecosystems listed in
`.github/dependabot.yml` (some repos have no file and only get security updates). This
skill turns that pile into merges, closures, and a short list of real work — cheapest
decisions first.

## Step 0 — Load the repo's own knowledge

This skill is the method and is shared by every repository. What is true of *this*
repository — which specs are known to flake, which dependencies are deliberately held
back, which directories are separate projects, how CI is named — lives in the repo.
Before touching a PR:

- Read `.claude/rules/dependabot.md` if it exists, plus `CLAUDE.md` and any rule it
  points at for the areas the PRs touch (a sub-project's own test commands, a CI
  merge-order rule).
- Read `.github/dependabot.yml`: its `groups` and `ignore` comments are the durable
  record of decisions already made.
- `gh repo view --json nameWithOwner --jq .nameWithOwner` gives the `<owner>/<repo>` used
  in the API calls below.

If the repo has no `.claude/rules/dependabot.md`, offer to create one from what the sweep
teaches you (Closing out, below).

## Quick start

```bash
# 1. Inventory
gh pr list --author "app/dependabot" --state open --limit 50 \
  --json number,title,createdAt,mergeStateStatus \
  --template '{{range .}}{{.number}}	{{.createdAt}}	{{.mergeStateStatus}}	{{.title}}{{"\n"}}{{end}}'

# 1b. What each PR actually bumps -- group PRs hide 5-10 packages behind one title.
#     This is where overlaps between PRs and risky packages show up.
for n in $(gh pr list --author "app/dependabot" --state open --json number --jq '.[].number'); do
  echo "=== #$n"; gh pr view $n --json body --jq '.body' | grep -E '^Updates `'
done

# 2. Per PR, see which checks are red
gh pr checks <N>

# 3. Get the *actual* error out of a failing job (logs are 95% runner noise)
<skill dir>/scripts/why-failed.sh <job-url-or-id>   # the script next to this SKILL.md
```

Then classify each PR with the decision tree below and work the buckets in order:
**A (merge) → B (recombine) → C (reject) → D (fix)**.

## Step 1 — Establish a baseline first

Before blaming any PR, know what the default branch does on its own, and confirm it is
current (`git fetch origin && git rev-list --left-right --count HEAD...origin/<default>`).
A bot PR opened last week was validated against a default branch that no longer exists:
its green checks have expired.

Diff a PR's failures against the repo's known flakes (from its rules file). But **"it's
flaky" is a hypothesis about one named test, never a verdict on a red run.** Treating it
as a verdict is how a real regression ships. Before writing any failure off:

- **Name the failing test.** "CI failed" is not a diagnosis. Only tests the repo has
  documented as flaky earn the benefit of the doubt, and only with their own signature.
- **Match the signature, not just the test.** A known-flaky test failing with a
  *different* message is a different problem.
- **Count across siblings.** A sweep gives you free controls: the other bot PRs are the
  same default branch with one dependency changed. A test that fails twice on one PR
  while passing on five others is a regression signal, whatever its history.

A re-run is for confirming a flake you have already identified — not for finding out
whether one exists. If you cannot name why it failed, you have not finished Step 2.

## Step 2 — Read the real failure

`gh run view --job <id> --log-failed` returns hundreds of lines of checkout/cleanup noise.
Use the helper, which strips the `job\tstep\ttimestamp` prefix and keeps only lines that
carry a diagnosis:

```bash
<skill dir>/scripts/why-failed.sh 103201174811
<skill dir>/scripts/why-failed.sh https://github.com/<owner>/<repo>/actions/runs/34580022116/job/103201174811
```

Almost every red Dependabot PR is one of two shapes, and both are visible in the first
20 lines of output:

- `npm error code ERESOLVE` — a peer dependency conflict. The install never ran; no test
  result on the PR means anything.
- A test/typecheck failure — the install worked and the new version genuinely broke code.

### Browser-test failures: read the artifact, not just the message

An end-to-end assertion tells you what was *observed*, never what the app *did*. The run
usually uploads a screenshot of the failing moment, with the command log and network
panel in it, and that is often the whole diagnosis:

```bash
run=$(gh pr checks <N> | grep -i e2e | grep -oE 'runs/[0-9]+' | cut -d/ -f2)
gh api repos/<owner>/<repo>/actions/runs/$run/artifacts \
  --jq '.artifacts[] | "\(.name) id=\(.id)"'
gh api repos/<owner>/<repo>/actions/artifacts/<id>/zip > shots.zip
unzip -o -q shots.zip -d shots && find shots -name '*.png'
```

This is not optional polish: a failure that reads as a flaky timing assertion can be a
real request in the network panel that the assertion never looked at. Server logs, when
uploaded, give the other side of the same moment.

## Step 3 — Classify

```
Is the PR green?
├─ yes ─────────────────────────────────────────────► BUCKET A: merge
└─ no → run why-failed.sh
   ├─ ERESOLVE, and the conflicting package is bumped
   │  by ANOTHER open Dependabot PR ──────────────────► BUCKET B: recombine
   ├─ ERESOLVE against a ceiling we cannot move
   │  (upstream peer range excludes the new version,
   │   latest + alpha included) ──────────────────────► BUCKET C: reject
   └─ tests/typecheck fail after a successful install ► BUCKET D: fix
```

Distinguishing B from C is the whole job, and it is one command:

```bash
npm view <blocking-package>@latest version peerDependencies
npm view <blocking-package> versions --json | tail   # check alphas too
```

If some published version accepts the new dependency, it's B (bump them together).
If nothing does, it's C (the ecosystem is not ready — reject).

## Step 4 — Act per bucket

### Bucket A — green, merge

```bash
gh pr checks <N>          # re-verify now, not from an old notification
gh pr merge <N> --squash  # use the repo's merge method
```

Check whether the repo allows auto-merge before relying on `--auto`: where
`allow_auto_merge` is false it merges immediately with checks still pending. Merge
explicitly, one at a time, and re-check the next PR after each merge.

#### Merge order: one PR per lockfile, then rebase the rest

PRs that touch the same lockfile conflict the moment one of them merges. A green batch is
therefore never "merge them all": group the PRs by lockfile (each `package-lock.json`,
`Gemfile.lock`, `go.sum`, workflows) and:

1. Merge the largest PR in each group first. PRs in *different* groups touch disjoint
   files and can be merged back to back.
2. Post `@dependabot rebase` on every PR left behind.
3. Wait for each one to resolve as one of two outcomes:
   - **The PR was closed.** Dependabot closes a PR it decides is no longer needed (for
     example, an earlier group PR's lockfile already moved the package) and says why in
     a comment. Read the comment and move on.
   - **The head SHA changed.** Only then run `gh pr checks <N> --watch`, which blocks
     until that commit's checks finish. Checking earlier reads the *old* commit's run,
     and `mergeable` can report true before the rebase lands.

   ```bash
   old=$(gh pr view <N> --json headRefOid --jq .headRefOid)
   until [ "$(gh pr view <N> --json state --jq .state)" != OPEN ] ||
         [ "$(gh pr view <N> --json headRefOid --jq .headRefOid)" != "$old" ]; do sleep 20; done
   gh pr checks <N> --watch
   ```
4. Merge once green on the new base, and repeat for the next PR in that group.

### Bucket B — recombine a split pair

Dependabot's `groups` exist to prevent this, but they do not always hold: a package and
its tooling (`vitest` and `@vitest/ui`, say) can still be split into two PRs. When the
tool peers an **exact** version of the other, each PR alone fails `npm ci`.

**Overlap is not the same as breakage — check the lockfile first.** When a caret range
lets one PR's lockfile move the peer too, both PRs go green. If `gh pr diff <N>` shows the
peer already moved in the lockfile, it is bucket A: merge the group PR, and Dependabot
closes the redundant one after a rebase. Recombine only when the split actually fails
`npm ci`.

Do not try to patch one bot branch onto the other. Open one replacement PR:

```bash
git checkout -b deps/<thing>-<major> origin/<default>
cd <the right directory>            # root, or the sub-project
npm install --save-dev pkg-a@^X pkg-b@^X
npm ci                              # the exact thing CI runs — must not ERESOLVE
```

Verify, commit both `package.json` and `package-lock.json`, and say
"Supersedes #A and #B" in the body so the bot PRs can be closed with a pointer.

### Bucket C — reject and record why

Closing the PR alone is not enough: Dependabot re-proposes the next patch release next
week and you re-litigate it weekly. Add an ignore entry to `.github/dependabot.yml`
**in the same PR**, with a comment naming the blocking peer range and the condition for
removing the entry.

```yaml
    ignore:
      # <blocker> <version> -- the newest release, alphas included -- peers
      # typescript ">=4.8.4 <6.1.0". TypeScript 7 cannot install alongside it
      # (see PR #<n>). Remove this once <blocker> widens that range.
      - dependency-name: "typescript"
        update-types: ["version-update:semver-major"]
```

Apply the ignore to **every** ecosystem block that ships the package. Validate before
pushing:

```bash
ruby -ryaml -e 'YAML.safe_load_file(".github/dependabot.yml"); puts "YAML OK"'
```

Then close the bot PR with a comment explaining the block and linking the config change.
A repo with no `dependabot.yml` has nowhere to record an ignore: say so and offer to add
the file rather than closing silently.

### Bucket D — real breakage, real work

The install succeeded and the new version changed behaviour. Take it on a branch, one PR
per dependency. Reproduce locally before reading release notes — the failure tells you
which subsystem moved. If the fix is larger than the bump is worth, demote it to
bucket C with an ignore entry and a note.

**The bump is not always what is broken.** It can equally expose a bug that was already
there, latent, waiting on an ordering that never came up before. The tell is a failure
you cannot reproduce locally on the new version but which CI reproduces consistently —
timing-dependent, and the new version only changed the odds.

When that happens the fix belongs in **its own PR against the default branch**, not
folded into the bot's branch: it is a user-facing `fix:` with its own changelog entry, it
wants its own revert handle, and it is worth merging whether or not the bump ever lands.
Merge it, update the bot PR from the default branch (`gh pr update-branch <N>`), and
re-run. That sequence is also the experiment — if the bump goes green, the latent bug
*was* the trigger.

To confirm a race rather than guess at one, force the ordering instead of waiting for it
(dispatch two events in the same tick, for instance). Verify the fix against the
**database or server**, not the rendered UI.

## Per-ecosystem gotchas

- **A sub-project with its own `package.json` is a separate npm project.** Its
  `typecheck`, `lint` and `test` are not covered by the root's; run them from inside that
  directory. A build step that does not typecheck (esbuild, for one) can be green while
  shipping type errors.
- **Read API source from the `node_modules` of the project you are changing.** Two
  projects in one repo can pin different versions of the same package.
- **A bump whose peer range demands a deliberately deferred migration** (a framework
  major the repo has not taken on) belongs to that migration, not to a weekly sweep:
  bucket C, referencing the existing ignore entries.
- **Ruby/bundler PRs** carry no lockfile peer resolution, so they are almost always
  bucket A or D. Run the test suite rather than trusting the bot.
- **github-actions PRs** change what CI runs, not the app. Read the release notes for
  changed inputs, and pin to a commit SHA if the repo does so for third-party actions.

## Closing out

For each bucket-C closure and each bucket-B supersession, leave a comment on the bot PR
pointing at the replacement or the ignore entry, so the next sweep does not re-investigate
a decision already made.

If a rejection reason is likely to resurface (an upstream peer ceiling, a deferred
migration), the ignore comment in `.github/dependabot.yml` is the durable record —
prefer it over a note anywhere else.

What the sweep taught you about *this repo* — a newly confirmed flaky test and its
signature, a package that must move in lockstep with another, a sub-project's quirks —
goes into the repo's `.claude/rules/dependabot.md`, in a separate PR from any code. What
you learned about the *method* goes into this skill, in `Ikigai-Systems/release-kit`.
