#!/bin/bash
#
# Runs the unit tests.
#
# `swift test` needs XCTest, which ships with full Xcode but not with the
# Command Line Tools, so the tests are compiled directly against the sources
# instead. That is CalendarCore minus its SwiftUI views, compiled into the
# test binary as one module so internals stay reachable. The views and the
# macOS app are UI code and are covered by running the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/tests"
mkdir -p "$BUILD_DIR"

# Globbed rather than listed file by file, so a new model or lunar source is
# picked up without editing this script. Views/ is left out: it needs SwiftUI
# and has nothing to assert on.
SOURCES=(
  "$ROOT/Sources/CalendarCore/Lunar/"*.swift
  "$ROOT/Sources/CalendarCore/Holidays/"*.swift
  "$ROOT/Sources/CalendarCore/Models/"*.swift
)

TESTS=(
  "$ROOT/Tests/CalendarCoreTests/TestSupport.swift"
  "$ROOT/Tests/CalendarCoreTests/RoughSolarTerms.swift"
  "$ROOT/Tests/CalendarCoreTests/LunarTests.swift"
  "$ROOT/Tests/CalendarCoreTests/main.swift"
)

echo "Compiling tests…"
swiftc -O -o "$BUILD_DIR/run-tests" "${SOURCES[@]}" "${TESTS[@]}"

# Preferences are read during the tests; keep them out of the real domain.
DEFAULTS_DOMAIN="com.menubarcalendar.tests"

MENUBAR_CALENDAR_HOLIDAYS="$ROOT/Sources/CalendarCore/Resources/holidays.json" \
  "$BUILD_DIR/run-tests" -NSArgumentDomain "$DEFAULTS_DOMAIN"
