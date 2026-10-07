#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate phoenix.svg and the iOS icon PNGs. Flat disc with the phoenix drawn as
sound-wave wing arcs; inspired by music-app icon language, own mark and colors."""
import math, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
INK = "#16110f"

def arc(cx, cy, r, a0, a1):
    x0, y0 = cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    return f'M{x0:.1f} {y0:.1f} A{r} {r} 0 0 {1 if a1 > a0 else 0} {x1:.1f} {y1:.1f}'

def wings():
    px, py = 512, 790
    out = []
    for r, w, a0, a1 in [(205, 60, -124, -176), (300, 52, -117, -170), (395, 44, -110, -164)]:
        out.append(f'<path d="{arc(px, py, r, a0, a1)}" stroke-width="{w}"/>')
        out.append(f'<path d="{arc(px, py, r, -180 - a0, -180 - a1)}" stroke-width="{w}"/>')
    return "\n    ".join(out)

SVG = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="disc" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ff8f2e"/>
      <stop offset="1" stop-color="#f03a1c"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="{INK}"/>
  <circle cx="512" cy="512" r="412" fill="url(#disc)"/>
  <g fill="none" stroke="{INK}" stroke-linecap="round">
    {wings()}
  </g>
  <g fill="{INK}">
    <!-- flame-shaped body -->
    <path d="M512 330 C 580 400, 606 500, 596 600 C 588 680, 556 730, 512 750 C 468 730, 436 680, 428 600 C 418 500, 444 400, 512 330 Z"/>
    <!-- tail fan -->
    <path d="M512 736 C 480 760, 450 800, 438 856 C 466 826, 490 812, 512 806 C 534 812, 558 826, 586 856 C 574 800, 544 760, 512 736 Z"/>
    <path d="M512 760 C 500 790, 496 820, 512 862 C 528 820, 524 790, 512 760 Z"/>
    <!-- single swept-back flame crest -->
    <path d="M488 296 C 452 272, 428 232, 432 180 C 452 214, 476 232, 500 240 C 506 258, 514 276, 530 290 Z"/>
    <!-- head and beak -->
    <circle cx="512" cy="330" r="50"/>
    <path d="M552 316 L 612 334 L 554 352 Z"/>
  </g>
  <circle cx="528" cy="322" r="9" fill="#ff8f2e"/>
</svg>
'''

def main():
    svg = HERE / "phoenix.svg"
    svg.write_text(SVG)
    for size in (29, 40, 58, 76, 80, 152, 1024):
        png = HERE / f"AppIcon-{size}.png"
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg), "-o", str(png)], check=True)
        # iOS icons must not carry an alpha channel
        subprocess.run(["magick", str(png), "-background", "black", "-alpha", "remove", "-alpha", "off", str(png)], check=True)
    print("icon set written to", HERE)

if __name__ == "__main__":
    sys.exit(main())
