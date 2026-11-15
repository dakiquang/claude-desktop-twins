#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "cdt --help exits 0" {
  run "$CDT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not affiliated with Anthropic"* ]] || false
}

@test "the long name and the alias are the same command" {
  run "$REPO_ROOT/bin/claude-desktop-twins" --version
  [ "$status" -eq 0 ]
  [ "$output" = "claude-desktop-twins 0.1.0" ]
}

@test "unknown command exits 64" {
  run "$CDT" frobnicate
  [ "$status" -eq 64 ]
}

@test "no arguments without a terminal prints usage" {
  run "$CDT" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]] || false
}

@test "slugify keeps lowercase letters and digits only" {
  load_libs
  [ "$(slugify "Work@Example.com")" = "workexamplecom" ]
  [ "$(slugify "personal+2@example.com")" = "personal2examplecom" ]
}

@test "version_cmp compares dotted versions numerically" {
  load_libs
  [ "$(version_cmp 5.11492.5 5.11492.5)" = 0 ]
  [ "$(version_cmp 5.11492.10 5.11492.5)" = 1 ]
  [ "$(version_cmp 5.9 5.11492.5)" = -1 ]
  [ "$(version_cmp 6 5.11492.5)" = 1 ]
}

@test "version_cmp handles suffixes without failing open" {
  load_libs
  [ "$(version_cmp 5.11492.6-beta 5.11492.5)" = 1 ]
  [ "$(version_cmp 5.11492.5-beta 5.11492.5)" = 0 ]
}
