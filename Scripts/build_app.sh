#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="3D AVC Studio"
PRODUCT_NAME="ThreeDAVCStudio"
BUILD_DIR="$ROOT/Build"
mkdir -p "$BUILD_DIR"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ENGINE_RESOURCES="$RESOURCES/Engine"
COMPLIANCE_RESOURCES="$RESOURCES/Compliance"
ICONSET_PARENT="$(mktemp -d "$BUILD_DIR/iconset.XXXXXX")"
ICONSET="$ICONSET_PARENT/3DAVCStudio.iconset"
DEFAULT_DECODER="$ROOT/Vendor/MVCDecoder/mvcdecoder"
MVC_DECODER_PATH="${MVC_DECODER_PATH:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_ARCH="${APP_ARCH:-universal}"

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
    --arch)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --arch" >&2
        exit 2
      fi
      APP_ARCH="$2"
      shift 2
      ;;
    --decoder-path)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --decoder-path" >&2
        exit 2
      fi
      MVC_DECODER_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

case "$APP_ARCH" in
  universal)
    ARCHS=(arm64 x86_64)
    ;;
  arm64|x86_64)
    ARCHS=("$APP_ARCH")
    ;;
  *)
    echo "Unknown --arch value: $APP_ARCH. Use universal, arm64, or x86_64." >&2
    exit 2
    ;;
esac

compile_swift_executable() {
  local source="$1"
  local output="$2"
  shift 2

  if [[ "${#ARCHS[@]}" == "1" ]]; then
    swiftc \
      -O \
      -parse-as-library \
      -target "${ARCHS[0]}-apple-macos13.0" \
      "$source" \
      -o "$output" \
      "$@"
    return
  fi

  local tmp
  tmp="$(mktemp -d "$BUILD_DIR/universal.XXXXXX")"
  local built=()
  for arch in "${ARCHS[@]}"; do
    swiftc \
      -O \
      -parse-as-library \
      -target "${arch}-apple-macos13.0" \
      "$source" \
      -o "$tmp/$(basename "$output").$arch" \
      "$@"
    built+=("$tmp/$(basename "$output").$arch")
  done
  lipo -create "${built[@]}" -output "$output"
  rm -rf "$tmp"
}

rm -rf "$BUILD_DIR"/*.app
mkdir -p "$MACOS" "$RESOURCES" "$ENGINE_RESOURCES" "$COMPLIANCE_RESOURCES"

compile_swift_executable \
  "$ROOT/App/Sources/ThreeDAVCStudio.swift" \
  "$MACOS/$PRODUCT_NAME" \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers

cp "$ROOT/App/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/App/Resources/ThirdPartyNotices.md" "$RESOURCES/ThirdPartyNotices.md"
cp "$ROOT/App/Resources/PrivacyInfo.xcprivacy" "$RESOURCES/PrivacyInfo.xcprivacy"
cp "$ROOT/Compliance/decoder_policy.json" "$COMPLIANCE_RESOURCES/decoder_policy.json"

python3 "$ROOT/Scripts/generate_app_icon.py" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES/3DAVCStudio.icns"
rm -rf "$ICONSET_PARENT"

compile_swift_executable \
  "$ROOT/Engine/Sources/Sony3DEngine.swift" \
  "$ENGINE_RESOURCES/sony3dengine" \
  -framework AVFoundation \
  -framework CoreVideo \
  -framework CoreMedia \
  -framework VideoToolbox

DECODER_SOURCE="$DEFAULT_DECODER"
DECODER_LABEL="Vendor/MVCDecoder/mvcdecoder"
if [[ -n "$MVC_DECODER_PATH" ]]; then
  DECODER_SOURCE="$MVC_DECODER_PATH"
  DECODER_LABEL="$MVC_DECODER_PATH"
fi

if [[ -f "$DECODER_SOURCE" ]]; then
  if [[ ! -x "$DECODER_SOURCE" ]]; then
    echo "MVC decoder exists but is not executable: $DECODER_LABEL" >&2
    exit 1
  fi
  cp "$DECODER_SOURCE" "$ENGINE_RESOURCES/mvcdecoder"
fi

SONY3D_DISABLE_LOCAL_DECODER=1 "$ENGINE_RESOURCES/sony3dengine" capabilities >"$ENGINE_RESOURCES/capabilities.json"

while IFS= read -r -d '' helper; do
  codesign \
    --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --entitlements "$ROOT/App/Resources/Helper.entitlements" \
    "$helper" >/dev/null
done < <(find "$ENGINE_RESOURCES" -maxdepth 1 -type f -perm -111 -print0)

codesign \
  --force \
  --sign "$CODE_SIGN_IDENTITY" \
  --entitlements "$ROOT/App/Resources/ThreeDAVCStudio.entitlements" \
  "$APP" >/dev/null

echo "Built: $APP"
echo "Signed with: $CODE_SIGN_IDENTITY"
echo "Architectures: ${ARCHS[*]}"
