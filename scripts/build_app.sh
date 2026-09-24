#!/bin/bash
#
# Builds MenuBarCalendar.app.
#
# There is no Xcode project: SwiftPM produces the binary and this script
# assembles the bundle around it. Output: dist/MenuBarCalendar.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MenuBarCalendar"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

UNIVERSAL=1
for arg in "$@"; do
  case "$arg" in
    --native) UNIVERSAL=0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

cd "$ROOT"

# ---------------------------------------------------------------- build
DEPLOYMENT_TARGET="14.0"

if [[ $UNIVERSAL -eq 1 ]]; then
  # `swift build --arch arm64 --arch x86_64` would be the direct route, but it
  # dispatches to xcbuild, which only ships with full Xcode. Building each
  # slice separately and merging with lipo works on the Command Line Tools.
  echo "Building universal binary (arm64 + x86_64)…"
  ARM_PATH="$ROOT/.build/arm"
  X86_PATH="$ROOT/.build/x86"

  swift build -c release --triple "arm64-apple-macosx$DEPLOYMENT_TARGET" --scratch-path "$ARM_PATH"
  swift build -c release --triple "x86_64-apple-macosx$DEPLOYMENT_TARGET" --scratch-path "$X86_PATH"

  ARM_BIN="$(swift build -c release --triple "arm64-apple-macosx$DEPLOYMENT_TARGET" --scratch-path "$ARM_PATH" --show-bin-path)"
  X86_BIN="$(swift build -c release --triple "x86_64-apple-macosx$DEPLOYMENT_TARGET" --scratch-path "$X86_PATH" --show-bin-path)"

  mkdir -p "$ROOT/.build/universal"
  BINARY="$ROOT/.build/universal/$APP_NAME"
  lipo -create -output "$BINARY" "$ARM_BIN/$APP_NAME" "$X86_BIN/$APP_NAME"
  # The resource bundle is architecture independent; take either slice's copy.
  BUNDLE_SEARCH_DIR="$ARM_BIN"
else
  echo "Building for the host architecture only…"
  swift build -c release
  BUNDLE_SEARCH_DIR="$(swift build -c release --show-bin-path)"
  BINARY="$BUNDLE_SEARCH_DIR/$APP_NAME"
fi

[[ -f "$BINARY" ]] || { echo "binary not found: $BINARY" >&2; exit 1; }

# ---------------------------------------------------------------- assemble
echo "Assembling bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# SwiftPM puts declared resources in their own bundle; it has to travel with
# the executable for Bundle.module to resolve.
find "$BUNDLE_SEARCH_DIR" -maxdepth 1 -name "${APP_NAME}_*.bundle" -exec \
  cp -R {} "$CONTENTS/Resources/" \;

# A plain copy as well, so the app still finds the data via Bundle.main if the
# resource bundle is ever stripped.
cp "$ROOT/Sources/CalendarCore/Resources/holidays.json" "$CONTENTS/Resources/"

# ---------------------------------------------------------------- icon
ICON_SRC="$ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  echo "Generating icon…"
  WORK="$(mktemp -d)"
  swift "$ROOT/scripts/make_icon.swift" "$WORK/icon.png" >/dev/null
  ICONSET="$WORK/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
              "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$WORK/icon.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$ICON_SRC"
  rm -rf "$WORK"
fi
cp "$ICON_SRC" "$CONTENTS/Resources/AppIcon.icns"

# ---------------------------------------------------------------- sign
# Ad-hoc signature. Enough for the app to run locally and for SMAppService to
# have a stable identity; it is not notarized, so first launch needs the
# right-click > Open path described in the README.
echo "Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo
echo "Built: $APP"
if [[ $UNIVERSAL -eq 1 ]]; then
  lipo -info "$CONTENTS/MacOS/$APP_NAME"
fi
du -sh "$APP" | awk '{print "Size:  " $1}'
