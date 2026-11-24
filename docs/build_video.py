"""Build the PayGuard demo video from real explorer screenshots + TTS narration."""
import json
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = "/root/aevum-payguard"
SHOTS = f"{ROOT}/docs/shots"
VO = f"{ROOT}/docs/vo"
BUILD = f"{ROOT}/docs/build"
FF = "/root/.hermes/tools/ffmpeg-9.0.1-linux-x64/bin/ffmpeg"
FP = "/root/.hermes/tools/ffmpeg-9.0.1-linux-x64/bin/ffprobe"

W, H = 1920, 1080
BG = (13, 17, 23)
INK = (230, 237, 243)
DIM = (139, 148, 158)
GREEN = (63, 185, 80)
AMBER = (240, 136, 62)

F_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
F_BODY = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
F_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

os.makedirs(BUILD, exist_ok=True)


def font(path, size):
    return ImageFont.truetype(path, size)


def wrap(draw, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def card(name, title, subtitle, footer, accent=GREEN, bullets=None):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # left accent rule
    d.rectangle([90, 250, 96, 250 + 300], fill=accent)
    d.text((130, 240), title, font=font(F_BOLD, 108), fill=INK)
    if subtitle:
        d.text((132, 380), subtitle, font=font(F_BODY, 40), fill=DIM)
    y = 470
    if bullets:
        for b in bullets:
            d.ellipse([134, y + 16, 148, y + 30], fill=accent)
            for line in wrap(d, b, font(F_BODY, 36), 1500):
                d.text((170, y), line, font=font(F_BODY, 36), fill=INK)
                y += 54
            y += 22
    if footer:
        d.text((132, 940), footer, font=font(F_MONO, 30), fill=DIM)
    d.text((1700, 990), "PAYGUARD", font=font(F_BOLD, 26), fill=(48, 54, 61))
    p = f"{BUILD}/{name}.png"
    img.save(p)
    return p


def shot(name, src, caption, accent=GREEN):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    s = Image.open(src).convert("RGB")
    # crop to a 16:9-ish window, then fit
    max_w, max_h = W - 200, 700
    ratio = min(max_w / s.width, max_h / s.height)
    s = s.resize((int(s.width * ratio), int(s.height * ratio)), Image.Resampling.LANCZOS)
    img.paste(s, ((W - s.width) // 2, 150))
    d.rectangle([(W - s.width) // 2, 150, (W + s.width) // 2, 150 + s.height], outline=(48, 54, 61), width=3)
    d.rectangle([0, 900, W, H], fill=(1, 4, 9))
    d.rectangle([100, 930, 106, 990], fill=accent)
    y = 936
    for line in wrap(d, caption, font(F_BODY, 38), 1560):
        d.text((140, y), line, font=font(F_BODY, 38), fill=INK)
        y += 52
    d.text((1700, 1020), "PAYGUARD", font=font(F_BOLD, 24), fill=(48, 54, 61))
    p = f"{BUILD}/{name}.png"
    img.save(p)
    return p


def dur(path):
    out = subprocess.run([FP, "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nk=1:nw=1", path], capture_output=True, text=True).stdout
    return float(out.strip())


segments = [
    ("s1", card("c_title", "PayGuard",
                "Agent payments yang tidak bisa membayar orang yang salah",
                "Aevum Testnet · chain 44005 · tUSD8 · blok 4.041.545",
                bullets=["Confirmation of Payee  +  spend envelope berskala sesi"])),
    ("s2", shot("c_registry", f"{SHOTS}/01_registry.png",
                "PayeeRegistry 0x5246b48c… — bytecode terverifikasi, bisa dibaca siapa saja")),
    ("s3", shot("c_reg_tx", f"{SHOTS}/02_reg_tx.png",
                "payee mendaftarkan namanya sendiri — owner tidak punya fungsi menempelkan nama")),
    ("s4", shot("c_pay_tx", f"{SHOTS}/03_pay_tx.png",
                "1,5 tUSD8 terbayar oleh agen: status Success, blok 4.041.545, gas 0,000000000001 QDAY")),
    ("s5", shot("c_block_tx", f"{SHOTS}/04_block_tx.png",
                "penolakan tercatat on-chain lewat logBlocked — bukan log lokal yang bisa diedit", accent=AMBER)),
    ("s6", shot("c_envelope", f"{SHOTS}/05_envelope.png",
                "plafon 2 tUSD8/tx · 4 tUSD8/hari · penghitung 1 pembayaran : 3 penolakan")),
    ("s7", card("c_security", "Kenapa tidak bisa dibobol", None,
                "github.com/Alfonova-Node/payguard",
                bullets=["previewPay di-scope ke msg.sender — tidak bisa berbohong soal limit",
                         "pemakaian harian per (agen, hari) — rotate sesi tidak mereset plafon",
                         "setiap penolakan menulis state ke chain",
                         "tidak ada kunci di dalam repo"])),
    ("s8", card("c_close", "PayGuard", "agen yang tidak bisa salah bayar",
                "github.com/Alfonova-Node/payguard")),
]

parts = []
total = 0.0
for name, img in segments:
    audio = f"{VO}/{name}.ogg"
    d = dur(audio)
    total += d
    out = f"{BUILD}/{name}.mp4"
    cmd = [FF, "-y", "-loop", "1", "-framerate", "30", "-i", img, "-i", audio,
           "-filter_complex",
           "[0:v]scale=1920:1080,format=yuv420p,fade=t=in:st=0:d=0.35[v]",
           "-map", "[v]", "-map", "1:a",
           "-af", "apad=pad_dur=0.7",
           "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
           "-c:a", "aac", "-b:a", "128k", "-shortest", out]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("FFMPEG FAIL", name, r.stderr[-600:])
        raise SystemExit(1)
    parts.append(out)
    print(f"{name}  {d:5.1f}s  {os.path.getsize(out)//1024} KB")

with open(f"{BUILD}/list.txt", "w") as f:
    for p in parts:
        f.write(f"file '{p}'\n")

final = f"{ROOT}/docs/PayGuard-demo.mp4"
r = subprocess.run([FF, "-y", "-f", "concat", "-safe", "0", "-i", f"{BUILD}/list.txt",
                    "-c", "copy", "-movflags", "+faststart", final],
                   capture_output=True, text=True)
if r.returncode != 0:
    print("CONCAT FAIL", r.stderr[-600:])
    raise SystemExit(1)

print(f"\nnarasi total: {total:.1f}s")
print("final:", final, os.path.getsize(final) // 1024, "KB")
print("durasi final:", dur(final))
