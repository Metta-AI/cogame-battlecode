#!/usr/bin/env python3
"""Cut `data/atlas_bc22.png` + `data/atlas_bc22.json` from the 2022 client art.

CI-TIME ONLY. The source is
`battlecode22/client/visualizer/src/static/img/**` at the pinned commit
`6ed05b679c0822e9bbe332812ff5655812dd023e`; the atlas is COMMITTED so the
runtime image and the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc22.py --engine /path/to/battlecode22 --out data

LICENCE, RECORDED HONESTLY. `battlecode22/client/LICENSE` **is** the GNU AGPL
v3, while `client/package.json` declares `"license": "GPL-3.0"`. Both facts are
recorded in `NOTICE`; the AGPL file is the one the repository relies on, and the
repository as a whole stays AGPL-3.0.

PALETTE FOLLOWS THE CLIENT'S OWN TWO TEAM COLOURS: the 2022 client ships every
robot sprite as `robots/blue_*.png` and `robots/red_*.png`, so BLUE = side A and
RED = side B. Because sides alternate every game the scorebug plate keeps the
ALIAS constant and recolours its swatch per game.

THE TERRAIN COLOURS ARE NOT IN HERE. The 2022 client draws its board from
photographic tiles (`tiles/terrain*.png`) that do not survive a 16 px cut, so
`render.nim` carries this repository's own paintbot-derived RUBBLE HEAT RAMP —
five steps from bare ground to near-black — and uses the atlas only for the
units, the two resource glyphs and `star.png`.

WHAT MAKES THIS YEAR'S CUT DIFFERENT FROM EVERY OTHER ONE. A bc22 building has
three orthogonal display states the rules make real, so the atlas carries all
of them rather than one sprite per type:

  * a LEVEL (1, 2 or 3) — `robots/{team}_{archon,lab,watchtower}_level{1,2,3}`;
  * a PROTOTYPE state, which can neither act nor move until a builder fills it
    — `robots/{team}_{archon,lab,watchtower}_prototype`;
  * a PORTABLE state, which moves and cannot act — and which takes NOTHING from
    a FURY, the year's largest unexploited play —
    `robots/{team}_{archon,lab,watchtower}_portable_level{1,2,3}`.

The upstream set is 177 PNGs, of which `robots/` holds 56; this cut uses 48 of
those plus `resources/lead.png`, `resources/gold.png` and `star.png`.
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

TILE = 16          # board pixels per map square in the viewer's native render
COLUMNS = 8

DROIDS = ["miner", "builder", "soldier", "sage"]
BUILDINGS = ["archon", "lab", "watchtower"]

# sprite name -> file under client/visualizer/src/static/img
SPRITE_FILES = {}
for _team in ("blue", "red"):
    for _kind in DROIDS:
        SPRITE_FILES[f"{_team}_{_kind}"] = f"robots/{_team}_{_kind}.png"
    for _kind in BUILDINGS:
        SPRITE_FILES[f"{_team}_{_kind}_prototype"] = \
            f"robots/{_team}_{_kind}_prototype.png"
        for _level in (1, 2, 3):
            SPRITE_FILES[f"{_team}_{_kind}_level{_level}"] = \
                f"robots/{_team}_{_kind}_level{_level}.png"
            SPRITE_FILES[f"{_team}_{_kind}_portable_level{_level}"] = \
                f"robots/{_team}_{_kind}_portable_level{_level}.png"
SPRITE_FILES["lead"] = "resources/lead.png"
SPRITE_FILES["gold"] = "resources/gold.png"
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
            raise SystemExit(f"::error::missing 2022 client sprite: {source}")
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
    png = args.out / "atlas_bc22.png"
    meta = args.out / "atlas_bc22.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas_bc22.json differs from a fresh cut of the client art")
            return 1
        print("bc22 atlas matches the 2022 client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
