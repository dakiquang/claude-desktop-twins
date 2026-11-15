#!/usr/bin/env bats
# import and uninstall

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "import registers an existing data dir without moving it" {
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext"; touch "$ext/Preferences"
  run "$CDT" import "$ext" --as work@example.com
  [ "$status" -eq 0 ]
  [ -f "$ext/Preferences" ]
  run cat "$APPS/work@example.com.app/Contents/MacOS/launcher"
  [[ "$output" == *"OtherLauncher/work"* ]] || false
  run "$CDT" import "$ext" --as other@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"already registered"* ]] || false
}

@test "import refuses a data dir in use" {
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext"
  FAKE_CLAUDE_SLEEP=60 "$CLAUDE_APP/Contents/MacOS/Claude" --user-data-dir="$ext" >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"; disown
  sleep 0.3
  run "$CDT" import "$ext" --as work@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"in use by a running Claude"* ]] || false
  [ ! -e "$DATA_ROOT/accounts/workexamplecom.plist" ]
}

@test "uninstall refuses while an account runs" {
  "$CDT" add work@example.com >/dev/null
  start_account work@example.com
  run "$CDT" uninstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"quit these accounts first"* ]] || false
  [ -d "$APPS/work@example.com.app" ]
}

@test "uninstall removes clones, helper and registry and keeps data" {
  "$CDT" add work@example.com >/dev/null
  "$CDT" add personal@example.com >/dev/null
  touch "$DATA_ROOT/profiles/workexamplecom/Cookies"
  run "$CDT" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$APPS" ]
  [ ! -e "$DATA_ROOT/bin" ]
  [ ! -e "$DATA_ROOT/accounts" ]
  [ -f "$DATA_ROOT/profiles/workexamplecom/Cookies" ]
  [[ "$output" == *"kept:"* ]] || false
}

@test "uninstall --purge-data moves profiles to the Trash but never imported dirs" {
  "$CDT" add work@example.com >/dev/null
  touch "$DATA_ROOT/profiles/workexamplecom/Cookies"
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext"
  "$CDT" import "$ext" --as imported@example.com >/dev/null
  run "$CDT" uninstall --purge-data <<< "y"
  [ "$status" -eq 0 ]
  [ ! -e "$DATA_ROOT" ]
  [ -d "$ext" ]
  ls "$HOME/.Trash" | grep -q '^workexamplecom '
}

@test "import refuses the plain Claude.app data dir" {
  mkdir -p "$HOME/Library/Application Support/Claude"
  run "$CDT" import "$HOME/Library/Application Support/Claude" --as main@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be imported"* ]] || false
}
