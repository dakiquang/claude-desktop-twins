#!/usr/bin/env bats

load test_helper

setup_file() { build_fixtures; }
setup() { common_setup; }
teardown() { common_teardown; }

profile() { echo "$DATA_ROOT/profiles/workexamplecom"; }
lib() { echo "$(profile)-3p/configLibrary"; }

@test "add blocks the clone's self-update in its own -3p folder" {
  run "$CDT" add work@example.com
  [ "$status" -eq 0 ]
  id="$(plutil -extract appliedId raw "$(lib)/_meta.json")"
  [ "$(plutil -extract disableAutoUpdates raw "$(lib)/$id.json")" = true ]
  [ "$(cat "$(profile)-3p/.claude-desktop-twins")" = "$id" ]
  # Claude's data stays in the data dir itself.
  [ ! -e "$(profile)/configLibrary" ]
}

@test "rebuild keeps one block and repairs a damaged one" {
  "$CDT" add work@example.com >/dev/null
  id="$(plutil -extract appliedId raw "$(lib)/_meta.json")"
  "$CDT" rebuild work@example.com >/dev/null
  [ "$(plutil -extract appliedId raw "$(lib)/_meta.json")" = "$id" ]
  [ "$(ls "$(lib)" | wc -l | tr -d ' ')" -eq 2 ]
  printf '{}' > "$(lib)/$id.json"
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 0 ]
  id2="$(plutil -extract appliedId raw "$(lib)/_meta.json")"
  [ "$(plutil -extract disableAutoUpdates raw "$(lib)/$id2.json")" = true ]
}

@test "a -3p folder the tool did not make is never touched" {
  ext="$BATS_TEST_TMPDIR/OtherLauncher/work"
  mkdir -p "$ext" "$ext-3p/configLibrary"
  printf '{"inferenceProvider":"gateway"}' > "$ext-3p/configLibrary/mine.json"
  before="$(cd "$ext-3p" && find . -type f -exec shasum {} + | sort)"
  run "$CDT" import "$ext" --as work@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"not cdt's"* ]] || false
  [ "$(cd "$ext-3p" && find . -type f -exec shasum {} + | sort)" = "$before" ]
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ -f "$ext-3p/configLibrary/mine.json" ]
  [ "$(cd "$ext-3p" && find . -type f -exec shasum {} + | sort)" = "$before" ]
}

@test "doctor reports the block, a missing one and a foreign folder" {
  "$CDT" add work@example.com >/dev/null
  run "$CDT" doctor
  [[ "$output" == *"ok    self-update blocked"* ]] || false
  rm -rf "$(profile)-3p"
  run "$CDT" doctor
  [[ "$output" == *"warn  self-update not blocked. Run: cdt rebuild work@example.com"* ]] || false
  mkdir -p "$(profile)-3p"
  run "$CDT" doctor
  [[ "$output" == *"not cdt's"* ]] || false
}

@test "remove and uninstall take the block away" {
  "$CDT" add work@example.com >/dev/null
  "$CDT" add personal@example.com >/dev/null
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ ! -e "$(profile)-3p" ]
  [ -d "$(profile)" ]
  run "$CDT" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$DATA_ROOT/profiles/personalexamplecom-3p" ]
}

@test "remove keeps a -3p folder Claude has added to" {
  "$CDT" add work@example.com >/dev/null
  touch "$(profile)-3p/claude_desktop_config.json"
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ -f "$(profile)-3p/claude_desktop_config.json" ]
  [ ! -e "$(lib)" ]
  [ ! -e "$(profile)-3p/.claude-desktop-twins" ]
}

@test "a configuration Claude applies later is never changed or removed" {
  "$CDT" add work@example.com >/dev/null
  printf '{"inferenceProvider":"gateway"}' > "$(lib)/other.json"
  printf '{"appliedId":"other","entries":[{"id":"other","name":"Gateway"}]}' > "$(lib)/_meta.json"
  before="$(cd "$(profile)-3p" && find . -type f -exec shasum {} + | sort)"
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"not cdt's"* ]] || false
  run "$CDT" doctor
  [[ "$output" == *"not cdt's and is left alone"* ]] || false
  run "$CDT" remove work@example.com
  [ "$status" -eq 0 ]
  [ "$(cd "$(profile)-3p" && find . -type f -exec shasum {} + | sort)" = "$before" ]
}

@test "an interrupted first write is repaired, not taken for someone else's folder" {
  "$CDT" add work@example.com >/dev/null
  id="$(cat "$(profile)-3p/.claude-desktop-twins")"
  rm -f "$(lib)/$id.json" "$(lib)/_meta.json"
  run "$CDT" rebuild work@example.com
  [ "$status" -eq 0 ]
  [ "$(plutil -extract appliedId raw "$(lib)/_meta.json")" = "$id" ]
  [ "$(plutil -extract disableAutoUpdates raw "$(lib)/$id.json")" = true ]
}
