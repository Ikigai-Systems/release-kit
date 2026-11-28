# A bump fails CI and you cannot say why

Read this from Bucket D when a test fails on a bump PR, passes on the default branch, and
the cause is not in the log. Use evidence at every step. Do not call it a flake.

## 1. Bisect on CI, not by reading release notes

Put the suspect versions on scratch branches and dispatch the same workflow on each:

```bash
git push origin <branch>:experiment/<name>
gh workflow run <e2e-workflow>.yaml --ref experiment/<name>
```

Bisect one dependency at a time (the bump's old version against its new one, then the
versions between). Count the same test across several bump PRs: a test failing on three
bump PRs and passing on the others is a regression signal. Delete every `experiment/*`
branch when done.

## 2. Reproduce locally if you can, and install honestly

- After `npm install pkg@old` run `npm ci` before rebuilding. Restoring `package.json` and
  the lockfile does not restore `node_modules`, and you will test the wrong version.
- Run the spec against an untouched default branch on the same machine first, and compare
  rates. Local runs are noisier than CI. A spec that goes red locally proves little.
- Slowing the browser (Chrome CPU throttling through the DevTools protocol) can expose a
  race that a fast machine hides. Do not throttle containers or services.

## 3. Instrument the page, and throw the log as the error

A CI log shows only the first line of an error. Record what the page did (events, order,
timestamps) in the test and throw it as the error message. Read the full text from the
test-results XML artifact, not from the job log.

## 4. Typical mechanisms

- **A dependency changed startup timing**, and a test that acts before the page is ready
  loses a race it used to win. Fix the test to wait for the real signal (a connection
  confirmed, a frame rendered), not a delay.
- **A dependency changed behaviour users see.** Fix the code, in its own PR.
- **A test sets state the app overwrites.** Drive it with real input events (a real
  double click), not by setting a selection or value directly on the DOM.

## 5. Prove the fix

A regression test must fail without the fix and pass with it. Run both. Then run the
failing test enough times on CI to shift the odds, or show the mechanism directly: one green
run does not fix an intermittent failure.
