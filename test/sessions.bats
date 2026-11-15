#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }

setup() {
  common_setup
  load_libs
  local fx="$REPO_ROOT/test/fixtures/sessions"
  mkdir -p "$CDT_PROFILES_DIR"
  cp -R "$fx/account-a" "$CDT_PROFILES_DIR/workexamplecom"
  cp -R "$fx/account-b" "$CDT_PROFILES_DIR/personalexamplecom"
  mkdir -p "$CDT_PROFILES_DIR/newexamplecom"
  account_create workexamplecom work@example.com "$CDT_PROFILES_DIR/workexamplecom"
  account_create personalexamplecom personal@example.com "$CDT_PROFILES_DIR/personalexamplecom"
  account_create newexamplecom new@example.com "$CDT_PROFILES_DIR/newexamplecom"
  export CDT_TRANSCRIPTS_DIR="$BATS_TEST_TMPDIR/transcripts"
  cp -R "$fx/transcripts" "$CDT_TRANSCRIPTS_DIR"
}
teardown() { common_teardown; }


@test "sessions list counts sessions, archived ones and folders" {
  run "$CDT" sessions list work
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sessions, 2 archived"* ]] || false
  [[ "$output" == *"2 /Users/example/work/api"* ]] || false
}

@test "default means the plain Claude data dir" {
  mkdir -p "$HOME/Library/Application Support"
  cp -R "$REPO_ROOT/test/fixtures/sessions/account-a" "$HOME/Library/Application Support/Claude"
  run "$CDT" sessions list default
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sessions, 2 archived"* ]] || false
}

@test "an account without a session store says so" {
  run "$CDT" sessions list new@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Code sessions"* ]] || false
}

@test "sessions copy points to Premium and changes nothing" {
  before="$(cd "$CDT_PROFILES_DIR" && find . -type f -exec shasum {} + | sort)"
  run "$CDT" sessions copy --from work --to personal@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"part of Claude Desktop Twins Premium"* ]] || false
  [[ "$output" == *"#premium"* ]] || false
  [ "$(cd "$CDT_PROFILES_DIR" && find . -type f -exec shasum {} + | sort)" = "$before" ]
  [ ! -e "$CDT_BACKUPS_DIR" ]
}
