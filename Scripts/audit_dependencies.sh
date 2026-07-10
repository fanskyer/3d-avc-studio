#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/Build/3D AVC Studio.app}"
REPORT="${2:-}"
BLOCKERS=0

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

emit() {
  echo "$1"
  if [[ -n "$REPORT" ]]; then
    echo "$1" >>"$REPORT"
  fi
}

if [[ -n "$REPORT" ]]; then
  rm -f "$REPORT"
  mkdir -p "$(dirname "$REPORT")"
fi

emit "Dependency audit: $APP"

while IFS= read -r -d '' exe; do
  rel="${exe#$APP/}"
  emit ""
  emit "== $rel"

  if codesign --verify --verbose=2 "$exe" >/tmp/sony3d-codesign-check.log 2>&1; then
    emit "- signed: yes"
  else
    emit "- blocker: code signature verification failed"
    sed 's/^/  /' /tmp/sony3d-codesign-check.log | while IFS= read -r line; do emit "$line"; done
    BLOCKERS=$((BLOCKERS + 1))
  fi

  while IFS= read -r dep; do
    case "$dep" in
      "$exe:"|"")
        continue
        ;;
    esac
    path="${dep#"${dep%%[![:space:]]*}"}"
    case "$path" in
      "$exe ("*"):")
        continue
        ;;
    esac
    path="${path%% (compatibility version*}"
    case "$path" in
      /System/Library/*|/usr/lib/*|@rpath/*|@executable_path/*|@loader_path/*)
        emit "- dependency ok: $path"
        ;;
      *)
        emit "- blocker: non-system dependency: $path"
        BLOCKERS=$((BLOCKERS + 1))
        ;;
    esac
  done < <(otool -L "$exe")
done < <(find "$APP/Contents" -type f -perm -111 -print0)

rm -f /tmp/sony3d-codesign-check.log

if [[ "$BLOCKERS" -gt 0 ]]; then
  emit ""
  emit "Dependency audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

emit ""
emit "Dependency audit passed."
