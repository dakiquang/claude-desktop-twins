# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-15

### Added

- `list --json`, `doctor --json` and `sessions list <account> --json`: machine-readable output with a `schema` number; `doctor --json` gives each check a stable id, a level and the fix command.
- `icon set <account> <file.icns>` and `icon reset <account>`: an account's own Dock and Cmd-Tab icon, kept across rebuilds and removed with the account.

## [0.1.0] - 2026-11-15

### Added

- `add`, `rebuild` and `remove [--purge]`: build, refresh and delete a per-account clone of Claude.app with its own bundle id, launcher and notification permission. A failed rebuild leaves the previous clone in place.
- `open`, the interactive menu and `list`: fuzzy account matching; a running account is brought forward instead of starting a second instance; stale clones are reported with the exact `rebuild` command.
- `doctor`: checks Claude.app, the helper, each clone's signature, identifier, version, notification permission and running instances, and the native `multiAccount` flag. Runs with no accounts.
- `sessions list` and `sessions copy [--cwd] [--dry-run] [--force]`: copy Code sessions between accounts with a backup first, no overwrites and archive state kept.
- `import <data dir> --as <account>`: adopt an existing data folder.
- `rebuild`, `remove` and `sessions copy --to` need the full account name; `remove --purge` never trashes an imported data dir.
- `uninstall [--purge-data]`: remove every clone, the helper and the registry.
- Each clone blocks its own self-update with Claude's "Block auto-updates" setting in `<data dir>-3p/configLibrary/`, created only when that folder does not exist and removed by `remove` and `uninstall`; `doctor` reports it.
- `cdt-helper`: requests notification permission, reads its status, and focuses a running account.

[Unreleased]: https://github.com/dakiquang/claude-desktop-twins/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/dakiquang/claude-desktop-twins/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dakiquang/claude-desktop-twins/releases/tag/v0.1.0
