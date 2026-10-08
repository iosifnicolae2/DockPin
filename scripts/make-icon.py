"""Draws the DockPin app icon (Resources/AppIcon.icns, AppIcon-1024.png, AppIcon-preview.png) and the
menu-bar template image.
Style: flat. A solid indigo square with a soft top-to-bottom gradient (full-bleed: macOS 26+ masks it to
its squircle) and one white glyph: a monitor whose Dock sits on its left edge. The menu-bar glyph is the
same drawing in black.
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


def glyph(draw, unit, origin=(0, 0), color=WHITE, cutout=None):
    """A monitor with the Dock on its left edge, on an 18-unit grid (the menu-bar size in points).
    `cutout` is the colour of the Dock's app dots; None leaves the Dock solid."""
    ox, oy = origin

    def box(x0, y0, x1, y1):
        return [ox + x0 * unit, oy + y0 * unit, ox + x1 * unit, oy + y1 * unit]

    draw.rounded_rectangle(box(1.5, 3.2, 16.5, 13.4), radius=2.0 * unit, outline=color, width=round(1.5 * unit))
    draw.rounded_rectangle(box(3.7, 5.3, 6.3, 11.3), radius=1.0 * unit, fill=color)
    if cutout:
        for cy in (6.55, 8.3, 10.05):
            draw.rounded_rectangle(box(4.45, cy - 0.5, 5.55, cy + 0.6), radius=0.3 * unit, fill=cutout)
    draw.rounded_rectangle(box(8.2, 13.4, 9.8, 15.4), radius=0, fill=color)
    draw.rounded_rectangle(box(5.8, 15.0, 12.2, 16.4), radius=0.7 * unit, fill=color)


def app_icon():
    img = background()
    unit = 640 * U / 18  # the glyph spans about 62% of the icon
    origin = ((N - 18 * unit) / 2, (N - 18 * unit) / 2 + 8 * U)
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(shadow), unit, (origin[0], origin[1] + 14 * U), color=(30, 20, 120, 70))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18 * U)))
    glyph(ImageDraw.Draw(img), unit, origin, cutout=BOTTOM + (255,))
    return img.resize((1024, 1024), Image.LANCZOS)


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template image of the same glyph."""
    px = pt * scale * 4
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(img), px / 18, color=(0, 0, 0, 255))
    return img.resize((pt * scale, pt * scale), Image.LANCZOS)


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
