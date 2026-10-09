"""Draws the BasePoint launcher icon at every size the platforms ask for.

The mark is a lowercase "b" (Base) with an amber dot (Point) on primary blue.
All geometry lives in GLYPH below, in a 100-unit design space. The same
shapes are also drawn by lib/widgets/brand_mark.dart and
lib/widgets/launch_intro.dart in the app, and by the launch splash's vector,
android/app/src/main/res/drawable/splash_mark.xml: change them all together.

Run from the repo root:  python tool/make_icons.py
Needs Pillow (pip install pillow).
"""
from pathlib import Path

from PIL import Image, ImageDraw

BLUE = (0x25, 0x54, 0xE8)  # AppColors.primary
WHITE = (255, 255, 255)
AMBER = (0xFF, 0xC2, 0x3D)

# 100-unit design space. The glyph's bounding box is x 28..82, y 18..80.5.
BAR = (28, 20, 41, 80, 6.5)  # x0, y0, x1, y1, corner radius
BOWL = (54, 58, 22.5, 9.5)  # cx, cy, outer r, inner r
DOT = (74, 26, 8)  # cx, cy, r
GLYPH_CENTER = (55, 49.25)
GLYPH_HEIGHT = 62.5

SUPERSAMPLE = 8
ROOT = Path(__file__).resolve().parent.parent


def render(size, *, height, background="round", opaque=False):
    """`height` is the glyph's height as a fraction of the canvas.

    background: "round" (rounded square, transparent corners), "full"
    (edge-to-edge square) or None (glyph only, for adaptive foregrounds).
    """
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    if background == "round":
        ImageDraw.Draw(img).rounded_rectangle([0, 0, s - 1, s - 1], radius=0.22 * s, fill=BLUE)
    elif background == "full":
        img.paste(BLUE, [0, 0, s, s])

    k = height * s / GLYPH_HEIGHT
    ox = s / 2 - GLYPH_CENTER[0] * k
    oy = s / 2 - GLYPH_CENTER[1] * k

    def box(x0, y0, x1, y1):
        return [ox + x0 * k, oy + y0 * k, ox + x1 * k, oy + y1 * k]

    def circle(cx, cy, r):
        return box(cx - r, cy - r, cx + r, cy + r)

    b = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(b)
    x0, y0, x1, y1, r = BAR
    d.rounded_rectangle(box(x0, y0, x1, y1), radius=r * k, fill=255)
    cx, cy, ro, ri = BOWL
    d.ellipse(circle(cx, cy, ro), fill=255)
    d.ellipse(circle(cx, cy, ri), fill=0)

    dot = Image.new("L", (s, s), 0)
    ImageDraw.Draw(dot).ellipse(circle(*DOT), fill=255)

    img = Image.composite(Image.new("RGBA", (s, s), WHITE + (255,)), img, b)
    img = Image.composite(Image.new("RGBA", (s, s), AMBER + (255,)), img, dot)

    # Premultiplied resize so the anti-aliased edges don't pick up dark fringes.
    out = img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    return out.convert("RGB") if opaque else out


def save(img, rel):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"{rel}  {img.size[0]}px")


# Same visual size on every launcher: about 62% of the visible tile.
TILE = 0.625
# Adaptive foregrounds are 108dp with only the middle 72dp visible, and the
# launcher may crop to a 66dp circle. At 48dp tall the glyph's farthest point
# is ~29.5dp from the centre, inside that circle.
ADAPTIVE = 48 / 108
# Maskable web icons: safe zone is the middle 80% circle.
MASKABLE = 0.44


def main():
    res = "android/app/src/main/res"
    for density, dp in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(render(round(48 * dp), height=TILE), f"{res}/mipmap-{density}/ic_launcher.png")
        save(render(round(108 * dp), height=ADAPTIVE, background=None),
             f"{res}/mipmap-{density}/ic_launcher_foreground.png")

    # iOS draws its own rounded corners and rejects an alpha channel on the
    # App Store icon, so these are opaque edge-to-edge squares.
    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for pt, scales in {20: (1, 2, 3), 29: (1, 2, 3), 40: (1, 2, 3), 60: (2, 3),
                       76: (1, 2), 83.5: (2,), 1024: (1,)}.items():
        for sc in scales:
            name = f"{pt:g}x{pt:g}@{sc}x"
            save(render(round(pt * sc), height=TILE, background="full", opaque=True),
                 f"{ios}/Icon-App-{name}.png")

    save(render(192, height=TILE), "web/icons/Icon-192.png")
    save(render(512, height=TILE), "web/icons/Icon-512.png")
    save(render(192, height=MASKABLE, background="full"), "web/icons/Icon-maskable-192.png")
    save(render(512, height=MASKABLE, background="full"), "web/icons/Icon-maskable-512.png")
    save(render(32, height=0.7), "web/favicon.png")


if __name__ == "__main__":
    main()
