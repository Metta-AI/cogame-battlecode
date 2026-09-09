#!/usr/bin/env python3
"""Cut `data/atlas_bc16.png` + `data/atlas_bc16.json` from the 2016 client art.

CI-TIME ONLY. The source is
`battlecode/battlecode-client-2016` at the pinned commit
`317e1f3ff902ae568619c051813335ecdd72322c`, directory
`src/main/battlecode/client/resources/art/`; the atlas is COMMITTED so the
runtime image and the wasm bundle carry no build step and no upstream tree.

    tools/build_sprite_atlas_bc16.py --client /path/to/battlecode-client-2016 \
        --out data
    tools/build_sprite_atlas_bc16.py --client ... --out data --check

LICENCE, RECORDED HONESTLY. `battlecode-client-2016/COPYING` is the GNU GPL
v3 (35 147 bytes). GPL-3.0 material may be combined with AGPL-3.0 material
under GPL-3.0 section 13, so this repository stays AGPL-3.0 and `NOTICE`
records the reasoning, the source repository, its commit and the exact
directory these sprites came from. NO CLIENT CODE IS SHIPPED, BUILT OR
EMBEDDED — only the images.

WHAT MAKES THIS YEAR'S CUT DIFFERENT FROM EVERY OTHER ONE. The 2016 client
ships **four team variants of every one of the twelve robot types**:
`{archon,scout,soldier,guard,viper,turret,ttm,zombieden,standardzombie,
rangedzombie,fastzombie,bigzombie}{0,1,2,3}.png`, where the index is
`Team.values()` — 0 = A, 1 = B, 2 = NEUTRAL, 3 = ZOMBIE. So this is the FIRST
year in the repo whose art can draw a NEUTRAL ROBOT AS ITSELF rather than as a
greyed team sprite — which matters, because `neutral_activation` is a headline
knob and a spectator has to be able to see what is being activated.

48 sprites (twelve types x four palettes) plus `creep.png` (the rubble
texture) are cut at 16 px, the viewer's native board scale.

THE TERRAIN COLOURS ARE NOT IN HERE: `render.nim` carries this repository's own
rubble heat ramp — six steps with hard breaks at the two thresholds that
matter (50, where every charge doubles, and 100, where the square becomes
impassable) — and uses the atlas only for the units.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image

TILE = 16
COLUMNS = 8

TYPES = ["zombieden", "standardzombie", "rangedzombie", "fastzombie",
         "bigzombie", "archon", "scout", "soldier", "guard", "viper",
         "turret", "ttm"]

# `Team.values()`: A, B, NEUTRAL, ZOMBIE.
TEAM_SUFFIX = {"a": 0, "b": 1, "neutral": 2, "horde": 3}


def sprite_files() -> dict[str, str]:
    out: dict[str, str] = {}
    for kind in TYPES:
        for team, index in TEAM_SUFFIX.items():
            out[f"{team}_{kind}"] = f"{kind}{index}.png"
    out["creep"] = "creep.png"
    return out


def build(art: pathlib.Path) -> tuple[Image.Image, dict]:
    files = sprite_files()
    names = sorted(files)
    rows = (len(names) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * TILE, rows * TILE), (0, 0, 0, 0))
    index: dict[str, dict[str, int]] = {}
    for i, name in enumerate(names):
        source = art / files[name]
        if not source.exists():
            raise SystemExit(f"::error::missing 2016 client sprite: {source}")
        cell = Image.open(source).convert("RGBA")
        # The client's PNGs are square but not 16 px; downscale with a box
        # filter so a 16 px board sprite keeps its silhouette.
        cell = cell.resize((TILE, TILE), Image.LANCZOS)
        x = (i % COLUMNS) * TILE
        y = (i // COLUMNS) * TILE
        sheet.paste(cell, (x, y))
        index[name] = {"x": x, "y": y, "w": TILE, "h": TILE}
    return sheet, {"tile": TILE, "sprites": index}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", required=True, type=pathlib.Path,
                    help="a checkout of battlecode/battlecode-client-2016")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    art = args.client / "src/main/battlecode/client/resources/art"
    if not art.is_dir():
        sys.stderr.write(f"no 2016 client art under {art}\n")
        return 1
    sheet, index = build(art)
    png = args.out / "atlas_bc16.png"
    meta = args.out / "atlas_bc16.json"
    text = json.dumps(index, sort_keys=True, separators=(",", ":")) + "\n"

    if args.check:
        if not meta.exists() or meta.read_text() != text:
            sys.stderr.write("data/atlas_bc16.json differs from the "
                             "pinned 2016 client art\n")
            return 1
        import io
        buf = io.BytesIO()
        sheet.save(buf, format="PNG", optimize=True)
        if not png.exists() or png.read_bytes() != buf.getvalue():
            sys.stderr.write("data/atlas_bc16.png differs from the "
                             "pinned 2016 client art\n")
            return 1
        print("the bc16 sprite atlas matches the pinned 2016 client art")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    sheet.save(png, format="PNG", optimize=True)
    meta.write_text(text)
    print(f"wrote {png} ({len(index['sprites'])} sprites) and {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
