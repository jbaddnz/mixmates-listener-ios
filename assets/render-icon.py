#!/usr/bin/env python3
"""Render the MixMates Listener app icon at 1024x1024.

Generates `mml-icon.png` next to this script: "mmL" wordmark in
MuseoModerno Bold 700 with the Spotify-green to cyan brand gradient,
"Listener" in Helvetica Neue at 80% white, on the #1A1A2E dark navy
that matches the launch screen.

The "mmL" wordmark uses the same height-matching technique as the
shared wordmark package at `mml-wordmark/`: the lowercase m's are
rendered at a larger font size than the uppercase L so all three
glyphs end up the same visual height. This is the same construction
the SwiftUI splash uses.

Usage:
    pip install Pillow
    python3 render-icon.py

The output PNG can be dropped into
`Listener/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

The MuseoModerno font is bundled with the wordmark package at
`mml-wordmark/fonts/`. It's licensed under the SIL Open Font License
1.1 — see `mml-wordmark/fonts/OFL.txt`. The script falls back to
Helvetica Neue (a system font on macOS) for "Listener".
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT_PATH = HERE / "mml-wordmark" / "fonts" / "MuseoModerno-Variable.ttf"
HELVETICA_FALLBACK = "/System/Library/Fonts/HelveticaNeue.ttc"
OUTPUT_PATH = HERE / "mml-icon.png"

SIZE = 1024
BG = (26, 26, 46)  # #1A1A2E
GRAD_START = (29, 185, 84)   # Spotify green #1DB954
GRAD_END = (44, 204, 211)    # cyan #2CCCD3

# MuseoModerno Bold 700 for the wordmark
WORDMARK_WEIGHT = 700

# Target visual height of the wordmark (m's x-height = L's cap-height
# in the height-matched mmL composition). Sized so the wordmark fits
# the 1024 canvas with comfortable horizontal padding. mmL aspect ratio
# is ~3.9:1, so visual height 200 → width ~780, leaving ~120px of
# horizontal padding on each side.
WORDMARK_VISUAL_HEIGHT = 200

LISTENER_SIZE = 110
GAP = 50


def render_char(char: str, font_size: int, weight: int) -> Image.Image:
    """Render a single character to a tightly cropped grayscale mask.

    Uses 5x font_size scratch canvas with text centred — Bauhaus-derived
    glyphs in MuseoModerno can have ink overshooting the nominal text
    bbox by ~14% of font size in heavy weights. Smaller scratch silently
    clips the overshoot. (Same fix as the wordmark package's build.py.)
    """
    font = ImageFont.truetype(str(FONT_PATH), font_size)
    font.set_variation_by_axes([weight])
    canvas_size = font_size * 5
    img = Image.new("L", (canvas_size, canvas_size), 0)
    draw = ImageDraw.Draw(img)
    draw.text((canvas_size // 2, canvas_size // 2), char, font=font, fill=255)
    bbox = img.getbbox()
    if bbox is None:
        return Image.new("L", (1, 1), 0)
    return img.crop(bbox)


def render_mmL_mask(target_visual_height: int) -> Image.Image:
    """Render the height-matched mmL wordmark as a grayscale alpha mask.

    Each glyph is scaled (via per-character font size) so its visual
    bbox height equals `target_visual_height`. The m's x-height ends up
    equal to the L's cap-height even though they're typographically
    different — that's what makes the height-matching work.
    """
    chars = ["m", "m", "L"]
    rendered = []
    for c in chars:
        probe = 220
        probe_img = render_char(c, probe, WORDMARK_WEIGHT)
        new_size = max(8, int(round(probe * target_visual_height / probe_img.height)))
        rendered.append(render_char(c, new_size, WORDMARK_WEIGHT))

    gap = max(2, target_visual_height // 24)
    canvas_w = sum(img.width for img in rendered) + gap * (len(rendered) - 1)
    canvas_h = max(img.height for img in rendered)
    canvas = Image.new("L", (canvas_w, canvas_h), 0)

    bottom = canvas_h
    x = 0
    for img in rendered:
        canvas.paste(img, (x, bottom - img.height))
        x += img.width + gap
    return canvas


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

    # Render the mmL wordmark mask
    mml_mask = render_mmL_mask(WORDMARK_VISUAL_HEIGHT)
    mml_w = mml_mask.width
    mml_h = mml_mask.height

    # "Listener" font/measurement
    listener_font = ImageFont.truetype(HELVETICA_FALLBACK, LISTENER_SIZE)
    measure = ImageDraw.Draw(Image.new("L", (1, 1)))
    list_bbox = measure.textbbox((0, 0), "Listener", font=listener_font)
    list_w = list_bbox[2] - list_bbox[0]
    list_h = list_bbox[3] - list_bbox[1]

    # Center the [wordmark + gap + Listener] stack vertically
    total_h = mml_h + GAP + list_h
    stack_top = (SIZE - total_h) // 2

    # mmL wordmark position (centered horizontally)
    mml_x = (SIZE - mml_w) // 2
    mml_y = stack_top

    # Listener position (centered horizontally)
    list_x = (SIZE - list_w) // 2 - list_bbox[0]
    list_y = stack_top + mml_h + GAP - list_bbox[1]

    # Composite the wordmark through its mask, applying the brand gradient
    # over the wordmark's bbox.
    full_mask = Image.new("L", (SIZE, SIZE), 0)
    full_mask.paste(mml_mask, (mml_x, mml_y))
    gradient = make_gradient(SIZE, SIZE)
    base.paste(gradient, (0, 0), full_mask)

    # Draw "Listener" in white at 80% opacity via an RGBA overlay
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
