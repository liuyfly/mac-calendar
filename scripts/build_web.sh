#!/bin/bash
#
# Assembles the web app into dist/web, ready to be served as static files.
#
#   ./scripts/build_web.sh                # version from git, e.g. 1a2b3c4
#   ./scripts/build_web.sh --serve        # then serve it on http://localhost:8080
#
# The holiday table is shared with the native apps and copied in from
# Sources/CalendarCore/Resources. The version is stamped into version.js and
# sw.js; a new version is what makes installed copies pick up the update.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist/web"

VERSION="${WEB_VERSION:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)}"
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  VERSION="$VERSION-$(date +%Y%m%d%H%M%S)"
fi

# --delete, so a file removed from web/ does not linger in the build.
mkdir -p "$OUT"
rsync -a --delete --delete-excluded \
  --exclude tests --exclude package.json --exclude '.*' "$ROOT/web/" "$OUT/"
cp "$ROOT/Sources/CalendarCore/Resources/holidays.json" "$OUT/holidays.json"

# Not `sed -i`, whose syntax differs between macOS and Linux.
sed "s/__VERSION__/$VERSION/" "$ROOT/web/sw.js" > "$OUT/sw.js"
printf "export const VERSION = '%s';\n" "$VERSION" > "$OUT/version.js"

# Every file must be in the service worker's list, or it is missing offline.
missing=0
while IFS= read -r file; do
  rel="${file#"$OUT"/}"
  [ "$rel" = "sw.js" ] && continue
  if ! grep -q "'$rel'" "$OUT/sw.js"; then
    echo "error: $rel is not listed in web/sw.js FILES" >&2
    missing=1
  fi
done < <(find "$OUT" -type f)
[ "$missing" = 0 ] || exit 1

echo "Built $OUT (version $VERSION)"

if [ "${1:-}" = "--serve" ]; then
  echo "Serving on http://localhost:8080 — Ctrl-C to stop"
  exec python3 -m http.server 8080 --directory "$OUT"
fi
