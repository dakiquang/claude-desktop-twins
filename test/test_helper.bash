# shellcheck shell=bash
# Shared setup: a temporary HOME, the fake Claude.app, a fake helper, and no
# LaunchServices or `open` side effects.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
CDT="$REPO_ROOT/bin/cdt"

build_fixtures() {
  FIXTURES="$BATS_FILE_TMPDIR/fixtures"
  mkdir -p "$FIXTURES"
  [ -x "$FIXTURES/fake-helper" ] || "$REPO_ROOT/test/make-fake-app.sh" "$FIXTURES" >/dev/null
}

common_setup() {
  FIXTURES="$BATS_FILE_TMPDIR/fixtures"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # A per-test copy so tests may change its version.
  cp -cR "$FIXTURES/FakeClaude.app" "$BATS_TEST_TMPDIR/Claude.app"
  export CLAUDE_APP="$BATS_TEST_TMPDIR/Claude.app"
  export CDT_LSREGISTER=true
  export CDT_OPEN="$BATS_TEST_TMPDIR/open-stub"
  export OPEN_LOG="$BATS_TEST_TMPDIR/open.log"
  export FAKE_HELPER_LOG="$BATS_TEST_TMPDIR/helper.log"
  printf '#!/bin/bash\necho "$*" >> "%s"\n' "$OPEN_LOG" > "$CDT_OPEN"
  chmod +x "$CDT_OPEN"
  DATA_ROOT="$HOME/Library/Application Support/claude-desktop-twins"
  APPS="$HOME/Applications/Claude Desktop Twins"
  mkdir -p "$DATA_ROOT/bin"
  cp "$FIXTURES/fake-helper" "$DATA_ROOT/bin/cdt-helper"
  BG_PIDS=""
}

common_teardown() {
  local p
  for p in $BG_PIDS; do kill "$p" 2>/dev/null || true; done
}

set_claude_version() {
  plutil -replace CFBundleShortVersionString -string "$1" "$CLAUDE_APP/Contents/Info.plist"
}

# Start an account's clone in the background through its launcher, like LaunchServices.
start_account() { # label
  local app="$APPS/$1.app"
  FAKE_CLAUDE_SLEEP=60 "$app/Contents/MacOS/launcher" >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"
  disown
  sleep 0.3
}

# Load the libraries into the test shell to call functions directly.
load_libs() {
  local f
  for f in common accounts clone updates launch doctor sessions import uninstall; do
    # shellcheck source=/dev/null
    . "$REPO_ROOT/lib/$f.sh"
  done
}
