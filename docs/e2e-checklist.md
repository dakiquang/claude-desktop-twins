# End-to-end checklist for a release

Run on a fresh macOS user account with Claude Desktop installed and two test accounts,
`work@example.com` and `personal@example.com` (replace with your own test accounts;
never paste real addresses into release notes).

- [ ] `brew install dakiquang/tap/claude-desktop-twins`; `cdt --help` and `cdt doctor` exit 0.
- [ ] `cdt add work@example.com` and `cdt add personal@example.com`; allow notifications
      in both prompts.
- [ ] Both apps appear in System Settings → Notifications under their own names.
- [ ] Sign in to each account in its own app.
- [ ] Trigger a notification in each account while it is in the background, click it,
      and capture:
      `log show --last 5m --predicate 'process == "usernoted" AND eventMessage CONTAINS "Bringing app"'`
      The output shows both `local.claude-desktop-twins.<slug>` bundle ids.
- [ ] Run `cdt open work` twice while it runs. `cdt doctor` shows one instance per data
      dir, and no Automation permission prompt appears.
- [ ] Simulate a Claude update: `plutil -replace LocalSourceVersion -string 0.0.1 "<clone>/Contents/Info.plist"`
      then `codesign --force --sign - "<clone>"`. `cdt list` marks it stale with the
      rebuild command; `cdt rebuild <account>` makes it current.
- [ ] `cdt sessions list default` and `cdt sessions list work --json` show the Code
      sessions; `cdt sessions copy` points to Premium and changes nothing.
- [ ] `cdt uninstall`, then `brew uninstall claude-desktop-twins`;
      `mdfind "kMDItemCFBundleIdentifier == 'local.claude-desktop-twins.*'"` prints nothing
      and `~/Applications/Claude Desktop Twins` is gone.
