#!/usr/bin/env python3
"""Package the generated PNG master into native desktop icon formats; no artwork is redrawn.

Requires Pillow. Run from any directory: python3 scripts/tools/package_brand_icons.py
The original app-icon.png remains unchanged.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "Windows/F2L.Windows/Assets/Brand"


def main() -> None:
    with Image.open(BRAND / "app-icon.png") as source:
        if source.width != source.height or "A" not in source.getbands():
            raise ValueError("The app icon must be a square PNG with alpha")
        icon = source.convert("RGBA").resize((1024, 1024), Image.Resampling.LANCZOS)
        icon.save(BRAND / "F2L.icns", format="ICNS")
        icon.save(BRAND / "F2L.ico", format="ICO", sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
    print("Packaged F2L.icns and F2L.ico from app-icon.png")


if __name__ == "__main__":
    main()
