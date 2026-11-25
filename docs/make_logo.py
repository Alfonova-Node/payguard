"""Generate PayGuard logo variants: square 512px, crisp at small sizes."""
import math
from PIL import Image, ImageDraw, ImageFont

S = 4              # supersample
BASE = 512
N = BASE * S

BG_DARK = (9, 13, 19)
TEAL = (45, 212, 191)
TEAL_D = (13, 148, 136)
GREEN = (52, 211, 153)
INK = (237, 245, 248)
F_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def radial_bg(size, inner=(17, 26, 38), outer=BG_DARK):
    img = Image.new("RGB", (size, size), outer)
    px = img.load()
    c = size / 2
    maxd = math.hypot(c, c)
    for y in range(0, size, 2):
        for x in range(0, size, 2):
            d = math.hypot(x - c, y - c) / maxd
            t = min(1.0, d ** 1.35)
            col = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
            px[x, y] = col
            if x + 1 < size:
                px[x + 1, y] = col
            if y + 1 < size:
                px[x, y + 1] = col
                if x + 1 < size:
                    px[x + 1, y + 1] = col
    return img


def hexagon(draw, cx, cy, r, **kw):
    pts = []
    for k in range(6):
        a = math.radians(60 * k - 90)
        pts.append((cx + r * math.cos(a) * 1.0, cy + r * math.sin(a) * 0.98))
    draw.polygon(pts, **kw)
    return pts


def check(draw, cx, cy, w, h, color, width):
    draw.line([(cx - w / 2, cy + h * 0.05), (cx - w * 0.12, cy + h * 0.42)], fill=color, width=width)
    draw.line([(cx - w * 0.12, cy + h * 0.42), (cx + w / 2, cy - h * 0.42)], fill=color, width=width)


# ---------- variant A: hex shield + check ----------
def variant_a():
    img = radial_bg(N)
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = N / 2
    r = N * 0.33
    hexagon(d, cx, cy + N * 0.006, r * 1.09, fill=(45, 212, 191, 26))
    hexagon(d, cx, cy, r, outline=TEAL, width=int(N * 0.021))
    hexagon(d, cx, cy, r * 0.855, outline=(45, 212, 191, 90), width=int(N * 0.008))
    check(d, cx, cy, r * 0.95, r * 0.9, INK, int(N * 0.038))
    return img


# ---------- variant B: PG monogram in rounded square ----------
def variant_b():
    img = radial_bg(N)
    d = ImageDraw.Draw(img, "RGBA")
    pad = N * 0.13
    d.rounded_rectangle([pad, pad, N - pad, N - pad], radius=N * 0.09,
                        outline=TEAL, width=int(N * 0.021))
    f = ImageFont.truetype(F_BOLD, int(N * 0.30))
    txt = "PG"
    tw = d.textlength(txt, font=f)
    d.text(((N - tw) / 2, N * 0.30), txt, font=f, fill=INK)
    # underline slash
    d.line([(N * 0.30, N * 0.685), (N * 0.70, N * 0.685)], fill=TEAL, width=int(N * 0.019))
    check(d, N * 0.5, N * 0.78, N * 0.16, N * 0.13, GREEN, int(N * 0.021))
    return img


# ---------- variant C: coin + check ----------
def variant_c():
    img = radial_bg(N)
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = N / 2
    R = N * 0.315
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(45, 212, 191, 22), outline=TEAL, width=int(N * 0.022))
    d.ellipse([cx - R * 0.80, cy - R * 0.80, cx + R * 0.80, cy + R * 0.80],
              outline=(45, 212, 191, 110), width=int(N * 0.009))
    check(d, cx, cy, R * 1.0, R * 0.95, INK, int(N * 0.040))
    # gate bars left+right = "pay guard"
    for sx in (-1, 1):
        x0 = cx + sx * R * 1.22
        d.line([(x0, cy - R * 0.62), (x0, cy + R * 0.62)], fill=(94, 234, 212, 150), width=int(N * 0.014))
    return img


outs = []
for name, fn in [("logo_a", variant_a), ("logo_b", variant_b), ("logo_c", variant_c)]:
    big = fn()
    final = big.resize((BASE, BASE), Image.Resampling.LANCZOS)
    p = f"/root/aevum-payguard/docs/logo/{name}.png"
    import os
    os.makedirs("/root/aevum-payguard/docs/logo", exist_ok=True)
    final.save(p, "PNG", optimize=True)
    small = final.resize((64, 64), Image.Resampling.LANCZOS)
    small.save(f"/root/aevum-payguard/docs/logo/{name}_64.png")
    outs.append(p)
    print(p)

# preview sheet with small-size test
sheet = Image.new("RGB", (1200, 460), BG_DARK)
x = 40
for p in outs:
    im = Image.open(p)
    sheet.paste(im.resize((300, 300), Image.Resampling.LANCZOS), (x, 40))
    tiny = im.resize((72, 72), Image.Resampling.LANCZOS)
    sheet.paste(tiny, (x + 110, 370))
    x += 390
sheet.save("/root/aevum-payguard/docs/logo/preview.png")
print("/root/aevum-payguard/docs/logo/preview.png")
