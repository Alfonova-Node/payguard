"""PayGuard logo, final geometry: one clean stroke, optically centred check, no artefacts."""
import math
import os
from PIL import Image, ImageDraw

S = 6
BASE = 512
N = BASE * S

INNER = (15, 24, 36)
OUTER = (8, 11, 17)
TEAL = (56, 217, 198)
INK = (240, 247, 250)

OUT = "/root/aevum-payguard/docs/logo"
os.makedirs(OUT, exist_ok=True)


def radial_bg(size, inner=INNER, outer=OUTER):
    img = Image.new("RGB", (size, size), outer)
    px = img.load()
    c = size / 2
    maxd = math.hypot(c, c)
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / maxd
            t = min(1.0, d ** 1.5)
            px[x, y] = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
    return img


def hex_pts(cx, cy, r, flat_top=False):
    off = 0 if flat_top else -90
    return [(cx + r * math.cos(math.radians(60 * k + off)),
             cy + r * math.sin(math.radians(60 * k + off))) for k in range(6)]


def draw_check(d, cx, cy, scale, color, width):
    """Check drawn from three points, optical centre shifted left/down slightly."""
    ox, oy = cx - 0.012 * scale, cy + 0.010 * scale
    a = (ox - 0.150 * scale, oy + 0.010 * scale)
    b = (ox - 0.045 * scale, oy + 0.115 * scale)
    c = (ox + 0.165 * scale, oy - 0.130 * scale)
    d.line([a, b], fill=color, width=width)
    d.line([b, c], fill=color, width=width)
    # round the elbow and endpoints
    r = width / 2
    for p in (a, b, c):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)


def variant_hex(flat_top=False):
    img = radial_bg(N)
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = N / 2
    r = N * 0.360
    pts = hex_pts(cx, cy, r, flat_top)
    # a single stroke, no shadow, no inner outline
    d.line(pts + [pts[0]], fill=TEAL, width=int(N * 0.026), joint="curve")
    draw_check(d, cx, cy, N, INK, int(N * 0.046))
    return img


def variant_coin():
    img = radial_bg(N)
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = N / 2
    R = N * 0.345
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=TEAL, width=int(N * 0.026))
    draw_check(d, cx, cy, N, INK, int(N * 0.046))
    return img


def save(img, name):
    final = img.resize((BASE, BASE), Image.Resampling.LANCZOS)
    p = f"{OUT}/{name}.png"
    final.save(p, "PNG", optimize=True)
    for s in (128, 64, 32):
        final.resize((s, s), Image.Resampling.LANCZOS).save(f"{OUT}/{name}_{s}.png")
    print(p, os.path.getsize(p), "bytes")
    return p


paths = [
    save(variant_hex(False), "pg_hex"),
    save(variant_hex(True), "pg_hexflat"),
    save(variant_coin(), "pg_coin"),
]

# preview: big + 128 + 64 + 32 on one sheet
sheet = Image.new("RGB", (1240, 560), (8, 11, 17))
x = 45
for p in paths:
    im = Image.open(p)
    sheet.paste(im.resize((300, 300), Image.Resampling.LANCZOS), (x, 40))
    sheet.paste(im.resize((64, 64), Image.Resampling.LANCZOS), (x + 20, 380))
    sheet.paste(im.resize((32, 32), Image.Resampling.LANCZOS), (x + 110, 400))
    x += 400
sheet.save(f"{OUT}/preview2.png")
print(f"{OUT}/preview2.png")
