## DocSource: a game-neutral TileSource read from an `mmo-core-world/1` document (the same JSON the server
## is seeded from; contract: docs/SHARD_CORE.md). Lets a new game run the core client before it has a
## custom loader: tiles come from doc.maps, walk flags from doc.walkable, art is generated flat colours
## (doc.client.colors: {"<tile id>": "#rrggbb"}; ids >= 64 are drawn as sprites), NPC dialogue from
## doc.client.dialogue: {"<map_id>": {"<talk>": {LOOK, NAME, JOB, ..., BYE}}} (see KeywordTalk).
## Only for data you may ship (e.g. tools/shard/fixture_game.py). Commercial game data needs its own
## loader that reads the player's install at run time, never a document in the repo.
## Optional doc.client keys: colors, dialogue, voxel (3D tile table), player_tile (hero sprite id).
class_name DocSource
extends TileSource

var game := ""
var _walk := PackedByteArray()
var _colors := {}
var _dialogue := {}
var _atlas: ImageTexture
var _atlas_img: Image


var _voxel: Dictionary = {}


func voxel_table() -> Dictionary:
	return _voxel


func load_doc(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var doc = JSON.parse_string(text) if text != "" else null
	if typeof(doc) != TYPE_DICTIONARY or doc.get("format", "") != "mmo-core-world/1":
		error = "DocSource: %s is not an mmo-core-world/1 document" % path
		return false
	game = String(doc.get("game", ""))
	for m in doc.get("maps", []):
		var t := PackedByteArray()
		for v in m["tiles"]:
			t.append(int(v))
		maps[int(m["id"])] = {"w": int(m["width"]), "h": int(m["height"]), "tiles": t, "key": String(m["key"])}
	for w in doc.get("walkable", []):
		_walk.append(1 if w else 0)
	var client: Dictionary = doc.get("client", {})
	_colors = client.get("colors", {})
	_dialogue = client.get("dialogue", {})
	_voxel = client.get("voxel", {})
	player_tile = int(client.get("player_tile", player_tile))
	_build_atlas()
	root = path
	source = "doc"
	return maps.has(0)


func walk_table() -> PackedByteArray:
	return _walk


func tile_at(map_id: int, x: int, y: int) -> int:
	var m: Dictionary = maps.get(map_id, {})
	if m.is_empty() or x < 0 or y < 0 or x >= m["w"] or y >= m["h"]:
		return -1
	return m["tiles"][y * m["w"] + x]


func map_size(map_id: int) -> Vector2i:
	var m: Dictionary = maps.get(map_id, {})
	return Vector2i(m["w"], m["h"]) if not m.is_empty() else Vector2i.ZERO


func atlas() -> Texture2D:
	return _atlas


func atlas_image() -> Image:
	return _atlas_img


func register_map(map_id: int, key: String, _w: int, _h: int) -> bool:
	return maps.has(map_id) and maps[map_id]["key"] == key


func start_talk(map_id: int, talk: int) -> Conversation:
	var d = _dialogue.get(str(map_id), {}).get(str(talk), null)
	return KeywordTalk.from_dict(d) if typeof(d) == TYPE_DICTIONARY else null


func _build_atlas() -> void:
	var img := Image.create(16 * TILE_PX, 16 * TILE_PX, false, Image.FORMAT_RGBA8)
	for id in 256:
		var c: Color
		if _colors.has(str(id)):
			c = Color(String(_colors[str(id)]))
		else:
			c = Color.from_hsv(fmod(id * 0.618034, 1.0), 0.45, 0.75)
		var r := tile_rect(id)
		if id < 64:
			img.fill_rect(Rect2i(r), c)
			img.fill_rect(Rect2i(int(r.position.x), int(r.position.y) + TILE_PX - 1, TILE_PX, 1), c.darkened(0.25))
		else:   # sprite: a filled diamond on transparent
			for py in TILE_PX:
				for px in TILE_PX:
					if absi(px - 7) + absi(py - 7) <= 6:
						img.set_pixel(int(r.position.x) + px, int(r.position.y) + py, c)
	_atlas_img = img
	_atlas = ImageTexture.create_from_image(img)
