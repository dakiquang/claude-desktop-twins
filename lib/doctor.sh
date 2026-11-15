# shellcheck shell=bash
# `cdt doctor`: explain anything that is off. Exits 1 when a check fails; warnings
# (stale clone, permission not granted) keep exit 0.

_doc_ok() { printf '  ok    %s\n' "$*"; }
_doc_warn() { printf '  warn  %s\n' "$*"; }
_doc_fail() { printf '  FAIL  %s\n' "$*"; DOCTOR_FAILED=1; }

# Status of the Desktop's native multi-account feature, read from the
# --desktop-features JSON that Claude passes to its helper processes.
multi_account_status() {
  # shellcheck disable=SC2009 # reads every command line, pgrep cannot print the JSON
  ps -axo command= 2>/dev/null |
    grep -o '"multiAccount":{"status":"[a-z_]*"' | head -n 1 |
    sed 's/.*"status":"\([a-z_]*\)"/\1/'
}

cmd_doctor() {
  local s label app id status pids n ma helper
  DOCTOR_FAILED=0
  info "Claude.app"
  if claude_app_ok; then
    _doc_ok "found at $CLAUDE_APP, version $(claude_version)"
  else
    _doc_fail "not found at $CLAUDE_APP (set CLAUDE_APP if it lives elsewhere)"
  fi

  info "helper"
  helper="$(helper_path)"
  if [ -x "$helper" ]; then
    _doc_ok "cdt-helper at $helper"
  elif command -v swiftc >/dev/null 2>&1; then
    _doc_ok "cdt-helper not built yet; it is built on the first cdt add"
  else
    _doc_fail "cdt-helper missing and swiftc not found. Run: xcode-select --install"
  fi

  info "accounts"
  if [ -z "$(account_slugs)" ]; then
    info "  no accounts yet: run cdt add <account>"
  fi
  for s in $(account_slugs); do
    label="$(account_label "$s")"
    app="$(clone_path "$s")"
    info "  $label ($s)"
    if [ ! -d "$app" ]; then
      _doc_fail "app missing at $app. Run: cdt rebuild $label"
      continue
    fi
    if codesign --verify --strict "$app" >/dev/null 2>&1; then
      _doc_ok "signature verifies"
    else
      _doc_fail "signature does not verify. Run: cdt rebuild $label"
    fi
    id="$(codesign -dv "$app/Contents/MacOS/Claude" 2>&1 | sed -n 's/^Identifier=//p')"
    if [ "$id" = "$(account_bundle_id "$s")" ]; then
      _doc_ok "signing identifier matches bundle id $id"
    else
      _doc_fail "signing identifier '$id' differs from $(account_bundle_id "$s"); notifications will be rejected. Run: cdt rebuild $label"
    fi
    if clone_is_stale "$s"; then
      _doc_warn "$(stale_message "$s")"
    else
      _doc_ok "built from the installed Claude $(clone_version "$s")"
    fi
    case "$(update_block_state "$(account_data_dir "$s")")" in
      blocked) _doc_ok "self-update blocked (Claude's Block auto-updates setting)" ;;
      foreign) _doc_warn "self-update not blocked: $(update_block_root "$(account_data_dir "$s")") holds a configuration that is not cdt's and is left alone" ;;
      *) _doc_warn "self-update not blocked. Run: cdt rebuild $label" ;;
    esac
    if [ -x "$app/Contents/MacOS/cdt-helper" ]; then
      status="$("$app/Contents/MacOS/cdt-helper" --status 2>/dev/null)"
      case "$status" in
        authorized|provisional) _doc_ok "notifications: $status" ;;
        *) _doc_warn "notifications: ${status:-unknown}. Allow them in System Settings > Notifications, or run: \"$app/Contents/MacOS/cdt-helper\"" ;;
      esac
    else
      _doc_fail "helper missing inside the app. Run: cdt rebuild $label"
    fi
    pids="$(data_dir_pids "$(account_data_dir "$s")")"
    n=0; [ -n "$pids" ] && n="$(printf '%s\n' "$pids" | wc -l | tr -d ' ')"
    if [ "$n" -gt 1 ]; then
      _doc_fail "$n instances on one data dir (pids $(echo "$pids" | tr '\n' ' ')); quit all but one"
    elif [ "$n" = 1 ]; then
      _doc_ok "running (pid $pids)"
    else
      _doc_ok "not running"
    fi
    dir_is_empty "$(account_data_dir "$s")" && _doc_warn "data dir is empty: open it and sign in"
  done

  info "native multi-account"
  ma="$(multi_account_status)"
  case "$ma" in
    "") info "  unknown (no Claude process running)" ;;
    supported) _doc_warn "Claude Desktop reports multiAccount as supported; the built-in feature may make this tool unnecessary" ;;
    *) _doc_ok "Claude Desktop reports multiAccount as $ma" ;;
  esac

  return "$DOCTOR_FAILED"
}
