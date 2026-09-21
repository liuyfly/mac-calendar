#!/bin/bash
#
# Runs the unit tests.
#
# `swift test` needs XCTest, which ships with full Xcode but not with the
# Command Line Tools, so the tests are compiled directly against the sources
# instead. Everything under Sources/MenuBarCalendar that does not depend on
# AppKit is included; the views and the status item controller are UI code and
# are covered by running the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/tests"
mkdir -p "$BUILD_DIR"

# Globbed rather than listed file by file, so a new model or lunar source is
# picked up without editing this script.
SOURCES=(
  "$ROOT/Sources/MenuBarCalendar/Lunar/"*.swift
  "$ROOT/Sources/MenuBarCalendar/Holidays/"*.swift
  "$ROOT/Sources/MenuBarCalendar/Models/"*.swift
)

TESTS=(
  "$ROOT/Tests/MenuBarCalendarTests/TestSupport.swift"
  "$ROOT/Tests/MenuBarCalendarTests/RoughSolarTerms.swift"
  "$ROOT/Tests/MenuBarCalendarTests/LunarTests.swift"
  "$ROOT/Tests/MenuBarCalendarTests/main.swift"
)

echo "Compiling tests…"
swiftc -O -o "$BUILD_DIR/run-tests" "${SOURCES[@]}" "${TESTS[@]}"

# Preferences are read during the tests; keep them out of the real domain.
DEFAULTS_DOMAIN="com.menubarcalendar.tests"

MENUBAR_CALENDAR_HOLIDAYS="$ROOT/Sources/MenuBarCalendar/Resources/holidays.json" \
  "$BUILD_DIR/run-tests" -NSArgumentDomain "$DEFAULTS_DOMAIN"
