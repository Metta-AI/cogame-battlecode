## The four 5x5 patterns, PURE.
##
## `GameWorld` ignores the `paintPatterns` array the map file carries
## ("//ignore patterns passed in with map and use hardcoded values") and uses
## four hard-coded 32-bit ints from `common/GameConstants.java`. The converter
## reads the map's copy so the reader is provably complete and then discards
## it (docs/RULES-BC25.md §Divergences item 7).
##
##     getPatternBit(pattern, dx, dy) = (pattern >> (5 * (dx + 2) + dy + 2)) & 1
##     bit 1 = SECONDARY colour, bit 0 = PRIMARY colour
##
## Decoded, with `dy = +2` on top and `dx = -2` on the left:
##
##     RESOURCE     PAINT        MONEY        DEFENSE
##     SSPSS        SPPPS        PSSSP        PPSPP
##     SPPPS        PSPSP        SSPSS        PSSSP
##     PPSPP        PPSPP        SPPPS        SSSSS
##     SPPPS        PSPSP        SSPSS        PSSSP
##     SSPSS        SPPPS        PSSSP        PPSPP
##
## All four are invariant under all eight square symmetries, which is why the
## engine's rotation/reflection logic is commented out and
## `markTowerPattern(type, loc, rotationAngle, reflect)` ignores both extra
## arguments. `tests/test_bc25_patterns.nim` byte-checks the generated tables
## against a regeneration from the ints.
##
## THE TOWER CHECK SKIPS THE CENTRE TILE (`dx == dy == 0 && isTowerPattern`) —
## a ruin is not paintable, so a tower pattern could never match if it did.
## The SRP check does not skip it, and additionally demands that ALL 25 tiles
## are paintable (`isValidPatternCenter(loc, false)` -> `areaIsPaintable`).

import units, paint

export units, paint

type
  PatternKind* = enum
    ## The engine's own `patternArray` indices: 0 resource, 1 defense tower,
    ## 2 money tower, 3 paint tower.
    pkResource = 0
    pkDefenseTower = 1
    pkMoneyTower = 2
    pkPaintTower = 3

  PatternTable* = array[5, array[5, bool]]
    ## `[dx + 2][dy + 2]` -> true when the tile takes the SECONDARY colour.

const
  PatternInts*: array[PatternKind, int] = [
    pkResource: ResourcePattern,
    pkDefenseTower: DefenseTowerPattern,
    pkMoneyTower: MoneyTowerPattern,
    pkPaintTower: PaintTowerPattern]

  Half* = PatternSize div 2          ## 2
  LoOffset* = -(PatternSize div 2)   ## -2
  HiOffset* = (PatternSize + 1) div 2 - 1   ## +2

func getPatternBit*(pattern, ddx, ddy: int): int =
  ## `GameWorld.getPatternBit`, verbatim.
  let bitNum = PatternSize * (ddx + Half) + ddy + Half
  (pattern shr bitNum) and 1

const PatternTables*: array[PatternKind, PatternTable] = block:
  var tables: array[PatternKind, PatternTable]
  for kind in PatternKind:
    for ddx in LoOffset .. HiOffset:
      for ddy in LoOffset .. HiOffset:
        tables[kind][ddx + Half][ddy + Half] =
          getPatternBit(PatternInts[kind], ddx, ddy) == 1
  tables

func patternKindFor*(t: UnitType): PatternKind =
  ## `GameWorld.towerTypeToPatternIndex`.
  case towerKindOf(t)
  of tkDefense: pkDefenseTower
  of tkMoney: pkMoneyTower
  of tkPaint: pkPaintTower

func patternKindFor*(kind: TowerKind): PatternKind =
  case kind
  of tkDefense: pkDefenseTower
  of tkMoney: pkMoneyTower
  of tkPaint: pkPaintTower

func wantedPaint*(kind: PatternKind, ddx, ddy: int, team: Team): int =
  ## The colour tile `(ddx, ddy)` of `kind` must carry for `team`.
  if PatternTables[kind][ddx + Half][ddy + Half]: secondaryPaint(team)
  else: primaryPaint(team)

func centreIsInsideBox*(l: Loc, width, height: int): bool =
  ## The edge half of `GameWorld.isValidPatternCenter`: at least
  ## `PATTERN_SIZE / 2` from the low edges and `(PATTERN_SIZE - 1) / 2` from
  ## the high ones — i.e. two tiles from every edge for a 5x5 pattern.
  not (l.x < Half or l.y < Half or
       l.x >= width - (PatternSize - 1) div 2 or
       l.y >= height - (PatternSize - 1) div 2)

func patternRows*(kind: PatternKind): array[5, string] =
  ## The five `P`/`S` rows the doctrine brief and the viewer print, `dy = +2`
  ## first so the picture reads the way the board does.
  for row in 0 .. 4:
    let ddy = HiOffset - row
    var text = ""
    for ddx in LoOffset .. HiOffset:
      text.add(if PatternTables[kind][ddx + Half][ddy + Half]: 'S' else: 'P')
    result[row] = text
