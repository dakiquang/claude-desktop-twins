#!/bin/bash
# Regenerate the README terminal screenshots from real `cdt` runs.
#
# Runs cdt in a throwaway HOME against the test suite's stand-in Claude.app and fake
# helper, so no real account, LaunchServices entry or notification prompt is touched.
# Accounts are example.com only. The throwaway paths are shown as they would appear on
# a real Mac: the temp HOME as ~ and the stand-in app as /Applications/Claude.app.
#
# Needs Google Chrome (headless) for rendering. Usage: docs/screenshots/make-screenshots.sh
set -eu -o pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/docs/screenshots"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome not found at $CHROME (set CHROME=...)" >&2; exit 1; }

S="$(mktemp -d -t cdt-shots)"
BG=""
cleanup() { [ -z "$BG" ] || kill "$BG" 2>/dev/null || true; rm -rf "$S"; }
trap cleanup EXIT

"$REPO/test/make-fake-app.sh" "$S/fx" >/dev/null
export HOME="$S/home"
mkdir -p "$HOME"
cp -cR "$S/fx/FakeClaude.app" "$S/Claude.app"
export CLAUDE_APP="$S/Claude.app" CDT_LSREGISTER=true CDT_OPEN=true FAKE_HELPER_LOG="$S/helper.log"
DATA="$HOME/Library/Application Support/claude-desktop-twins"
mkdir -p "$DATA/bin"
cp "$S/fx/fake-helper" "$DATA/bin/cdt-helper"
cd "$HOME"

# Run a command as it would be typed, with its output, into a transcript.
run() { # transcript cmd args...
  local t="$1"; shift
  printf '$ cdt %s\n' "$*" >> "$t"
  "$REPO/bin/cdt" "$@" >> "$t" 2>&1 || true
}

# Render a transcript as a terminal window PNG.
render() { # transcript name title
  local t="$1" name="$2" title="$3" lines height cols width
  sed -i '' -e "s#$S/home#~#g; s#$S/Claude.app#/Applications/Claude.app#g" "$t"
  lines="$(wc -l < "$t" | tr -d ' ')"
  cols="$(awk '{ if (length > m) m = length } END { print m }' "$t")"
  height=$((lines * 21 + 74))
  width=$((cols * 82 / 10 + 80))
  [ "$width" -ge 720 ] || width=720
  {
    cat <<'HTML'
<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#e9e9ee;padding:16px;font:13.5px/21px "SF Mono",Menlo,monospace}
.w{background:#1e1f24;border-radius:10px;box-shadow:0 6px 18px rgba(0,0,0,.25);overflow:hidden}
.b{height:30px;background:#2c2d33;display:flex;align-items:center;padding:0 12px;gap:8px;color:#9a9ba3;font:12px -apple-system,sans-serif}
.d{width:12px;height:12px;border-radius:50%}.t{flex:1;text-align:center;margin-right:52px}
pre{margin:0;padding:12px 16px;color:#d8d9de;white-space:pre}
.p{color:#8fb3ff}.ok{color:#7ee0a1}.wn{color:#f3c969}.dim{color:#8b8c94}
</style><div class="w"><div class="b"><span class="d" style="background:#ff5f57"></span>
<span class="d" style="background:#febc2e"></span><span class="d" style="background:#28c840"></span>
HTML
    printf '<span class="t">%s</span></div><pre>' "$title"
    sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' \
        -e 's#^\(\$ .*\)$#<span class="p">\1</span>#' \
        -e 's#^\(  *\)ok  #\1<span class="ok">ok</span>  #' \
        -e 's#^\(  *\)warn#\1<span class="wn">warn</span>#' \
        -e 's#^warning:#<span class="wn">warning:</span>#' "$t"
    printf '</pre></div>\n'
  } > "$S/$name.html"
  # A private profile keeps headless Chrome away from a Chrome the user has open; its
  # exit status is unreliable, so the written file is what counts.
  rm -f "$OUT/$name.png"
  "$CHROME" --headless=new --user-data-dir="$S/chrome" --no-first-run --disable-gpu \
    --hide-scrollbars --force-device-scale-factor=2 --window-size="$width","$height" \
    --screenshot="$OUT/$name.png" "file://$S/$name.html" >/dev/null 2>&1 || true
  [ -s "$OUT/$name.png" ] || { echo "failed to render $name.png" >&2; exit 1; }
  echo "wrote docs/screenshots/$name.png"
}

T="$S/add.txt"; run "$T" add work@example.com; run "$T" add personal@example.com
render "$T" add "cdt add"

# Start the work account (the stand-in app just sleeps) so list and doctor show it running.
FAKE_CLAUDE_SLEEP=120 "$HOME/Applications/Claude Desktop Twins/work@example.com.app/Contents/MacOS/launcher" >/dev/null 2>&1 &
BG=$!
sleep 0.5

T="$S/list.txt"; run "$T" list
render "$T" list "cdt list"
T="$S/doctor.txt"; run "$T" doctor
render "$T" doctor "cdt doctor"

F="$REPO/test/fixtures/sessions"
mkdir -p "$HOME/Library/Application Support/Claude" "$HOME/.claude/projects"
cp -R "$F/account-a/claude-code-sessions" "$HOME/Library/Application Support/Claude/"
cp -R "$F/account-b/claude-code-sessions" "$DATA/profiles/workexamplecom/"
cp -R "$F/transcripts/"* "$HOME/.claude/projects/"
T="$S/sessions.txt"
run "$T" sessions list default
render "$T" sessions "cdt sessions"
