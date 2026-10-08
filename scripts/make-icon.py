"""Draws the DockPin app icon (Resources/AppIcon.icns) and the menu-bar template image.
Usage: python3 scripts/make-icon.py   (needs Pillow; macOS iconutil)
"""
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
S = 4  # supersampling


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        g.putpixel((0, y), lerp(top, bottom, y / (h - 1)))
    return g.resize((w, h))


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def monitor(canvas, box, screen_top, screen_bottom, bezel, dock=False, stand=True):
    d = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = box
    w = x1 - x0
    if stand:
        neck_w = w * 0.12
        d.rounded_rectangle([x0 + w / 2 - neck_w / 2, y1 - 10 * S, x0 + w / 2 + neck_w / 2, y1 + w * 0.13], radius=6 * S, fill=bezel)
        d.rounded_rectangle([x0 + w * 0.3, y1 + w * 0.12, x1 - w * 0.3, y1 + w * 0.16], radius=8 * S, fill=bezel)
    d.rounded_rectangle(box, radius=w * 0.06, fill=bezel)
    inset = w * 0.035
    screen = [x0 + inset, y0 + inset, x1 - inset, y1 - inset]
    grad = vertical_gradient((int(screen[2] - screen[0]), int(screen[3] - screen[1])), screen_top, screen_bottom)
    canvas.paste(grad, (int(screen[0]), int(screen[1])),
                 rounded_mask(grad.size, [0, 0, grad.size[0] - 1, grad.size[1] - 1], w * 0.035))
    if dock:
        sx0, sy0, sx1, sy1 = screen
        sh = sy1 - sy0
        bar = [sx0 + sh * 0.06, sy0 + sh * 0.14, sx0 + sh * 0.06 + sh * 0.2, sy1 - sh * 0.14]
        d.rounded_rectangle(bar, radius=sh * 0.07, fill=(255, 255, 255, 235))
        colors = [(52, 199, 89), (255, 159, 10), (10, 132, 255), (191, 90, 242)]
        n = len(colors)
        bx0, by0, bx1, by1 = bar
        cell = (by1 - by0) / n
        r = (bx1 - bx0) * 0.3
        for i, c in enumerate(colors):
            cx, cy = (bx0 + bx1) / 2, by0 + cell * (i + 0.5)
            d.rounded_rectangle([cx - r, cy - r, cx + r, cy + r], radius=r * 0.45, fill=c)
        return bar
    return None


def pin(canvas, tip, size):
    """A red push-pin whose needle ends at `tip`, leaning right."""
    d = ImageDraw.Draw(canvas)
    tx, ty = tip
    head_c = (tx + size * 0.55, ty - size * 0.95)
    d.line([tip, head_c], fill=(200, 200, 210), width=int(size * 0.09))
    r = size * 0.36
    d.ellipse([head_c[0] - r, head_c[1] - r, head_c[0] + r, head_c[1] + r], fill=(235, 55, 65))
    hr = r * 0.38
    d.ellipse([head_c[0] - r * 0.45 - hr / 2, head_c[1] - r * 0.5 - hr / 2, head_c[0] - r * 0.45 + hr / 2, head_c[1] - r * 0.5 + hr / 2],
              fill=(255, 150, 155))


def app_icon(px=1024):
    size = (px * S, px * S)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    m = 100 * S * px / 1024
    tile = [m, m, size[0] - m, size[1] - m]
    radius = (tile[2] - tile[0]) * 0.225
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([tile[0], tile[1] + 12 * S, tile[2], tile[3] + 12 * S], radius=radius, fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(14 * S)))
    bg = vertical_gradient(size, (38, 48, 92), (14, 18, 38)).convert("RGBA")
    img.paste(bg, (0, 0), rounded_mask(size, tile, radius))

    tw = tile[2] - tile[0]
    cx, cy = size[0] / 2, tile[1] + tw * 0.47
    side_w, side_h = tw * 0.25, tw * 0.25 * 9 / 16
    for sign in (-1, 1):
        sx = cx + sign * tw * 0.335
        sy = cy + tw * 0.03
        monitor(img, [sx - side_w / 2, sy - side_h / 2, sx + side_w / 2, sy + side_h / 2],
                (92, 108, 160), (60, 72, 116), (150, 158, 182))
    cw, ch = tw * 0.52, tw * 0.52 * 9 / 16
    bar = monitor(img, [cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2],
                  (96, 170, 255), (54, 92, 220), (232, 236, 245), dock=True)
    pin(img, ((bar[0] + bar[2]) / 2, bar[1] + (bar[3] - bar[1]) * 0.08), tw * 0.16)
    return img.resize((px, px), Image.LANCZOS)


def menu_bar_template(pt=18, scale=2):
    """Black-on-transparent template: a screen with a Dock on its left edge."""
    px = pt * scale * S
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = px / 18
    d.rounded_rectangle([1.5 * u, 3.5 * u, 16.5 * u, 14 * u], radius=2.2 * u, outline=(0, 0, 0, 255), width=int(1.5 * u))
    d.rounded_rectangle([3.6 * u, 5.6 * u, 6.2 * u, 11.9 * u], radius=1 * u, fill=(0, 0, 0, 255))
    d.rounded_rectangle([7 * u, 15 * u, 11 * u, 16.4 * u], radius=0.6 * u, fill=(0, 0, 0, 255))
    return img.resize((pt * scale, pt * scale), Image.LANCZOS)


def main():
    master = app_icon(1024)
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
