## Tilesets: finds every tileset pack a player can switch to (docs/SHARD_CORE.md "Tilesets").
## Order: the game's default art (TileSource.default_tileset()), the game's other built-ins
## (TileSource.builtin_tilesets(), e.g. other platforms' art read from the install), then one pack per folder
## in user://tilesets/<id>/ (a tileset.json manifest, or a layout the game recognises via detect_tileset()).
## A pack that fails validation or cannot be read is skipped with a TILESET skip line; duplicate ids keep the first.
class_name Tilesets
extends RefCounted

const USER_DIR := "user://tilesets"


static func discover(src: TileSource, dirs: PackedStringArray = PackedStringArray([USER_DIR])) -> Array[TilesetPack]:
	var out: Array[TilesetPack] = []
	var by_id := {}
	if src == null:
		return out
	var base := src.default_tileset()
	if base:
		out.append(base)
		by_id[base.id] = base
	for p in src.builtin_tilesets():
		if p and p.image and not by_id.has(p.id):
			out.append(p)
			by_id[p.id] = p
	var found: Array = [] # [manifest, dir]
	for root in dirs:
		var da := DirAccess.open(root)
		if da == null:
			continue
		var subs := Array(da.get_directories())
		subs.sort()
		for sub in subs:
			var d := root.path_join(sub)
			var m := read_manifest(d, src)
			if m.is_empty():
				print("TILESET skip dir=%s (no tileset.json and no known layout)" % d)
				continue
			var errs := TilesetPack.validate(m, src.tileset_platforms())
			if not errs.is_empty():
				print("TILESET skip dir=%s invalid: %s" % [d, "; ".join(errs)])
				continue
			found.append([m, d])
	# packs whose fallback is another user pack load after it (two passes cover one level of chaining)
	for _pass in 2:
		var rest: Array = []
		for e in found:
			var m: Dictionary = e[0]
			if by_id.has(m["id"]):
				print("TILESET skip dir=%s duplicate id %s" % [e[1], m["id"]])
				continue
			var fb_id := String(m.get("fallback", ""))
			if fb_id != "" and not by_id.has(fb_id) and _pass == 0:
				rest.append(e)
				continue
			var fb: TilesetPack = by_id.get(fb_id, base)
			var p := TilesetPack.build(m, e[1], src, fb)
			if p.error != "":
				print("TILESET skip dir=%s id=%s: %s" % [e[1], m["id"], p.error])
				continue
			out.append(p)
			by_id[p.id] = p
		found = rest
	for p in out:
		print("TILESET id=%s name=\"%s\" platform=%s cell=%d mapped=%d/256 anim=%d %s" % [p.id, p.name, p.platform,
			p.cell, p.mapped_count(), p.anims.size(), "builtin" if p.builtin else "dir=" + p.dir])
	return out


## tileset.json in `d`, else whatever the game detects from the folder's files ({} = not a pack).
static func read_manifest(d: String, src: TileSource) -> Dictionary:
	var f := d.path_join("tileset.json")
	if FileAccess.file_exists(f):
		var m = JSON.parse_string(FileAccess.get_file_as_string(f))
		return m if m is Dictionary else {"schema": 0}
	return src.detect_tileset(d) if src else {}


static func find(list: Array[TilesetPack], pack_id: String) -> TilesetPack:
	for p in list:
		if p.id == pack_id:
			return p
	return null
