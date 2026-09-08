## Board rendering: bitworld sprite packets, drawn from the committed atlas.
##
## The atlas is cut from the official Battlecode client art
## (`tools/build_sprite_atlas.py`, credited in NOTICE) and preloaded into the
## wasm bundle with `--preload-file data@data`, exactly as coworld-ctf
## preloads its own `data/`. It looks like Battlecode because it IS
## Battlecode's art.
##
## The packet shape is `bitworld/spriteprotocol` v1 and the client is
## `client/broadcast_core.js`, byte-for-byte the starter's: ONE terrain
## sprite per game plus a DIFF of dirt / cheese / trap / robot objects per
## round. Re-sending the board every round would be a megabyte a frame; the
## diff is a few dozen bytes.

import std/[json, math, os, sequtils, sets, tables]
import pixie
import bitworld/spriteprotocol
import sheet
import years/dispatch
import years/bc26/[constants, maps, world]
from years/bc20/world as w20 import nil
from years/bc20/flood as f20 import nil
from years/bc20/constants as c20 import nil
from years/bc21/world as w21 import nil
from years/bc21/constants as c21 import nil
from years/bc24/world as w24 import nil
from years/bc24/constants as c24 import nil
from years/bc25/world as w25 import nil
from years/bc25/constants as c25 import nil
from years/bc25/units as u25 import nil
from years/bc23/world as w23 import nil
from years/bc23/constants as c23 import nil
from years/bc23/units as u23 import nil

const
  TileSize* = 16
  MapLayerId* = 0
  MapLayerKind* = 0
  ZoomableFlag* = 1
  BroadcastChromeSpriteId* = 4090
    ## The reserved sprite id whose LABEL carries the chrome JSON on the
    ## binary channel; `broadcast_core.js` feeds it straight to `onText` and
    ## never draws it. Must match `wire_constants.nim`.

  TerrainSpriteId = 1
  AtlasSpriteBase = 100
  DirtObjectBase = 8000
  CheeseObjectBase = 16000
  TrapAObjectBase = 24000
  TrapBObjectBase = 32000
  RobotObjectBase = 40000
  SoupObjectBase = 48000

  FloorColor = rgba(38, 32, 28, 255)
  WallColor = rgba(88, 74, 60, 255)
  GridColor = rgba(46, 39, 34, 255)

  ## bc20's board is a HEIGHTMAP under a rising sea, so the terrain sprite is
  ## re-cut whenever the water crosses an integer level and the nine-step
  ## elevation ramp is keyed to the CURRENT water line — the lattice then reads
  ## as terrain rising out of the sea rather than as a static heightmap.
  Bc20Ramp = [
    rgba(24, 30, 38, 255), rgba(34, 42, 46, 255), rgba(48, 56, 50, 255),
    rgba(64, 70, 54, 255), rgba(84, 84, 58, 255), rgba(106, 98, 64, 255),
    rgba(130, 114, 78, 255), rgba(158, 136, 98, 255), rgba(190, 166, 126, 255)
  ]
  Bc20WaterColor = rgba(28, 62, 104, 255)
  Bc20DeepWaterColor = rgba(16, 38, 70, 255)

  ## bc21's board is a PASSABILITY field: 0.1 is deep swamp and 1.0 is clean
  ## dirt, and the only thing it changes is how long an action costs. The
  ## terrain is drawn as a ramp between the 2021 client's own swamp and dirt
  ## tones so a spectator can see why a flank is slow. It never changes during
  ## a game, so the terrain sprite is cut ONCE per game.
  Bc21SwampColor = rgba(46, 58, 52, 255)
  Bc21DirtColor = rgba(150, 122, 84, 255)

  ## bc24's board is land, water, wall and -- for the first two hundred rounds
  ## only -- THE DAM. The 2024 client draws all four procedurally, so there is
  ## nothing upstream to reuse and nothing to credit: these are this
  ## repository's own paintbot-derived tones. The dam is drawn as a visibly
  ## TEMPORARY barricade because its dissolve at round 200 is the single most
  ## legible moment in the year, and the terrain sprite is therefore re-cut
  ## when the dam falls and whenever the water line moves.
  Bc24LandColor = rgba(58, 48, 36, 255)
  Bc24WaterColor = rgba(30, 66, 104, 255)
  Bc24WallColor = rgba(96, 82, 66, 255)
  Bc24DamColor = rgba(148, 120, 72, 255)
  Bc24SpawnAColor = rgba(96, 70, 44, 255)
  Bc24SpawnBColor = rgba(120, 116, 108, 255)

  ## bc25's board IS the picture: a flat colour per tile, and the score is the
  ## colour count. These six are the 2025 client's OWN `DEFAULT_GLOBAL_COLORS`
  ## (`client/src/colors.ts`), so the replay looks like the official client
  ## because it uses the official client's palette. Primary and secondary of
  ## the same clan differ only slightly in value while the two clans differ
  ## strongly in hue, which is exactly what makes coverage readable at a
  ## glance and at 360 px.
  Bc25TileColor = rgba(0x4c, 0x30, 0x1e, 255)
  Bc25WallColor = rgba(0x54, 0x7f, 0x31, 255)
  Bc25APrimary = rgba(0x66, 0x66, 0x66, 255)
  Bc25ASecondary = rgba(0x56, 0x56, 0x56, 255)
  Bc25BPrimary = rgba(0xb2, 0x8b, 0x52, 255)
  Bc25BSecondary = rgba(0x99, 0x77, 0x46, 255)
  Bc25RuinColor = rgba(0x2e, 0x23, 0x23, 255)

  ## bc23's board is TERRAIN plus three overlays a spectator has to be able to
  ## read at 6 px per tile: impassable storm squares, clouds (which blind and
  ## slow BOTH sides and are the one place the spectator sees more than the
  ## robots do), and directional currents. The tones are this repository's own
  ## paintbot-derived palette, because the 2023 client draws its terrain from
  ## photographic tiles that do not survive a 16 px cut.
  Bc23TileColor = rgba(0x2a, 0x33, 0x42, 255)
  Bc23WallColor = rgba(0x14, 0x18, 0x20, 255)
  Bc23CloudColor = rgba(0x55, 0x62, 0x78, 255)
  Bc23CurrentColor = rgba(0x3c, 0x4c, 0x66, 255)
  Bc23IslandColor = rgba(0x3a, 0x46, 0x3c, 255)
  Bc23IslandAColor = rgba(0x2f, 0x5c, 0x7a, 255)
  Bc23IslandBColor = rgba(0x6e, 0x36, 0x33, 255)
  Bc23WellAdColor = rgba(0x7a, 0x5a, 0x2e, 255)
  Bc23WellMnColor = rgba(0x2e, 0x5a, 0x7a, 255)
  Bc23WellExColor = rgba(0x6a, 0x33, 0x7a, 255)

type
  Atlas = ref object
    image: Image
    cells: Table[string, tuple[x, y, w, h: int]]

  Renderer* = ref object
    atlas: Atlas
    spriteIds: Table[string, int]
    nextSpriteId: int
    sentSprites: HashSet[int]
    liveObjects: HashSet[int]
    prevDirt: seq[bool]
    prevCheese: seq[bool]
    prevTrap: array[2, seq[int]]
    prevSoup: seq[int]
    prevRobotSprite: Table[int, int]
    terrainGame: int
    terrainStage: int
    atlasName: string

proc loadAtlas(name: string): Atlas =
  ## The atlas rides in the wasm bundle's preloaded `data/`. When that package
  ## has not mounted, say so plainly: the alternative is whatever error the
  ## image decoder happens to raise on a missing file, several frames from
  ## the real cause.
  let root = dataRoot()
  for asset in [name & ".png", name & ".json"]:
    if not fileExists(root / asset):
      raise newException(IOError,
        "the sprite atlas is missing: no " & (root / asset) &
        " (in the wasm bundle this means the preloaded data package did " &
        "not mount)")
  result = Atlas(image: readImage(root / (name & ".png")),
                 cells: initTable[string, tuple[x, y, w, h: int]]())
  let doc = parseJson(readFile(root / (name & ".json")))
  for name, cell in doc["sprites"]:
    result.cells[name] = (cell["x"].getInt(), cell["y"].getInt(),
                          cell["w"].getInt(), cell["h"].getInt())

proc newRenderer*(atlasName = "atlas"): Renderer =
  ## The atlas is per YEAR (`YearSpec.atlas`): `atlas` for bc26, `atlas_bc20`
  ## for the 2020 sprite set cut from the official client (credited in NOTICE).
  Renderer(atlas: loadAtlas(atlasName), spriteIds: initTable[string, int](),
           nextSpriteId: AtlasSpriteBase, sentSprites: initHashSet[int](),
           liveObjects: initHashSet[int](),
           prevRobotSprite: initTable[int, int](),
           terrainGame: -1, terrainStage: -1, atlasName: atlasName)

proc straightPixels(image: Image): seq[uint8] =
  ## `broadcast_core.js` blends sprites with straight (non-premultiplied)
  ## alpha; pixie stores premultiplied. Converting here rather than at blit
  ## time is what keeps a translucent rat from darkening as it moves.
  result = newSeq[uint8](image.width * image.height * 4)
  for i, px in image.data:
    ## pixie's `autoStraightAlpha` converter un-multiplies one pixel.
    let straight: ColorRGBA = px
    result[i * 4 + 0] = straight.r
    result[i * 4 + 1] = straight.g
    result[i * 4 + 2] = straight.b
    result[i * 4 + 3] = straight.a

proc cellImage(r: Renderer, name: string): Image =
  let cell = r.atlas.cells[name]
  result = newImage(cell.w, cell.h)
  result.draw(r.atlas.image, translate(vec2(-float32(cell.x),
                                            -float32(cell.y))))

proc spriteId(r: Renderer, packet: var seq[uint8], name: string): int =
  ## Sprite definitions are sent ONCE per session and cached by name.
  if name in r.spriteIds:
    return r.spriteIds[name]
  let id = r.nextSpriteId
  inc r.nextSpriteId
  r.spriteIds[name] = id
  let image = r.cellImage(name)
  packet.addSprite(id, image.width, image.height, straightPixels(image), name)
  r.sentSprites.incl(id)
  id

proc paletteOf(w: World, team: Team, sideAslot: int): string =
  ## Clan Ash is cheddar, Clan Basil is plum — the SEAT's palette, so a clan
  ## keeps its colour across games even though its side alternates.
  let slot = if team == teamA: sideAslot else: 1 - sideAslot
  if slot == 0: "cheddar" else: "plum"

proc dirFrame(d: Dir): int =
  ## `Direction.DIRECTION_ORDER`, the index the client art is cut on.
  case d
  of dCenter: 0
  of dWest: 1
  of dSouthwest: 2
  of dSouth: 3
  of dSoutheast: 4
  of dEast: 5
  of dNortheast: 6
  of dNorth: 7
  of dNorthwest: 8

proc renderTerrain(r: Renderer, w: World): Image =
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(FloorColor)
  let ctx = newContext(result)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      if w.walls[w.idx(loc(x, y))]:
        ctx.fillStyle = WallColor
        ctx.fillRect(rect(float32(px), float32(py),
                          float32(TileSize), float32(TileSize)))
      elif (x + y) mod 2 == 0:
        ctx.fillStyle = GridColor
        ctx.fillRect(rect(float32(px), float32(py),
                          float32(TileSize), float32(TileSize)))
  let mine = r.cellImage("cheese_mine")
  for m in w.cheeseMines:
    result.draw(mine, translate(vec2(
      float32(m.loc.x * TileSize),
      float32((w.height - 1 - m.loc.y) * TileSize))))

proc screenY(w: World, y, spriteTiles: int): int =
  ## Bottom-left tile of a sprite `spriteTiles` tall, in canvas pixels.
  (w.height - y - spriteTiles) * TileSize

proc addObj(r: Renderer, packet: var seq[uint8],
            objectId, x, y, z, spriteId: int) =
  packet.addObject(objectId, x, y, z, MapLayerId, spriteId)
  r.liveObjects.incl(objectId)

proc dropObj(r: Renderer, packet: var seq[uint8], objectId: int) =
  if objectId in r.liveObjects:
    packet.addDeleteObject(objectId)
    r.liveObjects.excl(objectId)

proc buildPacket*(r: Renderer, w: World, gameIndex, sideAslot: int,
                  chrome: string): seq[uint8] =
  ## One frame. The layer/viewport records go out on the first packet of each
  ## game (the board size changes between maps); everything else is a diff.
  var packet: seq[uint8]
  let n = w.width * w.height
  let newGame = r.terrainGame != gameIndex

  if newGame:
    r.terrainGame = gameIndex
    r.liveObjects.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)
    let terrain = r.renderTerrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)
    r.prevDirt = newSeq[bool](n)
    r.prevCheese = newSeq[bool](n)
    r.prevTrap[0] = newSeq[int](n)
    r.prevTrap[1] = newSeq[int](n)

  let
    dirtSprite = r.spriteId(packet, "dirt")
    cheeseSprite = r.spriteId(packet, "cheese")
    ratTrapSprite = r.spriteId(packet, "rat_trap")
    catTrapSprite = r.spriteId(packet, "cat_trap")

  for i in 0 ..< n:
    let l = w.indexToLoc(i)
    let px = l.x * TileSize
    let py = w.screenY(l.y, 1)

    let hasDirt = w.dirt[i]
    if hasDirt != r.prevDirt[i]:
      r.prevDirt[i] = hasDirt
      if hasDirt: r.addObj(packet, DirtObjectBase + i, px, py, 1, dirtSprite)
      else: r.dropObj(packet, DirtObjectBase + i)

    let hasCheese = w.cheeseAmounts[i] > 0
    if hasCheese != r.prevCheese[i]:
      r.prevCheese[i] = hasCheese
      if hasCheese: r.addObj(packet, CheeseObjectBase + i, px, py, 2, cheeseSprite)
      else: r.dropObj(packet, CheeseObjectBase + i)

    for t in 0 .. 1:
      let trap = w.trapAt[t][i]
      let kind = if trap == nil: 0 else: ord(trap.kind) + 1
      if kind != r.prevTrap[t][i]:
        r.prevTrap[t][i] = kind
        let base = if t == 0: TrapAObjectBase else: TrapBObjectBase
        if kind == 0:
          r.dropObj(packet, base + i)
        else:
          let sprite = if kind == ord(ttRatTrap) + 1: ratTrapSprite
                       else: catTrapSprite
          r.addObj(packet, base + i, px, py, 3, sprite)

  ## Robots. Object ids are stable for a robot's whole life, so the client's
  ## motion interpolation can glide it between rounds instead of teleporting.
  var seen = initHashSet[int]()
  for robot in w.liveRobots:
    let objectId = RobotObjectBase + (robot.id mod 20000)
    seen.incl(objectId)
    let name =
      case robot.unit
      of utBabyRat:
        "rat_" & paletteOf(w, robot.team, sideAslot) & "_" & $dirFrame(robot.dir)
      of utRatKing:
        "king_" & paletteOf(w, robot.team, sideAslot)
      of utCat:
        if robot.sleepTimeRemaining > 0: "cat_sleep" else: "cat_" & $dirFrame(robot.dir)
    let sprite = r.spriteId(packet, name)
    let tiles = UnitSpecs[robot.unit].size
    ## A rat king's `loc` is its CENTRE tile and a cat's is its bottom-left.
    let originX = if robot.unit == utRatKing: robot.loc.x - 1 else: robot.loc.x
    let originY = if robot.unit == utRatKing: robot.loc.y - 1 else: robot.loc.y
    r.addObj(packet, objectId, originX * TileSize, w.screenY(originY, tiles),
      5, sprite)

  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId notin seen:
      r.dropObj(packet, objectId)

  ## The chrome JSON rides as the LABEL of the reserved sprite id. It is
  ## never drawn; `broadcast_core.js` routes it straight to `onText`.
  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

# ---------------------------------------------------------------------------
#  bc20 — a heightmap under a rising sea
# ---------------------------------------------------------------------------

proc bc20SpriteName(r: w20.Robot, sideAslot: int): string =
  ## Palette follows the ENGINE SIDE, not the seat: red = side A, blue = side
  ## B, exactly as the 2020 client draws it. Because sides alternate every game
  ## the scorebug plate keeps the alias constant and recolours its swatch.
  let tint = if r.team == w20.teamA: "_red" else: "_blue"
  case r.kind
  of c20.rtHq: "hq" & tint
  of c20.rtMiner: "miner" & tint
  of c20.rtLandscaper: "landscaper" & tint
  of c20.rtDeliveryDrone:
    (if r.holdingUnit: "drone" & tint & "_carry" else: "drone" & tint)
  of c20.rtRefinery: "refinery" & tint
  of c20.rtVaporator: "vaporator" & tint
  of c20.rtDesignSchool: "design_school" & tint
  of c20.rtFulfillmentCenter: "fulfillment_center" & tint
  of c20.rtNetGun: "net_gun" & tint
  of c20.rtCow: "cow"

proc renderBc20Terrain(r: Renderer, w: w20.World): Image =
  ## A nine-step elevation ramp keyed to the CURRENT water level, plus a water
  ## overlay on flooded tiles. Re-cut only when the water crosses an integer
  ## level, so a 1499-round game sends seven terrain sprites, not 1499.
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(FloorColor)
  let ctx = newContext(result)
  let level = w.waterLevel
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let l = w20.loc(x, y)
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      let elevation = w20.getDirt(w, l)
      var colour: ColorRGBA
      if w20.isFlooded(w, l):
        colour = if float32(elevation) < level - 2.0'f32:
                   Bc20DeepWaterColor else: Bc20WaterColor
      else:
        let step = clamp(int(floor(float(elevation) - float(level))) + 2,
                         0, Bc20Ramp.high)
        colour = Bc20Ramp[step]
      ctx.fillStyle = colour
      ctx.fillRect(rect(float32(px), float32(py),
                        float32(TileSize), float32(TileSize)))

proc buildBc20Packet(r: Renderer, w: w20.World, gameIndex, sideAslot: int,
                     chrome: string): seq[uint8] =
  var packet: seq[uint8]
  let n = w.width * w.height
  let stage = f20.floodStageFor(w.waterLevel)
  let newGame = r.terrainGame != gameIndex

  if newGame:
    r.terrainGame = gameIndex
    r.terrainStage = -1
    r.liveObjects.clear()
    r.prevRobotSprite.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)
    r.prevSoup = newSeq[int](n)
    for i in 0 ..< n: r.prevSoup[i] = -1

  if stage != r.terrainStage:
    r.terrainStage = stage
    let terrain = r.renderBc20Terrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)

  let soupSprite = r.spriteId(packet, "soup")
  for i in 0 ..< n:
    let here = if w.soup[i] > 0: 1 else: 0
    if here == r.prevSoup[i]: continue
    r.prevSoup[i] = here
    let l = w20.indexToLoc(w, i)
    if here == 1:
      r.addObj(packet, SoupObjectBase + i, l.x * TileSize,
        (w.height - 1 - l.y) * TileSize, 2, soupSprite)
    else:
      r.dropObj(packet, SoupObjectBase + i)

  ## Robots. Object ids are stable for a robot's whole life, so the client's
  ## motion interpolation can glide it between rounds instead of teleporting.
  var seen = initHashSet[int]()
  for id, robot in w.robotsById:
    if robot.blocked: continue          ## riding inside a drone
    let objectId = RobotObjectBase + (id mod 20000)
    seen.incl(objectId)
    let sprite = r.spriteId(packet, bc20SpriteName(robot, sideAslot))
    r.addObj(packet, objectId, robot.loc.x * TileSize,
      (w.height - 1 - robot.loc.y) * TileSize, 5, sprite)

  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId < SoupObjectBase and
        objectId notin seen:
      r.dropObj(packet, objectId)

  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

# ---------------------------------------------------------------------------
#  bc21 — a passability field with four robot types
# ---------------------------------------------------------------------------

proc bc21SpriteName(r: w21.Robot): string =
  ## Palette follows the ENGINE SIDE, not the seat: red = side A, blue = side
  ## B, exactly as the 2021 client draws it. A NEUTRAL Enlightenment Center
  ## uses the untinted `center` cut.
  let tint =
    if r.team == w21.teamA: "_red"
    elif r.team == w21.teamB: "_blue"
    else: ""
  case r.kind
  of c21.rtEnlightenmentCenter: "center" & tint
  of c21.rtPolitician: "polit" & tint
  of c21.rtSlanderer: "slanderer" & tint
  of c21.rtMuckraker: "muck" & tint

proc renderBc21Terrain(r: Renderer, w: w21.World): Image =
  ## Each tile is interpolated between the swamp and dirt tones by its
  ## passability. Fixed for the whole game, so this is cut once.
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(FloorColor)
  let ctx = newContext(result)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      let p = clamp(w.passability[x + y * w.width], 0.0, 1.0)
      let mix = (p - 0.1) / 0.9
      let colour = rgba(
        uint8(clamp(float(Bc21SwampColor.r) +
          mix * (float(Bc21DirtColor.r) - float(Bc21SwampColor.r)), 0.0, 255.0)),
        uint8(clamp(float(Bc21SwampColor.g) +
          mix * (float(Bc21DirtColor.g) - float(Bc21SwampColor.g)), 0.0, 255.0)),
        uint8(clamp(float(Bc21SwampColor.b) +
          mix * (float(Bc21DirtColor.b) - float(Bc21SwampColor.b)), 0.0, 255.0)),
        255)
      ctx.fillStyle = colour
      ctx.fillRect(rect(float32(px), float32(py),
                        float32(TileSize), float32(TileSize)))

proc buildBc21Packet(r: Renderer, w: w21.World, gameIndex, sideAslot: int,
                     chrome: string): seq[uint8] =
  var packet: seq[uint8]
  let newGame = r.terrainGame != gameIndex

  if newGame:
    r.terrainGame = gameIndex
    r.terrainStage = -1
    r.liveObjects.clear()
    r.prevRobotSprite.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)
    let terrain = r.renderBc21Terrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)

  ## Robots. Object ids are stable for a robot's whole life, so the client's
  ## motion interpolation can glide it between rounds instead of teleporting.
  var seen = initHashSet[int]()
  for id, robot in w.robotsById:
    let objectId = RobotObjectBase + (id mod 20000)
    seen.incl(objectId)
    let sprite = r.spriteId(packet, bc21SpriteName(robot))
    r.addObj(packet, objectId, robot.loc.x * TileSize,
      (w.height - 1 - robot.loc.y) * TileSize,
      (if robot.kind == c21.rtEnlightenmentCenter: 4 else: 5), sprite)

  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId notin seen:
      r.dropObj(packet, objectId)

  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

# ---------------------------------------------------------------------------
#  bc24 -- one unit type, three trap types, six flags and a dam
# ---------------------------------------------------------------------------

proc bc24DuckSprite(w: w24.World, duck: w24.Robot): string =
  ## Palette follows the CLIENT's own two team colours: brown = side A, white
  ## = side B. A duck is drawn with the sprite of its DOMINANT SKILL --
  ## `base` until it has a level at all -- so a spectator can read the
  ## flock's specialisation off the board without a legend.
  let side = if duck.team == w24.teamA: "duck_brown" else: "duck_white"
  if not duck.spawned: return side & "_jailed"
  let a = w24.levelOf(duck, c24.skAttack)
  let b = w24.levelOf(duck, c24.skBuild)
  let h = w24.levelOf(duck, c24.skHeal)
  if a == 0 and b == 0 and h == 0: return side
  if a >= b and a >= h: return side & "_attack"
  if b >= h: return side & "_build"
  side & "_heal"

proc bc24TrapSprite(w: w24.World, trap: w24.Trap): string =
  let side = if trap.team == w24.teamA: "trap_brown" else: "trap_white"
  case trap.kind
  of c24.tkExplosive: side & "_explosive"
  of c24.tkStun: side & "_stun"
  of c24.tkWater: side & "_water"
  of c24.tkNone: side & "_stun"

proc bc24CrumbSprite(amount: int): string =
  if amount >= 400: "crumb_3"
  elif amount >= 200: "crumb_2"
  else: "crumb_1"

proc bc24TerrainStage(w: w24.World): int =
  ## The terrain is re-cut when the dam falls and then once every sixteen
  ## rounds, which is often enough to show digging and filling and rare enough
  ## that a 59x59 board is not re-rasterised a hundred times a second.
  if w24.isSetupPhase(w): 0 else: 1 + w.currentRound div 16

proc renderBc24Terrain(r: Renderer, w: w24.World): Image =
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(Bc24LandColor)
  let ctx = newContext(result)
  let setup = w24.isSetupPhase(w)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      let i = x + y * w.width
      var colour = Bc24LandColor
      if w.walls[i]: colour = Bc24WallColor
      elif w.water[i]: colour = Bc24WaterColor
      elif setup and w.dam[i]: colour = Bc24DamColor
      elif w.spawnZones[i] == 1: colour = Bc24SpawnAColor
      elif w.spawnZones[i] == 2: colour = Bc24SpawnBColor
      ctx.fillStyle = colour
      ctx.fillRect(rect(float32(px), float32(py),
                        float32(TileSize), float32(TileSize)))

proc buildBc24Packet(r: Renderer, w: w24.World, gameIndex, sideAslot: int,
                     chrome: string): seq[uint8] =
  var packet: seq[uint8]
  let newGame = r.terrainGame != gameIndex
  let stage = bc24TerrainStage(w)

  if newGame:
    r.terrainGame = gameIndex
    r.terrainStage = -1
    r.liveObjects.clear()
    r.prevRobotSprite.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)

  if r.terrainStage != stage:
    r.terrainStage = stage
    let terrain = r.renderBc24Terrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)

  ## Crumb piles, sized by amount.
  var crumbSeen = initHashSet[int]()
  for i in 0 ..< w.crumbTiles.len:
    let amount = int(w.crumbTiles[i])
    if amount == 0: continue
    let objectId = CheeseObjectBase + i
    crumbSeen.incl(objectId)
    let sprite = r.spriteId(packet, bc24CrumbSprite(amount))
    let l = w24.indexToLoc(w, i)
    r.addObj(packet, objectId, l.x * TileSize,
      (w.height - 1 - l.y) * TileSize, 1, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= CheeseObjectBase and objectId < TrapAObjectBase and
        objectId notin crumbSeen:
      r.dropObj(packet, objectId)

  ## OWN TRAPS ARE DRAWN, ENEMY TRAPS ARE NOT -- the fog belongs to the ducks,
  ## and drawing a hidden explosive would make every trap wave unsurprising.
  ## Which side is "own" is the SIDE-A seat's, so the spectator sees the clan
  ## whose plate is on the left.
  var trapSeen = initHashSet[int]()
  for i in 0 ..< w.trapLocations.len:
    let trap = w.trapLocations[i]
    if trap == nil: continue
    let base = if trap.team == w24.teamA: TrapAObjectBase else: TrapBObjectBase
    let objectId = base + i
    trapSeen.incl(objectId)
    let sprite = r.spriteId(packet, bc24TrapSprite(w, trap))
    let l = w24.indexToLoc(w, i)
    r.addObj(packet, objectId, l.x * TileSize,
      (w.height - 1 - l.y) * TileSize, 2, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= TrapAObjectBase and objectId < RobotObjectBase and
        objectId notin trapSeen:
      r.dropObj(packet, objectId)

  ## The six flags. A carried flag rides its carrier.
  var flagSeen = initHashSet[int]()
  for f in w.allFlags:
    let objectId = SoupObjectBase + f.id
    flagSeen.incl(objectId)
    let sprite = r.spriteId(packet,
      (if f.carriedBy >= 0: "flag_outline_thick" else: "flag"))
    r.addObj(packet, objectId, f.loc.x * TileSize,
      (w.height - 1 - f.loc.y) * TileSize, 6, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= SoupObjectBase and objectId notin flagSeen:
      r.dropObj(packet, objectId)

  ## The hundred ducks. Object ids are stable for a duck's whole life, so the
  ## client's motion interpolation glides it between rounds; a JAILED duck is
  ## dropped from the board and reported in the jail rail instead.
  var seen = initHashSet[int]()
  for duck in w.robots:
    if not duck.spawned: continue
    let objectId = RobotObjectBase + duck.execIndex
    seen.incl(objectId)
    let sprite = r.spriteId(packet, bc24DuckSprite(w, duck))
    r.addObj(packet, objectId, duck.loc.x * TileSize,
      (w.height - 1 - duck.loc.y) * TileSize, 5, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId < SoupObjectBase and
        objectId notin seen:
      r.dropObj(packet, objectId)

  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

# ---------------------------------------------------------------------------
#  bc25 -- a paint layer, walls, ruins and six unit types
# ---------------------------------------------------------------------------

proc bc25UnitSprite(unit: w25.Robot): string =
  ## Palette follows the CLIENT's own two team names,
  ## `TEAM_COLOR_NAMES = [Silver, Gold]`, so silver = side A and gold = side
  ## B. Sides alternate every game, so the scorebug plate keeps the ALIAS
  ## constant and recolours its swatch per game.
  let tint = if unit.team == u25.teamA: "_silver" else: "_gold"
  case unit.kind
  of c25.utSoldier: "soldier" & tint
  of c25.utSplasher: "splasher" & tint
  of c25.utMopper: "mopper" & tint
  of c25.utLevelOnePaintTower, c25.utLevelTwoPaintTower,
     c25.utLevelThreePaintTower: "paint_tower" & tint
  of c25.utLevelOneMoneyTower, c25.utLevelTwoMoneyTower,
     c25.utLevelThreeMoneyTower: "money_tower" & tint
  else: "defense_tower" & tint

proc bc25TerrainStage(w: w25.World): int =
  ## THE PAINT LAYER IS THE TERRAIN. It changes every round, so the sprite is
  ## re-cut on a fixed cadence rather than per round: four rounds is often
  ## enough that a splash is visible as it happens and rare enough that a
  ## 60x60 board is not re-rasterised twenty-four times a second.
  w.currentRound div 4

proc renderBc25Terrain(r: Renderer, w: w25.World): Image =
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(Bc25TileColor)
  let ctx = newContext(result)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      let i = x + y * w.width
      var colour = Bc25TileColor
      if w.walls[i]: colour = Bc25WallColor
      elif w.ruinAt[i]: colour = Bc25RuinColor
      else:
        case int(w.colours[i])
        of 1: colour = Bc25APrimary
        of 2: colour = Bc25ASecondary
        of 3: colour = Bc25BPrimary
        of 4: colour = Bc25BSecondary
        else: colour = Bc25TileColor
      ctx.fillStyle = colour
      ctx.fillRect(rect(float32(px), float32(py),
                        float32(TileSize), float32(TileSize)))

proc buildBc25Packet(r: Renderer, w: w25.World, gameIndex, sideAslot: int,
                     chrome: string): seq[uint8] =
  var packet: seq[uint8]
  let newGame = r.terrainGame != gameIndex
  let stage = bc25TerrainStage(w)

  if newGame:
    r.terrainGame = gameIndex
    r.terrainStage = -1
    r.liveObjects.clear()
    r.prevRobotSprite.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)

  if r.terrainStage != stage:
    r.terrainStage = stage
    let terrain = r.renderBc25Terrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)

  ## Unclaimed ruins. A ruin with a tower on it is covered by the tower
  ## sprite, so only the empty ones are drawn.
  var ruinSeen = initHashSet[int]()
  for l in w.allRuins:
    if w25.hasTower(w, l): continue
    let i = w25.idx(w, l)
    let objectId = CheeseObjectBase + i
    ruinSeen.incl(objectId)
    let sprite = r.spriteId(packet, "ruin")
    r.addObj(packet, objectId, l.x * TileSize,
      (w.height - 1 - l.y) * TileSize, 1, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= CheeseObjectBase and objectId < TrapAObjectBase and
        objectId notin ruinSeen:
      r.dropObj(packet, objectId)

  ## Every live unit. Object ids are stable for a unit's whole life, so the
  ## client's motion interpolation glides a robot between rounds instead of
  ## teleporting it. ENEMY MARKERS ARE NEVER DRAWN -- they are per-team state
  ## and drawing them would leak (Viewer, "Per-robot fog" in Out of scope).
  var seen = initHashSet[int]()
  for id in w.execOrder:
    let unit = w.robotsById[id]
    let objectId = RobotObjectBase + (id mod 20000)
    seen.incl(objectId)
    let sprite = r.spriteId(packet, bc25UnitSprite(unit))
    r.addObj(packet, objectId, unit.loc.x * TileSize,
      (w.height - 1 - unit.loc.y) * TileSize,
      (if u25.isTowerType(unit.kind): 4 else: 5), sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId < SoupObjectBase and
        objectId notin seen:
      r.dropObj(packet, objectId)

  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

# ---------------------------------------------------------------------------
#  bc23 -- storm terrain, clouds, currents, wells, islands and six unit types
# ---------------------------------------------------------------------------

proc bc23UnitSprite(unit: w23.Robot): string =
  ## Palette follows the CLIENT's own two team colours, blue = side A and
  ## red = side B. Sides alternate every game, so the scorebug plate keeps the
  ## ALIAS constant and recolours its swatch per game.
  let tint = if unit.team == u23.teamA: "blue_" else: "red_"
  case unit.kind
  of c23.rtHeadquarters: tint & "headquarters"
  of c23.rtCarrier: tint & "carrier"
  of c23.rtLauncher: tint & "launcher"
  of c23.rtDestabilizer: tint & "destabilizer"
  of c23.rtBooster: tint & "booster"
  of c23.rtAmplifier: tint & "amplifier"

proc bc23WellSprite(well: w23.Well): string =
  let base =
    case well.kind
    of u23.resAdamantium: "adamantium_well"
    of u23.resMana: "mana_well"
    of u23.resElixir: "elixir_well"
    of u23.resNone: "adamantium_well"
  if well.upgraded: base & "_upgraded" else: base

proc bc23TerrainStage(w: w23.World): int =
  ## The island tint and the well types both change during a game, so the
  ## terrain sprite is re-cut on a fixed cadence rather than per round: eight
  ## rounds is often enough that an island changing hands is visible as it
  ## happens and rare enough that a 60x30 board is not re-rasterised
  ## twenty-four times a second.
  w.currentRound div 8

proc renderBc23Terrain(r: Renderer, w: w23.World): Image =
  result = newImage(w.width * TileSize, w.height * TileSize)
  result.fill(Bc23TileColor)
  let ctx = newContext(result)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let px = x * TileSize
      ## The board's y axis grows NORTH; the canvas grows down.
      let py = (w.height - 1 - y) * TileSize
      let l = u23.loc(x, y)
      let i = w23.idx(w, l)
      var colour = Bc23TileColor
      if w.walls[i]:
        colour = Bc23WallColor
      else:
        let islandIdx = w23.islandAt(w, l)
        if islandIdx >= 0:
          colour =
            case w.islands[islandIdx].owner
            of 1: Bc23IslandAColor
            of 2: Bc23IslandBColor
            else: Bc23IslandColor
        elif w.currents[i] != u23.dCenter:
          colour = Bc23CurrentColor
      ctx.fillStyle = colour
      ctx.fillRect(rect(float32(px), float32(py),
                        float32(TileSize), float32(TileSize)))
      ## Clouds are a translucent haze ON TOP, so a spectator can see WHY a
      ## launcher group lost track of a carrier.
      if w.clouds[i]:
        ctx.fillStyle = rgba(Bc23CloudColor.r, Bc23CloudColor.g,
                             Bc23CloudColor.b, 110)
        ctx.fillRect(rect(float32(px), float32(py),
                          float32(TileSize), float32(TileSize)))
      ## A current is drawn as a faint bar along its own direction: a
      ## spectator who cannot see the currents cannot understand why a carrier
      ## is drifting.
      if w.currents[i] != u23.dCenter:
        let d = w.currents[i]
        ctx.fillStyle = rgba(0xa8, 0xc4, 0xe8, 90)
        let cx = float32(px + TileSize div 2)
        let cy = float32(py + TileSize div 2)
        let ddx = float32(u23.dx(d)) * 5.0
        let ddy = float32(-u23.dy(d)) * 5.0
        ctx.fillRect(rect(cx + ddx - 1.5, cy + ddy - 1.5, 3.0, 3.0))
      ## The boost / destabilise fields the doctrines paid elixir for: a
      ## boosted patch reads warm, a destabilised one cold.
      for t in 0 .. 1:
        let hundredths = w.tempo.hundredths[t][i]
        if hundredths < u23.BaseMultiplier:
          ctx.fillStyle = rgba(0xff, 0xc4, 0x6a, 40)
          ctx.fillRect(rect(float32(px), float32(py),
                            float32(TileSize), float32(TileSize)))
        elif hundredths > u23.BaseMultiplier and not w.clouds[i]:
          ctx.fillStyle = rgba(0x6a, 0xc4, 0xff, 40)
          ctx.fillRect(rect(float32(px), float32(py),
                            float32(TileSize), float32(TileSize)))

proc buildBc23Packet(r: Renderer, w: w23.World, gameIndex, sideAslot: int,
                     chrome: string): seq[uint8] =
  var packet: seq[uint8]
  let newGame = r.terrainGame != gameIndex
  let stage = bc23TerrainStage(w)

  if newGame:
    r.terrainGame = gameIndex
    r.terrainStage = -1
    r.liveObjects.clear()
    r.prevRobotSprite.clear()
    packet.addClearObjects()
    packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
    packet.addViewport(MapLayerId, w.width * TileSize, w.height * TileSize)

  if r.terrainStage != stage:
    r.terrainStage = stage
    let terrain = r.renderBc23Terrain(w)
    packet.addSprite(TerrainSpriteId, terrain.width, terrain.height,
      straightPixels(terrain), "terrain")
    packet.addObject(1, 0, 0, -32768, MapLayerId, TerrainSpriteId)

  ## Wells, with their resource glyph and their rate. A well turns into the
  ## elixir sprite the MOMENT it transforms, which is the single most
  ## watchable event of the elixir programme.
  var wellSeen = initHashSet[int]()
  for i in 0 ..< w.wellAt.len:
    if not w.wellAt[i].present: continue
    let l = w23.indexToLoc(w, i)
    let objectId = CheeseObjectBase + i
    wellSeen.incl(objectId)
    let sprite = r.spriteId(packet, bc23WellSprite(w.wellAt[i]))
    r.addObj(packet, objectId, l.x * TileSize,
      (w.height - 1 - l.y) * TileSize, 2, sprite)
  for objectId in toSeq(r.liveObjects):
    if objectId >= CheeseObjectBase and objectId < TrapAObjectBase and
        objectId notin wellSeen:
      r.dropObj(packet, objectId)

  ## Every live robot. Object ids are stable for a robot's whole life, so the
  ## client's motion interpolation glides it between rounds instead of
  ## teleporting it. A carrier that is FERRYING AN ANCHOR is badged, because
  ## that carrier is the most important unit on the board.
  var seen = initHashSet[int]()
  for id in w.execOrder:
    let unit = w.robotsById[id]
    let objectId = RobotObjectBase + (id mod 20000)
    seen.incl(objectId)
    let sprite = r.spriteId(packet, bc23UnitSprite(unit))
    r.addObj(packet, objectId, unit.loc.x * TileSize,
      (w.height - 1 - unit.loc.y) * TileSize,
      (if unit.kind == c23.rtHeadquarters: 4 else: 5), sprite)
    if w23.totalAnchors(unit) > 0:
      let badgeId = SoupObjectBase + (id mod 20000)
      seen.incl(badgeId)
      let badge = r.spriteId(packet,
        (if unit.acceleratingAnchors > 0: "accelerating_anchor" else: "anchor"))
      r.addObj(packet, badgeId, unit.loc.x * TileSize,
        (w.height - 1 - unit.loc.y) * TileSize, 6, badge)
  for objectId in toSeq(r.liveObjects):
    if objectId >= RobotObjectBase and objectId notin seen:
      r.dropObj(packet, objectId)

  packet.addSprite(BroadcastChromeSpriteId, 1, 1, [0'u8, 0, 0, 0], chrome)
  packet

proc buildSessionPacket*(r: Renderer, s: Session, chrome: string): seq[uint8] =
  ## The ONE place the renderer branches on the year. `Session` is an object
  ## variant, so the compiler checks that a new year gets an arm here.
  case s.year
  of yBc26: r.buildPacket(s.w26, s.gameIndex, s.sideAslot, chrome)
  of yBc20: r.buildBc20Packet(s.w20, s.gameIndex, s.sideAslot, chrome)
  of yBc21: r.buildBc21Packet(s.w21, s.gameIndex, s.sideAslot, chrome)
  of yBc24: r.buildBc24Packet(s.w24, s.gameIndex, s.sideAslot, chrome)
  of yBc25: r.buildBc25Packet(s.w25, s.gameIndex, s.sideAslot, chrome)
  of yBc23: r.buildBc23Packet(s.w23, s.gameIndex, s.sideAslot, chrome)
