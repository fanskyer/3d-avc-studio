#!/usr/bin/env python3
import math
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageDraw


ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def clamp(value):
    return max(0, min(255, int(round(value))))


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(4))


def rounded_rect_alpha(x, y, left, top, right, bottom, radius):
    if x < left or x >= right or y < top or y >= bottom:
        return 0.0
    cx = min(max(x, left + radius), right - radius - 1)
    cy = min(max(y, top + radius), bottom - radius - 1)
    distance = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, radius + 0.5 - distance))


def blend(dst, src):
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    a = sa + da * (1 - sa)
    if a <= 0:
        return (0, 0, 0, 0)
    return (
        (sr * sa + dr * da * (1 - sa)) / a,
        (sg * sa + dg * da * (1 - sa)) / a,
        (sb * sa + db * da * (1 - sa)) / a,
        a,
    )


def fill_rect(pixels, size, box, color, radius=0):
    left, top, right, bottom = box
    for y in range(max(0, top), min(size, bottom)):
        for x in range(max(0, left), min(size, right)):
            alpha = 1.0
            if radius:
                alpha = rounded_rect_alpha(x + 0.5, y + 0.5, left, top, right, bottom, radius)
            if alpha > 0:
                r, g, b, a = color
                pixels[y][x] = blend(pixels[y][x], (r, g, b, a * alpha))


def draw_icon(size):
    pixels = [[(0.0, 0.0, 0.0, 0.0) for _ in range(size)] for _ in range(size)]
    margin = max(1, round(size * 0.055))
    radius = size * 0.205
    bg_left = margin
    bg_top = margin
    bg_right = size - margin
    bg_bottom = size - margin
    dark = (12, 24, 38, 1)
    teal = (22, 186, 182, 1)
    blue = (36, 101, 205, 1)
    magenta = (202, 71, 180, 1)

    for y in range(size):
        for x in range(size):
            alpha = rounded_rect_alpha(x + 0.5, y + 0.5, bg_left, bg_top, bg_right, bg_bottom, radius)
            if alpha <= 0:
                continue
            gx = x / max(1, size - 1)
            gy = y / max(1, size - 1)
            base = mix(teal, blue, gx)
            base = mix(base, magenta, max(0.0, gy - 0.35) * 0.65)
            shade = 0.92 - 0.32 * gy + 0.08 * math.sin((gx + gy) * math.pi)
            color = (base[0] * shade, base[1] * shade, base[2] * shade, alpha)
            pixels[y][x] = blend(pixels[y][x], color)

    fill_rect(
        pixels,
        size,
        (round(size * 0.12), round(size * 0.13), round(size * 0.88), round(size * 0.87)),
        (255, 255, 255, 0.10),
        round(size * 0.16),
    )

    lens_y = round(size * 0.28)
    lens_h = round(size * 0.25)
    lens_w = round(size * 0.31)
    fill_rect(pixels, size, (round(size * 0.17), lens_y, round(size * 0.17) + lens_w, lens_y + lens_h), (255, 255, 255, 0.92), round(size * 0.055))
    fill_rect(pixels, size, (round(size * 0.52), lens_y, round(size * 0.52) + lens_w, lens_y + lens_h), (255, 255, 255, 0.92), round(size * 0.055))
    fill_rect(pixels, size, (round(size * 0.20), lens_y + round(size * 0.035), round(size * 0.45), lens_y + lens_h - round(size * 0.035)), dark, round(size * 0.04))
    fill_rect(pixels, size, (round(size * 0.55), lens_y + round(size * 0.035), round(size * 0.80), lens_y + lens_h - round(size * 0.035)), dark, round(size * 0.04))

    bar = max(1, round(size * 0.045))
    text_top = round(size * 0.61)
    text_left = round(size * 0.22)
    text_h = round(size * 0.20)
    text_w = round(size * 0.22)
    white = (255, 255, 255, 0.94)
    fill_rect(pixels, size, (text_left, text_top, text_left + text_w, text_top + bar), white, 0)
    fill_rect(pixels, size, (text_left + text_w - bar, text_top, text_left + text_w, text_top + text_h), white, 0)
    fill_rect(pixels, size, (text_left, text_top + text_h // 2 - bar // 2, text_left + text_w, text_top + text_h // 2 + bar), white, 0)
    fill_rect(pixels, size, (text_left, text_top + text_h - bar, text_left + text_w, text_top + text_h), white, 0)

    d_left = round(size * 0.53)
    d_w = round(size * 0.24)
    fill_rect(pixels, size, (d_left, text_top, d_left + bar, text_top + text_h), white, 0)
    fill_rect(pixels, size, (d_left, text_top, d_left + d_w - bar, text_top + bar), white, 0)
    fill_rect(pixels, size, (d_left, text_top + text_h - bar, d_left + d_w - bar, text_top + text_h), white, 0)
    fill_rect(pixels, size, (d_left + d_w - bar, text_top + bar, d_left + d_w, text_top + text_h - bar), white, round(size * 0.025))

    data = bytearray()
    for row in pixels:
        data.append(0)
        for r, g, b, a in row:
            data.extend([clamp(r), clamp(g), clamp(b), clamp(a * 255)])
    return bytes(data)


def png_chunk(kind, payload):
    chunk = kind + payload
    return struct.pack(">I", len(payload)) + chunk + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)


def source_camera():
    return Path(__file__).resolve().parent.parent / "App" / "Resources" / "3DAVCStudio-camera-chroma.png"


def remove_green_background(image):
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            # Keep cyan lens glass; only remove the intentionally vivid green key.
            if green > 80 and green > red * 1.25 and green > blue * 1.25:
                pixels[x, y] = (red, green, blue, 0)
            else:
                pixels[x, y] = (red, green, blue, alpha)
    return image


def production_icon(size):
    canvas_size = 1024
    base = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    margin = 38
    radius = 218
    draw.rounded_rectangle(
        (margin, margin, canvas_size - margin, canvas_size - margin),
        radius=radius,
        fill=(18, 47, 67, 255),
    )
    draw.rounded_rectangle(
        (margin + 20, margin + 20, canvas_size - margin - 20, canvas_size - margin - 20),
        radius=radius - 20,
        outline=(99, 185, 203, 130),
        width=10,
    )

    camera = remove_green_background(Image.open(source_camera()))
    camera.thumbnail((930, 930), Image.Resampling.LANCZOS)
    left = (canvas_size - camera.width) // 2
    top = (canvas_size - camera.height) // 2 - 8
    base.alpha_composite(camera, (left, top))
    return base.resize((size, size), Image.Resampling.LANCZOS)


def write_png(path, size):
    production_icon(size).save(path, "PNG")


def main():
    if len(sys.argv) != 2:
        print("usage: generate_app_icon.py OUT.iconset", file=sys.stderr)
        return 64
    iconset = Path(sys.argv[1])
    iconset.mkdir(parents=True, exist_ok=True)
    for name, size in ICON_SIZES:
        write_png(iconset / name, size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
