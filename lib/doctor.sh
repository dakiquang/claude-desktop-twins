# shellcheck shell=bash
# `cdt doctor [--json]`: explain anything that is off. Exits 1 when a check fails;
# warnings (stale clone, permission not granted) keep exit 0.
#
# Every check has a stable id. Text mode prints "ok/warn/FAIL message"; JSON mode
# collects {account, id, level, message, fix}, where fix is the command after "Run:".

_DOC_JSON=0
_DOC_ACCOUNT=""
_DOC_ITEMS=""

_doc() { # level id message
  local level="$1" id="$2" msg="$3" fix=""
  [ "$level" = fail ] && DOCTOR_FAILED=1
  if [ "$_DOC_JSON" = 1 ]; then
    case "$msg" in
      *"Run: "*) fix="${msg##*Run: }" ;;
      *"run: "*) fix="${msg##*run: }" ;;
    esac
    _DOC_ITEMS="${_DOC_ITEMS:+$_DOC_ITEMS,}{$(json_join \
      "\"account\":$(json_str_or_null "$_DOC_ACCOUNT")" \
      "\"id\":$(json_str "$id")" \
      "\"level\":$(json_str "$level")" \
      "\"message\":$(json_str "$msg")" \
      "\"fix\":$(json_str_or_null "$fix")")}"
    return 0
  fi
  case "$level" in
    ok) printf '  ok    %s\n' "$msg" ;;
    warn) printf '  warn  %s\n' "$msg" ;;
    fail) printf '  FAIL  %s\n' "$msg" ;;
  esac
}
_doc_ok() { _doc ok "$1" "$2"; }
_doc_warn() { _doc warn "$1" "$2"; }
_doc_fail() { _doc fail "$1" "$2"; }
_doc_section() { [ "$_DOC_JSON" = 1 ] || info "$*"; }

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
  case "${1:-}" in
    --json) _DOC_JSON=1 ;;
    "") _DOC_JSON=0 ;;
    *) die "usage: cdt doctor [--json]" ;;
  esac
  DOCTOR_FAILED=0
  _DOC_ACCOUNT=""
  _DOC_ITEMS=""

  _doc_section "Claude.app"
  if claude_app_ok; then
    _doc_ok claude_app "found at $CLAUDE_APP, version $(claude_version)"
  else
    _doc_fail claude_app "not found at $CLAUDE_APP (set CLAUDE_APP if it lives elsewhere)"
  fi

  _doc_section "helper"
  helper="$(helper_path)"
  if [ -x "$helper" ]; then
    _doc_ok helper "cdt-helper at $helper"
  elif command -v swiftc >/dev/null 2>&1; then
    _doc_ok helper "cdt-helper not built yet; it is built on the first cdt add"
  else
    _doc_fail helper "cdt-helper missing and swiftc not found. Run: xcode-select --install"
  fi

  _doc_section "accounts"
  if [ -z "$(account_slugs)" ]; then
    _doc_section "  no accounts yet: run cdt add <account>"
  fi
  for s in $(account_slugs); do
    label="$(account_label "$s")"
    app="$(clone_path "$s")"
    _DOC_ACCOUNT="$s"
    _doc_section "  $label ($s)"
    if [ ! -d "$app" ]; then
      _doc_fail app "app missing at $app. Run: cdt rebuild $label"
      continue
    fi
    if codesign --verify --strict "$app" >/dev/null 2>&1; then
      _doc_ok signature "signature verifies"
    else
      _doc_fail signature "signature does not verify. Run: cdt rebuild $label"
    fi
    id="$(codesign -dv "$app/Contents/MacOS/Claude" 2>&1 | sed -n 's/^Identifier=//p')"
    if [ "$id" = "$(account_bundle_id "$s")" ]; then
      _doc_ok identifier "signing identifier matches bundle id $id"
    else
      _doc_fail identifier "signing identifier '$id' differs from $(account_bundle_id "$s"); notifications will be rejected. Run: cdt rebuild $label"
    fi
    if clone_is_stale "$s"; then
      _doc_warn version "$(stale_message "$s")"
    else
      _doc_ok version "built from the installed Claude $(clone_version "$s")"
    fi
    case "$(update_block_state "$(account_data_dir "$s")")" in
      blocked) _doc_ok update_block "self-update blocked (Claude's Block auto-updates setting)" ;;
      foreign) _doc_warn update_block "self-update not blocked: $(update_block_root "$(account_data_dir "$s")") holds a configuration that is not cdt's and is left alone" ;;
      *) _doc_warn update_block "self-update not blocked. Run: cdt rebuild $label" ;;
    esac
    if [ -x "$app/Contents/MacOS/cdt-helper" ]; then
      status="$("$app/Contents/MacOS/cdt-helper" --status 2>/dev/null)"
      case "$status" in
        authorized|provisional) _doc_ok notifications "notifications: $status" ;;
        *) _doc_warn notifications "notifications: ${status:-unknown}. Allow them in System Settings > Notifications, or run: \"$app/Contents/MacOS/cdt-helper\"" ;;
      esac
    else
      _doc_fail notifications "helper missing inside the app. Run: cdt rebuild $label"
    fi
    pids="$(data_dir_pids "$(account_data_dir "$s")")"
    n=0; [ -n "$pids" ] && n="$(printf '%s\n' "$pids" | wc -l | tr -d ' ')"
    if [ "$n" -gt 1 ]; then
      _doc_fail instances "$n instances on one data dir (pids $(echo "$pids" | tr '\n' ' ')); quit all but one"
    elif [ "$n" = 1 ]; then
      _doc_ok instances "running (pid $pids)"
    else
      _doc_ok instances "not running"
    fi
    if dir_is_empty "$(account_data_dir "$s")"; then
      _doc_warn empty_data_dir "data dir is empty: open it and sign in"
    fi
  done
  _DOC_ACCOUNT=""

  _doc_section "native multi-account"
  ma="$(multi_account_status)"
  case "$ma" in
    "") _doc_section "  unknown (no Claude process running)" ;;
    supported) _doc_warn multi_account "Claude Desktop reports multiAccount as supported; the built-in feature may make this tool unnecessary" ;;
    *) _doc_ok multi_account "Claude Desktop reports multiAccount as $ma" ;;
  esac

  if [ "$_DOC_JSON" = 1 ]; then
    printf '{"schema":%s,"ok":%s,"checks":[%s]}\n' "$CDT_JSON_SCHEMA" \
      "$(json_bool "$DOCTOR_FAILED")" "$_DOC_ITEMS"
  fi
  return "$DOCTOR_FAILED"
}
