#!/usr/bin/env bash
# Tests for tool/build_release.sh: a release build must be refused (before flutter is ever invoked)
# when CONVEX_URL is missing or malformed. Uses a fake `flutter` so nothing is built.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/flutter" <<'FAKE'
#!/usr/bin/env bash
echo "FLUTTER_CALLED $*" >> "$FAKE_FLUTTER_LOG"
FAKE
chmod +x "$tmp/flutter"
export FAKE_FLUTTER_LOG="$tmp/log"
export PATH="$tmp:$PATH"
fail=0

expect_refused() { # name, env-assignment (may be empty), target
  : > "$FAKE_FLUTTER_LOG"
  if env -u CONVEX_URL $2 "$here/build_release.sh" "$3" >/dev/null 2>&1; then
    echo "FAIL: $1 was accepted"; fail=1
  elif [ -s "$FAKE_FLUTTER_LOG" ]; then
    echo "FAIL: $1 reached flutter"; fail=1
  else
    echo "ok: $1 refused"
  fi
}

expect_refused "missing URL"                 ""                                              appbundle
expect_refused "empty URL"                   "CONVEX_URL="                                   apk
expect_refused "http scheme"                 "CONVEX_URL=http://x.convex.cloud"              apk
expect_refused "non-convex host"             "CONVEX_URL=https://example.com"                apk
expect_refused "lookalike host"              "CONVEX_URL=https://x.convex.cloud.evil.com"    apk
expect_refused "path component"              "CONVEX_URL=https://x.convex.cloud/api"         apk
expect_refused "unknown target"              "CONVEX_URL=https://x.convex.cloud"             banana

: > "$FAKE_FLUTTER_LOG"
if CONVEX_URL="https://a-b-1.convex.cloud/" "$here/build_release.sh" appbundle >/dev/null 2>&1 \
   && grep -q -- "--dart-define=CONVEX_URL=https://a-b-1.convex.cloud" "$FAKE_FLUTTER_LOG" \
   && grep -q -- "build appbundle --release" "$FAKE_FLUTTER_LOG"; then
  echo "ok: valid URL builds with the define (trailing slash stripped)"
else
  echo "FAIL: valid URL was not passed through"; fail=1
fi
exit $fail
