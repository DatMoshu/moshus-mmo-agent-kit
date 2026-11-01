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

## The server announces each map as (map_id, key, size) in `map_info`; load that map's tiles from local data.
## Returns false when this source has no data for `key` (renderers then draw placeholders).
func register_map(_map_id: int, _key: String, _w: int, _h: int) -> bool:
	return false

## Start a conversation with an NPC whose server-side dialogue reference is `talk` (0 = none) on `map_id`.
## null when the NPC has nothing to say (or the source has no dialogue).
func start_talk(_map_id: int, _talk: int) -> Conversation:
	return null
