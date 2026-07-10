#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:-}"

if [[ -z "$ZIP" ]]; then
  ZIP="$(find "$ROOT/Release" -name '*.zip' -type f -print 2>/dev/null | sort | tail -1)"
fi

if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Release zip not found. Run ./Scripts/package_release.sh first." >&2
  exit 1
fi

MANIFEST="${ZIP%.zip}.manifest.txt"
if [[ ! -s "$MANIFEST" ]]; then
  echo "Missing manifest next to artifact: $MANIFEST" >&2
  exit 1
fi

DEPENDENCY_REPORT="${ZIP%.zip}.dependencies.txt"
if [[ ! -s "$DEPENDENCY_REPORT" ]]; then
  echo "Missing dependency report next to artifact: $DEPENDENCY_REPORT" >&2
  exit 1
fi

EXPECTED_SHA="$(awk -F= '/^artifact_sha256=/{print $2}' "$MANIFEST")"
ACTUAL_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  echo "SHA-256 mismatch for $ZIP" >&2
  echo "expected: $EXPECTED_SHA" >&2
  echo "actual:   $ACTUAL_SHA" >&2
  exit 1
fi

EXPECTED_DEPENDENCY_SHA="$(awk -F= '/^dependency_report_sha256=/{print $2}' "$MANIFEST")"
ACTUAL_DEPENDENCY_SHA="$(shasum -a 256 "$DEPENDENCY_REPORT" | awk '{print $1}')"
if [[ "$EXPECTED_DEPENDENCY_SHA" != "$ACTUAL_DEPENDENCY_SHA" ]]; then
  echo "Dependency report SHA-256 mismatch for $DEPENDENCY_REPORT" >&2
  echo "expected: $EXPECTED_DEPENDENCY_SHA" >&2
  echo "actual:   $ACTUAL_DEPENDENCY_SHA" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$ZIP" "$WORK"
APP="$WORK/3D AVC Studio.app"

if [[ ! -d "$APP" ]]; then
  echo "Artifact does not contain 3D AVC Studio.app at the zip root." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
"$ROOT/Scripts/audit_dependencies.sh" "$APP" >/dev/null
"$ROOT/Scripts/audit_architecture.sh" "$APP" >/dev/null
"$ROOT/Scripts/audit_entitlements.sh" "$APP" >/dev/null
"$ROOT/Scripts/audit_versions.sh" "$APP" >/dev/null

if [[ ! -x "$APP/Contents/Resources/Engine/sony3dengine" ]]; then
  echo "Artifact is missing bundled native engine." >&2
  exit 1
fi

if [[ ! -s "$APP/Contents/Resources/Engine/capabilities.json" ]]; then
  echo "Artifact is missing bundled native engine capabilities.json." >&2
  exit 1
fi

if find "$APP/Contents" \( -name 'ffmpeg' -o -name 'ffprobe' -o -name 'ldecod' -o -name 'decoder.cfg' \) -print -quit | grep -q .; then
  echo "Artifact contains forbidden development dependency." >&2
  exit 1
fi

if [[ ! -s "$APP/Contents/Resources/ThirdPartyNotices.md" ]]; then
  echo "Artifact is missing ThirdPartyNotices.md." >&2
  exit 1
fi

if [[ ! -s "$APP/Contents/Resources/Compliance/decoder_policy.json" ]]; then
  echo "Artifact is missing bundled decoder policy." >&2
  exit 1
fi

PRIVACY_MANIFEST="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ ! -s "$PRIVACY_MANIFEST" ]] || ! plutil -lint "$PRIVACY_MANIFEST" >/dev/null; then
  echo "Artifact is missing a valid PrivacyInfo.xcprivacy." >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$PRIVACY_MANIFEST" 2>/dev/null || true)" != "false" ]]; then
  echo "Artifact privacy manifest must set NSPrivacyTracking=false." >&2
  exit 1
fi

ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$ICON_FILE" || ! -s "$APP/Contents/Resources/${ICON_FILE%.icns}.icns" ]]; then
  echo "Artifact is missing bundled app icon." >&2
  exit 1
fi

echo "Release artifact audit passed: $ZIP"
