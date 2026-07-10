#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/Build/3D AVC Studio.app}"
INFO="$APP/Contents/Info.plist"
CAPABILITIES="$APP/Contents/Resources/Engine/capabilities.json"
BLOCKERS=0

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

if [[ ! -s "$INFO" || ! -s "$CAPABILITIES" ]]; then
  echo "Missing Info.plist or capabilities.json." >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
ENGINE_VERSION="$(python3 - "$CAPABILITIES" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("version", ""))
PY
)"

echo "Version audit: $APP"
echo "- App version: $APP_VERSION"
echo "- App build: $APP_BUILD"
echo "- Engine version: $ENGINE_VERSION"

if [[ ! "$APP_VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  echo "- Blocker: CFBundleShortVersionString must be semantic version X.Y.Z."
  BLOCKERS=$((BLOCKERS + 1))
fi

if [[ ! "$APP_BUILD" =~ ^[0-9]+$ ]]; then
  echo "- Blocker: CFBundleVersion must be a positive integer build number."
  BLOCKERS=$((BLOCKERS + 1))
elif [[ "$APP_BUILD" -le 0 ]]; then
  echo "- Blocker: CFBundleVersion must be greater than zero."
  BLOCKERS=$((BLOCKERS + 1))
fi

if [[ "$ENGINE_VERSION" == "$APP_VERSION" ]]; then
  echo "- Engine version matches app version."
else
  echo "- Blocker: engine version does not match app version."
  BLOCKERS=$((BLOCKERS + 1))
fi

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo
  echo "Version audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo "Version audit passed."
