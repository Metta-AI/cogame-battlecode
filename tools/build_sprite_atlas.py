#!/usr/bin/env python3
"""Cut `data/atlas.png` + `data/atlas.json` from the official client art.

CI-TIME ONLY. The source is `battlecode26/client/src/static/img/**` at tag
engine.1.2.5 (AGPL-3.0, credited in NOTICE); the atlas is COMMITTED so the
runtime image and the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas.py --engine /path/to/battlecode26-engine.1.2.5 \
        --out data

The two clan palettes come straight from the client's own two rat palettes:
`yellow` is Clan Ash's cheddar and `pink` is Clan Basil's plum. It looks like
Battlecode because it IS Battlecode's art.
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

TILE = 16          # board pixels per map tile in the viewer's native render
COLUMNS = 12

PALETTES = {"cheddar": "yellow", "plum": "pink"}
# rat_<n> follows Direction.DIRECTION_ORDER: 0 CENTER, 1 W, 2 SW, 3 S,
# 4 SE, 5 E, 6 NE, 7 N, 8 NW -- the same ordinal the map files and the
# replay use, so the renderer can index it directly.
DIR_FRAMES = list(range(9))


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

    for palette, source in PALETTES.items():
        for n in DIR_FRAMES:
            sprites.append((
                f"rat_{palette}_{n}",
                cell(Image.open(img_dir / f"robots/{source}/rat_{n}_64x64.png"),
                     TILE)))
        sprites.append((
            f"king_{palette}",
            cell(Image.open(img_dir / f"robots/{source}/rat_king_64x64.png"),
                 TILE * 3)))

    for n in DIR_FRAMES:
        sprites.append((f"cat_{n}",
                        cell(Image.open(img_dir / f"robots/cat/cat_{n}.png"),
                             TILE * 2)))
    # The pounce sheet only carries the four diagonals; scratch and feed
    # carry the full nine. One representative frame each is enough for the
    # board at this scale.
    for pose, frame in (("pounce", 1), ("scratch", 0), ("feed", 0)):
        sprites.append((
            f"cat_{pose}",
            cell(Image.open(img_dir / f"robots/cat/cat_{pose}_{frame}.png"),
                 TILE * 2)))
    sprites.append(("cat_sleep",
                    cell(Image.open(img_dir / "robots/cat/cat_feed_4.png"),
                         TILE * 2)))

    for name, path, size in (
        ("cheese", "icons/cheese_64x64.png", TILE),
        ("cheese_mine", "icons/cheese_mine.png", TILE),
        ("rat_trap", "icons/rat_trap.png", TILE),
        ("cat_trap", "icons/cat_trap.png", TILE),
        ("dirt", "icons/dirt.png", TILE),
        ("squeak", "robots/squeak.png", TILE),
    ):
        sprites.append((name, cell(Image.open(img_dir / path), size)))

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
    png = args.out / "atlas.png"
    meta = args.out / "atlas.json"
    doc = json.dumps({"tile": TILE, "sprites": index},
                     sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != doc:
            print("atlas.json differs from a fresh cut of the client art")
            return 1
        print("atlas matches the client art")
        return 0

    atlas.save(png, optimize=True)
    meta.write_text(doc)
    print(f"wrote {png} ({png.stat().st_size} bytes) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
