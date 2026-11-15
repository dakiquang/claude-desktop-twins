#!/bin/bash
# Build test doubles so tests never need the real Claude.app:
#   <out>/FakeClaude.app   minimal app bundle shaped like Claude.app
#   <out>/fake-helper      stands in for cdt-helper
# Usage: test/make-fake-app.sh <out dir> [version]
set -euo pipefail

out="${1:?usage: make-fake-app.sh <out dir> [version]}"
version="${2:-5.11492.5}"
app="$out/FakeClaude.app"
c="$app/Contents"
rm -rf "$app"
mkdir -p "$c/MacOS" "$c/Resources"

# Main binary: exits at once, or stays up for FAKE_CLAUDE_SLEEP seconds so tests can
# see it as a running account.
cat > "$out/fake-claude.c" <<'C'
#include <stdlib.h>
#include <unistd.h>
int main(void) {
  const char *s = getenv("FAKE_CLAUDE_SLEEP");
  if (s) sleep((unsigned) atoi(s));
  return 0;
}
C
clang -O0 -o "$c/MacOS/Claude" "$out/fake-claude.c"

cat > "$c/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.fake</string>
  <key>CFBundleName</key><string>FakeClaude</string>
  <key>CFBundleDisplayName</key><string>FakeClaude</string>
  <key>CFBundleExecutable</key><string>Claude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>fake</string>
    <key>CFBundleURLSchemes</key><array><string>fakeclaude</string></array>
  </dict></array>
</dict></plist>
PLIST
printf 'placeholder\n' > "$c/embedded.provisionprofile"
printf 'dummy asar\n' > "$c/Resources/app.asar"
codesign --force --sign - "$app" 2>/dev/null

# Helper double: logs its arguments to FAKE_HELPER_LOG; --status prints "authorized".
cat > "$out/fake-helper.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  const char *log = getenv("FAKE_HELPER_LOG");
  if (log) {
    FILE *f = fopen(log, "a");
    if (f) {
      for (int i = 1; i < argc; i++) fprintf(f, "%s%s", i > 1 ? " " : "", argv[i]);
      fprintf(f, "\n");
      fclose(f);
    }
  }
  if (argc > 1 && strcmp(argv[1], "--status") == 0) puts("authorized");
  return 0;
}
C
clang -O0 -o "$out/fake-helper" "$out/fake-helper.c"
rm -f "$out/fake-claude.c" "$out/fake-helper.c"
