#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate phoenix.svg and the iOS icon PNGs: a symmetric rising phoenix with three
feather tiers per wing and a flame tail, fire gradient on a dark ground. Own mark."""
import subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
BG = "#15100e"

def crescent(p, q, r_outer, r_inner, bulge=1):
    (x0, y0), (x1, y1) = p, q
    return (f'M{x0} {y0} A{r_outer} {r_outer} 0 0 {bulge} {x1} {y1} '
            f'A{r_inner} {r_inner} 0 0 {1 - bulge} {x0} {y0} Z')

def lens(p, q, r):
    (x0, y0), (x1, y1) = p, q
    return f'M{x0} {y0} A{r} {r} 0 0 1 {x1} {y1} A{r} {r} 0 0 1 {x0} {y0} Z'

def mirror(p):
    return (1024 - p[0], p[1])

# left wing tiers: (shoulder, tip, outer radius, inner radius); bulge below the chord so tips curl up
LEFT = [
    ((470, 400), (90, 170), 300, 900),
    ((475, 452), (110, 300), 280, 800),
    ((480, 502), (170, 440), 220, 700),
]
shapes = []
for p, q, ro, ri in LEFT:
    shapes.append(crescent(p, q, ro, ri, 1))
    shapes.append(crescent(mirror(p), mirror(q), ro, ri, 0))
# body: chest widening then tapering to the tail root
shapes.append('M512 356 C 584 396, 596 520, 566 640 C 548 704, 526 744, 512 772 '
              'C 498 744, 476 704, 458 640 C 428 520, 440 396, 512 356 Z')
# tail flames: tall centre tongue with two curling side tongues
shapes.append(lens((512, 690), (512, 985), 210))
shapes.append(crescent((500, 740), (436, 930), 150, 420, 0))
shapes.append(crescent((524, 740), (588, 930), 150, 420, 1))
# head turned right, beak, crest curling back
shapes.append('<circle cx="512" cy="336" r="38"/>')
shapes.append('M546 326 L 596 342 L 546 352 Z')
shapes.append(crescent((506, 302), (462, 250), 64, 180, 1))

paths = "\n    ".join(s if s.startswith('<') else f'<path d="{s}"/>' for s in shapes)

SVG = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="{BG}"/>
  <g fill="#ff6a1e">
    {paths}
  </g>
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
