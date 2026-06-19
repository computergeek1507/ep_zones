"""Generate the EP Zones app icon: a radar plane with a detection zone and a
tracked target, in the app's cyan-on-navy theme.

Outputs two PNGs under assets/icon/:
  ep_zones_icon.png     1024x1024 master (rounded navy background) — used for
                        Windows / Web / iOS / legacy Android.
  ep_zones_icon_fg.png  1024x1024 transparent foreground (artwork only, scaled
                        into the adaptive safe zone) — Android adaptive icon.

Run:  python tool/make_icon.py
"""

import os
from PIL import Image, ImageDraw

SS = 4  # supersample factor for anti-aliasing
SIZE = 1024
N = SIZE * SS

CYAN = (53, 194, 240)
AMBER = (255, 193, 7)
TARGET = (255, 82, 82)
WHITE = (255, 255, 255)
BG_TOP = (12, 20, 30)
BG_BOT = (18, 33, 50)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bot):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = c
    return img


def draw_artwork(draw, cx, cy, scale):
    """Draw the radar artwork centred at (cx, cy), sized by `scale` (full N)."""
    def S(v):
        return v * scale

    # Sensor sits near the top of the artwork; fan sweeps downward.
    sx, sy = cx, cy - S(0.36)
    R = S(0.78)

    # Detection fan (sector, ~±55° around straight down = 90°).
    fan = [sx - R, sy - R, sx + R, sy + R]
    draw.pieslice(fan, 35, 145, fill=CYAN + (28,))
    # Fan edges + concentric range arcs.
    for rr in (0.40, 0.62, 0.84):
        r = R * rr
        draw.arc([sx - r, sy - r, sx + r, sy + r], 35, 145,
                 fill=CYAN + (150,), width=round(S(0.012)))
    for ang_deg in (35, 145):
        import math
        a = math.radians(ang_deg)
        draw.line([sx, sy, sx + R * math.cos(a), sy + R * math.sin(a)],
                  fill=CYAN + (120,), width=round(S(0.010)))

    # Detection zone rectangle.
    zw, zh = S(0.52), S(0.42)
    zx, zy = cx + S(0.06), cy + S(0.16)
    zone = [zx - zw / 2, zy - zh / 2, zx + zw / 2, zy + zh / 2]
    draw.rectangle(zone, fill=CYAN + (45,), outline=CYAN + (255,),
                   width=round(S(0.028)))
    # Corner handles.
    h = S(0.030)
    for hx in (zone[0], zone[2]):
        for hy in (zone[1], zone[3]):
            draw.ellipse([hx - h, hy - h, hx + h, hy + h], fill=WHITE)

    # Tracked target dot inside the zone.
    tx, ty = zx - S(0.12), zy - S(0.04)
    tr = S(0.075)
    draw.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], fill=TARGET)
    draw.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], outline=WHITE,
                 width=round(S(0.018)))

    # Sensor marker on top.
    s = S(0.055)
    draw.ellipse([sx - s, sy - s, sx + s, sy + s], fill=AMBER)


def render(with_bg):
    base = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    if with_bg:
        bg = vertical_gradient(N, BG_TOP, BG_BOT).convert("RGBA")
        bg.putalpha(rounded_mask(N, round(N * 0.22)))
        base.alpha_composite(bg)

    overlay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # Full-bleed for the master, scaled into the safe zone for adaptive fg.
    scale = N if with_bg else N * 0.66
    draw_artwork(d, N // 2, N // 2, scale)
    base.alpha_composite(overlay)

    return base.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    render(True).save(os.path.join(OUT_DIR, "ep_zones_icon.png"))
    render(False).save(os.path.join(OUT_DIR, "ep_zones_icon_fg.png"))
    print("Wrote ep_zones_icon.png and ep_zones_icon_fg.png to", OUT_DIR)


if __name__ == "__main__":
    main()
