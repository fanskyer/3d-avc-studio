# 3D AVC Studio

Open-source macOS utility for preserving Sony 3D AVC / AVCHD 3D MVC camcorder
clips as side-by-side MP4.

The first validation target is Sony HDR-TD10 footage, but the project is meant
to be a general Sony 3D AVC / AVCHD 3D preservation tool.

## What This Preview Is

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

## Quick Start

1. Download the latest `3D-AVC-Studio-...open-source-preview...zip` from
   GitHub Releases.
2. Unzip it and open `3D AVC Studio.app`.
3. If macOS warns about an unidentified developer, open it from Finder with
   Control-click -> Open.
4. Add `.MTS` or `.M2TS` clips from a Sony 3D AVC / AVCHD 3D camera.
5. Leave the default settings unless you are testing a specific workflow:
   `H.265 Fast Apple`, `60p`, and source-folder output.
6. Open `Decoder Setup...`, choose a legally usable MVC decoder, then press
   `Test`. The app stores its private local copy in Application Support.

The Convert button remains disabled until a decoder is installed. The public
preview does not bundle one, but the setup screen makes its required command
shape visible and installs a user-supplied decoder without asking the user to
set an environment variable or rebuild the app.

## Running The App

- `Choose Files`: add one or more `.MTS` / `.M2TS` clips.
- `Choose Folder`: add every supported clip from a folder.
- `Output Folder`: choose a shared destination for converted files.
- `Use Source Folders`: write each output next to its source clip.
- `Decoder Setup...`: install, test, or remove a local MVC decoder. The app
  copies it into its own Application Support container; it does not upload it.
- `Support -> Copy Release Readiness`: copy the current decoder/release state.
- `Save Diagnostics`: create a local text report for troubleshooting. The app
  does not upload videos or diagnostics.

Ordinary 2D AVCHD clips are skipped because they do not contain the dependent
MVC view. Sony 3D AVC / AVCHD 3D clips should contain both the base AVC stream
and the dependent MVC stream.

## Research Decoder Bootstrap

For research use, the repo includes an optional local bootstrap script:

```bash
./Scripts/bootstrap_research_decoder.sh
```

That script downloads and builds h264-tools/JM reference helpers under
`Build/research-decoder/` on your Mac:

```text
Build/research-decoder/bin/ldecod
Build/research-decoder/bin/naluparser
Build/research-decoder/bin/yuvsbspipe
```

The generated files are not committed, not bundled, and not included in public
releases. The reference helper is useful for research and validation, but it is
not shipped as a product decoder.

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
