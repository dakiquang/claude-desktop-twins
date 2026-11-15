# claude-desktop-twins

Unofficial. Not affiliated with Anthropic.

Run several Claude Desktop accounts side by side on one Mac. Each account becomes its
own app, with its own Dock icon, Cmd-Tab entry and notifications. Clicking a
notification opens the account that sent it.

## The problem

Claude Desktop signs in to one account at a time. You can start a second copy on a
different data folder with `--user-data-dir`, but every copy still uses the same app
identity. macOS then treats all copies as one app: they share one Dock icon, one
notification setting, and a notification click brings up whichever copy macOS picks,
not the one that sent it.

## Install

```bash
brew install dakiquang/tap/claude-desktop-twins
```

This installs the `claude-desktop-twins` command and the short alias `cdt`. It needs
macOS 12 or later, Claude Desktop in `/Applications`, and the Xcode Command Line Tools
(`xcode-select --install`) to build a small helper.

## Use

```bash
cdt add work@example.com          # create an app for the account, ask for notifications
cdt add personal@example.com
cdt open work                     # open it, or bring it forward if it already runs
cdt                               # pick an account from a menu
cdt list                          # accounts, running state, versions
cdt doctor                        # check everything
```

Sign in to the right account the first time each app opens. The apps live in
`~/Applications/Claude Desktop Twins/`, so you can also keep them in the Dock or open
them from Spotlight.

After Claude Desktop updates, open the original Claude.app once so it installs the
update, then rebuild each account that `cdt list` marks as stale:

```bash
cdt rebuild work@example.com
```

Move Code sessions between accounts (the target account must have opened its Code tab
once):

```bash
cdt sessions list work
cdt sessions copy --from default --to work@example.com --cwd /projects/api --dry-run
cdt sessions copy --from default --to work@example.com --cwd /projects/api
```

Commands that change or delete things (`rebuild`, `remove`, the `--to` of `sessions copy`)
need the full account name; `open` and `sessions list` accept part of it.

`default` is plain Claude.app. A copy backs up the target first, never overwrites a
session that is already there, and keeps archived sessions archived.

Adopt a data folder made by another launcher or by hand:
(the data folder of plain Claude.app cannot be imported; add an account and copy
sessions into it instead)

```bash
cdt import ~/Library/Application\ Support/SomeOtherLauncher/work --as work@example.com
```

Remove one account, or everything:

```bash
cdt remove personal@example.com             # keeps its data folder
cdt remove personal@example.com --purge     # also moves the data folder to the Trash
cdt uninstall                               # all apps, the helper and the registry
cdt uninstall --purge-data                  # also data folders and session backups
brew uninstall claude-desktop-twins
```

## How it works

`cdt add` makes an APFS clone of `/Applications/Claude.app` (it shares disk blocks with
the original, so it takes almost no extra space) and changes a few things in the copy:

- a bundle id of its own, `local.claude-desktop-twins.<account>`, and a display name;
- a small launcher that starts Claude with `--user-data-dir` pointing at the account's
  folder under `~/Library/Application Support/claude-desktop-twins/profiles/`;
- an ad-hoc signature whose signing identifier equals the new bundle id, which macOS
  requires before it lets an app post notifications;
- a helper, `cdt-helper`, that asks macOS for notification permission on the app's
  behalf (Claude never asks by itself) and brings a running account forward without
  needing Automation permission.

The `claude://` link handler and Anthropic's provisioning profile are removed from the
copy. No Anthropic file is shipped with this tool: every clone is made on your Mac
from the Claude.app you installed.

`cdt open` never starts a second instance on a data folder that is in use. It looks for
a running Claude process on that folder and brings it forward instead.

## Limits

- Passkeys and the Secure Enclave device key do not work in the clones. They are tied
  to Anthropic's signature, which the clone no longer has.
- macOS asks for keychain access again after each rebuild, because the signature
  changes.
- Clones do not update themselves. Open the original Claude.app to update it, then run
  `cdt rebuild <account>` for each account `cdt list` marks as stale. A stale account
  keeps working on its older version until you rebuild it.
- The Code tab in every account shares `~/.claude`, `~/.claude.json` and the Claude
  Code keychain item. Settings, skills and transcripts are shared, and some account
  details from one account can show up in another. Session copying relies on this
  sharing.
- `cdt sessions copy` relies on an undocumented folder layout checked up to Claude
  5.11492.5. On a newer Claude it refuses to run unless you pass `--force`.
- macOS only.

If Claude Desktop ships its own multi-account support, `cdt doctor` will say so, and
you may not need this tool any more.

## Comparison

| | This tool | Byte-identical clones (for example `claude-desktop-profiles`) |
|---|---|---|
| Notification click opens the right account | Yes | No: all copies share one app identity |
| Own Dock icon, Cmd-Tab entry, notification settings | Yes | Shared |
| Clones update themselves | No: `cdt rebuild` after each update | Yes |
| Passkeys and device key | No | Yes |

Both approaches are valid. This one picks correct notifications over self-updating
clones.

## Disclaimer

Unofficial personal project, not affiliated with or endorsed by Anthropic. "Claude" is
used only to describe what the tool works with. It is not connected to any company or
employer, and comes with no promise of support. Use it at your own risk.

## License

MIT. See [LICENSE](LICENSE).
