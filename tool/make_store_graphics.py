"""Draws the Google Play store graphics from the same mark as the app icon.

  docs/play/icon-512.png       512 x 512, the store listing icon. Edge to edge:
                               Google Play rounds the corners itself.
  docs/play/feature-1024x500.png  1024 x 500, the banner at the top of the
                               listing. Opaque, as Play requires.

Run from the repo root:  python tool/make_store_graphics.py
Needs Pillow, and reuses the glyph from tool/make_icons.py.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from make_icons import BLUE, TILE, render

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "play"
FONTS = ROOT / "assets" / "fonts"


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f"PlusJakartaSans-{weight}.ttf"), size)


def icon():
    # Same proportions as the launcher icon, on a full square.
    img = render(512, height=TILE, background="full")
    img.save(OUT / "icon-512.png", optimize=True)


def feature():
    w, h = 1024, 500
    img = Image.new("RGB", (w, h), BLUE)

    # A large, soft circle behind the mark: a little depth without a gradient.
    halo = Image.new("L", (w, h), 0)
    ImageDraw.Draw(halo).ellipse([40, 30, 480, 470], fill=255)
    img.paste((0x2F, 0x5E, 0xF0), mask=halo)

    # The mark: white "b" and amber dot, no tile, centred in the circle.
    mark = render(300, height=0.86, background=None)
    img.paste(mark, (110, 100), mark)

    d = ImageDraw.Draw(img)
    x = 520
    d.text((x, 150), "BasePoint", font=font("ExtraBold", 84), fill=(255, 255, 255))
    d.text((x, 262), "The till for your", font=font("SemiBold", 34), fill=(0xDC, 0xE5, 0xFF))
    d.text((x, 304), "sari-sari store", font=font("SemiBold", 34), fill=(0xDC, 0xE5, 0xFF))
    d.text((x, 372), "Sell  ·  Stock  ·  Utang  ·  Offline",
           font=font("Medium", 22), fill=(0xFF, 0xC2, 0x3D))
    img.save(OUT / "feature-1024x500.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    icon()
    feature()
    for p in sorted(OUT.glob("*.png")):
        with Image.open(p) as im:
            print(f"{p.relative_to(ROOT)}  {im.size[0]}x{im.size[1]} {im.mode}")
