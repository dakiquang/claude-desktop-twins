# shellcheck shell=bash
# List and copy Claude Code sessions between accounts.
#
# Layout (checked on Claude 5.11492.5, undocumented by Anthropic):
#   <data dir>/claude-code-sessions/<accountUuid>/<orgUuid>/local_<uuid>.json
#   <data dir>/claude-code-sessions/<accountUuid>/<orgUuid>/archived-sessions.idx
#       {"v":1,"archived":["local_<uuid>", ...]}
# Transcripts live in the shared ~/.claude/projects/*/<cliSessionId>.jsonl.

# Newest Claude version the layout above was checked against. Copies refuse to run on
# a newer Claude unless --force, so a layout change fails closed.
CDT_SESSIONS_LAYOUT_VERSION="5.11492.5"

_json() { osascript -l JavaScript "$(dirname "${BASH_SOURCE[0]}")/json.js" "$@"; }

# Data dir for an account query or "default" (plain Claude.app).
sessions_data_dir() { # query
  local slug
  if [ "$1" = "default" ]; then
    echo "$CDT_DEFAULT_DATA_DIR"
    return 0
  fi
  slug="$(account_resolve "$1")" || return 1
  account_data_dir "$slug"
}

sessions_name() { # query -> slug or "default", for backup names and messages
  if [ "$1" = "default" ]; then echo default; else account_resolve "$1"; fi
}

# Org dirs of a store, one per line.
sessions_org_dirs() { # data_dir
  local d
  for d in "$1"/claude-code-sessions/*/*/; do
    [ -d "$d" ] && echo "${d%/}"
  done
}

_count_sessions() { # org_dir
  local f n=0
  for f in "$1"/local_*.json; do [ -f "$f" ] && n=$((n + 1)); done
  echo "$n"
}

# The org dir that receives copies: the one with the most sessions, newest on a tie.
sessions_target_dir() { # data_dir
  local d best="" best_n=-1 best_t=0 n t
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n="$(_count_sessions "$d")"
    t="$(stat -f %m "$d")"
    if [ "$n" -gt "$best_n" ] || { [ "$n" -eq "$best_n" ] && [ "$t" -gt "$best_t" ]; }; then
      best="$d"; best_n="$n"; best_t="$t"
    fi
  done <<EOF
$(sessions_org_dirs "$1")
EOF
  [ -n "$best" ] && echo "$best"
}

sessions_list() { # query
  local data d total archived
  data="$(sessions_data_dir "$1")" || return 1
  if [ -z "$(sessions_org_dirs "$data")" ]; then
    info "no Code sessions in $data"
    return 0
  fi
  while IFS= read -r d; do
    total="$(_count_sessions "$d")"
    archived="$(_json archived "$d/archived-sessions.idx" | grep -c . || true)"
    info "account ${d%/*}" | sed "s#$data/claude-code-sessions/##"
    info "  org ${d##*/}: $total sessions, $archived archived"
    if [ "$total" -gt 0 ]; then
      info "  top working folders:"
      _json scan "$d" | cut -d $'\x1f' -f2 | grep . | sort | uniq -c | sort -rn | head -n 5 |
        sed 's/^ */    /'
    fi
  done <<EOF
$(sessions_org_dirs "$data")
EOF
}

_transcript_exists() { # cliSessionId
  [ -n "$1" ] || return 1
  ls "$CDT_TRANSCRIPTS_DIR"/*/"$1.jsonl" >/dev/null 2>&1
}

sessions_copy() {
  local from="" to="" cwd="" dry=0 force=0 a
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --from) from="${1:-}"; shift ;;
      --to) to="${1:-}"; shift ;;
      --cwd) cwd="${1:-}"; shift ;;
      --dry-run) dry=1 ;;
      --force) force=1 ;;
      *) err "unknown argument: $a"; return 1 ;;
    esac
  done
  [ -n "$from" ] && [ -n "$to" ] ||
    { err "usage: cdt sessions copy --from <account|default> --to <account|default> [--cwd <text>] [--dry-run] [--force]"; return 1; }

  local version
  version="$(claude_version)"
  if [ "$force" = 0 ]; then
    if [ -z "$version" ]; then
      err "cannot read the Claude.app version at $CLAUDE_APP; use --force to copy anyway"
      return 1
    fi
    # Fail closed: anything but "same or older" refuses.
    case "$(version_cmp "$version" "$CDT_SESSIONS_LAYOUT_VERSION")" in
      0|-1) ;;
      *)
      err "the session layout was checked up to Claude $CDT_SESSIONS_LAYOUT_VERSION; Claude.app is $version."
      err "Check that sessions still work this way, then rerun with --force."
      return 1
        ;;
    esac
  fi

  # The target gets written to, so it must be named exactly.
  if [ "$to" != default ]; then
    to="$(account_resolve_exact "$to")" || return 1
  fi
  local src_data dst_data src_name dst_name target
  src_data="$(sessions_data_dir "$from")" || return 1
  dst_data="$(sessions_data_dir "$to")" || return 1
  src_name="$(sessions_name "$from")"
  dst_name="$(sessions_name "$to")"
  [ "$src_data" != "$dst_data" ] || { err "source and target are the same"; return 1; }
  [ -n "$(sessions_org_dirs "$src_data")" ] || { err "no Code sessions in $src_data"; return 1; }
  target="$(sessions_target_dir "$dst_data")"
  if [ -z "$target" ]; then
    err "$to has no session store yet. Open the Code tab in that account once, then retry."
    return 1
  fi
  if [ "$(sessions_org_dirs "$dst_data" | wc -l | tr -d " ")" -gt 1 ]; then
    warn "$to has several org dirs; writing to the one with the most sessions (shown below)."
  fi
  if [ -n "$(data_dir_pids "$dst_data")" ]; then
    warn "$to is running; copied sessions appear after it restarts."
  fi

  local plan copy_ids="" skipped="" archived_ids="" d id path_cwd cli
  local n_copy=0 n_skip=0 n_arch=0 n_missing=0 src_archived
  plan="$(mktemp -t cdt-sessions)"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    src_archived="$(_json archived "$d/archived-sessions.idx")" || { rm -f "$plan"; return 1; }
    _json scan "$d" > "$plan.scan" || { rm -f "$plan" "$plan.scan"; return 1; }
    while IFS=$'\x1f' read -r id path_cwd cli; do
      [ -n "$id" ] || continue
      if [ -n "$cwd" ]; then
        case "$path_cwd" in *"$cwd"*) ;; *) continue ;; esac
      fi
      case " $copy_ids " in *" $id "*) continue ;; esac
      if [ -e "$target/$id.json" ]; then
        skipped="$skipped $id"; n_skip=$((n_skip + 1))
        continue
      fi
      printf '%s\037%s\037%s\n' "$id" "$d/$id.json" "$target/$id.json" >> "$plan"
      copy_ids="$copy_ids $id"; n_copy=$((n_copy + 1))
      if printf '%s\n' "$src_archived" | grep -xF "$id" >/dev/null; then
        archived_ids="$archived_ids $id"; n_arch=$((n_arch + 1))
      fi
      _transcript_exists "$cli" || n_missing=$((n_missing + 1))
    done < "$plan.scan"
  done <<EOF
$(sessions_org_dirs "$src_data")
EOF
  rm -f "$plan.scan"

  info "from $src_name to $dst_name (${target#"$dst_data"/})"
  [ -n "$cwd" ] && info "filter: working folder contains '$cwd'"

  if [ "$dry" = 1 ]; then
    rm -f "$plan"
    info "dry run, nothing written"
    info "would copy: $n_copy, archived: $n_arch, skipped (already there): $n_skip, missing transcripts: $n_missing"
    [ -n "$skipped" ] && info "skipped ids:$skipped"
    return 0
  fi

  if [ "$n_copy" -eq 0 ]; then
    rm -f "$plan"
    info "nothing to copy. skipped (already there): $n_skip"
    [ -n "$skipped" ] && info "skipped ids:$skipped"
    return 0
  fi

  local backup
  backup="$CDT_BACKUPS_DIR/$(date +%Y%m%d-%H%M%S)-$$-$dst_name.tgz"
  mkdir -p "$CDT_BACKUPS_DIR" || { rm -f "$plan"; return 1; }
  if ! tar -czf "$backup" -C "$dst_data" claude-code-sessions; then
    rm -f "$plan" "$backup"
    err "backup failed; nothing copied."
    return 1
  fi
  info "backup: $backup"

  # Each file is copied to a temp name and moved into place, so a failed copy never
  # leaves a truncated session that later runs would skip as "already there".
  local src dst copied=0 failed="" merge_ids=""
  while IFS=$'\x1f' read -r id src dst; do
    [ -e "$dst" ] && continue   # never overwrite, even if it appeared meanwhile
    if cp "$src" "$dst.cdt-tmp" && mv -n "$dst.cdt-tmp" "$dst" && [ ! -e "$dst.cdt-tmp" ]; then
      copied=$((copied + 1))
      case " $archived_ids " in *" $id "*) merge_ids="$merge_ids $id" ;; esac
    else
      rm -f "$dst.cdt-tmp"
      failed="$failed $id"
    fi
  done < "$plan"
  rm -f "$plan"

  if [ -n "$merge_ids" ]; then
    # shellcheck disable=SC2086
    _json merge-archived "$target/archived-sessions.idx" $merge_ids >/dev/null ||
      { err "copied $copied sessions but could not update the archive index; restore from $backup if needed"; return 1; }
  fi
  n_arch="$(printf '%s' "$merge_ids" | wc -w | tr -d ' ')"
  info "copied: $copied, archived: $n_arch, skipped (already there): $n_skip, missing transcripts: $n_missing"
  [ -n "$skipped" ] && info "skipped ids:$skipped"
  if [ -n "$failed" ]; then
    err "could not copy:$failed (backup: $backup)"
    return 1
  fi
  return 0
}

cmd_sessions() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list)
      [ -n "${1:-}" ] || die "usage: cdt sessions list <account|default>"
      sessions_list "$1" || exit 1 ;;
    copy) sessions_copy "$@" || exit 1 ;;
    *) die "usage: cdt sessions list <account|default> | cdt sessions copy --from <a> --to <b> [--cwd <text>] [--dry-run] [--force]" ;;
  esac
}
