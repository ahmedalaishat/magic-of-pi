# Renders the app icon. Run from the project folder:
#   python3 tools/make_icon.py PiVisualizer/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import math, colorsys, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

S = 1024
C = S / 2
digits = [int(c) for c in open("PiVisualizer/pi-digits.txt").read().strip()]

def hue(h, s=0.75, v=1.0):
    r, g, b = colorsys.hsv_to_rgb(h % 1, s, v)
    return int(r * 255), int(g * 255), int(b * 255)

# Background: deep violet in the middle fading to black.
bg = Image.radial_gradient("L").resize((S, S))
base = Image.new("RGB", (S, S), (24, 10, 46))
img = Image.composite(Image.new("RGB", (S, S)), base, bg.point(lambda v: min(255, int(v * 1.25))))

# Chord ring, same layout as the app: digit d owns a tenth of the ring.
R = 0.40 * S
seg = 2 * math.pi / 10
gap = seg * 0.12
def angle(d, f): return -math.pi / 2 + d * seg + gap / 2 + f * (seg - gap)
def pt(a, r=1.0): return (C + math.cos(a) * R * r, C + math.sin(a) * R * r)

chords = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dc = ImageDraw.Draw(chords, "RGBA")
N = 1500
for i in range(N - 1):
    a, b = digits[i], digits[i + 1]
    p0 = pt(angle(a, i / (N - 1))); p1 = pt(angle(b, (i + 1) / (N - 1)))
    c = (C + ((p0[0] - C) + (p1[0] - C)) * 0.12, C + ((p0[1] - C) + (p1[1] - C)) * 0.12)
    pts = []
    for k in range(25):
        t = k / 24; u = 1 - t
        pts.append((u*u*p0[0] + 2*u*t*c[0] + t*t*p1[0], u*u*p0[1] + 2*u*t*c[1] + t*t*p1[1]))
    dc.line(pts, fill=hue(a / 10 + 0.55) + (38,), width=2)
img = Image.alpha_composite(img.convert("RGBA"), chords)

da = ImageDraw.Draw(img, "RGBA")
for d in range(10):
    da.arc([C - R * 1.06, C - R * 1.06, C + R * 1.06, C + R * 1.06],
           math.degrees(angle(d, 0)), math.degrees(angle(d, 1)), fill=hue(d / 10 + 0.55) + (255,), width=16)

# Darken the middle so the glyph reads clearly over the chords.
shade = Image.radial_gradient("L").resize((int(S * 0.8), int(S * 0.8)))
veil = Image.new("RGBA", (S, S), (0, 0, 0, 0))
veil.paste(Image.new("RGBA", shade.size, (6, 2, 14, 255)), (int(S * 0.1), int(S * 0.1)),
           shade.point(lambda v: int(max(0, 235 - v * 1.6))))
img = Image.alpha_composite(img, veil).convert("RGB")

# Smooth diagonal gradient (blue → violet → pink), built small and scaled up so it has no seams.
small = Image.new("RGB", (64, 64))
for yy in range(64):
    for xx in range(64):
        small.putpixel((xx, yy), hue(0.55 + 0.42 * (xx + yy) / 126, 0.7))
gradient = small.resize((S, S), Image.BICUBIC)

# π outline with a soft glow.
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf", 760)
mask = Image.new("L", (S, S), 0)
dm = ImageDraw.Draw(mask)
box = dm.textbbox((0, 0), "π", font=font, stroke_width=13)
x = (S - (box[2] - box[0])) / 2 - box[0]
y = (S - (box[3] - box[1])) / 2 - box[1] - 8
dm.text((x, y), "π", font=font, fill=0, stroke_width=13, stroke_fill=255)
glow = Image.composite(gradient, Image.new("RGB", (S, S)), mask.filter(ImageFilter.GaussianBlur(30)))
img = ImageChops.screen(img, glow)
img = ImageChops.screen(img, glow)
img = Image.composite(gradient, img, mask)
img.save(sys.argv[1])
