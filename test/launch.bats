#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; load_libs; }
teardown() { common_teardown; }

register() { # label [non-empty]
  local slug
  slug="$(slugify "$1")"
  mkdir -p "$CDT_PROFILES_DIR/$slug"
  account_create "$slug" "$1" "$CDT_PROFILES_DIR/$slug"
  [ -z "${2:-}" ] || touch "$CDT_PROFILES_DIR/$slug/Preferences"
}

@test "an exact match wins over substring matches" {
  register work@example.com used
  register work2@example.com used
  run account_resolve "Work@Example.com"
  [ "$status" -eq 0 ]
  [ "$output" = "workexamplecom" ]
}

@test "a substring query matches ignoring case and punctuation" {
  register personal@example.com used
  register work@example.com used
  run account_resolve "PERSONAL"
  [ "$output" = "personalexamplecom" ]
}

@test "among several matches an empty data dir is dropped" {
  register work@example.com used
  register work-old@example.com
  run account_resolve "work"
  [ "$status" -eq 0 ]
  [ "$output" = "workexamplecom" ]
}

@test "an ambiguous query lists candidates and exits 1" {
  register work@example.com used
  register work2@example.com used
  run account_resolve "work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"several accounts match"* ]] || false
  [[ "$output" == *"work2@example.com"* ]] || false
}

@test "no match exits 1" {
  register work@example.com used
  run account_resolve "nobody"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no account matches"* ]] || false
}

@test "account_pid ignores a shell whose command line contains the data dir" {
  "$CDT" add work@example.com >/dev/null
  data="$(account_data_dir workexamplecom)"
  bash -c "sleep 30; : --user-data-dir=$data " >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"; disown
  sleep 0.2
  [ -z "$(account_pid workexamplecom)" ]
  start_account work@example.com
  [ -n "$(account_pid workexamplecom)" ]
}

@test "account_pid does not match a data dir that only shares a prefix" {
  "$CDT" add work@example.com >/dev/null
  "$CDT" add work@example.com.au >/dev/null
  start_account work@example.com.au
  [ -z "$(account_pid workexamplecom)" ]
  [ -n "$(account_pid workexamplecomau)" ]
}

@test "open on a running account focuses it and never starts another instance" {
  "$CDT" add work@example.com >/dev/null
  : > "$FAKE_HELPER_LOG"
  start_account work@example.com
  pid="$(account_pid workexamplecom)"
  run "$CDT" open work
  [ "$status" -eq 0 ]
  [[ "$output" == *"is running (pid $pid)"* ]] || false
  grep -qx -- "--focus $pid" "$FAKE_HELPER_LOG"
  [ ! -e "$OPEN_LOG" ]
  run "$CDT" open work
  [ "$(data_dir_pids "$(account_data_dir workexamplecom)" | wc -l | tr -d ' ')" = 1 ]
}

@test "open on a stopped account opens its app" {
  "$CDT" add work@example.com >/dev/null
  run "$CDT" open work@example.com
  [ "$status" -eq 0 ]
  [ "$(cat "$OPEN_LOG")" = "$APPS/work@example.com.app" ]
}

@test "open on a stale clone still opens it and prints the rebuild command" {
  "$CDT" add work@example.com >/dev/null
  set_claude_version 5.20000.1
  run "$CDT" open work
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale: built for 5.11492.5, Claude.app is 5.20000.1. Run: cdt rebuild work@example.com"* ]] || false
  [ -s "$OPEN_LOG" ]
}

@test "list shows running state, versions and stale accounts" {
  "$CDT" add work@example.com >/dev/null
  "$CDT" add personal@example.com >/dev/null
  start_account work@example.com
  set_claude_version 5.20000.1
  run "$CDT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"work@example.com"*"yes"*"5.11492.5"*"stale"* ]] || false
  [[ "$output" == *"personal@example.com"*"no"*"empty data dir"* ]] || false
  [[ "$output" == *"Run: cdt rebuild personal@example.com"* ]] || false
}

@test "data dir match does not catch a longer path that starts with a space" {
  short="$BATS_TEST_TMPDIR/x/Claude"
  mkdir -p "$short" "$short Work"
  FAKE_CLAUDE_SLEEP=60 "$CLAUDE_APP/Contents/MacOS/Claude" --user-data-dir="$short Work" >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"; disown
  sleep 0.3
  [ -z "$(data_dir_pids "$short")" ]
  [ -n "$(data_dir_pids "$short Work")" ]
}

@test "a flagless Claude counts as running on the default data dir" {
  FAKE_CLAUDE_SLEEP=60 "$CLAUDE_APP/Contents/MacOS/Claude" >/dev/null 2>&1 &
  BG_PIDS="$BG_PIDS $!"; disown
  sleep 0.3
  [ -n "$(data_dir_pids "$CDT_DEFAULT_DATA_DIR")" ]
  [ -z "$(data_dir_pids "$BATS_TEST_TMPDIR/other")" ]
}
