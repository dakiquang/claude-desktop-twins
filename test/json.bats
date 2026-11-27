#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

# Read one value from JSON on stdin; fails when the JSON does not parse.
jget() { plutil -extract "$1" raw -o - -; }
jvalid() { plutil -convert json -o /dev/null -; }

ICNS=/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns

@test "list --json is valid with no accounts" {
  run "$CDT" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jvalid
  [ "$(printf '%s' "$output" | jget schema)" = 1 ]
  [ "$(printf '%s' "$output" | jget claude_version)" = "5.11492.5" ]
  run sh -c "printf '%s' '$output' | plutil -extract accounts.0 raw -o - -"
  [ "$status" -ne 0 ]
}

@test "list --json keeps quotes, backslashes and unicode in labels" {
  "$CDT" add 'Ann "A" \ é@example.com' >/dev/null
  "$CDT" add work@example.com >/dev/null
  run "$CDT" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jvalid
  [ "$(printf '%s' "$output" | jget accounts.0.label)" = 'Ann "A" \ é@example.com' ]
  [ "$(printf '%s' "$output" | jget accounts.1.state)" = current ]
  [ "$(printf '%s' "$output" | jget accounts.1.running)" = false ]
  [ "$(printf '%s' "$output" | jget accounts.1.update_block)" = blocked ]
}

@test "list --json reports a running account and a stale clone" {
  "$CDT" add work@example.com >/dev/null
  start_account work@example.com
  set_claude_version 5.20000.1
  run "$CDT" list --json
  [ "$(printf '%s' "$output" | jget accounts.0.running)" = true ]
  [ -n "$(printf '%s' "$output" | jget accounts.0.pid)" ]
  [ "$(printf '%s' "$output" | jget accounts.0.state)" = stale ]
}

@test "doctor --json lists checks with ids and fix commands" {
  "$CDT" add work@example.com >/dev/null
  set_claude_version 5.20000.1
  run "$CDT" doctor --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jvalid
  [ "$(printf '%s' "$output" | jget ok)" = true ]
  [[ "$output" == *'"id":"version","level":"warn"'* ]] || false
  [[ "$output" == *'"fix":"cdt rebuild work@example.com"'* ]] || false
  [[ "$output" == *'"account":"workexamplecom"'* ]] || false
  [[ "$output" != *"Claude.app"$'\n'* ]] || false
}

@test "doctor --json fails with ok false when an app is missing" {
  "$CDT" add work@example.com >/dev/null
  rm -rf "$APPS/work@example.com.app"
  run "$CDT" doctor --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | jget ok)" = false ]
  [[ "$output" == *'"id":"app","level":"fail"'* ]] || false
}

@test "sessions list --json counts sessions, archived and folders" {
  "$CDT" add work@example.com >/dev/null
  cp -R "$REPO_ROOT/test/fixtures/sessions/account-a/claude-code-sessions" "$DATA_ROOT/profiles/workexamplecom/"
  run "$CDT" sessions list work --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jvalid
  [ "$(printf '%s' "$output" | jget orgs.0.sessions)" = 4 ]
  [ "$(printf '%s' "$output" | jget orgs.0.archived)" = 2 ]
  [ "$(printf '%s' "$output" | jget orgs.0.folders.0.folder)" = /Users/example/work/api ]
  [ "$(printf '%s' "$output" | jget orgs.0.folders.0.sessions)" = 2 ]
}

@test "sessions list --json is valid for an account without sessions" {
  "$CDT" add work@example.com >/dev/null
  run "$CDT" sessions list work --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"orgs":[]'* ]] || false
}

@test "icon set puts the icns in the clone, keeps it on rebuild, and reset removes it" {
  [ -f "$ICNS" ] || skip "no system icns to test with"
  "$CDT" add work@example.com >/dev/null
  run "$CDT" icon set work@example.com "$ICNS"
  [ "$status" -eq 0 ]
  c="$APPS/work@example.com.app/Contents"
  [ "$(plutil -extract CFBundleIconFile raw "$c/Info.plist")" = cdt-account.icns ]
  run plutil -extract CFBundleIconName raw "$c/Info.plist"
  [ "$status" -ne 0 ]
  cmp -s "$ICNS" "$c/Resources/cdt-account.icns"
  run codesign --verify --strict "$APPS/work@example.com.app"
  [ "$status" -eq 0 ]
  "$CDT" rebuild work@example.com >/dev/null
  cmp -s "$ICNS" "$c/Resources/cdt-account.icns"
  [ "$("$CDT" list --json | jget accounts.0.icon)" = "$DATA_ROOT/icons/workexamplecom.icns" ]
  run "$CDT" icon reset work@example.com
  [ "$status" -eq 0 ]
  [ ! -e "$c/Resources/cdt-account.icns" ]
  [ ! -e "$DATA_ROOT/icons/workexamplecom.icns" ]
}

@test "icon set and reset restart the notification services so banners show the new icon" {
  [ -f "$ICNS" ] || skip "no system icns to test with"
  "$CDT" add work@example.com >/dev/null
  "$CDT" rebuild work@example.com >/dev/null
  [ ! -e "$KILLALL_LOG" ]
  run "$CDT" icon set work@example.com "$ICNS"
  [ "$status" -eq 0 ]
  [ "$(cat "$KILLALL_LOG")" = "usernoted NotificationCenter" ]
  run "$CDT" icon reset work@example.com
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$KILLALL_LOG" | tr -d ' ')" = 2 ]
}

@test "icon set refuses a file that is not icns, and remove deletes the stored icon" {
  [ -f "$ICNS" ] || skip "no system icns to test with"
  "$CDT" add work@example.com >/dev/null
  printf 'not an icon' > "$BATS_TEST_TMPDIR/x.icns"
  run "$CDT" icon set work@example.com "$BATS_TEST_TMPDIR/x.icns"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an .icns file"* ]] || false
  "$CDT" icon set work@example.com "$ICNS" >/dev/null
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ ! -e "$DATA_ROOT/icons/workexamplecom.icns" ]
}

@test "icon set refuses while the account runs" {
  [ -f "$ICNS" ] || skip "no system icns to test with"
  "$CDT" add work@example.com >/dev/null
  start_account work@example.com
  run "$CDT" icon set work@example.com "$ICNS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is running"* ]] || false
}
