#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

clone() { echo "$APPS/work@example.com.app"; }

@test "add builds a clone with its own identity" {
  run "$CDT" add work@example.com
  [ "$status" -eq 0 ]
  c="$(clone)/Contents"
  [ "$(plutil -extract CFBundleIdentifier raw "$c/Info.plist")" = "local.claude-desktop-twins.workexamplecom" ]
  [ "$(plutil -extract CFBundleDisplayName raw "$c/Info.plist")" = "Claude · work@example.com" ]
  [ "$(plutil -extract CFBundleExecutable raw "$c/Info.plist")" = "launcher" ]
  [ "$(plutil -extract LocalSourceVersion raw "$c/Info.plist")" = "5.11492.5" ]
  run plutil -extract CFBundleURLTypes raw "$c/Info.plist"
  [ "$status" -ne 0 ]
  [ ! -e "$c/embedded.provisionprofile" ]
  [ -d "$DATA_ROOT/profiles/workexamplecom" ]
  [ -f "$DATA_ROOT/accounts/workexamplecom.plist" ]
}

@test "main binary and helper are signed with the bundle id as identifier" {
  "$CDT" add work@example.com
  c="$(clone)/Contents"
  run codesign -dv "$c/MacOS/Claude"
  [[ "$output" == *"Identifier=local.claude-desktop-twins.workexamplecom"* ]] || false
  run codesign -dv "$c/MacOS/cdt-helper"
  [[ "$output" == *"Identifier=local.claude-desktop-twins.workexamplecom"* ]] || false
  run codesign --verify --strict "$(clone)"
  [ "$status" -eq 0 ]
}

@test "launcher starts Claude on the account's data dir" {
  "$CDT" add work@example.com
  run cat "$(clone)/Contents/MacOS/launcher"
  [[ "$output" == *'--user-data-dir='*'claude-desktop-twins/profiles/workexamplecom'* ]] || false
  [[ "$output" == *'exec "$(dirname "$0")/Claude"'* ]] || false
}

@test "add asks for notification permission through the clone's helper" {
  "$CDT" add work@example.com
  # The default mode (no arguments) is the permission request.
  [ -s "$FAKE_HELPER_LOG" ]
  [ "$(head -n 1 "$FAKE_HELPER_LOG")" = "" ]
}

@test "add twice for the same account fails with a clear message" {
  "$CDT" add work@example.com
  run "$CDT" add Work@Example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
}

@test "add rejects a name without letters or digits" {
  run "$CDT" add "@@@"
  [ "$status" -eq 1 ]
  [ ! -d "$DATA_ROOT/accounts" ] || [ -z "$(ls "$DATA_ROOT/accounts")" ]
}

@test "a failed rebuild leaves the previous clone intact" {
  "$CDT" add work@example.com
  before="$(shasum "$(clone)/Contents/Info.plist")"
  printf 'not a plist' > "$CLAUDE_APP/Contents/Info.plist"
  export CLAUDE_APP
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 1 ]
  [ "$(shasum "$(clone)/Contents/Info.plist")" = "$before" ]
  run codesign --verify --strict "$(clone)"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$APPS" | grep building || true)" ]
}

@test "rebuild picks up a new Claude version" {
  "$CDT" add work@example.com
  set_claude_version 5.20000.1
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 0 ]
  [ "$(plutil -extract LocalSourceVersion raw "$(clone)/Contents/Info.plist")" = "5.20000.1" ]
}

cdt_version() { sed -n 's/^CDT_VERSION="\(.*\)"$/\1/p' "$REPO_ROOT/lib/common.sh"; }

@test "add records the cdt version that built the clone" {
  v="$(cdt_version)"
  [ -n "$v" ]
  run "$CDT" add work@example.com
  [ "$status" -eq 0 ]
  [ "$(plutil -extract CDTBuilderVersion raw "$(clone)/Contents/Info.plist")" = "$v" ]
}

@test "rebuild records the cdt version on a clone built without it" {
  "$CDT" add work@example.com
  # A clone from cdt 0.2.0 or older has no such key.
  plutil -remove CDTBuilderVersion "$(clone)/Contents/Info.plist" >/dev/null 2>&1 || true
  run plutil -extract CDTBuilderVersion raw "$(clone)/Contents/Info.plist"
  [ "$status" -ne 0 ]
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 0 ]
  [ "$(plutil -extract CDTBuilderVersion raw "$(clone)/Contents/Info.plist")" = "$(cdt_version)" ]
}

@test "rebuild and remove refuse while the account runs" {
  "$CDT" add work@example.com
  start_account work@example.com
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"is running"* ]] || false
  run "$CDT" remove work@example.com
  [ "$status" -eq 1 ]
  [ -d "$(clone)" ]
}

@test "remove deletes the clone and registry but keeps data" {
  "$CDT" add work@example.com
  touch "$DATA_ROOT/profiles/workexamplecom/Cookies"
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ ! -e "$(clone)" ]
  [ ! -e "$DATA_ROOT/accounts/workexamplecom.plist" ]
  [ -f "$DATA_ROOT/profiles/workexamplecom/Cookies" ]
}

@test "remove --purge moves the data dir to the Trash after confirmation" {
  "$CDT" add work@example.com
  touch "$DATA_ROOT/profiles/workexamplecom/Cookies"
  run "$CDT" remove work@example.com --purge <<< "n"
  [ "$status" -eq 1 ]
  [ -d "$(clone)" ]
  run "$CDT" remove work@example.com --purge <<< "y"
  [ "$status" -eq 0 ]
  [ ! -e "$DATA_ROOT/profiles/workexamplecom" ]
  ls "$HOME/.Trash" | grep -q '^workexamplecom '
}

@test "destructive commands need the full account name" {
  "$CDT" add work@example.com >/dev/null
  run "$CDT" remove work
  [ "$status" -eq 1 ]
  [[ "$output" == *"Did you mean: work@example.com?"* ]] || false
  [ -d "$(clone)" ]
  run "$CDT" rebuild WORK@example.com
  [ "$status" -eq 0 ]
}

@test "remove --purge never trashes an imported data dir" {
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext"; touch "$ext/Cookies"
  "$CDT" import "$ext" --as work@example.com >/dev/null
  run "$CDT" remove work@example.com --purge <<< "y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"never purged"* ]] || false
  [ -f "$ext/Cookies" ]
}

@test "remove refuses while another launcher's Claude uses the data dir" {
  "$CDT" add work@example.com >/dev/null
  FAKE_CLAUDE_SLEEP=60 "$CLAUDE_APP/Contents/MacOS/Claude" --user-data-dir="$DATA_ROOT/profiles/workexamplecom" >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"; disown
  sleep 0.3
  run "$CDT" remove work@example.com --purge <<< "y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is running"* ]] || false
  [ -d "$DATA_ROOT/profiles/workexamplecom" ]
}

@test "a rebuild after an interrupted one restores the leftover clone" {
  "$CDT" add work@example.com >/dev/null
  mkdir -p "$APPS/.cdt-work"
  mv "$(clone)" "$APPS/.cdt-work/workexamplecom.old.app"
  printf 'not a plist' > "$CLAUDE_APP/Contents/Info.plist"
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 1 ]
  [ -d "$(clone)" ]
  run codesign --verify --strict "$(clone)"
  [ "$status" -eq 0 ]
}

@test "rebuild refuses to recreate a missing imported data dir" {
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext"
  "$CDT" import "$ext" --as work@example.com >/dev/null
  rm -rf "$ext"
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"data dir not found"* ]] || false
  [ ! -e "$ext" ]
}

@test "add rejects reserved and hidden names" {
  run "$CDT" add default
  [ "$status" -eq 1 ]
  run "$CDT" add .work.old
  [ "$status" -eq 1 ]
}

@test "add rejects the name reserved for the Premium app, in any case or punctuation" {
  for name in premium Premium PRE-MIUM; do
    run "$CDT" add "$name"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'premium' is reserved"* ]] || false
  done
  [ ! -e "$DATA_ROOT/accounts/premium.plist" ]
  [ ! -e "$DATA_ROOT/profiles/premium" ]
  [ ! -e "$APPS/Premium.app" ]
}
