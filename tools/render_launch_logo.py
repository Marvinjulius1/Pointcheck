# Renders the launch wordmark: "POINTCHECK" in white + the Pointcheck logo (red/green score pills
# taken from the app icon), on transparent.
# Usage: python3 tools/render_launch_logo.py PointcheckPhone/Assets.xcassets/LaunchLogo.imageset (needs Pillow + Inter Display)
import sys, json, os
from PIL import Image, ImageDraw, ImageFont

out_dir = sys.argv[1]
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-ExtraBold.otf"
TEXT = "POINTCHECK"
FONT_PT = 22          # size in points
TRACK = -0.012        # letter spacing in em
SS = 8                # supersampling factor
LOGO_SCALE = 1.9      # logo height relative to the cap height of the text
ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "PointcheckPhone",
                    "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
LOGO_BOX = (150, 170, 874, 854)   # the two pills inside the 1024 px icon

def render(scale):
    k = scale * SS
    font = ImageFont.truetype(FONT, FONT_PT * k)
    asc, desc = font.getmetrics()
    # cap height from the glyph box of "H"
    hb = font.getbbox("H")
    cap_top, cap_bottom = hb[1], hb[3]
    cap = cap_bottom - cap_top
    # text width with tracking
    widths = [font.getlength(c) for c in TEXT]
    track = TRACK * FONT_PT * k
    text_w = sum(widths) + track * (len(TEXT) - 1)
    # logo: the pills from the app icon, black corners made transparent
    logo = Image.open(ICON).convert("RGBA").crop(LOGO_BOX)
    mark_h = cap * LOGO_SCALE
    mark_w = mark_h * logo.width / logo.height
    gap = cap * 0.45
    pad = 2 * k
    W = int(text_w + gap + mark_w + 2 * pad + 0.5)
    H = int(mark_h + 2 * pad + 0.5)
    img = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    y_cap_top = pad + (H - 2 * pad - cap) / 2
    x = pad
    for c, w in zip(TEXT, widths):
        d.text((x, y_cap_top - cap_top), c, font=font, fill=(255, 255, 255, 255))
        x += w + track
    mx = pad + text_w + gap
    my = pad + (H - 2 * pad - mark_h) / 2
    logo = logo.resize((round(mark_w), round(mark_h)), Image.LANCZOS)
    # black background of the icon → transparent (keeps the pill edges smooth)
    r_, g_, b_, a_ = logo.split()
    alpha = Image.eval(Image.merge("RGB", (r_, g_, b_)).convert("L"), lambda v: min(255, v * 4))
    logo.putalpha(alpha)
    img.alpha_composite(logo, (round(mx), round(my)))
    final = img.resize((max(1, round(W / SS)), max(1, round(H / SS))), Image.LANCZOS)
    return final

os.makedirs(out_dir, exist_ok=True)
images = []
for s in (1, 2, 3):
    name = f"LaunchLogo@{s}x.png" if s > 1 else "LaunchLogo.png"
    im = render(s)
    im.save(os.path.join(out_dir, name), optimize=True)
    images.append({"idiom": "universal", "filename": name, "scale": f"{s}x"})
    print(name, im.size)
with open(os.path.join(out_dir, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
