"""Draws the DockPin app icon (Resources/AppIcon.icns, AppIcon-1024.png, AppIcon-preview.png) and the
menu-bar template image.
Style: flat. A solid indigo square with a soft top-to-bottom gradient (full-bleed: macOS 26+ masks it to
its squircle) and one white glyph: the Dock, standing up as on a left edge: a see-through bar holding three app tiles.
The menu-bar glyph is the same drawing in black.
Usage: python3 scripts/make-icon.py   (needs Pillow; macOS iconutil)
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
N = 2048  # drawing size; scaled down at the end for smooth edges
U = N / 1024  # one unit of the 1024 design grid

TOP, BOTTOM = (112, 112, 242), (80, 76, 222)  # indigo, a touch lighter at the top
WHITE = (255, 255, 255, 255)


def background():
    strip = Image.new("RGBA", (1, N))
    for y in range(N):
        t = y / (N - 1)
        strip.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,))
    return strip.resize((N, N))


def glyph(unit, size, color=WHITE):
    """The Dock itself, standing up as it does on the left edge: a see-through rounded bar holding three
    solid app tiles, on an 18-unit grid (the menu-bar size in points). Returns an RGBA layer of `size`."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    off = (size - 18 * unit) / 2

    def box(x0, y0, x1, y1):
        return [off + x0 * unit, off + y0 * unit, off + x1 * unit, off + y1 * unit]

    bar = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(bar).rounded_rectangle(box(5.8, 1.4, 12.2, 16.6), radius=2.2 * unit, fill=color[:3] + (95,))
    layer.alpha_composite(bar)  # the Dock's glass: the background shows through
    for top in (2.5, 7.0, 11.5):  # three app tiles
        draw.rounded_rectangle(box(7.0, top, 11.0, top + 4.0), radius=1.0 * unit, fill=color)
    return layer


def app_icon():
    img = background()
    unit = 760 * U / 18  # the Dock spans about 75% of the icon's height
    art = glyph(unit, N)
    shadow = Image.new("RGBA", (N, N), (30, 20, 120, 0))
    shadow.putalpha(art.getchannel("A").point(lambda v: v * 70 // 255))
    shadow = shadow.transform((N, N), Image.AFFINE, (1, 0, 0, 0, 1, -16 * U))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20 * U)))
    img.alpha_composite(art)
    return img.resize((1024, 1024), Image.LANCZOS)


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template image of the same glyph."""
    px = pt * scale * 4
    return glyph(px / 18, px, color=(0, 0, 0, 255)).resize((pt * scale, pt * scale), Image.LANCZOS)


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
