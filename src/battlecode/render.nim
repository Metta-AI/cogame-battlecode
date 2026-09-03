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

import std/[json, os, sequtils, sets, tables]
import pixie
import bitworld/spriteprotocol
import sheet
import years/bc26/[constants, maps, world]

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

  FloorColor = rgba(38, 32, 28, 255)
  WallColor = rgba(88, 74, 60, 255)
  GridColor = rgba(46, 39, 34, 255)

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
    terrainGame: int

proc loadAtlas(): Atlas =
  let root = dataRoot()
  result = Atlas(image: readImage(root / "atlas.png"),
                 cells: initTable[string, tuple[x, y, w, h: int]]())
  let doc = parseJson(readFile(root / "atlas.json"))
  for name, cell in doc["sprites"]:
    result.cells[name] = (cell["x"].getInt(), cell["y"].getInt(),
                          cell["w"].getInt(), cell["h"].getInt())

proc newRenderer*(): Renderer =
  Renderer(atlas: loadAtlas(), spriteIds: initTable[string, int](),
           nextSpriteId: AtlasSpriteBase, sentSprites: initHashSet[int](),
           liveObjects: initHashSet[int](), terrainGame: -1)

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
