#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="3D AVC Studio"
APP="$ROOT/Build/$APP_NAME.app"
RELEASE_DIR="$ROOT/Release"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --sign" >&2
        exit 2
      fi
      CODE_SIGN_IDENTITY="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" "$ROOT/Scripts/build_app.sh" >/dev/null
"$ROOT/Scripts/audit_dependencies.sh" "$APP" "$ROOT/Build/open_source_dependency_audit.txt" >/dev/null
"$ROOT/Scripts/audit_architecture.sh" "$APP" >/dev/null
"$ROOT/Scripts/audit_entitlements.sh" "$APP" >/dev/null
"$ROOT/Scripts/audit_versions.sh" "$APP" >/dev/null

if find "$APP/Contents" \( -name 'ldecod' -o -name 'decoder.cfg' -o -name 'ffmpeg' -o -name 'ffprobe' \) -print -quit | grep -q .; then
  echo "Open-source preview app must not bundle research decoder artifacts." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CHANNEL="open-source-preview"
ARTIFACT_BASENAME="3D-AVC-Studio-${VERSION}-${BUILD}-${CHANNEL}-${STAMP}"
ZIP="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
MANIFEST="$RELEASE_DIR/$ARTIFACT_BASENAME.manifest.txt"
DEPENDENCY_REPORT="$RELEASE_DIR/$ARTIFACT_BASENAME.dependencies.txt"

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP" "$MANIFEST" "$DEPENDENCY_REPORT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cp "$ROOT/Build/open_source_dependency_audit.txt" "$DEPENDENCY_REPORT"

ZIP_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
DEPENDENCY_SHA256="$(shasum -a 256 "$DEPENDENCY_REPORT" | awk '{print $1}')"
APP_SIZE="$(du -sh "$APP" | awk '{print $1}')"
ZIP_SIZE="$(du -sh "$ZIP" | awk '{print $1}')"
GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
CAPABILITIES="$(tr '\n' ' ' < "$APP/Contents/Resources/Engine/capabilities.json")"
SIGNING_SUMMARY="$(codesign -dv "$APP" 2>&1 | tr '\n' ';' | sed 's/;$//')"
HAS_BUNDLED_DECODER="false"
if [[ -x "$APP/Contents/Resources/Engine/mvcdecoder" ]]; then
  HAS_BUNDLED_DECODER="true"
fi

cat > "$MANIFEST" <<TXT
product=$APP_NAME
bundle_id=$BUNDLE_ID
version=$VERSION
build=$BUILD
channel=$CHANNEL
created_utc=$STAMP
git_commit=$GIT_COMMIT
requested_signing_identity=$CODE_SIGN_IDENTITY
signing_summary=$SIGNING_SUMMARY
app_path=$APP
artifact=$ZIP
dependency_report=$DEPENDENCY_REPORT
app_size=$APP_SIZE
artifact_size=$ZIP_SIZE
artifact_sha256=$ZIP_SHA256
dependency_report_sha256=$DEPENDENCY_SHA256
bundled_decoder=$HAS_BUNDLED_DECODER
commercial_app_store_release=false
capabilities=$CAPABILITIES
TXT

echo "Packaged open-source preview: $ZIP"
echo "Manifest: $MANIFEST"
echo "Dependency report: $DEPENDENCY_REPORT"
