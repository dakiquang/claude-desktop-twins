# shellcheck shell=bash
# Keep each clone from updating itself, with Claude's own "Block auto-updates" setting.
#
# Claude reads a local configuration from <data dir>-3p/configLibrary/: _meta.json names
# the applied entry, <id>.json holds its keys. With --user-data-dir every account has its
# own -3p folder, so {"disableAutoUpdates": true} there blocks that clone's updater only;
# /Applications/Claude.app keeps updating. Checked on Claude 5.11492.5, see
# docs/notes/claude-update-behaviour.md.
#
# The same folder holds a third-party inference setup (Bedrock, Vertex, a gateway), and
# Claude moves the data dir there when it finds one. So the tool only creates the folder
# when it does not exist, marks it, and never edits or deletes a folder it did not make.

CDT_UPDATE_MARKER=".claude-desktop-twins"

update_block_root() { # data_dir -> its -3p folder (a dir already ending in -3p is used as is)
  case "$1" in
    *-3p) echo "$1" ;;
    *) echo "$1-3p" ;;
  esac
}

_update_block_mine() { # root -> the entry id the tool wrote, from its marker
  cat "$1/$CDT_UPDATE_MARKER" 2>/dev/null
}

_update_block_applied() { # root -> appliedId from _meta.json, empty if missing or unreadable
  plutil -extract appliedId raw "$1/configLibrary/_meta.json" 2>/dev/null
}

# blocked: the tool's entry is the applied one and blocks updates
# absent:  no -3p folder, or the tool's own folder with a missing or damaged entry
# foreign: a -3p folder the tool did not make, or one where Claude or the user has since
#          applied another entry (for example an inference setup); never touched
update_block_state() { # data_dir
  local root mine applied
  root="$(update_block_root "$1")"
  [ -e "$root" ] || { echo absent; return 0; }
  [ -f "$root/$CDT_UPDATE_MARKER" ] || { echo foreign; return 0; }
  mine="$(_update_block_mine "$root")"
  applied="$(_update_block_applied "$root")"
  if [ -n "$applied" ] && [ "$applied" != "$mine" ]; then
    echo foreign
  elif [ -n "$mine" ] && [ "$applied" = "$mine" ] &&
    [ "$(plutil -extract disableAutoUpdates raw "$root/configLibrary/$mine.json" 2>/dev/null)" = true ]; then
    echo blocked
  else
    echo absent
  fi
}

# Write the block, or repair the tool's own damaged one. Only the tool's own files are
# written: the marker, its entry and a _meta.json that is missing or already points at
# that entry. Prints the resulting state; returns 0 unless writing failed.
update_block_ensure() { # data_dir
  local root lib id state
  state="$(update_block_state "$1")"
  case "$state" in
    blocked|foreign) echo "$state"; return 0 ;;
  esac
  root="$(update_block_root "$1")"
  lib="$root/configLibrary"
  id="$(_update_block_mine "$root")"
  [ -n "$id" ] || id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  # The marker goes first, so an interrupted write is repaired next time, not taken
  # for someone else's folder.
  mkdir -p "$lib" &&
    printf '%s\n' "$id" > "$root/$CDT_UPDATE_MARKER" &&
    printf '{\n  "disableAutoUpdates": true\n}\n' > "$lib/$id.json" &&
    printf '{"appliedId":"%s","entries":[{"id":"%s","name":"Default"}]}\n' "$id" "$id" > "$lib/_meta.json" ||
    return 1
  echo blocked
}

# Remove the tool's files. Anything else in the folder stays, and so does the whole
# folder when Claude or the user has applied another entry.
update_block_remove() { # data_dir
  local root mine
  root="$(update_block_root "$1")"
  [ -f "$root/$CDT_UPDATE_MARKER" ] || return 0
  [ "$(update_block_state "$1")" = foreign ] && return 0
  mine="$(_update_block_mine "$root")"
  [ -n "$mine" ] && rm -f "$root/configLibrary/$mine.json"
  rm -f "$root/configLibrary/_meta.json" "$root/$CDT_UPDATE_MARKER"
  rmdir "$root/configLibrary" 2>/dev/null
  rmdir "$root" 2>/dev/null
  return 0
}

# Message for clone_build and doctor.
update_block_apply() { # slug
  local data label
  data="$(account_data_dir "$1")"
  label="$(account_label "$1")"
  case "$(update_block_ensure "$data")" in
    blocked) ;;
    foreign) warn "$label: $(update_block_root "$data") holds a configuration that is not cdt's (it may be a third-party inference setup); left alone, so this clone may update itself." ;;
    *) warn "$label: could not write the update block in $(update_block_root "$data")" ;;
  esac
}
