# 3D AVC Studio Third-Party Notices

The open-source preview is designed to be dependency-clean and explicit about
what is, and is not, bundled.

## Apple System Frameworks

3D AVC Studio uses Apple system frameworks provided by macOS, including
SwiftUI, AppKit, AVFoundation, CoreMedia, CoreVideo, and VideoToolbox.

## Bundled Conversion Components

The clean preview bundle includes the native `sony3dengine` helper built from
this product source tree. It must not include Homebrew FFmpeg binaries, Python
scripts, JM `ldecod`, or h264-tools artifacts.

## MVC Decoder

MVC decode is required for final conversion. The open-source preview does not
ship an MVC decoder binary. Users who build locally with their own decoder are
responsible for making sure that decoder is legal for their use case.
