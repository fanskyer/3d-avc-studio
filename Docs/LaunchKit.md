# Launch Kit

## Release Positioning

3D AVC Studio is an open-source macOS preview for converting Sony 3D AVC /
AVCHD 3D MVC clips into full side-by-side HEVC MP4 files. It keeps media local.
The optional Research Decoder is downloaded and compiled locally only after an
in-app notice; no decoder binary is shipped in the release.

Do not describe the preview as a commercial product, an App Store app, or as
universal support for every Sony 3D camera. The validated real-world target is
Sony HDR-TD10 footage.

## Reddit Draft

**Recommended first community:** r/ffmpeg for technical discussion. Consider
asking moderators before posting if their current self-promotion rule is
unclear. A second, more user-focused post can go to an appropriate camcorder or
Sony community after gathering a few compatibility reports.

**Suggested title:**

```text
I made an open-source macOS tool for turning Sony AVCHD 3D MVC clips into SBS HEVC
```

**Suggested body:**

```text
I have been preserving old Sony 3D AVC / AVCHD 3D footage and built a small
macOS utility around that workflow: 3D AVC Studio.

It detects Sony MVC streams, reconstructs the two views, stacks them as full
side-by-side video, and writes an HEVC MP4 with the original audio where
possible. The current real-world validation target is HDR-TD10 footage.

The project is open source and keeps video local. The public app does not ship
an MVC decoder binary. Instead, Decoder Setup can optionally download and
compile the research decoder locally after showing a notice about the legal and
patent boundary.

I would especially value compatibility reports from owners of other Sony 3D
AVCHD cameras: camera model, clip format, whether the output played correctly,
and any diagnostics. Please do not upload private family footage.

GitHub release: https://github.com/fanskyer/3d-avc-studio/releases
```

## Posting Notes

- Do not lead with Buy Me a Coffee. Put support links in the project README and
  only mention them if someone asks how to support maintenance.
- Do not cross-post identical text on the same day. Reply thoughtfully to
  technical questions and collect compatibility reports in GitHub Issues.
- Lead with the preservation problem and disclose that you built the tool.
- Check each community's current self-promotion rule immediately before posting.
