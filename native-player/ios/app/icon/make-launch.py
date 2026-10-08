# Launch images: black with the Bennu disc. Without these, iOS runs iPhone apps letterboxed at 320x480.
import os
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
disc = Image.open(os.path.join(here, "AppIcon-152.png")).convert("RGBA")
sizes = {"Launch-480@2x": (640, 960), "Launch-568@2x": (640, 1136),
         "Launch-Pad-Portrait": (768, 1024), "Launch-Pad-Portrait@2x": (1536, 2048),
         "Launch-Pad-Landscape": (1024, 768), "Launch-Pad-Landscape@2x": (2048, 1536)}
for name, (w, h) in sizes.items():
    im = Image.new("RGB", (w, h), (18, 18, 18))
    d = int(min(w, h) * 0.18)
    logo = disc.resize((d, d), Image.LANCZOS)
    im.paste(logo, ((w - d) // 2, (h - d) // 2), logo)
    im.save(os.path.join(here, name + ".png"), optimize=True)
    print(name, w, h)
