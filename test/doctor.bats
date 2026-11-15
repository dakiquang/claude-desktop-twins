#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "doctor with no accounts says so and exits 0" {
  run "$CDT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"no accounts yet: run cdt add <account>"* ]] || false
  [[ "$output" == *"version 5.11492.5"* ]] || false
}

@test "doctor exits 1 when Claude.app is missing" {
  CLAUDE_APP="$BATS_TEST_TMPDIR/missing.app" run "$CDT" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found at"* ]] || false
}

@test "doctor reports a healthy clone" {
  "$CDT" add work@example.com >/dev/null
  run "$CDT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"signature verifies"* ]] || false
  [[ "$output" == *"signing identifier matches bundle id local.claude-desktop-twins.workexamplecom"* ]] || false
  [[ "$output" == *"notifications: authorized"* ]] || false
}

@test "doctor reports a stale clone with the rebuild command" {
  "$CDT" add work@example.com >/dev/null
  set_claude_version 5.20000.1
  run "$CDT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale: built for 5.11492.5, Claude.app is 5.20000.1. Run: cdt rebuild work@example.com"* ]] || false
}

@test "doctor fails when a clone is missing" {
  "$CDT" add work@example.com >/dev/null
  rm -rf "$APPS/work@example.com.app"
  run "$CDT" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"app missing"* ]] || false
}
