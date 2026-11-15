# How Claude Desktop updates when only clones run

Checked 15/11/2026 against Claude Desktop 5.11492.5 on macOS (Apple silicon), by reading
the shipped `app.asar` and the running processes. No new Claude release was published
during the check, so the update itself was not observed.

## Decision

Clones do not change how updates work. `clone_build` leaves Claude's updater alone.

- A clone carries an ad-hoc signature. Squirrel.Mac checks a downloaded update
  against the running app's designated requirement, which for an ad-hoc signature is
  the clone's own code hash, so the update is expected to be rejected and the clone to
  stay on the version it was built from. This is inferred from how Squirrel.Mac works,
  not yet observed (see the end of this note).
- The user updates the original `/Applications/Claude.app` by opening it, then runs
  `cdt rebuild <account>` for each clone that `cdt list`, `cdt open` or `cdt doctor`
  reports as stale. Stale means the clone's `LocalSourceVersion` differs from the
  `CFBundleShortVersionString` of Claude.app. The CLI makes no network calls.

## Findings

- `disableAutoUpdates` ("Block auto-updates") can come from two places:
  - Managed preferences at `/Library/Managed Preferences/com.anthropic.claudefordesktop.plist`
    and `/Library/Managed Preferences/<user>/com.anthropic.claudefordesktop.plist`.
    Both paths are fixed, need root or MDM, and would also stop updates for the
    original Claude.app.
  - A local configuration under `<data dir>-3p/`, beside the data dir:
    `configLibrary/<id>.json`, chosen by `configLibrary/_meta.json`. A data dir started
    with `--user-data-dir` gets its own `-3p` folder, so this would apply to one clone
    only. The key's settings entry lists scopes `1p` and `3p`, so it should also apply
    to a normal sign-in. This came out of a competitor's README
    (`claude-multiprofile`) and a second read of `app.asar`; it was not run.
  - Risk: the same folder holds the third-party inference setup. When Claude finds an
    inference provider configured there, it moves the data dir to the `-3p` folder at
    startup, which would hide the account's sign-in. A file holding only
    `disableAutoUpdates` is expected not to trigger this; not verified.
  - The tool uses neither place today.
- `CLAUDE_E2E_MANAGED_PLIST` overrides that path. It is a test hook in Claude's own
  end-to-end tests, undocumented and likely to change; the tool does not use it.
- Updates install either as a whole-bundle swap or a contents swap
  (`squirrelContentsSwitch`). Both run inside Squirrel after the signature check.

## Still to observe on the next Claude release

1. With only clones running, does a clone log an update failure in
   `~/Library/Logs/Claude/main.log`, prompt the user, or stay silent?
2. Does the clone bundle stay unchanged on disk afterwards?
3. Does `/Applications/Claude.app` update while it is never launched? (Expected: no.
   The updater runs inside the app.)

4. With a `-3p` local configuration that sets only `disableAutoUpdates`, does a clone on
   a fresh data dir keep its data dir, still sign in normally, and log that updates
   are off? If yes, writing it per clone is a safer way to keep clones from updating
   than relying on Squirrel rejecting the update.

If 1 or 2 shows the clone being replaced or broken, revisit this decision before v0.1.0.
