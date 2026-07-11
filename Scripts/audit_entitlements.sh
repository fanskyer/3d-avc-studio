#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/Build/3D AVC Studio.app}"
BLOCKERS=0
HELPER_ENTITLEMENTS=""

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

plist_true() {
  local file="$1"
  local key="$2"
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)" == "true" ]]
}

MAIN="$APP/Contents/MacOS/ThreeDAVCStudio"
MAIN_ENTITLEMENTS="$(mktemp)"
codesign -d --entitlements :- "$MAIN" >"$MAIN_ENTITLEMENTS" 2>/dev/null || true
trap 'rm -f "$MAIN_ENTITLEMENTS" "$HELPER_ENTITLEMENTS"' EXIT

echo "Entitlements audit: $APP"

if grep -q 'com.apple.security.app-sandbox\|com.apple.security.inherit' "$MAIN_ENTITLEMENTS"; then
  echo "- Blocker: open-source preview must not sandbox the main executable."
  BLOCKERS=$((BLOCKERS + 1))
else
  echo "- Main executable is unsandboxed so it can run a user-provided local decoder."
fi

while IFS= read -r -d '' exe; do
  [[ "$exe" == "$MAIN" ]] && continue
  rel="${exe#$APP/}"
  HELPER_ENTITLEMENTS="$(mktemp)"
  codesign -d --entitlements :- "$exe" >"$HELPER_ENTITLEMENTS" 2>/dev/null || true
  if grep -q 'com.apple.security.app-sandbox\|com.apple.security.inherit' "$HELPER_ENTITLEMENTS"; then
    echo "- Blocker: helper executable must not use sandbox inheritance: $rel"
    BLOCKERS=$((BLOCKERS + 1))
  else
    echo "- Helper executable is unsandboxed for the local decoder workflow: $rel"
  fi
  rm -f "$HELPER_ENTITLEMENTS"
done < <(find "$APP/Contents" -type f -perm -111 -print0)

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo
  echo "Entitlements audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo "Entitlements audit passed."
