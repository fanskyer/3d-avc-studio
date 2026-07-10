# 3D AVC Studio

Open-source macOS utility for preserving Sony 3D AVC / AVCHD 3D MVC camcorder
clips as side-by-side MP4.

The first validation target is Sony HDR-TD10 footage, but the project is meant
to be a general Sony 3D AVC / AVCHD 3D preservation tool.

## Status

This is an early open-source preview.

- Native SwiftUI Mac app shell.
- Bundled native `sony3dengine` helper.
- Sony 3D AVC / AVCHD 3D stream detection.
- MVC access-unit extraction/interleave pipeline work.
- Side-by-side YUV stacking and Apple HEVC MP4 writing path.
- Local diagnostics and privacy-first support flow.
- No bundled MVC decoder in the public preview.

Because the preview does not ship an MVC decoder, full conversion may require a
local decoder that you are legally allowed to use.

## Download

Use the latest GitHub Release preview build.

The app is intentionally distributed without patented/commercial decoder
binaries. If macOS warns about an unidentified developer, open it from Finder
with Control-click -> Open, or build from source.

## Build From Source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift toolchain included with Xcode

Build the app:

```bash
./Scripts/build_app.sh
```

The app is written to:

```text
Build/3D AVC Studio.app
```

Create and audit a preview release zip:

```bash
./Scripts/package_open_source_release.sh
./Scripts/audit_open_source_release.sh
```

## Decoder Boundary

The public preview does not include an MVC decoder binary.

For local experiments, you may provide a decoder executable at:

```text
Vendor/MVCDecoder/mvcdecoder
```

or build with an explicit path:

```bash
./Scripts/build_app.sh --decoder-path /path/to/mvcdecoder
```

Users are responsible for making sure any decoder, codec, patent license, or
third-party tool they use is legal for their jurisdiction and use case.

For research use, the repo includes an optional local bootstrap script:

```bash
./Scripts/bootstrap_research_decoder.sh
```

That script downloads and builds h264-tools/JM reference helpers under
`Build/research-decoder/` on your Mac. The generated files are not committed,
not bundled, and not included in public releases. The reference helper is useful
for research and validation, but it is not shipped as a product decoder.

## Sponsorship

If this helps recover old 3D footage, sponsorship is welcome:

- Buy Me a Coffee: https://www.buymeacoffee.com/3davcstudio

Sponsorship supports maintenance, testing, documentation, and research. It does
not purchase decoder rights, bundled codec licenses, warranty, or guaranteed
support.

## License

3D AVC Studio source code is released under the MIT License.

The license covers this repository's original code only. It does not grant
rights to third-party decoders, patented codecs, Sony trademarks, or user media.

See [Docs/OpenSourceRelease.md](Docs/OpenSourceRelease.md) and
[Engine/README.md](Engine/README.md) for technical details.
