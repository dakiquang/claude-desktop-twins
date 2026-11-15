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
  DST="$CDT_PROFILES_DIR/personalexamplecom/claude-code-sessions/33333333-3333-4333-8333-333333333333/44444444-4444-4444-8444-444444444444"
  S1=local_aaaaaaaa-0000-4000-8000-000000000001
  S2=local_aaaaaaaa-0000-4000-8000-000000000002
  S3=local_aaaaaaaa-0000-4000-8000-000000000003
  S4=local_aaaaaaaa-0000-4000-8000-000000000004
}
teardown() { common_teardown; }

archived() { osascript -l JavaScript "$REPO_ROOT/lib/json.js" archived "$DST/archived-sessions.idx"; }

@test "dry run writes nothing" {
  before="$(ls -lT "$DST")"
  run "$CDT" sessions copy --from work --to personal@example.com --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would copy: 3, archived: 2, skipped (already there): 1, missing transcripts: 2"* ]] || false
  [ "$(ls -lT "$DST")" = "$before" ]
  [ ! -d "$CDT_BACKUPS_DIR" ]
}

@test "copy backs up, never overwrites and merges archive state once" {
  run "$CDT" sessions copy --from work --to personal@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"copied: 3, archived: 2, skipped (already there): 1, missing transcripts: 2"* ]] || false
  [[ "$output" == *"skipped ids: $S1"* ]] || false
  ls "$CDT_BACKUPS_DIR"/*-personalexamplecom.tgz
  tar -tzf "$CDT_BACKUPS_DIR"/*-personalexamplecom.tgz | grep -q "$S1.json"
  grep -q "keep me" "$DST/$S1.json"
  [ -f "$DST/$S2.json" ] && [ -f "$DST/$S3.json" ] && [ -f "$DST/$S4.json" ]
  run archived
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
  [ "$(printf '%s\n' "$output" | grep -cx "$S2")" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -cx "$S4")" -eq 1 ]
  # A second run copies nothing and adds no duplicate archive entries.
  run "$CDT" sessions copy --from work --to personal@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to copy. skipped (already there): 4"* ]] || false
  [ "$(archived | grep -c .)" -eq 3 ]
}

@test "the --cwd filter copies only matching sessions" {
  run "$CDT" sessions copy --from work --to personal@example.com --cwd /work/
  [ "$status" -eq 0 ]
  [[ "$output" == *"copied: 2, archived: 2"* ]] || false
  [ -f "$DST/$S2.json" ] && [ -f "$DST/$S4.json" ]
  [ ! -e "$DST/$S3.json" ]
}

@test "a target without a session store stops with the Code tab message" {
  run "$CDT" sessions copy --from work --to new@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"Open the Code tab in that account once, then retry."* ]] || false
  [ ! -d "$CDT_BACKUPS_DIR" ]
}

@test "copy refuses a newer Claude than the checked layout unless --force" {
  set_claude_version 9.0.0
  run "$CDT" sessions copy --from work --to personal@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"rerun with --force"* ]] || false
  [ ! -e "$DST/$S2.json" ]
  run "$CDT" sessions copy --from work --to personal@example.com --force
  [ "$status" -eq 0 ]
  [ -f "$DST/$S2.json" ]
}

@test "default means the plain Claude data dir" {
  mkdir -p "$HOME/Library/Application Support"
  cp -R "$REPO_ROOT/test/fixtures/sessions/account-a" "$HOME/Library/Application Support/Claude"
  run "$CDT" sessions copy --from default --to personal@example.com --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"from default to personalexamplecom"* ]] || false
}

@test "sessions list counts sessions, archived ones and folders" {
  run "$CDT" sessions list work
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sessions, 2 archived"* ]] || false
  [[ "$output" == *"2 /Users/example/work/api"* ]] || false
}

@test "copy to the same account is refused" {
  run "$CDT" sessions copy --from work --to work@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"same"* ]] || false
}

@test "a session without a working folder keeps its other fields" {
  src="$CDT_PROFILES_DIR/workexamplecom/claude-code-sessions/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222"
  printf '{"sessionId":"local_aaaaaaaa-0000-4000-8000-000000000005","cliSessionId":"c0000000-0000-4000-8000-000000000001"}\n' > "$src/local_aaaaaaaa-0000-4000-8000-000000000005.json"
  run "$CDT" sessions copy --from work --to personal@example.com --cwd c0000000 --dry-run
  [[ "$output" == *"would copy: 0"* ]] || false
  run "$CDT" sessions copy --from work --to personal@example.com --dry-run
  [[ "$output" == *"would copy: 4, archived: 2, skipped (already there): 1, missing transcripts: 2"* ]] || false
}

@test "the target account must be named in full" {
  run "$CDT" sessions copy --from work --to personal
  [ "$status" -eq 1 ]
  [[ "$output" == *"Did you mean: personal@example.com?"* ]] || false
  [ ! -e "$DST/$S2.json" ]
}

@test "a failed copy is reported, leaves no partial file and is not archived" {
  # A read-only file at the temp name makes cp fail for this one session.
  touch "$DST/$S2.json.cdt-tmp"; chmod 444 "$DST/$S2.json.cdt-tmp"
  run "$CDT" sessions copy --from work --to personal@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not copy: $S2"* ]] || false
  [ ! -e "$DST/$S2.json" ]
  [ -z "$(ls "$DST" | grep cdt-tmp || true)" ]
  [ "$(archived | grep -cx "$S2" || true)" -eq 0 ]
  [ "$(archived | grep -cx "$S4")" -eq 1 ]
}
