# How Claude Desktop updates when only clones run

Checked 15/11/2026 against Claude Desktop 5.11492.5 on macOS (Apple silicon), by reading
the shipped `app.asar`, the running processes and a test launch (check 4). No new Claude release was published
during the check, so the update itself was not observed.

## Decision

Each clone blocks its own updater with Claude's "Block auto-updates" setting, written
to the clone's `<data dir>-3p/configLibrary/` (see `lib/updates.sh`). The original
`/Applications/Claude.app` keeps updating as usual. The tool writes that folder only when
it does not exist and never edits one it did not make; a clone with such a folder is
left to Squirrel, which is expected to reject the update because of the ad-hoc
signature (inferred, not observed). `cdt doctor` reports which case applies.

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
    `configLibrary/<id>.json` holding `{"disableAutoUpdates": true}`, chosen by
    `configLibrary/_meta.json` (`{"appliedId": "<id>", "entries": [{"id": "<id>", "name": "Default"}]}`).
    A data dir started with `--user-data-dir` gets its own `-3p` folder, so this applies
    to one clone only. Checked 15/11/2026 on 5.11492.5 (check 4 below): it works.
  - Risk: the same folder holds the third-party inference setup. When Claude finds an
    inference provider configured there, it moves the data dir to the `-3p` folder at
    startup, which would hide the account's sign-in. A file holding only
    `disableAutoUpdates` does not trigger this (check 4). A `-3p` folder the user
    already has may be their inference setup and must not be edited.
  - The tool uses the local configuration, never managed preferences.
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
4. Done 15/11/2026 on 5.11492.5: `/Applications/Claude.app` started on a fresh data dir
   with only that `-3p` configuration logged `[updater] Auto-updates disabled by
   enterprise policy` and ran no update check, while running clones without it logged
   `App is installed, enabling initial check and auto-updates`. Claude wrote its data into
   the data dir, not into `-3p`, and went down the normal sign-in path
   (`[startup-sign-in]`, no third-party mode). Signing in with the setting on was not
   tried. The original app was used because the setting is read by the same code in a
   clone.

If 1 or 2 shows the clone being replaced or broken, revisit this decision before v0.1.0.
