#!/usr/bin/env python3
"""Draw the Stop & Shoot app icon. Output is an opaque 1024 PNG."""
from pathlib import Path
from PIL import Image, ImageDraw

def icon(size, path):
    scale = 4
    canvas = size * scale
    bg = (18, 22, 30, 255)
    image = Image.new("RGBA", (canvas, canvas), bg)
    draw = ImageDraw.Draw(image)
    pad = int(canvas * 0.16)
    width = canvas - 2 * pad
    cx = canvas // 2
    radius = int(width * 0.36)
    cy = pad + int(width * 0.40)
    orange = (255, 138, 36, 255)
    draw.polygon(
        [(cx - int(radius * 0.86), cy + int(radius * 0.5)), (cx + int(radius * 0.86), cy + int(radius * 0.5)), (cx, pad + width)],
        fill=orange,
    )
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=orange)
    lens = int(radius * 0.58)
    draw.ellipse([cx - lens, cy - lens, cx + lens, cy + lens], fill=bg)
    inner = int(radius * 0.36)
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=(255, 255, 255, 255))
    pupil = int(radius * 0.14)
    draw.ellipse([cx - pupil, cy - pupil, cx + pupil, cy + pupil], fill=bg)
    image = image.resize((size, size), Image.Resampling.LANCZOS)
    flat = Image.new("RGB", (size, size), (18, 22, 30))
    flat.paste(image, mask=image.split()[-1])
    flat.save(path)

if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    icon(1024, root / "ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
