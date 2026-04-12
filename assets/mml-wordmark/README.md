# MixMates Wordmark Package

Two brand wordmarks in MuseoModerno Bold 700 with the MixMates brand
gradient (Spotify green `#1DB954` → cyan `#2CCCD3`):

- **mmL** — lowercase m + uppercase L, with the m's visual x-height
  scaled UP to match the L's cap-height. Both glyphs visually equal
  height. This is the wordmark used by the iOS Listener app.
- **mms** — all lowercase, natural typography. The s sits at its
  natural x-height (slightly shorter than the m).

This package is **drop-in copyable** into other MixMates projects so all
surfaces use the same wordmark rendering. Run `python3 build.py` from
inside the package and you get the same PNGs and SVGs every time.

## Contents

```
mml-wordmark/
├── README.md                    this file
├── build.py                     regenerates everything; only depends on
│                                Pillow and the bundled font
├── fonts/
│   ├── MuseoModerno-Variable.ttf   variable font, weights 100-900
│   └── OFL.txt                     SIL Open Font License 1.1
├── png/
│   ├── mmL@1x.png   240×60      iOS asset @1x
│   ├── mmL@2x.png   480×120     iOS asset @2x
│   ├── mmL@3x.png   720×180     iOS asset @3x
│   ├── mmL1024.png  1024×256    medium / web hero
│   ├── mmL2048.png  2048×512    print / large display
│   ├── mms@1x.png   240×60
│   ├── mms@2x.png   480×120
│   ├── mms@3x.png   720×180
│   ├── mms1024.png  1024×256
│   └── mms2048.png  2048×512
└── sources/
    ├── mmL.svg                  vector source — references MuseoModerno
    └── mms.svg                  by font-family, needs the bundled font
                                 to be installed/loaded for correct render
```

## Design notes

- **Aspect ratio**: 4:1 horizontal. The wordmarks are wide by nature
  because three letters at this weight don't compress into a square
  without distortion. The 4:1 canvas leaves ~20px horizontal padding
  and ~5px vertical padding around the glyphs at 1x scale.
- **Visual height**: the m's x-height is 50px at 1x. With MuseoModerno
  Bold 700, the m's bbox is 525 units tall at font size 1000, so the
  m font size for a 50px x-height is `50 * 1000/525 ≈ 95.24`.
- **mmL height-matching**: the L's cap-height is 700 units at font size
  1000, so the L is rendered at font size `50 * 1000/700 ≈ 71.43`.
  This makes m and L visually the same 50px height. In SVG this is
  done with two `<tspan>` elements at the calculated font sizes inside
  one `<text>` element so they share a baseline.
- **Brand gradient**: applied as a horizontal linear gradient across
  the wordmark glyph mask. Each glyph carries its slice of the
  gradient (greener on the left, cyan on the right).

## Using the package in another project

Copy the entire `mml-wordmark/` directory into the destination project.
Then either:

- **Use the pre-rendered PNGs** in `png/` directly. Pick the size that
  matches your target.
- **Render fresh** with `python3 build.py` (requires Pillow). The
  script regenerates everything from the bundled font.
- **Use the SVGs** in `sources/` if your target supports SVG with live
  text. The font family is `MuseoModerno` and the font weight is `700`;
  ensure the font is installed/loaded in the rendering environment.
  (For projects that need vector but can't depend on the font being
  available, run a tool like Inkscape's `--export-text-to-path` to
  outline the text first.)

## iOS-specific behaviour

When `build.py` is run from inside the iOS repo
(`mixmates-listener-ios/assets/mml-wordmark/`), it also writes the mmL
PNGs into `Listener/Assets.xcassets/LaunchLogo.imageset/` and updates
the `Contents.json` to declare them as @1x/@2x/@3x. Other consuming
projects can ignore that step — the script silently skips it if the
iOS asset directory doesn't exist alongside the package.

## Regenerating the package

```bash
pip install Pillow
python3 build.py
```

That's it. Idempotent — running multiple times produces identical
output (modulo PNG metadata timestamps).
