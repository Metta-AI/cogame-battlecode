#!/usr/bin/env python3
"""Cut `data/atlas_bc21.png` + `data/atlas_bc21.json` from the 2021 client art.

CI-TIME ONLY. The source is `battlecode21/client/visualizer/src/static/img/**`
at the pinned commit `ed39c1a49574db57e5463d720736220506280294`
(`client/LICENSE` is the GNU AGPL v3, the same licence this repository carries;
credited in NOTICE); the atlas is COMMITTED so the runtime image and the wasm
bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc21.py --engine /path/to/battlecode21 --out data

Palette follows the ENGINE SIDE, not the seat: red = side A, blue = side B,
exactly as the 2021 client draws it. Because sides alternate every game the
scorebug plate keeps the alias constant and recolours its swatch per game.
It looks like Battlecode 2021 because it IS Battlecode 2021's art.
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

TILE = 16          # board pixels per map tile in the viewer's native render
COLUMNS = 8

# sprite name -> file under client/visualizer/src/static/img
SPRITE_FILES = {
    # the four robot types, in both engine colours plus the neutral cut
    "center": "robots/center.png",
    "center_red": "robots/center_red.png",
    "center_blue": "robots/center_blue.png",
    "polit": "robots/polit.png",
    "polit_red": "robots/polit_red.png",
    "polit_blue": "robots/polit_blue.png",
    "slanderer": "robots/slanderer.png",
    "slanderer_red": "robots/slanderer_red.png",
    "slanderer_blue": "robots/slanderer_blue.png",
    "muck": "robots/muck.png",
    "muck_red": "robots/muck_red.png",
    "muck_blue": "robots/muck_blue.png",
    # the terrain pair the passability ramp interpolates between
    "dirt": "tiles/DirtTerrain.png",
    "raw_dirt": "tiles/RawDirtTerrain.png",
    "swamp": "tiles/SwampTerrain.png",
    "raw_swamp": "tiles/RawSwampTerrain.png",
    "terrain": "tiles/terrain.png",
    # effects
    "empower_red_1": "effects/empower/polit_empower_red_1.png",
    "empower_red_2": "effects/empower/polit_empower_red_2.png",
    "empower_blue_1": "effects/empower/polit_empower_blue_1.png",
    "empower_blue_2": "effects/empower/polit_empower_blue_2.png",
    "empower_empty_1": "effects/empower/polit_empower_empty_1.png",
    "empower_empty_2": "effects/empower/polit_empower_empty_2.png",
    "expose_red": "effects/expose/expose_red.png",
    "expose_blue": "effects/expose/expose_blue.png",
    "expose_empty": "effects/expose/expose_empty.png",
    "expose_empty_small": "effects/expose/expose_empty_small.png",
    "camo_red": "effects/camouflage/camo_red.png",
    "camo_blue": "effects/camouflage/camo_blue.png",
    "embezzle_red_1": "effects/embezzle/slanderer_embezzle_red_1.png",
    "embezzle_red_2": "effects/embezzle/slanderer_embezzle_red_2.png",
    "embezzle_blue_1": "effects/embezzle/slanderer_embezzle_blue_1.png",
    "embezzle_blue_2": "effects/embezzle/slanderer_embezzle_blue_2.png",
    "embezzle_empty_1": "effects/embezzle/slanderer_embezzle_empty_1.png",
    "embezzle_empty_2": "effects/embezzle/slanderer_embezzle_empty_2.png",
    "death_empty": "effects/death/death_empty.png",
}


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
            raise SystemExit(f"::error::missing 2021 client sprite: {source}")
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
    png = args.out / "atlas_bc21.png"
    meta = args.out / "atlas_bc21.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc21.json differs from a fresh cut of the client art")
            return 1
        print("bc21 atlas matches the 2021 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
