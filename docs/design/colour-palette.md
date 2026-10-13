# Colour palette

Marathon's colour: an OLED-black UI with one accent (Marathon teal), and
five category hues for app icons and anything else that has to tell apps
apart. Every colour is defined in OKLCH. The UI tokens themselves
(`MColors`, the surface ladder, status colours) are in
`docs/UI_DESIGN_SYSTEM.md` §2.1; this page sets the hues around them.

## Why OKLCH

OKLCH's lightness tracks perceived lightness, so two colours with the same
L and C look equally heavy whatever their hue, and stay near the same grey
in greyscale; HSL's do not. That lets the palette set lightness and chroma
once and vary only the hue. Gamut limits differ by hue (greens and cyans
run out of sRGB chroma first), so the generator lowers chroma until a
colour is in gamut rather than clipping it.

## Brand

| | Hex | OKLCH hue |
|---|---|---|
| Marathon teal (`accentBright`) | `#1de9b6` | ≈ 172° |
| Floor (`background`) | `#040404` | — |

Teal is the anchor: every other hue is placed relative to it.

## Category families

Five families, placed round the wheel from teal so no two are neighbours,
and kept out of the yellow-green band (≈ 95–150°), where colours at icon
lightness turn olive. Members of a family sit within ±18° of each other
(an analogous scheme), so an app's colour says its category before its
object does; families are far enough apart that categories never blur.

| Family | Shape (square corners) | Hue band | Apps (hue) |
|---|---|---|---|
| Communication | bottom left: the bubble's tail | 154–192, on teal | Messages 154, Mail 172, Phone 192 |
| Places & web | bottom right: the pin's point | 234–266, blue | Browser 234, Maps 250, Store 266 |
| Media | none: the lens, the disc | 302–338, magenta | Gallery 302, Music 320, Camera 338 |
| Time & notes | top left: the page's corner | 56–84, amber | Calendar 56, Clock 70, Notes 84 |
| Tools & system | top left and bottom right: machined | 354–36, red to orange | Terminal 354, Calculator 8, Test 22, Settings 36 |

A new app takes its category's shape and a free hue in its band. A
category that needs a sixth family takes the yellow-green gap only at
higher lightness (L ≥ 0.75), where it reads lime, not olive.

## Tonal ramp

Each hue is used only through one ramp (Material 3's tonal-palette idea:
fixed hue, set lightness steps). Matte: each tone is a soft vertical step
(top L + 0.03, hue + 4° → bottom L − 0.02), light from above as on BB10's
icons, never a highlight.

| Tone | L | C | Use |
|---|---|---|---|
| F | 0.68 | 0.16 | icon frame |
| D | 0.50 | 0.15 | the object |
| E | 0.39 | 0.13 | a darker plane |
| L | 0.64 | 0.13 | a lighter plane |
| T | 0.85 | 0.07 | a pale tint |
| C | `#F7F3E5` → `#EFE9D4` | — | the cream gap and cut-outs, every icon |

Hues 45–110 sit 0.09 lighter in D, E, L and 0.06 in F, or they go brown.

`scripts/build-app-icons.py` holds the numbers; change them there and
regenerate.
