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

if plist_true "$MAIN_ENTITLEMENTS" 'com.apple.security.app-sandbox'; then
  echo "- Main executable has app sandbox entitlement."
else
  echo "- Blocker: main executable is missing app sandbox entitlement."
  BLOCKERS=$((BLOCKERS + 1))
fi

if plist_true "$MAIN_ENTITLEMENTS" 'com.apple.security.files.user-selected.read-write'; then
  echo "- Main executable has user-selected read/write entitlement."
else
  echo "- Blocker: main executable is missing user-selected read/write entitlement."
  BLOCKERS=$((BLOCKERS + 1))
fi

if grep -q 'com.apple.security.inherit' "$MAIN_ENTITLEMENTS"; then
  echo "- Blocker: main executable should not use sandbox inheritance."
  BLOCKERS=$((BLOCKERS + 1))
else
  echo "- Main executable does not use sandbox inheritance."
fi

while IFS= read -r -d '' exe; do
  [[ "$exe" == "$MAIN" ]] && continue
  rel="${exe#$APP/}"
  HELPER_ENTITLEMENTS="$(mktemp)"
  codesign -d --entitlements :- "$exe" >"$HELPER_ENTITLEMENTS" 2>/dev/null || true
  if plist_true "$HELPER_ENTITLEMENTS" 'com.apple.security.app-sandbox' &&
     plist_true "$HELPER_ENTITLEMENTS" 'com.apple.security.inherit'; then
    echo "- Helper executable inherits sandbox: $rel"
  else
    echo "- Blocker: helper executable must have app-sandbox and inherit entitlements: $rel"
    BLOCKERS=$((BLOCKERS + 1))
  fi
  rm -f "$HELPER_ENTITLEMENTS"
done < <(find "$APP/Contents" -type f -perm -111 -print0)

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo
  echo "Entitlements audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo "Entitlements audit passed."
