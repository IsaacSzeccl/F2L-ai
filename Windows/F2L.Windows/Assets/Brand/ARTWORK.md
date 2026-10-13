# F2L original brand artwork

Created on 11 October 2026 with the built-in image-generation tool. Ten PNG masters are preserved byte-for-byte from the tool output. These are raster originals; no editable vector master was produced. All nine images after the first used `learning-doorway.png` as the identity or palette reference. No stock artwork or external brand marks were used.

## Visual direction

A book becomes a doorway, with a winding amber path and a flame: learning as a welcoming place you enter, one useful step at a time. Teal, sage, amber and ivory extend Pip's existing palette; a deep plum tile and landscape connect it to the launch screen. Gouache and layered paper textures keep it related to Pip without turning every illustration into another mascot picture.

## Where the artwork is used

| Master | Placement |
|---|---|
| `Brand/learning-doorway.png` | Entry screen emblem above the native animated wordmark; setup sidebar signature |
| `Brand/app-icon.png` | Source for the packaged macOS and Windows application icons |
| `Brand/launch-landscape.png` | Entry screen background, fading out before Pip walks home |
| `Illustrations/your-work.png` | Your work setup sidebar |
| `Illustrations/your-pace.png` | Your AI setup sidebar |
| `Illustrations/your-plan.png` | Your plan setup sidebar |
| `Illustrations/first-spark.png` | Just getting started experience card |
| `Illustrations/exploring.png` | Tried a few things experience card |
| `Illustrations/daily-practice.png` | Part of my routine experience card |
| `Illustrations/settings-compass.png` | Settings header |

Paths above are relative to `Windows/F2L.Windows/Assets/`. Both desktop hosts consume the same sources. Existing Pip artwork, emotes and the earlier welcome illustration are retained. Native text and accessible labels provide meaning; the images are decorative. Reduced Motion keeps the entry screen brief and still. The full-bleed landscape is opaque; all other originals preserve alpha.

## Packaging and review

- `python3 scripts/tools/package_brand_icons.py` packages the app-icon master into `Brand/F2L.icns` and `Brand/F2L.ico` using Pillow. Only format conversion and size resampling are performed; the original PNG remains unchanged.
- `swift scripts/tools/preview_brand.swift` renders the contact sheet at `docs/previews/f2l-brand-board.png`.
- `scripts/build-app.sh` copies shared originals and the native icon into the signed Mac bundle.
- `build/F2L.app/Contents/MacOS/F2L --render build/brand-render --animate-intro` renders the real launch, all three setup screens, and Settings with synthetic example data. It also writes a looping entry-screen GIF.
- `docs/asset-manifest.json` records dimensions, byte sizes and SHA-256 hashes.

## Exact generation prompts

### learning-doorway

```text
Use case: logo-brand.
Asset type: original F2L desktop application brand emblem, a transparent raster master.
Primary request: invent a beautiful distinctive symbol for F2L, a calm teaching companion that helps adults learn tools while working. NO text or letters. One central compact emblem: two thick open-book leaves curve upward to form an inviting arched doorway, a single warm amber path sweeps from the lower left through its center, a small asymmetric amber flame crowns the arch. The left book leaf is deep teal #2F8F86, right leaf muted sage #88A998, the inner doorway warm ivory #FFFAF3, path and flame amber #F2A33A. Read as one unified sculptural cut-paper mark, not a pile of separate icons. Refined 2D painted cut-paper surfaces with very restrained warm gouache grain, strong simple silhouette, broad shapes readable at small size, gently rounded contours. Adult friendly, imaginative and ownable. Square canvas, emblem centered occupying 78% of width and height, ample transparent margin, real alpha background. Flat front view, no perspective, no letters, no watermark, no cast shadow, no stock lightbulb, no graduation cap, no mascot, no mockup. Must work on both ivory and dark plum UI backgrounds.
```

### your-work

```text
Use case: illustration-story. Asset type: original F2L desktop onboarding illustration, square transparent PNG. A refined warm hand-painted gouache and layered cut-paper illustration for an adult teaching companion. The attached image is ONLY the palette, surface texture and visual identity reference; do not repeat its emblem. Deep teal #2F8F86, muted sage #88A998, amber #F2A33A, ivory #FFFAF3, small warm brown accents. Soft tactile paper grain inside shapes, crisp organic outlines, gentle dimensional layers, charming but not childish. One readable central composition occupying 82% of square canvas, generous clear margins. True alpha background, no backdrop rectangle, no text or letters, no numbers, no logos, no mascot, no human, no floating particles or sparkles, no mockup.
Scene: an imaginative miniature workbench: a teal laptop opened on a cream folded paper desk, the screen showing three broad amber and sage spreadsheet blocks (no text), a small amber pencil leaning against two stacked notebooks, and one curving strip of paper flowing from the laptop into a neat open page. Calm organized creativity; an invitation to bring your real work. Compact triangular arrangement, laptop dominant, large simple forms readable at 200 pixels.
```

### your-pace

```text
Use case: illustration-story. Asset type: original F2L desktop onboarding illustration, square transparent PNG. A refined warm hand-painted gouache and layered cut-paper illustration for an adult teaching companion. The attached image is ONLY the palette, surface texture and visual identity reference; do not repeat its emblem. Deep teal #2F8F86, muted sage #88A998, amber #F2A33A, ivory #FFFAF3, small warm brown accents. Soft tactile paper grain inside shapes, crisp organic outlines, gentle dimensional layers, charming but not childish. One readable central composition occupying 82% of square canvas, generous clear margins. True alpha background, no backdrop rectangle, no text or letters, no numbers, no logos, no mascot, no human, no floating particles or sparkles, no mockup.
Scene: three broad smooth stepping stones made of folded cream paper, gently ascending beside a small amber lantern with a soft ivory center. A single teal ribbon connects the stones, and a tiny two-leaf sage sprout grows from the last stone. A calm metaphor for learning at your own pace. Lantern is a simple object with no face, clearly different from a mascot. No trophy, no finish line, no race; welcoming unhurried progress. Compact balanced composition readable at 200 pixels.
```

### your-plan

```text
Use case: illustration-story. Asset type: original F2L desktop onboarding illustration, square transparent PNG. A refined warm hand-painted gouache and layered cut-paper illustration for an adult teaching companion. The attached image is ONLY the palette, surface texture and visual identity reference; do not repeat its emblem. Deep teal #2F8F86, muted sage #88A998, amber #F2A33A, ivory #FFFAF3, small warm brown accents. Soft tactile paper grain inside shapes, crisp organic outlines, gentle dimensional layers, charming but not childish. One readable central composition occupying 82% of square canvas, generous clear margins. True alpha background, no backdrop rectangle, no text or letters, no numbers, no logos, no mascot, no human, no floating particles or sparkles, no mockup.
Scene: a delightful unfolded ivory paper map with a thick curving amber path that connects exactly three teal circular milestones; a small upright amber flag on the last milestone, and a chunky sage pencil alongside the map. No symbols or writing on map, no geography, no dotted microdetails. A concrete personal learning journey. Compact three-quarter view, map dominant, clean forms readable at 200 pixels.
```

### first-spark

```text
Use case: stylized-concept. Asset type: original F2L experience-card illustration. Reference image is palette and painted paper texture only. Square transparent PNG of ONE large simple tactile object icon, centered with 15% margin, true alpha background. Premium warm gouache / cut-paper appearance, crisp soft organic edges. Deep teal #2F8F86, amber #F2A33A, ivory and muted sage. Very few broad forms, legible displayed at only 60 pixels, no microdetails. Adult welcoming education app. NO text, letters, digits, logos, faces, mascot, background disc, framing, shadow outside object, floating glitter or decorative confetti.
Subject: a single little amber flame with a warm ivory core rising from an open teal seed-pod cup. A first spark of learning. Bold friendly asymmetry; one beautiful compact silhouette, no additional objects.
```

### exploring

```text
Use case: stylized-concept. Asset type: original F2L experience-card illustration. Reference image is palette and painted paper texture only. Square transparent PNG of ONE large simple tactile object icon, centered with 15% margin, true alpha background. Premium warm gouache / cut-paper appearance, crisp soft organic edges. Deep teal #2F8F86, amber #F2A33A, ivory and muted sage. Very few broad forms, legible displayed at only 60 pixels, no microdetails. Adult welcoming education app. NO text, letters, digits, logos, faces, mascot, background disc, framing, shadow outside object, floating glitter or decorative confetti.
Subject: a chunky teal magnifying glass with amber short rounded handle, held diagonally, with one simple cream folded page visible inside the circular lens. The feeling of trying and discovering. One compact cohesive object, no eye or text in lens.
```

### daily-practice

```text
Use case: stylized-concept. Asset type: original F2L experience-card illustration. Reference image is palette and painted paper texture only. Square transparent PNG of ONE large simple tactile object icon, centered with 15% margin, true alpha background. Premium warm gouache / cut-paper appearance, crisp soft organic edges. Deep teal #2F8F86, amber #F2A33A, ivory and muted sage. Very few broad forms, legible displayed at only 60 pixels, no microdetails. Adult welcoming education app. NO text, letters, digits, logos, faces, mascot, background disc, framing, shadow outside object, floating glitter or decorative confetti.
Subject: a small thick sage notebook with cream page edges, a teal elastic band and a wide amber bookmark folded over its top. Cover bears one simple large ivory check mark. The feeling of a comfortable everyday learning habit. Three-quarter view, compact and clear, no writing.
```

### app-icon

```text
Use case: logo-brand / identity-preserve. Asset type: finished original F2L desktop application icon, square transparent PNG. The attached image is the exact approved F2L symbol: teal and sage open-book doorway, ivory inner arch, amber winding path and flame. Preserve this identity, simplify only fine texture for small size. Put this emblem centrally on a deep plum #24232F rounded-square tile with very subtly layered painted-paper surface. Tile occupies 88% of square canvas, generous symmetrical transparent margin and fully transparent rounded corners outside the tile. Emblem occupies 72% of tile height. Bold warm amber flame and flowing path, sage and teal book, luminous ivory doorway, high contrast. Flat front view, polished Mac/Windows app icon, slight tactile depth within tile, no cast shadow outside tile. No text, letters, numbers, mockup, surrounding objects, dramatic 3D or glass. One icon only.
```

### launch-landscape

```text
Use case: illustration-story. Asset type: F2L desktop launch-screen background, WIDE landscape 16:9, preferably 1920x1080 or wider. Reference image is only the F2L palette, painted texture and doorway/path motif. Create a serene original paper-cut landscape at dusk: deep plum #191923 sky and gentle layered hills in very dark muted teal and sage, a restrained warm amber path winds along the BOTTOM QUARTER from lower left toward a tiny softly illuminated ivory doorway on the FAR RIGHT edge. A few broad abstract book-page-shaped hills at the bottom corners. Center 65% of image must be almost empty dark plum with subtle paper grain, so large ivory text and Pip can be overlaid clearly. Upper half also dark and calm. Art concentrated along bottom and outer edges. Sophisticated tactile gouache illustration, adult friendly quiet wonder. Do not reproduce the logo, no large flame, no mascot, no text, no letters, no watermark, no stars or busy particles, no UI mockup. Full-bleed opaque image, not transparent.
```

### settings-compass

```text
Use case: stylized-concept. Asset type: F2L settings header illustration, square transparent PNG. Reference image is ONLY palette and warm painted-paper texture. One compact original compass-like tuning dial, ivory circular face in a chunky deep teal housing, a broad asymmetric amber needle, and two small sage rounded adjustment tabs on its outer edge. Suggest finding the settings that fit you; not navigation directions. No letters, compass labels, numbers, tick marks, gear teeth, text or logo. Broad simple forms readable at 60 pixels, crisp organic edges with subtle warm gouache grain. Slight three-quarter angle, centered with 15% clear margin. True alpha, no background disc behind the object, no shadow outside the object, no mascot, no floating decorations.
```
