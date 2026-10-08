"""Writes the DockPin icon sources: Resources/AppIcon.icon (an Icon Composer icon: a pastel wallpaper layer and a
Liquid Glass Dock with three dots) and the menu-bar template image Resources/MenuBarIcon(@2x).png.
scripts/make-icon.sh runs this, then compiles the .icon. Open Resources/AppIcon.icon in Icon Composer to tweak it.
Usage: python3 scripts/make-icon.py   (needs Pillow)
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
ICON = os.path.join(RES, "AppIcon.icon")

# The Dock in icon points (1024 canvas, centered): a bar holding three round dots.
DOT, GAP, PAD = 150, 44, 40
BAR_W, BAR_H = DOT + 2 * PAD, 3 * DOT + 2 * GAP + 2 * PAD
BAR_RADIUS = BAR_W // 2 - 20
DOT_CENTERS = [(i - 1) * (DOT + GAP) for i in range(3)]  # top to bottom
DOT_COLORS = ["srgb:0.50,0.76,1.00,1.0",  # sky blue
              "srgb:1.00,0.58,0.76,1.0",  # pink
              "srgb:1.00,0.76,0.42,1.0"]  # warm yellow

# The wallpaper: the reference pastel, a diagonal wash from the top-left to the bottom-right.
WASH = [(0.00, (150, 220, 255)),  # light cyan
        (0.30, (208, 224, 252)),  # pale blue
        (0.48, (236, 226, 248)),  # white-lilac
        (0.66, (250, 214, 226)),  # pink
        (1.00, (255, 218, 150))]  # warm yellow


def wash(t):
    for (t0, c0), (t1, c1) in zip(WASH, WASH[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
    return WASH[-1][1]


def wallpaper(size=1024):
    """The pastel wash, leaning so the yellow sits towards the right and the cyan in the top-left corner."""
    n = 256  # smooth enough to draw small and scale up
    img = Image.new("RGB", (n, n))
    img.putdata([wash(min(1.0, 0.55 * x / (n - 1) + 0.45 * y / (n - 1)) ) for y in range(n) for x in range(n)])
    return img.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(size / 100))


def circle_svg(diameter):
    r = diameter / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{diameter}" height="{diameter}" '
            f'viewBox="0 0 {diameter} {diameter}"><circle cx="{r}" cy="{r}" r="{r}" fill="#ffffff"/></svg>\n')


def rounded_svg(width, height, radius):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            f'<rect width="{width}" height="{height}" rx="{radius}" fill="#ffffff"/></svg>\n')


def layer(name, image, fill=None, y=0, glass=True):
    entry = {"name": name, "image-name": image, "glass": glass,
             "position": {"scale": 1, "translation-in-points": [0, y]}}
    if fill:
        entry["fill"] = {"solid": fill}
    return entry


def icon_json():
    dots = [layer(f"dot {i + 1}", "dot.svg", color, y) for i, (color, y) in enumerate(zip(DOT_COLORS, DOT_CENTERS))]
    return {
        "fill": {"automatic-gradient": "extended-srgb:0.90000,0.90000,1.00000,1.00000"},
        "groups": [  # front to back
            {"name": "Dots", "layers": dots, "lighting": "individual", "specular": True,
             "shadow": {"kind": "neutral", "opacity": 0.3}, "translucency": {"enabled": False, "value": 0}},
            {"name": "Dock", "layers": [layer("Dock", "dock.svg", "srgb:1,1,1,0.85")], "specular": True,
             "blur-material": 0.6, "shadow": {"kind": "neutral", "opacity": 0.55},
             "translucency": {"enabled": True, "value": 0.3}},
            {"name": "Wallpaper", "layers": [layer("Wallpaper", "wallpaper.png", glass=False)], "specular": False},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template image of the same Dock: a see-through bar and three solid dots."""
    px = pt * scale * 4
    unit = px / BAR_H * 0.85  # the bar is 85% of the image's height
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = px / 2, px / 2
    draw.rounded_rectangle([cx - BAR_W / 2 * unit, cy - BAR_H / 2 * unit, cx + BAR_W / 2 * unit, cy + BAR_H / 2 * unit],
                           radius=BAR_RADIUS * unit, fill=(0, 0, 0, 95))
    for dy in DOT_CENTERS:
        draw.ellipse([cx - DOT / 2 * unit, cy + (dy - DOT / 2) * unit, cx + DOT / 2 * unit, cy + (dy + DOT / 2) * unit],
                     fill=(0, 0, 0, 255))
    return img.resize((pt * scale, pt * scale), Image.LANCZOS)


def main():
    os.makedirs(os.path.join(ICON, "Assets"), exist_ok=True)
    wallpaper().save(os.path.join(ICON, "Assets", "wallpaper.png"))
    with open(os.path.join(ICON, "Assets", "dock.svg"), "w") as f:
        f.write(rounded_svg(BAR_W, BAR_H, BAR_RADIUS))
    with open(os.path.join(ICON, "Assets", "dot.svg"), "w") as f:
        f.write(circle_svg(DOT))
    with open(os.path.join(ICON, "icon.json"), "w") as f:
        json.dump(icon_json(), f, indent=2)
        f.write("\n")
    menu_bar_template(18, 1).save(os.path.join(RES, "MenuBarIcon.png"))
    menu_bar_template(18, 2).save(os.path.join(RES, "MenuBarIcon@2x.png"))
    print("wrote Resources/AppIcon.icon and MenuBarIcon(@2x).png")


if __name__ == "__main__":
    main()
