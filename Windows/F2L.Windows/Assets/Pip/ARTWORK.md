# Pip production artwork

Generated on 8 October 2026 with the built-in image-generation tool. These are project assets, not placeholders or vector reconstructions.

- `expressions.png`: 16 painted poses, including neutral, blink, speaking, thoughtful, curious/listening, focused and warm wave.
- `directions.png`: 16 poses, including pointing left/right/up/down, side profiles, walking and rear views.
- Reference: [original Pip concept](../../../../docs/companion-concepts/character-studies-f2l.png), left column only.

The source PNGs retain their generated alpha. The Windows renderer reads the 16 main connected silhouettes in each atlas and uses runtime CroppedBitmap views of the original images; it does not draw the character from shapes. Separate sprite extraction avoids clipping the cap where generated spacing differs from a perfect grid. Sprites share a foot baseline. Both source atlases can also be consumed by the macOS host.

Art review notes: the second upward pose lowers the pointing hand, so the runtime holds the first upward pose. The left walking loop uses the consistent generated right-profile frames mirrored at render time; a separately generated left profile is also present. Hand-painted frame variations are intentionally restrained in timing. Reduced motion selects stills.

## Expression generation prompt

```text
Use case: identity-preserve / stylized-concept.
Asset type: production transparent sprite atlas for F2L's animated Windows/macOS desktop companion.
Reference image: use ONLY PIP, the amber lantern sprite in the LEFT column of the attached original concept sheet. Preserve Pip's amber painted lantern cloak, asymmetric folded flame cap, cream face, navy bead eyes, tiny brown mitten hands and feet, teal round clasp. Do not use Mori or Tiko.
Create ONE transparent PNG sprite sheet, exactly FOUR columns by FOUR rows, equal square cells, preferably 2048x2048 overall. NO text, labels, numbers, grid lines, boxes, checkerboard, scenery, or ground shadows. Real transparent alpha around every sprite. Each cell contains one full-body Pip, same body size and baseline and same frontal camera, all parts fully inside the cell with a generous 12% transparent margin. Separate every cell by transparent gutter. This is hand-painted 2D game animation artwork with warm gouache/paper pigment texture inside the character, crisp organic edges. Not vector shapes, not a 3D render.
Cell order, left to right:
Row 1: calm friendly neutral eyes open; same neutral with eyes gently closed blinking; speaking with small open mouth; speaking with smaller mouth and slight friendly expression.
Row 2: thoughtful hand at chin eyes to side; thoughtful same pose subtle eyebrow/head movement; thoughtful eyes briefly closed; thoughtful return to original pose.
Row 3: curious listening head tilt eyes open; same listening tilt leaning slightly forward; listening gentle blink; listening returning to first pose.
Row 4: focused attentive front hands ready; same focused pose slight anticipatory hand lift; warm small smile and one hand wave; same warm wave with a small wrist change.
Frame changes are restrained and consistent for looping animation at small desktop size. Friendly adult-appropriate teacher. No worried or angry face, no reward badges. Keep the original Pip identity, silhouette, colors, painterly texture and relative feature placement consistent across all sixteen cells.
```

## Direction generation prompt

```text
Use case: identity-preserve / stylized-concept.
Asset: a second production transparent sprite atlas for the SAME Pip lantern character in the provided expression atlas. Preserve the amber/orange folded lantern cloak, asymmetrical folded flame cap, cream face, navy eyes, brown mitten hands and feet, teal clasp, and the warm painted gouache texture. Match proportions and render style exactly. This is 2D painted animation, not vector geometry or 3D.
Create ONE square PNG image with real transparent alpha, FOUR columns and FOUR rows of equal square cells. NO text, numbers, cell borders, backgrounds, checkerboard or ground shadows. No stray confetti or floating marks. Each figure fully visible, all limbs inside its cell, 12% clear gutter. Match actor size and ground baseline across cells for animation.
Left-to-right cell layout:
Row 1: Pip in a three-quarter LEFT-facing pose, one arm clearly extended horizontally pointing LEFT; same left-facing pose with subtle arm and cloak change; Pip three-quarter RIGHT-facing pointing RIGHT; same right-facing with subtle arm/cloak change.
Row 2: Pip looking and gesturing UP with one mitten raised, gaze upward; same pointing-up pose subtle change; Pip looking and pointing DOWN with arm lowered, gaze down; same downward gesture subtle change.
Row 3: genuine LEFT SIDE profile walking pose first foot forward; same left side profile with opposite foot forward; genuine RIGHT SIDE profile walking first foot forward; same right profile opposite foot forward.
Row 4: BACK view of Pip (back of amber cloak and folded cap, no face); same back view slight turn; FRONT three-quarter left with small open speaking mouth and relaxed hands; FRONT three-quarter right with small open speaking mouth and relaxed hands.
These are animated desktop teaching poses. Point with a clear mitten gesture and gaze; no handheld pointer, no arrows, no extra props. Keep every sprite consistent as one original character. Clean antialiased alpha edges and clean transparent gaps, no floating painted flecks outside silhouettes.
```


## Welcome illustration

`welcome-journey.png` (1254 × 1254, transparent) is the illustration on the first-time setup window: Pip reading a page on a stack of books beside a winding path. It was made with an image-generation tool during the setup work on 8 October, using this file's production Pip as the character reference; the exact prompt was not recorded.

## Pip emotes

`Emotes/*.png` (256 × 256, transparent) replace system emoji everywhere in F2L: `hello` (wave, motion lines), `happy` (smile, heart), `cheer` (smile and wave, sparkles), `thinking` (hand at chin, thought dots), `curious` (head tilt, question mark) and `focused` (attentive, target ring). Each is a painted pose from `expressions.png` (frames 14, 3, 15, 4, 8 and 12) with a small accent drawn in Pip's amber and teal by `PipEmote` in `Sources/F2L/Pip.swift`. The Mac app draws them live; the PNGs for Windows are regenerated with:

```bash
swift build --product F2L && "$(swift build --show-bin-path)/F2L" --export-emotes Windows/F2L.Windows/Assets/Pip/Emotes
```
