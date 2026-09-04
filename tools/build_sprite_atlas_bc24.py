#!/usr/bin/env python3
"""Cut `data/atlas_bc24.png` + `data/atlas_bc24.json` from the 2024 client art.

CI-TIME ONLY. The source is `battlecode24/client/src/static/img/**` at the
pinned commit `166c79bbf4156c866caf434062cb1f403c01695f`; the atlas is
COMMITTED so the runtime image and the wasm bundle carry no build step and no
upstream tree.

    tools/build_sprite_atlas_bc24.py --engine /path/to/battlecode24 --out data

LICENCE, RECORDED HONESTLY. `client/package.json` declares
`"license": "GPL-3.0"` and THE CLIENT DIRECTORY HAS NO LICENSE FILE OF ITS OWN
-- unlike battlecode21, whose `client/LICENSE` was the AGPL. GPLv3 section 13
and AGPLv3 section 13 expressly permit the combination, which is exactly what
this repository is; the repository as a whole stays AGPL-3.0 and `NOTICE`
records the sprite files' own terms and names the source directories.

PALETTE FOLLOWS THE CLIENT'S OWN TWO TEAM COLOURS: brown = side A, white =
side B. Because sides alternate every game the scorebug plate keeps the ALIAS
constant and recolours its swatch per game.

TERRAIN IS NOT IN HERE. The 2024 client draws land, water, walls and the dam
procedurally, so there is nothing upstream to reuse and nothing to credit;
`render.nim` draws them in this repository's own paintbot-derived tile palette.
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
    # the one unit type, in both team colours, by dominant skill plus jailed
    "duck_brown": "robots/brown/base.png",
    "duck_brown_attack": "robots/brown/attack.png",
    "duck_brown_build": "robots/brown/build.png",
    "duck_brown_heal": "robots/brown/heal.png",
    "duck_brown_jailed": "robots/brown/jailed.png",
    "duck_white": "robots/white/base.png",
    "duck_white_attack": "robots/white/attack.png",
    "duck_white_build": "robots/white/build.png",
    "duck_white_heal": "robots/white/heal.png",
    "duck_white_jailed": "robots/white/jailed.png",
    # traps, in both team colours and the neutral cut the endcard uses
    "trap_brown_explosive": "traps/brown/explosive.png",
    "trap_brown_stun": "traps/brown/stun.png",
    "trap_brown_water": "traps/brown/water.png",
    "trap_white_explosive": "traps/white/explosive.png",
    "trap_white_stun": "traps/white/stun.png",
    "trap_white_water": "traps/white/water.png",
    "trap_explosive": "traps/explosive.png",
    "trap_stun": "traps/stun.png",
    "trap_water": "traps/water.png",
    # the flag, and the crumb piles sized by amount
    "flag": "resources/bread.png",
    "flag_outline": "resources/bread_outline.png",
    "flag_outline_thick": "resources/bread_outline_thick.png",
    "crumb_1": "resources/crumb_1.png",
    "crumb_2": "resources/crumb_2.png",
    "crumb_3": "resources/crumb_3.png",
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
            raise SystemExit(f"::error::missing 2024 client sprite: {source}")
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
    png = args.out / "atlas_bc24.png"
    meta = args.out / "atlas_bc24.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc24.json differs from a fresh cut of the client art")
            return 1
        print("bc24 atlas matches the 2024 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
