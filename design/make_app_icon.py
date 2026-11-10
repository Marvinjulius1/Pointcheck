import math, sys
from PIL import Image, ImageDraw, ImageFilter

N = 2048  # supersampled
img = Image.new("RGB", (N, N))
px = img.load()

# Background: court-blue gradient with a soft light from the top left.
top, bottom = (28, 96, 168), (8, 30, 64)
for y in range(N):
    t = y / (N - 1)
    base = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    for x in range(N):
        d = math.hypot(x - N * 0.25, y - N * 0.15) / (N * 1.1)
        glow = max(0.0, 1 - d) ** 2 * 0.35
        px[x, y] = tuple(min(255, int(base[i] + (255 - base[i]) * glow * 0.35)) for i in range(3))

draw = ImageDraw.Draw(img)

# Faint court lines (service line + centre line) in the lower part.
line = (255, 255, 255)
overlay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)
od.line([(0, int(N * 0.80)), (N, int(N * 0.80))], fill=line + (34,), width=int(N * 0.012))
od.line([(N // 2, int(N * 0.80)), (N // 2, N)], fill=line + (34,), width=int(N * 0.012))
img = Image.alpha_composite(img.convert("RGBA"), overlay)

# Ball shadow.
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
cx, cy, r = N // 2, int(N * 0.47), int(N * 0.30)
sd.ellipse([cx - r * 0.95, cy + r * 0.92, cx + r * 0.95, cy + r * 1.18], fill=(0, 0, 0, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(N * 0.03))
img = Image.alpha_composite(img, shadow)

# Ball with radial shading.
ball = Image.new("RGBA", (N, N), (0, 0, 0, 0))
bp = ball.load()
light = (cx - r * 0.35, cy - r * 0.40)
for y in range(cy - r, cy + r + 1):
    for x in range(cx - r, cx + r + 1):
        if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
            d = math.hypot(x - light[0], y - light[1]) / (r * 1.7)
            d = min(1.0, d)
            hi, mid, lo = (246, 255, 176), (220, 255, 79), (150, 190, 20)
            if d < 0.45:
                t = d / 0.45; c = tuple(hi[i] * (1 - t) + mid[i] * t for i in range(3))
            else:
                t = (d - 0.45) / 0.55; c = tuple(mid[i] * (1 - t) + lo[i] * t for i in range(3))
            bp[x, y] = tuple(int(v) for v in c) + (255,)
img = Image.alpha_composite(img, ball)

# Seams: two white arcs, clipped to the ball.
seams = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sd = ImageDraw.Draw(seams)
w = int(r * 0.075)
R = int(r * 1.05)
sd.ellipse([cx - r - R * 1.55, cy - R, cx - r + R * 0.45, cy + R], outline=(255, 255, 255, 235), width=w)
sd.ellipse([cx + r - R * 0.45, cy - R, cx + r + R * 1.55, cy + R], outline=(255, 255, 255, 235), width=w)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
clipped = Image.new("RGBA", (N, N), (0, 0, 0, 0))
clipped.paste(seams, (0, 0), Image.composite(seams.split()[3], Image.new("L", (N, N), 0), mask))
img = Image.alpha_composite(img, clipped)

# Check mark in court blue across the ball.
check = Image.new("RGBA", (N, N), (0, 0, 0, 0))
cd = ImageDraw.Draw(check)
pts = [(cx - r * 0.46, cy + r * 0.02), (cx - r * 0.12, cy + r * 0.36), (cx + r * 0.52, cy - r * 0.34)]
cw = int(r * 0.20)
cd.line(pts, fill=(12, 44, 92, 255), width=cw, joint="curve")
for p in (pts[0], pts[2]):
    cd.ellipse([p[0] - cw / 2, p[1] - cw / 2, p[0] + cw / 2, p[1] + cw / 2], fill=(12, 44, 92, 255))
img = Image.alpha_composite(img, check)

# Glossy highlight on the ball.
gloss = Image.new("RGBA", (N, N), (0, 0, 0, 0))
gd = ImageDraw.Draw(gloss)
gd.ellipse([cx - r * 0.62, cy - r * 0.82, cx + r * 0.10, cy - r * 0.38], fill=(255, 255, 255, 48))
gloss = gloss.filter(ImageFilter.GaussianBlur(N * 0.03))
img = Image.alpha_composite(img, gloss)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
