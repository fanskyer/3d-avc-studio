# Open Source Preview

3D AVC Studio is now positioned as an open-source, sponsor-supported research
and preservation utility for Sony 3D AVC / AVCHD 3D footage.

## What Ships

- SwiftUI Mac app shell.
- Native `sony3dengine` helper for stream detection, transport extraction,
  MVC access-unit interleave, SBS YUV stacking, and Apple VideoToolbox HEVC
  writing.
- Minimal build and release scripts.
- Decoder policy metadata that explains why MVC decoder binaries are not
  included by default.

## What Does Not Ship

The open-source preview release does not bundle an MVC decoder binary. The app
therefore reports `conversionComplete=false` unless the user builds locally with
an explicit decoder path:

```bash
./Scripts/build_app.sh --decoder-path /path/to/mvcdecoder
```

Users are responsible for making sure any decoder, codec, patent license, or
third-party tool they use is legal for their jurisdiction and use case.

## Sponsor Model

Development is supported by voluntary sponsorship. Suggested links:

- Buy Me a Coffee: https://www.buymeacoffee.com/3davcstudio
Sponsorship is appreciation for maintenance and research; it is not a purchase
of patented codec rights, bundled decoders, warranty, or guaranteed support.

## GitHub Preview Release

```bash
./Scripts/package_open_source_release.sh
./Scripts/audit_open_source_release.sh
```

The generated manifest records `channel=open-source-preview` and confirms that
the release does not bundle an MVC decoder by default.
