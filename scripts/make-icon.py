"""Draws the DockPin app icon (Resources/AppIcon.icns, AppIcon-1024.png, AppIcon-preview.png) and the
menu-bar template image.
Style: one simple element on a vivid violet square (full-bleed: macOS 26+ masks it to its squircle): the
Dock, standing up as on a left edge, a frosted glass bar holding four colourful app tiles.
The menu-bar glyph is the same Dock in one colour.
Usage: python3 scripts/make-icon.py   (needs Pillow; macOS iconutil)
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
N = 2048  # drawing size; scaled down at the end for smooth edges
U = N / 1024  # one unit of the 1024 design grid

WHITE = (255, 255, 255, 255)
BAR = (6.75, 1.4, 11.25, 16.6)  # the Dock on the 18-unit grid (the menu-bar size in points)
TILES = (2.2, 5.77, 9.33, 12.9)  # tops of its four app tiles, each 2.9 units square
TILE_COLORS = [((90, 200, 255), (0, 122, 255)),   # blue
               ((120, 236, 120), (36, 190, 70)),  # green
               ((255, 214, 80), (255, 140, 0)),   # orange
               ((255, 120, 180), (240, 40, 110))]  # pink


def gradient(size, top, bottom, diagonal=False):
    """`size`-square RGBA image fading from `top` to `bottom`, downwards or towards the bottom-right."""
    ramp = Image.linear_gradient("L").resize((size, size))
    if diagonal:
        ramp = Image.blend(ramp, ramp.rotate(90), 0.5)
    return Image.composite(Image.new("RGBA", (size, size), bottom + (255,)),
                           Image.new("RGBA", (size, size), top + (255,)), ramp)


def background():
    """Vivid violet to indigo, with a soft glow at the top."""
    img = gradient(N, (150, 95, 255), (70, 40, 225), diagonal=True)
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-0.2 * N, -0.55 * N, 1.2 * N, 0.45 * N], fill=(255, 255, 255, 60))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(N * 0.12)))
    return img


def boxer(unit, size):
    off = (size - 18 * unit) / 2
    return lambda x0, y0, x1, y1: [off + x0 * unit, off + y0 * unit, off + x1 * unit, off + y1 * unit]


def shape(size, box, radius, fill=255):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=fill)
    return m


def dock(unit, size):
    """The Dock as on macOS, standing up as on a left edge: a frosted glass bar holding four colourful app
    tiles. Returns an RGBA layer of `size`."""
    box = boxer(unit, size)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bar = shape(size, box(*BAR), 1.65 * unit)
    shadow = Image.new("RGBA", (size, size), (25, 10, 90, 0))
    shadow.putalpha(bar.point(lambda v: v * 110 // 255).transform((size, size), Image.AFFINE, (1, 0, 0, 0, 1, -0.45 * unit)))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(0.7 * unit)))
    glass = gradient(size, (255, 255, 255), (225, 220, 255))
    glass.putalpha(bar.point(lambda v: v * 92 // 255))  # frosted: the violet shows through
    layer.alpha_composite(glass)
    rim = Image.new("RGBA", (size, size), WHITE)
    rim.putalpha(ImageChops.subtract(bar, shape(size, box(BAR[0] + 0.14, BAR[1] + 0.14, BAR[2] - 0.14, BAR[3] - 0.14),
                                                     1.51 * unit)).point(lambda v: v * 170 // 255))
    layer.alpha_composite(rim)
    for top, (light, dark) in zip(TILES, TILE_COLORS):
        tile_box = box(7.55, top, 10.45, top + 2.9)
        mask = shape(size, tile_box, 0.8 * unit)
        tile_shadow = Image.new("RGBA", (size, size), (20, 0, 60, 0))
        tile_shadow.putalpha(mask.point(lambda v: v * 80 // 255).transform((size, size), Image.AFFINE, (1, 0, 0, 0, 1, -0.18 * unit)))
        layer.alpha_composite(tile_shadow.filter(ImageFilter.GaussianBlur(0.22 * unit)))
        tile = gradient(size, light, dark)
        tile.putalpha(mask)
        layer.alpha_composite(tile)
        x0, y0, x1, y1 = tile_box  # gloss on the upper half
        gloss = Image.new("RGBA", (size, size), WHITE)
        gloss.putalpha(ImageChops.multiply(mask, shape(size, [x0, y0, x1, y0 + (y1 - y0) * 0.5], 0.8 * unit,
                                                       fill=26)))
        layer.alpha_composite(gloss)
    return layer


def template_glyph(unit, size):
    """One-colour version for the menu bar: a see-through bar and four solid tiles."""
    box = boxer(unit, size)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box(*BAR), radius=1.65 * unit, fill=(0, 0, 0, 95))
    for top in TILES:
        draw.rounded_rectangle(box(7.55, top, 10.45, top + 2.9), radius=0.8 * unit, fill=(0, 0, 0, 255))
    return layer


def app_icon():
    img = background()
    img.alpha_composite(dock(840 * U / 18, N))  # the Dock spans about 70% of the icon's height
    return img.resize((1024, 1024), Image.LANCZOS)


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template image of the same Dock."""
    px = pt * scale * 4
    return template_glyph(px / 18, px).resize((pt * scale, pt * scale), Image.LANCZOS)


def masked_preview(master):
    """How macOS shows the icon (squircle mask + shadow), for the README and release page."""
    size, inset = 1024, 100
    art = master.resize((size - 2 * inset, size - 2 * inset), Image.LANCZOS)
    m = Image.new("L", art.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, art.size[0] - 1, art.size[1] - 1], radius=art.size[0] * 0.225, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("L", (size, size), 0)
    shadow.paste(m.point(lambda v: v * 90 // 255), (inset, inset + 12))
    out.paste((0, 0, 0, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(18)))
    out.paste(art, (inset, inset), m)
    return out


def main():
    master = app_icon()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for base in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
                master.resize((base * scale, base * scale), Image.LANCZOS).save(os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(RES, "AppIcon.icns")], check=True)
    master.save(os.path.join(RES, "AppIcon-1024.png"))
    masked_preview(master).save(os.path.join(RES, "AppIcon-preview.png"))
    menu_bar_template(18, 1).save(os.path.join(RES, "MenuBarIcon.png"))
    menu_bar_template(18, 2).save(os.path.join(RES, "MenuBarIcon@2x.png"))
    print("wrote Resources/AppIcon.icns, AppIcon-1024.png, AppIcon-preview.png, MenuBarIcon(@2x).png")


if __name__ == "__main__":
    main()
