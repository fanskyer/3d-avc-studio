#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/Build/3D AVC Studio.app}"
REQUIRED_ARCHS="${REQUIRED_ARCHS:-arm64 x86_64}"
BLOCKERS=0

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

echo "Architecture audit: $APP"
echo "Required architectures: $REQUIRED_ARCHS"

while IFS= read -r -d '' exe; do
  rel="${exe#$APP/}"
  archs="$(lipo -archs "$exe" 2>/dev/null || true)"
  echo ""
  echo "== $rel"
  if [[ -z "$archs" ]]; then
    echo "- Blocker: could not inspect executable architectures."
    BLOCKERS=$((BLOCKERS + 1))
    continue
  fi
  echo "- architectures: $archs"
  for required in $REQUIRED_ARCHS; do
    if echo " $archs " | grep -q " $required "; then
      echo "- has $required"
    else
      echo "- Blocker: missing required architecture $required."
      BLOCKERS=$((BLOCKERS + 1))
    fi
  done
done < <(find "$APP/Contents" -type f -perm -111 -print0)

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo ""
  echo "Architecture audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo ""
echo "Architecture audit passed."
