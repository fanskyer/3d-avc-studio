#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/Build/research-decoder"
SRC="$WORK/h264-tools"
BIN="$WORK/bin"
REPO="${H264_TOOLS_REPO:-https://github.com/carrardt/h264-tools.git}"

mkdir -p "$WORK" "$BIN"

cat <<'TEXT'
Research decoder bootstrap

This script downloads and builds h264-tools/JM reference helpers on this Mac.
It does not add decoder source or binaries to the repository, and it does not
make the generated files part of the public release.

The h264-tools/JM notices warn that product use may involve third-party patent
rights. Use this only if you understand and accept the legal obligations for
your jurisdiction and use case.

TEXT

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 "$REPO" "$SRC"
else
  git -C "$SRC" pull --ff-only
fi

python3 - "$SRC" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
malloc_patch = (
    "#include <malloc.h>",
    "#ifdef __APPLE__\n#include <malloc/malloc.h>\n#else\n#include <malloc.h>\n#endif",
)

def patch(path, replacements):
    text = path.read_text()
    original = text
    for old, new in replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text)

patch(root / "tools" / "yuvsbspipe.c", [malloc_patch])
patch(
    root / "tools" / "naluparser.c",
    [
        ("#include <stdio.h>\n", "#include <stdio.h>\n#include <stdlib.h>\n#include <unistd.h>\n"),
        malloc_patch,
    ],
)
PY

common=(clang -std=gnu99 -fno-strict-aliasing -fsigned-char -O2)
ldecod_sources=("$SRC"/ldecod/*.c)
tool_sources=("$SRC"/tools/*.c)

echo "Building ldecod..."
"${common[@]}" "${ldecod_sources[@]}" -lm -o "$BIN/ldecod"

echo "Building helper tools..."
for source in "${tool_sources[@]}"; do
  name="$(basename "$source" .c)"
  "${common[@]}" "$source" -o "$BIN/$name"
done

cp "$ROOT/Research/MVCDecoderAdapter/mvcdecoder" "$BIN/mvcdecoder"
chmod 755 "$BIN/mvcdecoder"

cat >"$WORK/README.txt" <<TEXT
Research decoder helpers built locally.

Generated files:
- $BIN/ldecod
- $BIN/naluparser
- $BIN/yuvsbspipe
- $BIN/mvcdecoder

Source:
- $SRC

These files are not committed and are not included in public release artifacts.
The h264-tools/JM notices warn that product use may involve third-party patent
rights. You are responsible for any decoder, codec, patent, or media-rights
obligations that apply to your own use.

Current app integration:
The generated mvcdecoder adapter implements the app decoder contract:

  mvcdecoder decode COMBINED_MVC.h264 LEFT.yuv RIGHT.yuv --width W --height H

To use it in the app, open Decoder Setup and choose:

  $BIN/mvcdecoder

The app copies the adapter and its locally-built ldecod/configuration support
files into Application Support. They remain user-installed local research
dependencies and are never bundled into a public release artifact.
TEXT

echo
echo "Built research helpers under: $WORK"
echo "Read: $WORK/README.txt"
