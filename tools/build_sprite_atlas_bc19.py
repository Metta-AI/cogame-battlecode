#!/usr/bin/env python3
"""Cut `data/atlas_bc19.png` + `data/atlas_bc19.json` from the 2019 client art.

CI-TIME ONLY. The source is `battlecode/battlecode19` at the pinned commit
`80cf1cc535ec5a30559274aa1b49807ad4859925`, the SIX files
`app/public/assets/img/s_{castle,church,pilgrim,crusader,prophet,preacher}.png`
(40x40 each, 130-339 bytes). The atlas is COMMITTED so the runtime image and
the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc19.py --engine /path/to/battlecode19 --out data
    tools/build_sprite_atlas_bc19.py --engine ... --out data --check

LICENCE, RECORDED HONESTLY AND VERIFIED BEFORE PINNING. The repository ROOT
`LICENSE` is the GNU GPL v3 and it is the ONLY licence file anywhere in the
tree -- there is no per-directory `LICENSE` and neither `app/package.json` nor
`coldbrew/package.json` declares a `"license"` field -- so
`app/public/assets/img/**` is covered by that one licence and nothing else.
GPL-3.0 material may be combined with AGPL-3.0 material under GPL-3.0 section
13, so this repository stays AGPL-3.0 and `NOTICE` records the reasoning, the
source repository, its commit and the exact six files. NO CLIENT CODE IS
SHIPPED, BUILT OR EMBEDDED -- only the images.

**THE SIBLING DIRECTORIES `app/public/assets/{css,js,fonts}` ARE THIRD-PARTY**
(Bootstrap, jQuery, Chartist, Pe-icon-7-stroke) **AND ARE NOT USED, NOT CUT
AND NOT SHIPPED.**

WHAT MAKES THIS YEAR'S CUT DIFFERENT. The 2019 client ships ONE sprite per
unit type and colours it at draw time: `coldbrew/vis.js:486` draws RED as
`#DD0048` and BLUE as plain `blue`. So the twelve cells here are the six
icons TINTED at those two team colours -- the palette is the engine's own
visualiser's, not this repository's taste.

**THE UPSTREAM VISUALISER HAS NO DEPOT ART AT ALL** (`vis.js` draws robots as
coloured circles and terrain as rectangles), so the karbonite and fuel depot
pips are drawn PROCEDURALLY by `src/battlecode/render.nim` and are credited to
nobody.
"""

from __future__ import annotations

import argparse
import io
import json
import pathlib
import sys

from PIL import Image

TILE = 16
COLUMNS = 6

TYPES = ["castle", "church", "pilgrim", "crusader", "prophet", "preacher"]

# `coldbrew/vis.js:486`: `ctx.fillStyle = robot.team === 0 ? '#DD0048' :
# 'blue'`. CSS `blue` is #0000FF.
TEAM_COLOURS = {"a": (0xDD, 0x00, 0x48), "b": (0x00, 0x00, 0xFF)}


def tint(cell: Image.Image, colour: tuple[int, int, int]) -> Image.Image:
    """Recolour a client icon at one of the visualiser's two team colours.

    The icons are single-colour silhouettes with an alpha channel, so the
    tint is a flat fill masked by the alpha -- which is exactly what the
    upstream canvas does when it fills a path in the team colour.
    """
    alpha = cell.split()[3]
    solid = Image.new("RGBA", cell.size, colour + (255,))
    solid.putalpha(alpha)
    return solid


def build(img_dir: pathlib.Path) -> tuple[Image.Image, dict]:
    names: list[str] = []
    cells: dict[str, Image.Image] = {}
    for kind in TYPES:
        source = img_dir / f"s_{kind}.png"
        if not source.exists():
            raise SystemExit(f"::error::missing 2019 client sprite: {source}")
        icon = Image.open(source).convert("RGBA")
        # The client's PNGs are 40x40; downscale with a Lanczos filter so a
        # 16 px board sprite keeps its silhouette.
        icon = icon.resize((TILE, TILE), Image.LANCZOS)
        for team, colour in TEAM_COLOURS.items():
            name = f"{team}_{kind}"
            names.append(name)
            cells[name] = tint(icon, colour)
    names.sort()
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
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of battlecode/battlecode19")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    img_dir = args.engine / "app/public/assets/img"
    if not img_dir.is_dir():
        sys.stderr.write(f"no 2019 client art under {img_dir}\n")
        return 1
    sheet, index = build(img_dir)
    png = args.out / "atlas_bc19.png"
    meta = args.out / "atlas_bc19.json"
    text = json.dumps(index, sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != text:
            sys.stderr.write("data/atlas_bc19.json differs from the "
                             "pinned 2019 client art\n")
            return 1
        buf = io.BytesIO()
        sheet.save(buf, format="PNG", optimize=True)
        if not png.exists() or png.read_bytes() != buf.getvalue():
            sys.stderr.write("data/atlas_bc19.png differs from the "
                             "pinned 2019 client art\n")
            return 1
        print("the bc19 sprite atlas matches the pinned 2019 client art")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    sheet.save(png, format="PNG", optimize=True)
    meta.write_text(text)
    print(f"wrote {png} ({len(index['sprites'])} sprites) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
