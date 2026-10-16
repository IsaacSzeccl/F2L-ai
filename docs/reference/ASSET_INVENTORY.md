# F2L asset inventory

Audited and archived on 8 October 2026. All visual assets created for this project during the companion work are stored inside this checkout, together with generation prompts and the bundled font licence. The four generated PNGs were checked against their original tool outputs and match byte for byte.

See [CHANGELOG.md](../../CHANGELOG.md) for implementation changes and validation, and [asset-manifest.json](../asset-manifest.json) for exact byte sizes, dimensions and SHA-256 hashes. Paths in the manifest are relative to the repository root.

## Production assets

### Original F2L brand collection — 11 October 2026

Ten new original PNGs now give the application its own identity beyond Pip: an open-book doorway emblem, a desktop icon, a dusk landscape for the entry screen, three distinct setup illustrations, three learning-experience badges, and a Settings compass. They are integrated in both desktop hosts. The original generated PNG bytes are preserved, with native `.icns` and `.ico` files packaged from the icon master.

See the [visual catalog](../previews/f2l-brand-board.png), [brand assets](../../Windows/F2L.Windows/Assets/Brand/), [setup illustrations](../../Windows/F2L.Windows/Assets/Illustrations/), and [exact prompts and usage map](../../Windows/F2L.Windows/Assets/Brand/ARTWORK.md). Reproduce the catalog with `swift scripts/tools/preview_brand.swift` and the platform icons with `python3 scripts/tools/package_brand_icons.py`.

### Pip and supporting resources

Added on 11 October 2026: `playful.png`, a third 16-pose atlas for wink, dance, stretch and peekaboo idle animations. Both apps now consume 48 poses. Its exact built-in image-generation prompt is recorded in `ARTWORK.md`; `scripts/tools/preview_pip.swift` renders four looping GIF previews into `build/pip-previews/`.

| Asset | Purpose and source |
|---|---|
| [expressions.png](../../Windows/F2L.Windows/Assets/Pip/expressions.png) | 1254 × 1254 transparent atlas; 16 painted expression/speech poses. Generated on 8 October from the original Pip concept. |
| [directions.png](../../Windows/F2L.Windows/Assets/Pip/directions.png) | 1254 × 1254 transparent atlas; 16 pointing, profile, walking and rear-view poses. Generated on 8 October using the expression atlas as the character reference. |
| [playful.png](../../Windows/F2L.Windows/Assets/Pip/playful.png) | 1254 × 1254 transparent atlas; 16 wink, dance, yawn/stretch and peekaboo frames. Generated on 11 October using expressions.png as the character reference. |
| [welcome-journey.png](../../Windows/F2L.Windows/Assets/Pip/welcome-journey.png) | 1254 × 1254 transparent illustration for the first-time setup window (Pip reading on a stack of books beside a path). Generated on 8 October with the production Pip as reference. |
| [Emotes/](../../Windows/F2L.Windows/Assets/Pip/Emotes) | Six 256 × 256 Pip emotes (hello, happy, cheer, thinking, curious, focused) used instead of system emoji. Generated from expressions.png poses with drawn accents by `F2L --export-emotes`; see ARTWORK.md. |
| [ai-tools.json](../../Windows/F2L.Windows/Assets/Knowledge/ai-tools.json) | Pip's AI tools library: 68 tools with summary, official site, platforms, access, getting-started steps, features and suited kinds of work. Written for F2L on 11 October 2026; read by both apps. Update its `checked` date and this manifest's hash when it changes. |
| [ARTWORK.md](../../Windows/F2L.Windows/Assets/Pip/ARTWORK.md) | Exact production generation prompts, reference link and reviewed frame-selection exceptions. |
| [Inter-Regular.ttf](../../Windows/F2L.Windows/Assets/Fonts/Inter-Regular.ttf) | Regular UI font from the official Inter 4.1 distribution. |
| [Inter-Medium.ttf](../../Windows/F2L.Windows/Assets/Fonts/Inter-Medium.ttf) | Medium UI font from the same distribution. |
| [Inter-SemiBold.ttf](../../Windows/F2L.Windows/Assets/Fonts/Inter-SemiBold.ttf) | Semibold UI font from the same distribution. |
| [LICENSE.txt](../../Windows/F2L.Windows/Assets/Fonts/LICENSE.txt) | Inter's bundled SIL Open Font License; retain alongside redistributed font files. |

Font provenance: [official Inter 4.1 release](https://github.com/rsms/inter/releases/tag/v4.1), downloaded from its `Inter-4.1.zip` release asset. Artwork provenance: the built-in image-generation tool, using this project's original Pip design. No external mascot artwork is used for Pip.

The [Windows project](../../Windows/F2L.Windows/F2L.Windows.csproj) embeds both PNGs and all three fonts as WPF resources and copies the font licence to build output. [PipSprites.cs](../../Windows/F2L.Windows/PipSprites.cs) maps the source figures to frames without rewriting the PNGs. [PipView.xaml.cs](../../Windows/F2L.Windows/PipView.xaml.cs) defines animation sequences. The source assets are sufficient to rebuild the character; no temporary directory, image-generation cache or online image URL is required at runtime. The same PNGs are available for future Mac integration.

## Design originals and previews

| Asset | Purpose and provenance |
|---|---|
| [character-studies.png](../companion-concepts/character-studies.png) | Original 1774 × 887 Pip/Mori/Tiko exploration. Preserved unchanged, including its historical Beacon subtitle. |
| [character-studies-f2l.png](../companion-concepts/character-studies-f2l.png) | 1774 × 887 F2L-labelled concept revision; the left-column Pip is the production character reference. |
| [IMAGE_PROMPT.md](../companion-concepts/IMAGE_PROMPT.md) | Original exploration and brand-revision prompts, dated 7 October. |
| [layout-exploration-2026-10-07.html](../companion-concepts/layout-exploration-2026-10-07.html) | Unchanged archive of the original interactive layout study, copied from the conversation's visualization workspace. Historical Beacon wording and shape-based placeholder art remain as design history; this is not the current app or production character. The original host supplied carousel navigation and optional Tweak controls; a standalone browser may show only the first layout. |
| [pip-ui-before-textures.png](../previews/pip-ui-before-textures.png) | 948 × 939 controlled WPF preview from before the painted character replacement. Archived from `Windows/artifacts/pip-conversation.png`. |
| [pip-ui-textured.png](../previews/pip-ui-textured.png) | 948 × 939 controlled WPF preview after the painted character update. Archived from `Windows/artifacts/pip-textured-ui.png`. |

The previews contain synthetic demonstration messages, not captures of a user's working application. All six images above and in production retain their original PNG bytes. Generated character artwork is used as received; no editable layered painting source was produced.

## Storage and verification

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-assets.ps1
```

This command allows the local verification script for that PowerShell process only; it does not change the machine's execution-policy setting. The verifier checks every manifest entry for existence, byte size and SHA-256 equality, and reports any unlisted file in the three asset roots: `Windows/F2L.Windows/Assets/`, `docs/companion-concepts/` and `docs/previews/`. It does not modify assets or update hashes automatically. For an intentional asset change, review the image and provenance, then update its manifest entry and this inventory. Keep new assets inside one of those roots.

The root `.gitattributes` disables Git line-ending conversion inside those asset roots, including prompt and licence text, so the recorded bytes survive Windows/macOS checkouts unchanged.

These files are eligible for source control; they are saved locally but are not guaranteed to be committed, pushed or backed up merely by being listed here. The app's built executables and temporary preview output remain reproducible build artifacts. Runtime conversations live at `%LOCALAPPDATA%\F2L\conversation.json`; API keys remain in the ignored local settings file. Neither is part of this archive. The installed desktop shortcut is an external installation item documented in the change log.
