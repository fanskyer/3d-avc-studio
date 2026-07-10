#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:-}"
BLOCKERS=0

if [[ -z "$ZIP" ]]; then
  ZIP="$(find "$ROOT/Release" -name '*-open-source-preview-*.zip' -type f -print 2>/dev/null | sort | tail -1)"
fi

blocker() {
  echo "- Blocker: $1"
  BLOCKERS=$((BLOCKERS + 1))
}

ok() {
  echo "- OK: $1"
}

manifest_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2)}' "$file"
}

echo "Open-source release audit:"

if [[ -n "$ZIP" && -f "$ZIP" ]]; then
  ok "Found release zip: ${ZIP#$ROOT/}"
else
  blocker "Open-source preview zip not found. Run Scripts/package_open_source_release.sh."
fi

if [[ "$BLOCKERS" == "0" ]]; then
  MANIFEST="${ZIP%.zip}.manifest.txt"
  if [[ -s "$MANIFEST" ]]; then
    ok "Found manifest."
    channel="$(manifest_value channel "$MANIFEST")"
    commercial="$(manifest_value commercial_app_store_release "$MANIFEST")"
    if [[ "$channel" == "open-source-preview" ]]; then
      ok "Manifest channel is open-source-preview."
    else
      blocker "Manifest channel must be open-source-preview; got ${channel:-missing}."
    fi
    if [[ "$commercial" == "false" ]]; then
      ok "Manifest marks commercial_app_store_release=false."
    else
      blocker "Manifest must mark commercial_app_store_release=false."
    fi
  else
    blocker "Missing manifest next to zip."
  fi
fi

if [[ "$BLOCKERS" == "0" ]]; then
  "$ROOT/Scripts/audit_release_artifact.sh" "$ZIP" >/dev/null || blocker "Release artifact audit failed."
fi

if [[ "$BLOCKERS" == "0" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  ditto -x -k "$ZIP" "$WORK"
  APP="$WORK/3D AVC Studio.app"
  if [[ -x "$APP/Contents/Resources/Engine/mvcdecoder" ]]; then
    blocker "Open-source preview must not bundle mvcdecoder by default."
  else
    ok "No bundled mvcdecoder in open-source preview."
  fi
  if find "$APP/Contents" \( -name 'ldecod' -o -name 'decoder.cfg' -o -name 'ffmpeg' -o -name 'ffprobe' \) -print -quit | grep -q .; then
    blocker "Open-source preview contains development decoder artifacts."
  else
    ok "No legacy/reference decoder artifacts found."
  fi
  if grep -q '"conversionComplete": false' "$APP/Contents/Resources/Engine/capabilities.json"; then
    ok "Capabilities honestly report conversionComplete=false."
  else
    blocker "Open-source preview without decoder should report conversionComplete=false."
  fi
fi

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo
  echo "Open-source release audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo "Open-source release audit passed."
