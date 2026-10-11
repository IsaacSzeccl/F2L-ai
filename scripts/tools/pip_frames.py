#!/usr/bin/env python3
"""Regenerates Assets/Pip/frames.json from the three Pip atlases.

The atlases hold 16 transparent poses each. Finding them means flood-filling ~1.5M pixels per atlas,
so both apps read the precomputed rectangles instead of repeating the scan on every launch.
Run this only after replacing the artwork:  python3 scripts/tools/pip_frames.py
"""
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PIP = ROOT / "Windows" / "F2L.Windows" / "Assets" / "Pip"
ALPHA_MIN = 48  # same threshold as PipSprites.FindFrames


def find_frames(path: Path) -> list[list[int]]:
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    alpha = image.getchannel("A").tobytes()
    seen = bytearray(width * height)
    regions = []
    for start in range(width * height):
        if seen[start] or alpha[start] < ALPHA_MIN:
            continue
        seen[start] = 1
        queue = deque([start])
        left, right, top, bottom, count = width, 0, height, 0, 0
        while queue:
            pixel = queue.popleft()
            x, y = pixel % width, pixel // width
            count += 1
            left, right, top, bottom = min(left, x), max(right, x), min(top, y), max(bottom, y)
            for n, ok in ((pixel - 1, x > 0), (pixel + 1, x + 1 < width), (pixel - width, y > 0), (pixel + width, y + 1 < height)):
                if ok and not seen[n] and alpha[n] >= ALPHA_MIN:
                    seen[n] = 1
                    queue.append(n)
        if count < width * height / 1000:
            continue
        x0, y0 = max(0, left - 2), max(0, top - 2)
        regions.append((count, [x0, y0, min(width - 1, right + 2) - x0 + 1, min(height - 1, bottom + 2) - y0 + 1]))
    actors = sorted((r for _, r in sorted(regions, key=lambda r: -r[0])[:16]), key=lambda r: r[1] + r[3] / 2)
    if len(actors) != 16:
        sys.exit(f"{path.name}: expected 16 poses, found {len(actors)}")
    rows = [sorted(actors[i:i + 4], key=lambda r: r[0] + r[2] / 2) for i in range(0, 16, 4)]
    return [rect for row in rows for rect in row]


def main() -> None:
    manifest = {"version": 1, "displayWidth": 288, "canvas": [320, 340], "baseline": 325}
    for name in ("expressions", "directions", "playful"):
        image = Image.open(PIP / f"{name}.png")
        manifest[name] = {"atlas": list(image.size), "frames": find_frames(PIP / f"{name}.png")}
    out = PIP / "frames.json"
    out.write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"Wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
