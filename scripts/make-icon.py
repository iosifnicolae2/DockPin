"""Writes the DockPin icon sources: Resources/AppIcon.icon (an Icon Composer icon: a pastel wallpaper layer and a
Liquid Glass Dock with four app tiles) and the menu-bar template image Resources/MenuBarIcon(@2x).png.
scripts/make-icon.sh runs this, then compiles the .icon. Open Resources/AppIcon.icon in Icon Composer to tweak it.
Usage: python3 scripts/make-icon.py   (needs Pillow)
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
ICON = os.path.join(RES, "AppIcon.icon")

# The Dock in icon points (1024 canvas, centered): a bar holding four square tiles.
TILE, GAP, PAD = 176, 24, 28
BAR_W, BAR_H = TILE + 2 * PAD, 4 * TILE + 3 * GAP + 2 * PAD
TILE_CENTERS = [round((i - 1.5) * (TILE + GAP)) for i in range(4)]  # top to bottom
TILE_COLORS = ["srgb:0.55,0.78,1.00,1.0",  # sky blue
               "srgb:0.52,0.87,0.64,1.0",  # mint
               "srgb:1.00,0.79,0.48,1.0",  # peach
               "srgb:1.00,0.60,0.77,1.0"]  # pink


def wallpaper(size=1024):
    """Soft iridescent pastel: cyan top-left, lilac-white centre, pink and warm yellow towards the bottom-right."""
    s = 2 * size  # drawn at 2x for smooth blurs
    img = Image.new("RGB", (s, s), (236, 230, 252))
    blobs = [((160, 150), 420, (140, 218, 255)), ((520, 470), 300, (244, 238, 255)),
             ((860, 700), 380, (255, 182, 220)), ((420, 960), 330, (255, 224, 160)),
             ((960, 180), 260, (214, 200, 255))]
    u = s / 1024
    for (cx, cy), r, color in blobs:
        blob = Image.new("L", (s, s), 0)
        ImageDraw.Draw(blob).ellipse([(cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u], fill=255)
        img = Image.composite(Image.new("RGB", (s, s), color), img, blob.filter(ImageFilter.GaussianBlur(r * 0.6 * u)))
    return img.resize((size, size), Image.LANCZOS)


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
    tiles = [layer(f"tile {i + 1}", "tile.svg", color, y) for i, (color, y) in enumerate(zip(TILE_COLORS, TILE_CENTERS))]
    return {
        "fill": {"automatic-gradient": "extended-srgb:0.90000,0.90000,1.00000,1.00000"},
        "groups": [  # front to back
            {"name": "Tiles", "layers": tiles, "lighting": "individual", "specular": True,
             "shadow": {"kind": "neutral", "opacity": 0.3}, "translucency": {"enabled": False, "value": 0}},
            {"name": "Dock", "layers": [layer("Dock", "dock.svg", "srgb:1,1,1,0.85")], "specular": True,
             "blur-material": 0.6, "shadow": {"kind": "neutral", "opacity": 0.55},
             "translucency": {"enabled": True, "value": 0.3}},
            {"name": "Wallpaper", "layers": [layer("Wallpaper", "wallpaper.png", glass=False)], "specular": False},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template image of the same Dock: a see-through bar and four solid tiles."""
    px = pt * scale * 4
    unit = px / BAR_H * 0.85  # the bar is 85% of the image's height
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = px / 2, px / 2
    draw.rounded_rectangle([cx - BAR_W / 2 * unit, cy - BAR_H / 2 * unit, cx + BAR_W / 2 * unit, cy + BAR_H / 2 * unit],
                           radius=72 * unit, fill=(0, 0, 0, 95))
    for ty in TILE_CENTERS:
        draw.rounded_rectangle([cx - TILE / 2 * unit, cy + (ty - TILE / 2) * unit, cx + TILE / 2 * unit,
                                cy + (ty + TILE / 2) * unit], radius=40 * unit, fill=(0, 0, 0, 255))
    return img.resize((pt * scale, pt * scale), Image.LANCZOS)


def main():
    os.makedirs(os.path.join(ICON, "Assets"), exist_ok=True)
    wallpaper().save(os.path.join(ICON, "Assets", "wallpaper.png"))
    with open(os.path.join(ICON, "Assets", "dock.svg"), "w") as f:
        f.write(rounded_svg(BAR_W, BAR_H, 78))
    with open(os.path.join(ICON, "Assets", "tile.svg"), "w") as f:
        f.write(rounded_svg(TILE, TILE, 44))
    with open(os.path.join(ICON, "icon.json"), "w") as f:
        json.dump(icon_json(), f, indent=2)
        f.write("\n")
    menu_bar_template(18, 1).save(os.path.join(RES, "MenuBarIcon.png"))
    menu_bar_template(18, 2).save(os.path.join(RES, "MenuBarIcon@2x.png"))
    print("wrote Resources/AppIcon.icon and MenuBarIcon(@2x).png")


if __name__ == "__main__":
    main()
