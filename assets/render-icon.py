#!/usr/bin/env python3
"""Render the MixMates Listener app icon at 1024x1024.

Generates `mml-icon.png` next to this script: "MML" in Modak with the
Spotify-green to cyan brand gradient, "Listener" in Helvetica Neue at
80% white, on the #1A1A2E dark navy that matches the launch screen.

Usage:
    pip install Pillow
    python3 render-icon.py

The output PNG can be dropped into
`Listener/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

The Modak font is bundled alongside this script. It's licensed under
the SIL Open Font License 1.1 — see `Modak-OFL.txt`. The script falls
back to Helvetica Neue (a system font on macOS) for "Listener".
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

SIZE = 1024
BG = (26, 26, 46)  # #1A1A2E
GRAD_START = (29, 185, 84)   # Spotify green #1DB954
GRAD_END = (44, 204, 211)    # cyan #2CCCD3

MODAK_PATH = HERE / "Modak-Regular.ttf"
HELVETICA_FALLBACK = "/System/Library/Fonts/HelveticaNeue.ttc"
OUTPUT_PATH = HERE / "mml-icon.png"

MML_SIZE = 360
LISTENER_SIZE = 130
GAP = 36


def make_gradient(width: int, height: int) -> Image.Image:
    """Horizontal linear gradient from GRAD_START to GRAD_END."""
    grad = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(grad)
    for x in range(width):
        t = x / (width - 1)
        r = int(GRAD_START[0] + (GRAD_END[0] - GRAD_START[0]) * t)
        g = int(GRAD_START[1] + (GRAD_END[1] - GRAD_START[1]) * t)
        b = int(GRAD_START[2] + (GRAD_END[2] - GRAD_START[2]) * t)
        draw.line([(x, 0), (x, height - 1)], fill=(r, g, b))
    return grad


def main() -> None:
    base = Image.new("RGB", (SIZE, SIZE), BG)

    modak = ImageFont.truetype(str(MODAK_PATH), MML_SIZE)
    listener_font = ImageFont.truetype(HELVETICA_FALLBACK, LISTENER_SIZE)

    # Compute text bboxes for vertical centering of the stack
    measure = ImageDraw.Draw(Image.new("L", (1, 1)))
    mml_bbox = measure.textbbox((0, 0), "MML", font=modak)
    mml_w = mml_bbox[2] - mml_bbox[0]
    mml_h = mml_bbox[3] - mml_bbox[1]

    list_bbox = measure.textbbox((0, 0), "Listener", font=listener_font)
    list_w = list_bbox[2] - list_bbox[0]
    list_h = list_bbox[3] - list_bbox[1]

    total_h = mml_h + GAP + list_h
    stack_top = (SIZE - total_h) // 2

    # MML position
    mml_x = (SIZE - mml_w) // 2 - mml_bbox[0]
    mml_y = stack_top - mml_bbox[1]

    # Listener position
    list_x = (SIZE - list_w) // 2 - list_bbox[0]
    list_y = stack_top + mml_h + GAP - list_bbox[1]

    # Draw MML through a gradient mask
    mml_mask = Image.new("L", (SIZE, SIZE), 0)
    mml_mask_draw = ImageDraw.Draw(mml_mask)
    mml_mask_draw.text((mml_x, mml_y), "MML", font=modak, fill=255)

    gradient = make_gradient(SIZE, SIZE)
    base.paste(gradient, (0, 0), mml_mask)

    # Draw Listener in white at 80% opacity via an RGBA overlay
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.text(
        (list_x, list_y),
        "Listener",
        font=listener_font,
        fill=(255, 255, 255, 204),  # 80% alpha
    )

    base = base.convert("RGBA")
    base = Image.alpha_composite(base, overlay)
    base = base.convert("RGB")

    base.save(OUTPUT_PATH)
    print(f"Saved {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
