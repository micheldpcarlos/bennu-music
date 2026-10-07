#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the iOS icon set from phoenix-source.png (user-supplied artwork: white phoenix
and sound waves on a green disc). The disc is cut out with a circular mask and placed on
a dark background so iOS's rounded corners never show white. Run with the build venv
python (it has Pillow): native-player/build-venv/bin/python app/icon/make-icon.py"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops
HERE = Path(__file__).resolve().parent
BG = (18, 18, 18)

def main():
    src = Image.open(HERE / "phoenix-source.png").convert("RGB")
    # bounding box of everything that is not the white margin
    diff = ImageChops.difference(src, Image.new("RGB", src.size, (255, 255, 255))).convert("L").point(lambda v: 255 if v > 24 else 0)
    x0, y0, x1, y1 = diff.getbbox()
    cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 - 5  # inside the anti-aliased rim
    # supersampled circular mask for a smooth edge
    big = Image.new("L", (src.width * 4, src.height * 4), 0)
    ImageDraw.Draw(big).ellipse([(cx - r) * 4, (cy - r) * 4, (cx + r) * 4, (cy + r) * 4], fill=255)
    mask = big.resize(src.size, Image.LANCZOS)
    out = Image.composite(src, Image.new("RGB", src.size, BG), mask)
    # square, 1024
    side = max(out.size)
    square = Image.new("RGB", (side, side), BG)
    square.paste(out, ((side - out.width) // 2, (side - out.height) // 2))
    master = square.resize((1024, 1024), Image.LANCZOS)
    master.save(HERE / "AppIcon-1024.png")
    for size in (29, 40, 58, 76, 80, 152):
        master.resize((size, size), Image.LANCZOS).save(HERE / f"AppIcon-{size}.png")
    print(f"disc centre=({cx:.0f},{cy:.0f}) r={r:.0f}; corner={master.getpixel((2, 2))} disc={master.getpixel((512, 60))} icon set written")

if __name__ == "__main__":
    sys.exit(main())
