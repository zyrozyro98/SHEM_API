from pathlib import Path
import os

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Run: python -m pip install pillow"
    ) from exc

root = Path(__file__).resolve().parent.parent
out_dir = root / 'assets' / 'icon'
out_dir.mkdir(parents=True, exist_ok=True)

# Premium brand palette: dark brown and luxury gold.
base = '#1B120C'
gold = '#B69449'
light = '#F5F1EA'

# Main icon: dark background with gold shopping bag and brand wordmark.
img = Image.new('RGBA', (1024, 1024), base)
draw = ImageDraw.Draw(img)

draw.rounded_rectangle((210, 300, 814, 740), radius=80, fill=base, outline=gold, width=20)

handle_points = []
for t in [i / 90 for i in range(91)]:
    x = 290 + 470 * t
    y = 350 - 230 * (t * (1 - t))
    handle_points.append((x, y))
for t in [i / 90 for i in range(91)]:
    x = 760 - 470 * t
    y = 350 - 230 * (t * (1 - t))
    handle_points.append((x, y))
draw.line(handle_points, fill=gold, width=18)

draw.line([(275, 620), (350, 620), (455, 715), (610, 715), (700, 620), (760, 620)], fill=gold, width=12)

font_big = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 260)
font_small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 120)

bbox_m = draw.textbbox((0, 0), 'M', font=font_big)
text_w = bbox_m[2] - bbox_m[0]
text_h = bbox_m[3] - bbox_m[1]
text_x = 512 - text_w / 2
text_y = 480 - text_h / 2
for dx, dy in [(-8, 8), (0, 0), (8, -8)]:
    draw.text((text_x + dx, text_y + dy), 'M', font=font_big, fill=gold)

brand = 'SHE'
bbox_brand = draw.textbbox((0, 0), brand, font=font_small)
brand_w = bbox_brand[2] - bbox_brand[0]
brand_x = 512 - brand_w / 2
draw.text((brand_x, 760), brand, font=font_small, fill=light)

img.save(out_dir / 'app_icon.png')

# Foreground-only version for adaptive icon workflow.
foreground = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
fd = ImageDraw.Draw(foreground)
fd.rounded_rectangle((210, 300, 814, 740), radius=80, fill=(27, 18, 12, 255), outline=(182, 148, 73, 255), width=20)
fd.line(handle_points, fill=(182, 148, 73, 255), width=18)
fd.line([(275, 620), (350, 620), (455, 715), (610, 715), (700, 620), (760, 620)], fill=(182, 148, 73, 255), width=12)

bbox_m_fg = fd.textbbox((0, 0), 'M', font=font_big)
text_w_fg = bbox_m_fg[2] - bbox_m_fg[0]
text_h_fg = bbox_m_fg[3] - bbox_m_fg[1]
text_x_fg = 512 - text_w_fg / 2
text_y_fg = 480 - text_h_fg / 2
for dx, dy in [(-8, 8), (0, 0), (8, -8)]:
    fd.text((text_x_fg + dx, text_y_fg + dy), 'M', font=font_big, fill=(182, 148, 73, 255))

bbox_brand_fg = fd.textbbox((0, 0), brand, font=font_small)
brand_w_fg = bbox_brand_fg[2] - bbox_brand_fg[0]
brand_x_fg = 512 - brand_w_fg / 2
fd.text((brand_x_fg, 760), brand, font=font_small, fill=(245, 241, 234, 255))

foreground.save(out_dir / 'app_icon_foreground.png')

print(f"Created {out_dir / 'app_icon.png'}")
print(f"Created {out_dir / 'app_icon_foreground.png'}")
