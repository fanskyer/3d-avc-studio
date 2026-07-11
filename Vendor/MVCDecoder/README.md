# Optional MVC Decoder

The public preview does not include an MVC decoder binary.

For local experiments, place a decoder executable here:

```text
Vendor/MVCDecoder/mvcdecoder
```

The build script copies that executable into:

```text
3D AVC Studio.app/Contents/Resources/Engine/mvcdecoder
```

for the local decoder workflow. The open-source preview is intentionally not
sandboxed because it must be able to run a decoder selected by the user.

You can also build with a one-off path:

```bash
./Scripts/build_app.sh --decoder-path /path/to/mvcdecoder
```

Required command shape:

```text
mvcdecoder decode COMBINED_MVC.h264 LEFT.yuv RIGHT.yuv --width W --height H
```

The decoder must write complete YUV420p left/right view files. Each output size
must be a whole number of `width * height * 3 / 2` frames.

Users are responsible for making sure any decoder they provide is legal for
their use case and jurisdiction.
