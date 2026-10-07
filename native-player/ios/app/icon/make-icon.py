#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate phoenix.svg and the iOS icon PNGs: a rimless gradient disc, a flowing
phoenix silhouette built from variable-width swooshes, and three sound-wave arcs
radiating from its beak. Own mark and colors."""
import math, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
BG = "#16110f"
INK = "#b5141c"

def crescent(p, q, r_outer, r_inner, bulge=1):
    """Pointed swoosh between p and q: outer arc one way, inner arc back."""
    (x0, y0), (x1, y1) = p, q
    return (f'M{x0} {y0} A{r_outer} {r_outer} 0 0 {bulge} {x1} {y1} '
            f'A{r_inner} {r_inner} 0 0 {1 - bulge} {x0} {y0} Z')

def arc(cx, cy, r, a0, a1):
    x0, y0 = cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    return f'M{x0:.1f} {y0:.1f} A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}'

shapes = [
    # neck + chest + belly: one crescent bulging to the right
    crescent((516, 330), (530, 860), 320, 900, 1),
    # wings: bulge below the chord with the tip high, so each plume rises and curls up
    crescent((545, 480), (170, 250), 260, 700, 1),
    crescent((535, 545), (210, 420), 220, 600, 1),
    crescent((575, 480), (870, 230), 240, 640, 0),
    crescent((590, 545), (840, 400), 200, 540, 0),
    # tail plumes flowing down-left, kept inside the disc
    crescent((530, 860), (300, 880), 160, 500, 1),
    crescent((530, 860), (400, 960), 120, 380, 1),
    crescent((530, 860), (590, 950), 90, 260, 0),
    # crest
    crescent((520, 272), (610, 230), 60, 200, 0),
    crescent((532, 286), (620, 276), 60, 200, 0),
]
body = "\n    ".join(f'<path d="{d}"/>' for d in shapes)
beak = (405, 300)
waves = "\n    ".join(
    f'<path d="{arc(beak[0], beak[1], r, 172, 248)}" stroke-width="{w}"/>'
    for r, w in [(70, 22), (115, 20), (160, 18)])

SVG = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="disc" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#d8281a"/>
      <stop offset="0.28" stop-color="#ff8a22"/>
      <stop offset="0.5" stop-color="#ffe45c"/>
      <stop offset="0.72" stop-color="#ff9a2a"/>
      <stop offset="1" stop-color="#d8301a"/>
    </linearGradient>
    <radialGradient id="gloss" cx="35%" cy="25%" r="45%">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.25"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="clip"><circle cx="512" cy="512" r="430"/></clipPath>
  </defs>
  <rect width="1024" height="1024" fill="{BG}"/>
  <circle cx="512" cy="512" r="430" fill="url(#disc)"/>
  <g clip-path="url(#clip)" fill="{INK}">
    {body}
    <!-- head facing left, beak, crest -->
    <circle cx="500" cy="300" r="42"/>
    <path d="M462 290 L 405 300 L 462 312 Z"/>
  </g>
  <g fill="none" stroke="{INK}" stroke-linecap="round" clip-path="url(#clip)">
    {waves}
  </g>
  <circle cx="490" cy="294" r="8" fill="#ffe45c"/>
  <circle cx="512" cy="512" r="430" fill="url(#gloss)"/>
</svg>
'''

def main():
    svg = HERE / "phoenix.svg"
    svg.write_text(SVG)
    for size in (29, 40, 58, 76, 80, 152, 1024):
        png = HERE / f"AppIcon-{size}.png"
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg), "-o", str(png)], check=True)
        subprocess.run(["magick", str(png), "-background", "black", "-alpha", "remove", "-alpha", "off", str(png)], check=True)
    print("icon set written to", HERE)

if __name__ == "__main__":
    sys.exit(main())
