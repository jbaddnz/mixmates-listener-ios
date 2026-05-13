#!/usr/bin/env python3
"""Build the MixMates wordmark package.

Generates two wordmarks — `mmL` (lowercase m + uppercase L, height-matched
so the m's visual x-height equals the L's cap-height) and `mms` (natural
lowercase) — in MuseoModerno Bold 700 with the brand gradient (Spotify
green → cyan).

Outputs:
- `png/mmL@1x.png` … `png/mmL-2048.png` — raster at 5 sizes
- `png/mms@1x.png` … `png/mms-2048.png` — raster at 5 sizes
- `png/listener-app-icon-1024.png` — square 1024×1024 app-icon-style
  composition: dark navy background, mmL wordmark with brand gradient,
  "Listener" subtitle in Helvetica Neue at 80% white. The same recipe
  the iOS Listener target ships as its App Store icon.
- `sources/mmL.svg`, `sources/mms.svg` — SVG with live text + tspan;
  consumers need MuseoModerno available at render time
- (font + OFL license already in `fonts/`, not regenerated)

iOS-specific behaviour (only if this script is run from inside the iOS
repo, i.e. if the relevant `Listener/Assets.xcassets/*.imageset/` or
`AppIcon.appiconset/` directories exist relative to the script):
- Writes mmL @1x/@2x/@3x PNGs into `LaunchLogo.imageset/`
- Writes the listener app icon into `AppIcon.appiconset/AppIcon.png`

Other consuming projects can ignore the iOS steps — the script silently
skips them if the target directories don't exist.

The "Listener" subtitle in the app icon uses Helvetica Neue, which is a
system font on macOS. On non-macOS hosts the subtitle render falls back
to Pillow's default font (functional but visually off); the app-icon
output is intended to be regenerated on macOS.

Usage:
    pip install Pillow
    python3 build.py

Designed to be portable. The script is self-contained: it only depends
on Pillow and the bundled font in `fonts/`. Drop this whole `mml-wordmark/`
folder into another mixmates project, run `python3 build.py`, and you
get the same wordmarks rendered the same way. The listener-specific app
icon output stays in `png/` regardless — consuming projects can either
adapt the config at the top of `main()` for their own subtitle/branding
or skip the app-icon step entirely.
"""

import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# === Paths ===
SCRIPT_DIR = Path(__file__).resolve().parent
PNG_DIR = SCRIPT_DIR / "png"
SOURCES_DIR = SCRIPT_DIR / "sources"
FONT_PATH = SCRIPT_DIR / "fonts" / "MuseoModerno-Variable.ttf"

# Optional: iOS asset catalog targets — relative to this script's location.
# Only updated if the directory exists.
IOS_LAUNCH_LOGO_DIR = SCRIPT_DIR.parent.parent / "Listener" / "Assets.xcassets" / "LaunchLogo.imageset"
IOS_APP_ICON_DIR = SCRIPT_DIR.parent.parent / "Listener" / "Assets.xcassets" / "AppIcon.appiconset"

# === App icon config (Listener-specific) ===
# 1024×1024 square: dark navy bg, mmL wordmark with brand gradient,
# "Listener" subtitle in Helvetica Neue at 80% white. The bg matches the
# `LaunchBackground` color in the iOS asset catalog and the SplashView so
# the launch→sign-in transition is seamless. Other consuming projects can
# adapt or skip this section.
APP_ICON_SIZE = 1024
APP_ICON_BG = (26, 26, 46)              # #1A1A2E — matches LaunchBackground
APP_ICON_WORDMARK_VISUAL_HEIGHT = 200    # m x-height = L cap-height = 200px
APP_ICON_SUBTITLE = "Listener"
APP_ICON_SUBTITLE_SIZE = 110
APP_ICON_GAP = 50                        # vertical gap between wordmark and subtitle
APP_ICON_SUBTITLE_FONT = "/System/Library/Fonts/HelveticaNeue.ttc"  # macOS-only

# === Font config ===
FONT_WEIGHT = 700  # MuseoModerno Bold

# === Brand gradient ===
GRAD_START = (29, 185, 84)   # Spotify green #1DB954
GRAD_END = (44, 204, 211)    # cyan #2CCCD3

# === Canonical canvas dimensions (1x) ===
# 4:1 aspect — wordmarks are wide by nature. Visual height of the m
# (x-height) is 50 at 1x scale. The whole wordmark fits with ~20px
# padding on the left/right and ~5px top/bottom.
CANVAS_W_1X = 240
CANVAS_H_1X = 60
TARGET_VISUAL_HEIGHT_1X = 50

# Sizes the package emits, as multipliers of the 1x canvas.
PACKAGE_SCALES = {
    "@1x":  1,    # 240 × 60
    "@2x":  2,    # 480 × 120
    "@3x":  3,    # 720 × 180
    "1024": 1024 / CANVAS_W_1X,   # 1024 × 256
    "2048": 2048 / CANVAS_W_1X,   # 2048 × 512
}

WORDMARKS = [
    # (name, chars, force_equal — True scales each char to target height)
    ("mmL", ["m", "m", "L"], True),
    ("mms", ["m", "m", "s"], False),
]


# ============================================================================
# Rendering primitives
# ============================================================================

def render_char(char: str, font_size: int) -> Image.Image:
    """Render a single character to a tightly cropped grayscale mask.

    Uses a 5×font_size scratch canvas with text centred — Bauhaus-derived
    glyphs in MuseoModerno can have ink that overshoots PIL's nominal text
    bbox by ~14% of the font size in heavy weights. A small scratch canvas
    silently clips that overshoot. 5× headroom is comfortable for any
    weight.
    """
    font = ImageFont.truetype(str(FONT_PATH), font_size)
    font.set_variation_by_axes([FONT_WEIGHT])
    canvas_size = font_size * 5
    img = Image.new("L", (canvas_size, canvas_size), 0)
    draw = ImageDraw.Draw(img)
    draw.text((canvas_size // 2, canvas_size // 2), char, font=font, fill=255)
    bbox = img.getbbox()
    if bbox is None:
        return Image.new("L", (1, 1), 0)
    return img.crop(bbox)


def render_wordmark_mask(chars: list, force_equal: bool, target_visual_height: int) -> Image.Image:
    """Render the wordmark glyph composition as a grayscale alpha mask.

    `force_equal=True`: every character is scaled (via per-character font
    size) so its visual bbox height equals `target_visual_height`. This
    is what makes the mmL variant work — the m's x-height ends up equal
    to the L's cap-height even though they're typographically different.

    `force_equal=False`: every character is rendered at the same font
    size — the size that gives m a visual height of target_visual_height.
    Lowercase ascenders / different glyph shapes keep their natural
    proportions. This is the mms variant.
    """
    if force_equal:
        rendered = []
        for c in chars:
            probe = 220
            probe_img = render_char(c, probe)
            new_size = max(8, int(round(probe * target_visual_height / probe_img.height)))
            rendered.append(render_char(c, new_size))
    else:
        probe = 220
        m_img = render_char("m", probe)
        font_size = max(8, int(round(probe * target_visual_height / m_img.height)))
        rendered = [render_char(c, font_size) for c in chars]

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


def make_horizontal_gradient_rgba(width: int, height: int) -> Image.Image:
    """Brand gradient as RGBA, fully opaque (alpha 255 everywhere)."""
    grad = Image.new("RGB", (width, height), GRAD_START)
    draw = ImageDraw.Draw(grad)
    for x in range(width):
        t = x / max(width - 1, 1)
        r = int(GRAD_START[0] + (GRAD_END[0] - GRAD_START[0]) * t)
        g = int(GRAD_START[1] + (GRAD_END[1] - GRAD_START[1]) * t)
        b = int(GRAD_START[2] + (GRAD_END[2] - GRAD_START[2]) * t)
        draw.line([(x, 0), (x, height - 1)], fill=(r, g, b))
    return grad.convert("RGBA")


def render_wordmark_png(chars: list, force_equal: bool, scale_multiplier: float) -> Image.Image:
    """Render a wordmark as a transparent-background RGBA PNG at the
    given scale multiplier of the 1x canvas (240×60)."""
    canvas_w = max(1, int(round(CANVAS_W_1X * scale_multiplier)))
    canvas_h = max(1, int(round(CANVAS_H_1X * scale_multiplier)))
    target_h = max(1, int(round(TARGET_VISUAL_HEIGHT_1X * scale_multiplier)))

    mask = render_wordmark_mask(chars, force_equal, target_h)

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    place_x = (canvas_w - mask.width) // 2
    place_y = (canvas_h - mask.height) // 2

    grad = make_horizontal_gradient_rgba(mask.width, mask.height)
    canvas.paste(grad, (place_x, place_y), mask)
    return canvas


# ============================================================================
# SVG generation
# ============================================================================

# Pre-measured ratios for MuseoModerno Bold 700 (font size 1000):
#   m height = 525, L height = 700, s height = 513
# So for visual-height H pixels:
#   m font size = H * 1000/525 = H * 1.9048
#   L font size = H * 1000/700 = H * 1.4286
M_FONT_RATIO = 1000 / 525   # 1.9048 — multiply visual height by this for m
L_FONT_RATIO = 1000 / 700   # 1.4286 — multiply visual height by this for L

SVG_TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <defs>
    <linearGradient id="brand" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#1DB954"/>
      <stop offset="100%" stop-color="#2CCCD3"/>
    </linearGradient>
  </defs>
{body}
</svg>
"""


def generate_mmL_svg() -> str:
    """SVG for mmL with tspan-based size adjustment so m visually = L."""
    width = CANVAS_W_1X
    height = CANVAS_H_1X
    visual_h = TARGET_VISUAL_HEIGHT_1X
    m_font_size = visual_h * M_FONT_RATIO  # ≈ 95.24
    L_font_size = visual_h * L_FONT_RATIO  # ≈ 71.43
    # Baseline y: position so the wordmark is vertically centered.
    # Bottom of glyphs at y = (height + visual_h) / 2 = 55
    baseline_y = (height + visual_h) / 2
    body = (
        f'  <text x="50%" y="{baseline_y:.2f}" text-anchor="middle"\n'
        f'        font-family="MuseoModerno" font-weight="700" fill="url(#brand)">\n'
        f'    <tspan font-size="{m_font_size:.2f}">mm</tspan>'
        f'<tspan font-size="{L_font_size:.2f}">L</tspan>\n'
        f'  </text>'
    )
    return SVG_TEMPLATE.format(width=width, height=height, body=body)


def generate_mms_svg() -> str:
    """SVG for mms — single text element, natural lowercase."""
    width = CANVAS_W_1X
    height = CANVAS_H_1X
    visual_h = TARGET_VISUAL_HEIGHT_1X
    font_size = visual_h * M_FONT_RATIO  # m's font size, s shares it
    baseline_y = (height + visual_h) / 2
    body = (
        f'  <text x="50%" y="{baseline_y:.2f}" text-anchor="middle"\n'
        f'        font-family="MuseoModerno" font-weight="700"\n'
        f'        font-size="{font_size:.2f}" fill="url(#brand)">mms</text>'
    )
    return SVG_TEMPLATE.format(width=width, height=height, body=body)


# ============================================================================
# App icon rendering (Listener-specific)
# ============================================================================

def render_app_icon(
    wordmark_chars: list,
    wordmark_force_equal: bool,
    subtitle: str,
) -> Image.Image:
    """Render a square app icon: dark `APP_ICON_BG` background, wordmark
    (composed via the same primitives as the package's mmL/mms outputs)
    with the brand gradient applied, plus a subtitle in Helvetica Neue at
    80% white below.

    The wordmark + subtitle stack is vertically centred. Horizontal
    centring is per-element. The wordmark glyph composition (height-
    matched mmL or natural mms) is controlled by `wordmark_force_equal`,
    matching the same flag used by `render_wordmark_mask`.

    Helvetica Neue is a macOS system font. On other hosts the subtitle
    will fall back to Pillow's default font; regenerate on macOS for a
    faithful render.
    """
    size = APP_ICON_SIZE
    base = Image.new("RGB", (size, size), APP_ICON_BG)

    # Render the wordmark mask at the target visual height
    wm_mask = render_wordmark_mask(
        wordmark_chars,
        wordmark_force_equal,
        APP_ICON_WORDMARK_VISUAL_HEIGHT,
    )
    wm_w = wm_mask.width
    wm_h = wm_mask.height

    # Measure the subtitle's text bounding box (without rendering yet)
    try:
        subtitle_font = ImageFont.truetype(APP_ICON_SUBTITLE_FONT, APP_ICON_SUBTITLE_SIZE)
    except OSError:
        # Fallback: Pillow's default bitmap font. Renders something usable
        # on non-macOS hosts; regenerate on macOS for the canonical icon.
        subtitle_font = ImageFont.load_default()
    measure = ImageDraw.Draw(Image.new("L", (1, 1)))
    sub_bbox = measure.textbbox((0, 0), subtitle, font=subtitle_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_h = sub_bbox[3] - sub_bbox[1]

    # Centre the [wordmark + gap + subtitle] stack vertically
    total_h = wm_h + APP_ICON_GAP + sub_h
    stack_top = (size - total_h) // 2

    # Wordmark position (centred horizontally)
    wm_x = (size - wm_w) // 2
    wm_y = stack_top

    # Subtitle position (centred horizontally, baseline-adjusted)
    sub_x = (size - sub_w) // 2 - sub_bbox[0]
    sub_y = stack_top + wm_h + APP_ICON_GAP - sub_bbox[1]

    # Composite the wordmark: gradient applied through the wordmark mask.
    # Full-canvas mask makes the gradient visible only inside the glyphs.
    full_mask = Image.new("L", (size, size), 0)
    full_mask.paste(wm_mask, (wm_x, wm_y))
    gradient = make_horizontal_gradient_rgba(size, size).convert("RGB")
    base.paste(gradient, (0, 0), full_mask)

    # Draw the subtitle in white at 80% opacity via an RGBA overlay
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.text(
        (sub_x, sub_y),
        subtitle,
        font=subtitle_font,
        fill=(255, 255, 255, 204),  # 80% alpha
    )

    base = base.convert("RGBA")
    base = Image.alpha_composite(base, overlay)
    return base.convert("RGB")


# ============================================================================
# Main
# ============================================================================

def main() -> None:
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)

    # Render package PNGs at all scales
    for name, chars, force_equal in WORDMARKS:
        for label, scale in PACKAGE_SCALES.items():
            img = render_wordmark_png(chars, force_equal, scale)
            out_path = PNG_DIR / f"{name}{label}.png"
            img.save(out_path)
            print(f"  {out_path.relative_to(SCRIPT_DIR)}  ({img.width}×{img.height})")

    # Generate SVG sources
    (SOURCES_DIR / "mmL.svg").write_text(generate_mmL_svg())
    print(f"  sources/mmL.svg")
    (SOURCES_DIR / "mms.svg").write_text(generate_mms_svg())
    print(f"  sources/mms.svg")

    # Render the Listener app icon (mmL wordmark + "Listener" subtitle on
    # dark navy). Listener-specific output; other projects can adapt the
    # config at the top of the file or remove this block.
    app_icon = render_app_icon(
        wordmark_chars=["m", "m", "L"],
        wordmark_force_equal=True,
        subtitle=APP_ICON_SUBTITLE,
    )
    app_icon_path = PNG_DIR / "listener-app-icon-1024.png"
    app_icon.save(app_icon_path)
    print(f"  {app_icon_path.relative_to(SCRIPT_DIR)}  ({app_icon.width}×{app_icon.height})")

    # Wire up the iOS AppIcon asset if we're in the iOS repo. Only writes
    # the 1024×1024 PNG; modern Xcode generates smaller variants at build
    # time from this single source.
    if IOS_APP_ICON_DIR.exists():
        print(f"\nUpdating iOS AppIcon asset at {IOS_APP_ICON_DIR}")
        dst = IOS_APP_ICON_DIR / "AppIcon.png"
        app_icon.save(dst)
        print(f"  {dst.relative_to(SCRIPT_DIR.parent.parent)}")

    # Wire up the iOS LaunchLogo asset if we're in the iOS repo
    if IOS_LAUNCH_LOGO_DIR.exists():
        print(f"\nUpdating iOS LaunchLogo asset at {IOS_LAUNCH_LOGO_DIR}")
        # Remove any existing wordmark/PDF files in the imageset
        for old in IOS_LAUNCH_LOGO_DIR.glob("*.png"):
            old.unlink()
        for old in IOS_LAUNCH_LOGO_DIR.glob("*.pdf"):
            old.unlink()

        # Copy mmL @1x/@2x/@3x into the imageset
        for label in ("@1x", "@2x", "@3x"):
            src = PNG_DIR / f"mmL{label}.png"
            dst = IOS_LAUNCH_LOGO_DIR / f"LaunchLogo{label}.png"
            shutil.copy(src, dst)
            print(f"  {dst.relative_to(SCRIPT_DIR.parent.parent)}")

        # Write Contents.json declaring the three scales
        contents_json = '''{
  "images" : [
    {
      "filename" : "LaunchLogo@1x.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchLogo@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "LaunchLogo@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'''
        (IOS_LAUNCH_LOGO_DIR / "Contents.json").write_text(contents_json)
        print(f"  Listener/Assets.xcassets/LaunchLogo.imageset/Contents.json")


if __name__ == "__main__":
    main()
