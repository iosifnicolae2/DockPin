"""Draws docs/dockpin-screens.png: three monitors in a row and a laptop, the Dock on the center one.
An illustration, not a screenshot, so nothing personal is in it.
Usage: python3 scripts/make-readme-image.py   (needs Pillow)
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 2  # drawn at 2x, scaled down for smooth edges
W, H = 1600, 670


def wallpaper(size, tint):
    """Soft pastel wash like the app icon's screen; `tint` shifts it per display."""
    w, h = size
    img = Image.new("RGB", (w, h), (236, 230, 252))
    d = ImageDraw.Draw(img)
    blobs = [((0.15, 0.1), 0.55, (150, 222, 255)), ((0.55, 0.45), 0.45, (240, 232, 255)),
             ((0.85, 0.75), 0.5, (255, 196, 224)), ((0.4, 0.95), 0.45, (255, 226, 170))]
    for (fx, fy), fr, color in blobs:
        r = fr * w
        c = tuple(min(255, max(0, v + tint)) for v in color)
        d.ellipse([fx * w - r, fy * h - r, fx * w + r, fy * h + r], fill=c)
    return img.filter(ImageFilter.GaussianBlur(w * 0.12))


def monitor(canvas, x, y, w, h, tint, dock=False, menu_bar=False):
    d = ImageDraw.Draw(canvas)
    bezel = 10 * S
    # stand
    d.rounded_rectangle([x + w * 0.44, y + h, x + w * 0.56, y + h + 46 * S], radius=6 * S, fill=(196, 200, 210))
    d.rounded_rectangle([x + w * 0.32, y + h + 40 * S, x + w * 0.68, y + h + 52 * S], radius=6 * S, fill=(176, 180, 192))
    # body + screen
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 10 * S, x + w, y + h + 10 * S], radius=18 * S, fill=(0, 0, 0, 60))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16 * S)))
    d.rounded_rectangle([x, y, x + w, y + h], radius=18 * S, fill=(30, 31, 36))
    sx, sy, sw, sh = x + bezel, y + bezel, w - 2 * bezel, h - 2 * bezel
    screen = wallpaper((int(sw), int(sh)), tint).convert("RGBA")
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=10 * S, fill=255)
    canvas.paste(screen, (int(sx), int(sy)), mask)
    if menu_bar:
        bar = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(bar).rectangle([sx, sy, sx + sw, sy + 12 * S], fill=(255, 255, 255, 110))
        canvas.alpha_composite(bar)
    if dock:
        bar_w = sh * 0.16
        top, bottom = sy + sh * 0.18, sy + sh * 0.86
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.rounded_rectangle([sx + 8 * S, top, sx + 8 * S + bar_w, bottom], radius=bar_w * 0.35,
                             fill=(255, 255, 255, 175), outline=(255, 255, 255, 235), width=2 * S)
        colors = [(64, 156, 255), (52, 199, 89), (255, 159, 10), (255, 79, 140), (175, 82, 222), (90, 200, 250)]
        tile = bar_w * 0.62
        gap = (bottom - top - len(colors) * tile) / (len(colors) + 1)
        cx = sx + 8 * S + bar_w / 2
        for i, c in enumerate(colors):
            ty = top + gap + i * (tile + gap)
            ld.rounded_rectangle([cx - tile / 2, ty, cx + tile / 2, ty + tile], radius=tile * 0.24, fill=c + (255,))
        canvas.alpha_composite(layer)


def laptop(canvas, x, y, w, h):
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([x, y, x + w, y + h], radius=12 * S, fill=(30, 31, 36))
    b = 8 * S
    screen = wallpaper((int(w - 2 * b), int(h - 2 * b)), -6).convert("RGBA")
    canvas.paste(screen, (int(x + b), int(y + b)))
    d.rounded_rectangle([x - w * 0.08, y + h, x + w * 1.08, y + h + 14 * S], radius=7 * S, fill=(196, 200, 210))


def main():
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    mw, mh = 470 * S, 265 * S
    gap = 14 * S
    top = 40 * S
    left = (W * S - 3 * mw - 2 * gap) / 2
    for i in range(3):
        monitor(img, left + i * (mw + gap), top, mw, mh, tint=(-8, 0, 8)[i], dock=(i == 1), menu_bar=(i == 1))
    lw, lh = 330 * S, 205 * S
    laptop(img, (W * S - lw) / 2, top + mh + 110 * S, lw, lh)
    out = os.path.join(ROOT, "docs", "dockpin-screens.png")
    img.resize((W, H), Image.LANCZOS).save(out)
    print("wrote docs/dockpin-screens.png")


if __name__ == "__main__":
    main()
