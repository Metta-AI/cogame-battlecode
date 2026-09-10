#!/usr/bin/env python3
"""Cut `data/atlas_bc17.png` + `data/atlas_bc17.json` from the 2017 client art.

CI-TIME ONLY. The source is `battlecode/battlecode-client-17` at the pinned
commit `feb3e03820ba442ab233f05d2432b0dc2833aa98`, exactly TWENTY-TWO files.

(The design note calls this set "twenty-one" in its headline while its own
file list -- fourteen team sprites, five map sprites, three bullet sprites --
enumerates twenty-two. The ENUMERATION is what is implemented and what
`NOTICE` records; the headline count is an arithmetic slip against it.)
The atlas is COMMITTED so the runtime image and the wasm bundle carry no build
step and no upstream tree.

    tools/build_sprite_atlas_bc17.py --client /path/to/battlecode-client-17 \
        --out data
    tools/build_sprite_atlas_bc17.py --client ... --out data --check

LICENCE, RECORDED HONESTLY AND VERIFIED BEFORE PINNING. The repository ROOT
`LICENSE` is the GNU AFFERO GENERAL PUBLIC LICENSE v3 -- **the same licence
this repository carries**, so there is no combination argument to make at all
-- while `package.json` declares `"license": "GPL-3.0"`. THE TWO DISAGREE, both
are compatible with this repository's AGPL-3.0, and `NOTICE` records the
discrepancy rather than papering over it. NO CLIENT CODE IS SHIPPED, BUILT OR
EMBEDDED -- only the images.

The exact twenty-one files, with their real upstream dimensions:

    src/static/img/sprites/{archon,tank}_{red,blue}.png              50x50
    src/static/img/sprites/{gardener,lumberjack,soldier,scout,
                            bullet_tree}_{red,blue}.png              32x32
    src/static/img/map/{full_health_tree,low_health_tree,sapling,
                        tree_bullets,tree_robots}.png                32x32
    src/static/img/bullets/bullet_{slow,medium,fast}.png          26/18/16

`sprites/*_neutral.png`, `sprites/recruit_*.png` (a unit type the shipped
`RobotType` does not have), `sprites/unknown.png`, `src/static/img/controls/`
(the client's own transport icons -- this repository has its own chrome),
`yellow_star.png` and `map/tiled_1.jpg` (a background texture the float
renderer does not want) are NOT used, NOT cut and NOT shipped.

RED IS TEAM A AND BLUE IS TEAM B, which is the official client's own palette;
the in-game aliases stay the repository's year-neutral `Clan Ash` / `Clan
Basil` and the colours are the viewer's business alone.
"""

from __future__ import annotations

import argparse
import io
import json
import pathlib
import sys

from PIL import Image

TILE = 32
COLUMNS = 6

# cell name -> (subdirectory, file stem). Every cell is resized to TILE and
# the renderer scales it by the body's own float radius, so an archon at
# radius 2 really is drawn twice the size of a soldier at radius 1.
CELLS: dict[str, tuple[str, str]] = {}
for _kind in ["archon", "gardener", "lumberjack", "soldier", "tank", "scout",
              "bullet_tree"]:
    CELLS[f"{_kind}_a"] = ("sprites", f"{_kind}_red")
    CELLS[f"{_kind}_b"] = ("sprites", f"{_kind}_blue")
CELLS["tree_mature"] = ("map", "full_health_tree")
CELLS["tree_hurt"] = ("map", "low_health_tree")
CELLS["tree_sapling"] = ("map", "sapling")
CELLS["tree_bullets"] = ("map", "tree_bullets")
CELLS["tree_robots"] = ("map", "tree_robots")
CELLS["bullet_slow"] = ("bullets", "bullet_slow")
CELLS["bullet_medium"] = ("bullets", "bullet_medium")
CELLS["bullet_fast"] = ("bullets", "bullet_fast")


def build(img_dir: pathlib.Path) -> tuple[Image.Image, dict]:
    cells: dict[str, Image.Image] = {}
    for name, (sub, stem) in CELLS.items():
        source = img_dir / sub / f"{stem}.png"
        if not source.exists():
            raise SystemExit(f"::error::missing 2017 client sprite: {source}")
        # Two of the twenty-one are not RGBA upstream (`bullet_slow` is a
        # palette image and `tree_bullets` is greyscale+alpha), so every cell
        # is converted before it is scaled.
        icon = Image.open(source).convert("RGBA")
        if icon.size != (TILE, TILE):
            icon = icon.resize((TILE, TILE), Image.LANCZOS)
        cells[name] = icon
    names = sorted(cells)
    if len(names) != 22:
        raise SystemExit(f"::error::expected 22 atlas cells, built "
                         f"{len(names)}")
    rows = (len(names) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * TILE, rows * TILE), (0, 0, 0, 0))
    index: dict[str, dict[str, int]] = {}
    for i, name in enumerate(names):
        x = (i % COLUMNS) * TILE
        y = (i // COLUMNS) * TILE
        sheet.paste(cells[name], (x, y))
        index[name] = {"x": x, "y": y, "w": TILE, "h": TILE}
    return sheet, {"tile": TILE, "sprites": index}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", required=True, type=pathlib.Path,
                    help="a checkout of battlecode/battlecode-client-17")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    img_dir = args.client / "src/static/img"
    if not img_dir.is_dir():
        sys.stderr.write(f"no 2017 client art under {img_dir}\n")
        return 1
    sheet, index = build(img_dir)
    png = args.out / "atlas_bc17.png"
    meta = args.out / "atlas_bc17.json"
    text = json.dumps(index, sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != text:
            sys.stderr.write("data/atlas_bc17.json differs from the "
                             "pinned 2017 client art\n")
            return 1
        buf = io.BytesIO()
        sheet.save(buf, format="PNG", optimize=True)
        if not png.exists() or png.read_bytes() != buf.getvalue():
            sys.stderr.write("data/atlas_bc17.png differs from the "
                             "pinned 2017 client art\n")
            return 1
        print("the bc17 sprite atlas matches the pinned 2017 client art")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    sheet.save(png, format="PNG", optimize=True)
    meta.write_text(text)
    print(f"wrote {png} ({len(index['sprites'])} sprites) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
