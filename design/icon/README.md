# Currents app icon

![preview](preview.png)

A sleek fish, nose tilted 8° upward as if rising to the surface, with a single
"current" running along its flank. White mark, theme-coloured current, on the
charcoal that Apple's own iOS 26 dark-appearance icons use.

Everything in this folder and every icon PNG in the app is generated from one
set of control points in [`scripts/render_app_icon.py`](../../scripts/render_app_icon.py):

```
pip install cairosvg pillow numpy
python scripts/render_app_icon.py          # all PNGs, SVGs, this preview
python scripts/render_app_icon.py --swift  # ios/Shared/CurrentsMark.swift
```

The SwiftUI `CurrentsMark` view is emitted from the same curves, so the logo
inside the app, on the watch and in share cards is the icon, not a redraw of it.

## Why this mark

The brief was a sleek, simple icon in the spirit of Apple's dark system icons
and Fishbrain's mark, but tied to fishing. Earlier explorations (`../app-icons/`)
tried hooks with sonar rings, map pins and water drops; this round went back to
the reference and designed against it directly.

**What the reference icons have in common** (Clock, Calendar, the "m" app):

- One big, centred glyph that fills roughly two thirds of the tile.
- Near-black charcoal, not pure black: sampled at `#38383A` at the top fading
  to `#202022` at the bottom. Pure black kills the Liquid Glass edge light.
- White as the dominant colour, with exactly one accent (Clock's orange second
  hand, Calendar's red "Fri", the "m"'s cyan). Never more than two colours.
- Round, even stroke weights. No outlines around filled shapes, no gradients
  inside the glyph, no text.

**What the Human Interface Guidelines ask for** (App icons, June 2026 revision):

- "Find a concept or element that captures the essence of your app… express it
  in a simple, unique way with a minimal number of shapes."
- "Consider basing your icon design around filled, overlapping shapes" rather
  than outlines. That ruled out the monoline-fish-in-a-ring variant, which also
  shrank the fish to a third of the tile.
- "Avoid extremely thin line weights and sharp corners" — the nose and tail
  tips are rounded geometrically (not with a stroke trick) so the SwiftUI path
  matches the PNG exactly.
- "Keep your icon's core visual features the same in the default, dark, clear,
  and tinted appearances." The three variants only change the background
  falloff and swap the accent for a grey in tinted mode.
- "Alternate app icons in iOS and iPadOS require their own dark, clear, and
  tinted variants." Every theme set now ships all three.
- watchOS: "Avoid using black for your icon's background." The watch icon uses
  a lighter charcoal and the mark is scaled to 70% so the tail clears the
  circular mask.
- Let the system draw highlights, shadows and blur. The PNGs carry only the
  background gradient; no glow, no bevel.

**Fish, not hook.** A fish silhouette is the one shape every angler reads
instantly at 29px, which is why Fishbrain built its brand on one. The hook
concepts needed sonar rings to say "app", and the rings were the first thing to
blur at small sizes.

**The current line is the name.** "Currents" is moving water; one wave through
the fish says it without a second object. It is also the only coloured element,
so the alternate icons (Ocean, Forest, Ember, Sunset, Amethyst, Teal, Rose,
Gold) are one mark in eight accents, exactly as the HIG wants alternates to
"remain closely related" and never "be mistaken for another app."

**The tilt.** The flat fish read as a clip-art goldfish. Eight degrees nose-up
gives it direction — the same trick as the Maps pin leaning into its drop — and
the forward lean keeps the mark optically centred once the tail flares.

## Files

| Path | Purpose |
|---|---|
| `currents-icon.svg` | Editable source of the default icon (1024 viewBox 0–1). |
| `layers/background.svg`, `layers/fish.svg`, `layers/current.svg` | Separate layers to drop into Icon Composer for a Liquid Glass `.icon`. |
| `preview.png` | Contact sheet: all themes × default/dark/tinted, a size ladder, the transparent in-app mark, the watch icon. |

### Liquid Glass (optional next step)

Xcode 26's Icon Composer produces a layered `.icon` bundle that the system lights
and refracts live. The three SVGs in `layers/` are ready to import: background
as the background layer, then `fish` and `current` as two foreground layers
(current above fish, so the system's specular highlight separates them). Export
the `.icon` next to the asset catalog and point `ASSETCATALOG_COMPILER_APPICON_NAME`
at it; the flat 1024 PNGs stay as the fallback for older systems and for the
App Store listing. This needs a Mac, so it is not wired into CI here.

## Palette

| Role | Value |
|---|---|
| Background, default | `#3A3A3C → #1F1F21` |
| Background, dark | `#2C2C2E → #161618` |
| Background, tinted | `#1C1C1E` flat |
| Background, watch | `#48484A → #2A2A2C` |
| Fish | `#F5F5F7` (pure white in tinted) |
| Current, tinted | `#9A9A9E` |
| Current, per theme | the light stop of `ThemeOption.gradient` (`LiquidGlass.swift`), e.g. Ocean `#26D1FA` |
