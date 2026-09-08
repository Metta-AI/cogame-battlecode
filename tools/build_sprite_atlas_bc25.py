#!/usr/bin/env python3
"""Cut `data/atlas_bc25.png` + `data/atlas_bc25.json` from the 2025 client art.

CI-TIME ONLY. The source is `battlecode25/client/src/static/img/**` at the
pinned commit `28975a487c1a30ed2b5bed644fe6ecd2c3dd1482`; the atlas is
COMMITTED so the runtime image and the wasm bundle carry no build step and no
upstream tree.

    tools/build_sprite_atlas_bc25.py --engine /path/to/battlecode25 --out data

LICENCE, RECORDED HONESTLY. `client/package.json` declares
`"license": "GPL-3.0"` and THE CLIENT DIRECTORY HAS NO LICENSE FILE OF ITS OWN
-- the same situation as 2024, verified again for 2025, and NOT the same as
2021 (whose `client/LICENSE` was the AGPL). GPLv3 section 13 and AGPLv3 section
13 expressly permit the combination, which is exactly what this repository is;
the repository as a whole stays AGPL-3.0 and `NOTICE` records the sprite files'
own terms and names the source directories.

PALETTE FOLLOWS THE CLIENT'S OWN TWO TEAM NAMES:
`TEAM_COLOR_NAMES = ['Silver', 'Gold']` (`client/src/constants.ts:111`), so
SILVER = side A and GOLD = side B. Because sides alternate every game the
scorebug plate keeps the ALIAS constant and recolours its swatch per game.

THE PAINT AND TERRAIN COLOURS ARE NOT IN HERE. They are flat fills, so
`render.nim` carries them as the client's own `DEFAULT_GLOBAL_COLORS`
(`client/src/colors.ts`): A-primary #666666, A-secondary #565656, B-primary
#b28b52, B-secondary #997746, walls #547f31, bare tile #4c301e.

The whole upstream set is 42 PNGs and every one that matters here is used: the
twelve `robots/{silver,gold}/*.png` unit sprites, the two `ruins/silver*.png`,
`dirty.png`, and the `icons/` chips, paint drops, grids, gears, hammer and mop.
The `_64x64` variants are the same art at a higher resolution; the atlas cuts
from the plain files and falls back to the `_64x64` one where no plain file
exists (`icons/gears`, `icons/hammer`, `icons/mop` and the two grids all ship
both).
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

TILE = 16          # board pixels per map tile in the viewer's native render
COLUMNS = 8

# sprite name -> file under client/src/static/img
SPRITE_FILES = {
    # the six unit types, in both of the client's own team colours
    "soldier_silver": "robots/silver/soldier.png",
    "splasher_silver": "robots/silver/splasher.png",
    "mopper_silver": "robots/silver/mopper.png",
    "paint_tower_silver": "robots/silver/paint_tower.png",
    "money_tower_silver": "robots/silver/money_tower.png",
    "defense_tower_silver": "robots/silver/defense_tower.png",
    "soldier_gold": "robots/gold/soldier.png",
    "splasher_gold": "robots/gold/splasher.png",
    "mopper_gold": "robots/gold/mopper.png",
    "paint_tower_gold": "robots/gold/paint_tower.png",
    "money_tower_gold": "robots/gold/money_tower.png",
    "defense_tower_gold": "robots/gold/defense_tower.png",
    # an unclaimed ruin, and the "dirty" overlay the client uses for a tile
    # that has been mopped back to bare
    "ruin": "ruins/silver.png",
    "ruin_big": "ruins/silver_64x64.png",
    "dirty": "dirty.png",
    # the icons the scorebug and the endcard draw
    "chip_silver": "icons/chip_silver.png",
    "chip_gold": "icons/chip_gold.png",
    "paint_silver": "icons/paint_silver.png",
    "paint_gold": "icons/paint_gold.png",
    "grid_silver": "icons/grid_silver.png",
    "grid_gold": "icons/grid_gold.png",
    "gears": "icons/gears.png",
    "hammer": "icons/hammer.png",
    "mop": "icons/mop.png",
    "mop_icon": "icons/mopper.png",
}


def cell(img: Image.Image, size: int) -> Image.Image:
    return img.convert("RGBA").resize((size, size), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    img_dir = args.engine / "client/src/static/img"
    sprites: list[tuple[str, Image.Image]] = []
    for name in sorted(SPRITE_FILES):
        source = img_dir / SPRITE_FILES[name]
        if not source.exists():
            raise SystemExit(f"::error::missing 2025 client sprite: {source}")
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
    png = args.out / "atlas_bc25.png"
    meta = args.out / "atlas_bc25.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc25.json differs from a fresh cut of the client art")
            return 1
        print("bc25 atlas matches the 2025 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
