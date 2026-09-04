#!/usr/bin/env python3
"""Cut `data/atlas_bc20.png` + `data/atlas_bc20.json` from the 2020 client art.

CI-TIME ONLY. The source is `battlecode20/client/visualizer/src/static/img/**`
at the pinned commit (GPL-3.0, credited in NOTICE); the atlas is COMMITTED so
the runtime image and the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc20.py --engine /path/to/battlecode20 --out data

Palette follows the ENGINE SIDE, not the seat: red = side A, blue = side B,
exactly as the 2020 client draws it. Because sides alternate every game the
scorebug plate keeps the alias constant and recolours its swatch per game.
It looks like Battlecode 2020 because it IS Battlecode 2020's art.
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
    "hq_red": "sprites/HQ_red.png",
    "hq_blue": "sprites/HQ_blue.png",
    "miner_red": "sprites/Miner_red.png",
    "miner_blue": "sprites/Miner_blue.png",
    "landscaper_red": "sprites/Landscaper_red.png",
    "landscaper_blue": "sprites/Landscaper_blue.png",
    "drone_red": "sprites/Drone_red.png",
    "drone_blue": "sprites/Drone_blue.png",
    "drone_red_carry": "sprites/Drone_red_carry.png",
    "drone_blue_carry": "sprites/Drone_blue_carry.png",
    "refinery_red": "sprites/Refinery_red.png",
    "refinery_blue": "sprites/Refinery_blue.png",
    "vaporator_red": "sprites/Vaporator_red.png",
    "vaporator_blue": "sprites/Vaporator_blue.png",
    # SOUPER_* is the 2020 client's own file name for the Design School.
    "design_school_red": "sprites/SOUPER_red.png",
    "design_school_blue": "sprites/SOUPER_blue.png",
    "fulfillment_center_red": "sprites/Fulfillment_red.png",
    "fulfillment_center_blue": "sprites/Fulfillment_blue.png",
    "net_gun_red": "sprites/Net_gun_red.png",
    "net_gun_blue": "sprites/Net_gun_blue.png",
    "cow": "sprites/Cow.png",
    "soup": "soup.png",
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
            raise SystemExit(f"::error::missing 2020 client sprite: {source}")
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
    png = args.out / "atlas_bc20.png"
    meta = args.out / "atlas_bc20.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc20.json differs from a fresh cut of the client art")
            return 1
        print("bc20 atlas matches the 2020 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
