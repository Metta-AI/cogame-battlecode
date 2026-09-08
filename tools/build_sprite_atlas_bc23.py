#!/usr/bin/env python3
"""Cut `data/atlas_bc23.png` + `data/atlas_bc23.json` from the 2023 client art.

CI-TIME ONLY. The source is
`battlecode23/client/visualizer/src/static/img/**` at the pinned commit
`af42086ecd09709dc603b2aaa9e9b98312c9ef79`; the atlas is COMMITTED so the
runtime image and the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc23.py --engine /path/to/battlecode23 --out data

LICENCE, RECORDED HONESTLY AND IT IS SIMPLER THIS YEAR.
`battlecode23/client/LICENSE` **is** the GNU AGPL v3 — unlike 2024 and 2025,
whose clients carried no LICENSE file at all — while
`client/package.json` declares `"license": "GPL-3.0"`. Both facts are recorded
in `NOTICE`; the AGPL file is the one the repository relies on, and the
repository as a whole stays AGPL-3.0.

PALETTE FOLLOWS THE CLIENT'S OWN TWO TEAM COLOURS: the 2023 client ships every
robot sprite as `robots/blue_*.png` and `robots/red_*.png`, so BLUE = side A
and RED = side B. Because sides alternate every game the scorebug plate keeps
the ALIAS constant and recolours its swatch per game.

THE TERRAIN COLOURS ARE NOT IN HERE. The 2023 client draws its board from
photographic tiles (`tiles/terrain*.png`) that do not survive a 16 px cut, so
`render.nim` carries this repository's own paintbot-derived tones for the
storm squares, clouds and currents and uses the atlas only for the units, the
wells, the two anchors and the resource glyphs.

The upstream set is 83 PNGs and every one that matters here is used: the
twelve `robots/{blue,red}_*.png` unit sprites, the six well sprites with their
upgraded variants, the two anchors, the three resource glyphs and `star.png`.
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

TILE = 16          # board pixels per map tile in the viewer's native render
COLUMNS = 8

ROBOTS = ["headquarters", "carrier", "launcher", "amplifier", "destabilizer",
          "booster"]

# sprite name -> file under client/visualizer/src/static/img
SPRITE_FILES = {}
for _team in ("blue", "red"):
    for _kind in ROBOTS:
        SPRITE_FILES[f"{_team}_{_kind}"] = f"robots/{_team}_{_kind}.png"
for _res in ("adamantium", "mana", "elixir"):
    SPRITE_FILES[_res] = f"resources/{_res}.png"
    SPRITE_FILES[f"{_res}_well"] = f"resources/{_res}_well.png"
    SPRITE_FILES[f"{_res}_well_upgraded"] = f"resources/{_res}_well_upgraded.png"
SPRITE_FILES["anchor"] = "resources/anchor.png"
SPRITE_FILES["accelerating_anchor"] = "resources/accelerating_anchor.png"
SPRITE_FILES["star"] = "star.png"


def cell(img: Image.Image, size: int) -> Image.Image:
    return img.convert("RGBA").resize((size, size), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    img_dir = args.engine / "client/visualizer/src/static/img"
    sprites: list[tuple[str, Image.Image]] = []
    for name in sorted(SPRITE_FILES):
        source = img_dir / SPRITE_FILES[name]
        if not source.exists():
            raise SystemExit(f"::error::missing 2023 client sprite: {source}")
        sprites.append((name, cell(Image.open(source), TILE)))

    width_cell = max(s.width for _, s in sprites)
    height_cell = max(s.height for _, s in sprites)
    rows = (len(sprites) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (COLUMNS * width_cell, rows * height_cell),
                      (0, 0, 0, 0))
    index: dict[str, dict[str, int]] = {}
    for i, (name, sprite) in enumerate(sprites):
        x = (i % COLUMNS) * width_cell
        y = (i // COLUMNS) * height_cell
        atlas.paste(sprite, (x, y))
        index[name] = {"x": x, "y": y, "w": sprite.width, "h": sprite.height}

    args.out.mkdir(parents=True, exist_ok=True)
    png = args.out / "atlas_bc23.png"
    meta = args.out / "atlas_bc23.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc23.json differs from a fresh cut of the client art")
            return 1
        print("bc23 atlas matches the 2023 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
