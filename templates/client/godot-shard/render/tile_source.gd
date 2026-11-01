## TileSource: the client half of a game adapter (contract: docs/SHARD_CORE.md). Rendering-neutral:
## tile ids per map, one 16x16-px image per tile id, and (optionally) NPC dialogue. DocSource implements it
## from a world document; a game adds its own (e.g. a reader for the player's install). The core client
## (net/, render/, ui/, scenes/) knows no game.
class_name TileSource
extends RefCounted

const TILE_PX := 16

var root := ""   # where the data came from (diagnostics only)
var source := "" # kind of data found ("install", "fixture", "doc", ...); "" = nothing found
var maps := {}   # map_id -> {"w": int, "h": int, "tiles": PackedByteArray, "key": String}
var error := ""  # why loading failed
var player_tile := 31 # tile id drawn for players (the game's hero sprite)
var tileset: TilesetPack # the art renderers draw (null = this source's own atlas()); main.set_tileset() sets it
var _default_pack: TilesetPack

## Per-tile-id walk flags (1 = walkable) when the adapter ships them; empty = use the renderer's profile table.
func walk_table() -> PackedByteArray:
	return PackedByteArray()

## Voxel tile table for the 3D view (format: docs/VOXEL_TABLE.md). Empty = the generic
## client/render/voxel/tile_profiles.json (flat ground, every id >= 64 a sprite).
func voxel_table() -> Dictionary:
	return {}

## Tile id at (x, y) on map_id, or -1 outside the map / map unknown.
func tile_at(_map_id: int, _x: int, _y: int) -> int:
	return -1

## Map size in tiles (Vector2i.ZERO when unknown).
func map_size(_map_id: int) -> Vector2i:
	return Vector2i.ZERO

## Atlas texture with every tile (null when no data), and the source rect for one tile.
func atlas() -> Texture2D:
	return null

## The same atlas as a CPU Image (16 x 16 grid of tiles), for renderers that build geometry or sprites
## from pixels (works headless, where a texture's image may not be readable). null when no data.
func atlas_image() -> Image:
	return null

func tile_rect(tile: int) -> Rect2:
	return Rect2((tile % 16) * TILE_PX, (tile / 16) * TILE_PX, TILE_PX, TILE_PX)

## ---------------------------------------------------------------- tilesets (docs/SHARD_CORE.md "Tilesets")
## atlas() / atlas_image() / tile_rect() stay this source's own art (the default pack, and the voxel colours unless
## a pack asks to be sampled). Renderers draw through the view_* calls, which follow the active pack.

func set_tileset(pack: TilesetPack) -> void:
	tileset = pack


func view_atlas() -> Texture2D:
	return tileset.texture if tileset and tileset.texture else atlas()


func view_atlas_image() -> Image:
	return tileset.image if tileset and tileset.image else atlas_image()


## Source rect of tile id `tile` in view_atlas() (animated packs advance with the clock).
func view_tile_rect(tile: int) -> Rect2:
	return tileset.rect(tile, Time.get_ticks_msec()) if tileset and tileset.image else tile_rect(tile)


## Pixel size of one tile in view_atlas().
func view_cell() -> int:
	return tileset.cell if tileset and tileset.image else TILE_PX


## The default pack: this source's own atlas under the game's id/name for it. Built once.
func default_tileset() -> TilesetPack:
	if _default_pack == null and atlas_image() != null:
		_default_pack = TilesetPack.from_image(default_tileset_id(), default_tileset_name(), atlas_image(),
			default_tileset_meta())
	return _default_pack


func default_tileset_id() -> String:
	return "default"


func default_tileset_name() -> String:
	return "Default"


## platform / credit / licence shown for the default pack.
func default_tileset_meta() -> Dictionary:
	return {}


## Other packs the game builds from the player's data (e.g. another platform's art in the same install).
func builtin_tilesets() -> Array[TilesetPack]:
	return []


## A manifest's source {"kind": "install", "extractor": E, "path": P}: a 16-column sheet of the 256 tiles at
## the manifest's tile_size, read from the player's own install. null = this game has no such extractor / no data.
func extract_tileset(_extractor: String, _path: String) -> Image:
	return null


## A manifest for a pack folder without tileset.json (a community layout the game recognises); {} = unknown.
func detect_tileset(_dir: String) -> Dictionary:
	return {}


## Allowed manifest "platform" ids (empty = any lowercase slug).
func tileset_platforms() -> PackedStringArray:
	return PackedStringArray()

## The server announces each map as (map_id, key, size) in `map_info`; load that map's tiles from local data.
## Returns false when this source has no data for `key` (renderers then draw placeholders).
func register_map(_map_id: int, _key: String, _w: int, _h: int) -> bool:
	return false

## Start a conversation with an NPC whose server-side dialogue reference is `talk` (0 = none) on `map_id`.
## null when the NPC has nothing to say (or the source has no dialogue).
func start_talk(_map_id: int, _talk: int) -> Conversation:
	return null
