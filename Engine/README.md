# Conversion Engine Boundary

The app talks to a bundled engine through a small command-line contract.

Expected command shape:

```text
sony3dengine convert INPUT OUTPUT --profile sony-3d-avc --codec h265-vt --deinterlace 60 --bitrate 12000k
```

The engine can call a bundled MVC decoder at:

```text
Contents/Resources/Engine/mvcdecoder
```

For source builds, place a local executable at:

```text
Vendor/MVCDecoder/mvcdecoder
```

`Scripts/build_app.sh` copies it into the app bundle before generating engine
capabilities. The open-source preview is intentionally not sandboxed because it
must be able to run a decoder selected by the user.

Decoder command shape:

```text
mvcdecoder decode COMBINED_MVC.h264 LEFT.yuv RIGHT.yuv --width W --height H
```

The decoder must write YUV420p left/right view files with complete frame-sized
outputs. `sony3dengine` validates those files before stacking and encoding.

Exit codes:

- `0`: converted successfully.
- `20`: skipped because the clip has no complete Sony 3D AVC MVC dependent
  view stream for the selected camera profile.
- Other non-zero values: conversion failed.

Stdout/stderr should be progress-oriented plain text. The app filters and
displays it in the conversion log.

## Current Native Engine

`Engine/Sources/Sony3DEngine.swift` builds into
`Contents/Resources/Engine/sony3dengine` for the clean app bundle. It currently
implements:

- command parsing for `convert`, `probe`, and `capabilities`;
- the `sony-3d-avc` camera profile, with `sony-avchd-3d` kept as a compatible
  alias;
- 188-byte TS and 192-byte M2TS packet layout detection;
- base AVC and dependent MVC PID scanning;
- native H.264 SPS metadata parsing for dimensions and VUI timing;
- native PES payload extraction for base/dependent streams;
- native H.264 NAL scanning and MVC access-unit interleave;
- native YUV420p full side-by-side frame stacking;
- native HEVC MP4 writing through AVFoundation and VideoToolbox;
- native source-audio passthrough muxing into the final MP4 when AVFoundation
  can read an audio track from the input clip;
- full `convert` pipeline orchestration with an explicit MVC decoder boundary;
- external bundled `mvcdecoder` executable contract and output validation;
- exit code `20` for clips with no dependent MVC stream.

MVC decode is the remaining boundary before local builds with a user-provided
decoder can run the whole conversion path. It is also the main licensing
boundary for any redistributable binary.
