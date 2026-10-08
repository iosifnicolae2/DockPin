"""Draws the DockPin app icon (Resources/AppIcon.icns, AppIcon-1024.png) and the menu-bar template image.
Style: white glossy squircle frame, pastel iridescent "screen" with a small left Dock, and a glossy
black round badge with a white push-pin overlapping the bottom-right corner.
Usage: python3 scripts/make-icon.py   (needs Pillow; macOS iconutil)
"""
import math
import os
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
N = 2048  # drawing size; scaled down at the end for smooth edges
U = N / 1024  # one unit of the 1024 design grid


def mask(box, radius):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).rounded_rectangle([v * U for v in box], radius=radius * U, fill=255)
    return m


def circle_mask(cx, cy, r, blur=0):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse([(cx - r) * U, (cy - r) * U, (cx + r) * U, (cy + r) * U], fill=255)
    return m.filter(ImageFilter.GaussianBlur(blur * U)) if blur else m


def solid(color):
    return Image.new("RGBA", (N, N), color)


def vertical(top, bottom, box):
    """Vertical gradient filling `box` (design units), transparent elsewhere."""
    x0, y0, x1, y1 = [round(v * U) for v in box]
    strip = Image.new("RGBA", (1, y1 - y0))
    for y in range(y1 - y0):
        t = y / max(1, y1 - y0 - 1)
        strip.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    layer.paste(strip.resize((x1 - x0, y1 - y0)), (x0, y0))
    return layer


def iridescent(box):
    """Soft pastel wash: cyan top-left, white-violet centre, pink and warm yellow bottom-right."""
    layer = solid((236, 230, 252, 255))
    blobs = [((250, 240), 330, (150, 222, 255)), ((300, 420), 260, (190, 236, 255)),
             ((560, 470), 280, (240, 232, 255)), ((700, 640), 300, (255, 190, 222)),
             ((480, 760), 220, (250, 214, 240)), ((870, 500), 240, (255, 226, 160)),
             ((560, 880), 230, (255, 222, 170))]
    for (cx, cy), r, color in blobs:
        layer = Image.composite(solid(color + (255,)), layer, circle_mask(cx, cy, r, blur=r * 0.55))
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask(box, SCREEN_RADIUS))
    return out


def drop_shadow(m, offset, blur, alpha):
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shifted = ImageChops.offset(m, 0, round(offset * U)).filter(ImageFilter.GaussianBlur(blur * U))
    shadow.putalpha(shifted.point(lambda v: v * alpha // 255))
    return shadow


def frame(img):
    """Full-bleed white body: macOS 26+ masks it to the system squircle and adds the shadow itself
    (an icon that doesn't fill the canvas gets shrunk onto a grey plate)."""
    box = [0, 0, 1024, 1024]
    img = Image.alpha_composite(img, vertical((255, 255, 255, 255), (230, 233, 240, 255), box))
    return Image.alpha_composite(img, vertical((255, 255, 255, 120), (255, 255, 255, 0), [0, 0, 1024, 380]))


SCREEN = [120, 120, 904, 904]
SCREEN_RADIUS = 150


def screen(img):
    inner = mask(SCREEN, SCREEN_RADIUS)
    # the frame's lip casts a soft inner shadow onto the screen
    img = Image.alpha_composite(img, drop_shadow(inner, 5, 8, 80))
    img = Image.alpha_composite(img, iridescent(SCREEN))
    ImageDraw.Draw(img).rounded_rectangle([v * U for v in SCREEN], radius=SCREEN_RADIUS * U, outline=(255, 255, 255, 210), width=round(3 * U))
    return img


def dock(img):
    """A frosted Dock on the screen's left edge, with four app tiles."""
    bar = [164, 300, 260, 680]
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([v * U for v in bar], radius=34 * U, fill=(255, 255, 255, 170), outline=(255, 255, 255, 235), width=round(3 * U))
    colors = [(64, 156, 255), (52, 199, 89), (255, 159, 10), (255, 79, 140)]
    cx = (bar[0] + bar[2]) / 2
    for i, c in enumerate(colors):
        cy = bar[1] + 60 + i * 87
        d.rounded_rectangle([(cx - 26) * U, (cy - 26) * U, (cx + 26) * U, (cy + 26) * U], radius=12 * U, fill=c + (255,))
    img = Image.alpha_composite(img, drop_shadow(layer.getchannel("A"), 6, 10, 50))
    return Image.alpha_composite(img, layer)


def push_pin(size_px):
    """White push-pin, upright, drawn on its own transparent square of `size_px`."""
    p = Image.new("RGBA", (size_px, size_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(p)
    s = size_px / 100
    white = (255, 255, 255, 255)
    d.rounded_rectangle([30 * s, 6 * s, 70 * s, 18 * s], radius=5 * s, fill=white)       # top cap
    d.polygon([(36 * s, 16 * s), (64 * s, 16 * s), (60 * s, 46 * s), (40 * s, 46 * s)], fill=white)  # body
    d.rounded_rectangle([20 * s, 44 * s, 80 * s, 56 * s], radius=6 * s, fill=white)      # collar
    d.polygon([(47 * s, 55 * s), (53 * s, 55 * s), (50.5 * s, 94 * s), (49.5 * s, 94 * s)], fill=white)  # needle
    return p


def badge(img):
    cx, cy, r = 752, 752, 176
    img = Image.alpha_composite(img, drop_shadow(circle_mask(cx, cy, r), 12, 18, 120))
    # white rim
    rim = vertical((255, 255, 255, 255), (222, 226, 234, 255), [cx - r, cy - r, cx + r, cy + r])
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), circle_mask(cx, cy, r)))
    img = Image.alpha_composite(img, rim)
    # glossy black lens with concentric rings
    lens_r = r - 18
    lens = vertical((46, 48, 56, 255), (6, 6, 9, 255), [cx - lens_r, cy - lens_r, cx + lens_r, cy + lens_r])
    lens.putalpha(ImageChops.multiply(lens.getchannel("A"), circle_mask(cx, cy, lens_r)))
    img = Image.alpha_composite(img, lens)
    d = ImageDraw.Draw(img)
    for rr, color in ((lens_r - 22, (70, 72, 82, 255)), (lens_r - 58, (30, 31, 38, 255))):
        d.ellipse([(cx - rr) * U, (cy - rr) * U, (cx + rr) * U, (cy + rr) * U], outline=color, width=round(3 * U))
    # highlight
    hl = Image.new("L", (N, N), 0)
    ImageDraw.Draw(hl).ellipse([(cx - 105) * U, (cy - 128) * U, (cx + 30) * U, (cy - 50) * U], fill=120)
    hl = ImageChops.multiply(hl.filter(ImageFilter.GaussianBlur(16 * U)), circle_mask(cx, cy, lens_r))
    shine = solid((255, 255, 255, 255))
    shine.putalpha(hl)
    img = Image.alpha_composite(img, shine)
    # the pin, tilted like it was just pushed in
    pin_px = round(190 * U)
    pin = push_pin(pin_px).rotate(-32, resample=Image.BICUBIC, expand=False)
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    layer.paste(pin, (round((cx - 95 + 6) * U), round((cy - 95 + 4) * U)), pin)
    return Image.alpha_composite(img, layer)


def app_icon():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for step in (frame, screen, dock, badge):
        img = step(img)
    return img.resize((1024, 1024), Image.LANCZOS)


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template: a screen with a Dock on its left edge."""
    px = pt * scale * 4
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = px / 18
    d.rounded_rectangle([1.5 * u, 3.5 * u, 16.5 * u, 14 * u], radius=2.2 * u, outline=(0, 0, 0, 255), width=int(1.5 * u))
    d.rounded_rectangle([3.6 * u, 5.6 * u, 6.2 * u, 11.9 * u], radius=1 * u, fill=(0, 0, 0, 255))
    d.rounded_rectangle([7 * u, 15 * u, 11 * u, 16.4 * u], radius=0.6 * u, fill=(0, 0, 0, 255))
    return img.resize((pt * scale, pt * scale), Image.LANCZOS)


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
    menu_bar_template(18, 1).save(os.path.join(RES, "MenuBarIcon.png"))
    menu_bar_template(18, 2).save(os.path.join(RES, "MenuBarIcon@2x.png"))
    print("wrote Resources/AppIcon.icns, AppIcon-1024.png, MenuBarIcon(@2x).png")


if __name__ == "__main__":
    main()
