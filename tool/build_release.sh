#!/usr/bin/env bash
# Release build wrapper: refuses to build unless CONVEX_URL is an explicit, well-formed deployment URL.
# It never supplies a URL itself. Usage:
#   CONVEX_URL=https://<deployment>.convex.cloud tool/build_release.sh appbundle|ipa|apk [extra flutter args]
set -euo pipefail

target="${1:-}"
case "$target" in
  appbundle|ipa|apk|ios) shift ;;
  *) echo "usage: CONVEX_URL=https://<deployment>.convex.cloud $0 appbundle|ipa|apk|ios [flutter args]" >&2; exit 64 ;;
esac

url="${CONVEX_URL:-}"
if [[ -z "$url" ]]; then
  echo "error: CONVEX_URL is not set. Release builds must name their backend explicitly." >&2
  exit 1
fi
# Bare https origin of a *.convex.cloud deployment: no path, query or fragment.
if [[ ! "$url" =~ ^https://[a-z0-9][a-z0-9-]*\.convex\.cloud/?$ ]]; then
  echo "error: CONVEX_URL must look like https://<deployment>.convex.cloud (got: $url)" >&2
  exit 1
fi

exec flutter build "$target" --release --dart-define="CONVEX_URL=${url%/}" "$@"
