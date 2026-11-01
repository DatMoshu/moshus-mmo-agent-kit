## VoxelProfiles: the voxel tile table (docs/VOXEL_TABLE.md) plus per-tile voxel templates.
## A template is one tile's 16x16 (or res x res) height/colour field for one 8-neighbour context, stored as an
## RGBA8 Image so chunk assembly is a C++ blit: R = top height + 64 (1/16 tile units), G = EGA colour index of the
## top pixel (0 = ground colour), B = canopy colour index + 1 (0 = none), A = category index (255 = void).
## Built from the TileSource's atlas pixels at runtime; nothing here is ever written to disk.
class_name VoxelProfiles
extends RefCounted

const H_BIAS := 64
const VOID := 255
const INF := 1 << 20
# 8-neighbour order used by masks: N, E, S, W, NE, SE, SW, NW
const NB := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

var cat_names: PackedStringArray = []
var cat_of_tile := PackedInt32Array()
var base := PackedInt32Array()     # per category
var noise := PackedInt32Array()
var opaque := PackedByteArray()
var opaque_tile := PackedByteArray() # per tile id (LOS)
var walkable := PackedByteArray() # per tile id: the server's collision table ("walk" section; autopilot pathing)
var glow := PackedByteArray()
var water := PackedByteArray()
var ground_col: Array[Color] = []
var side_col: Array[Color] = []
var black_water := PackedInt32Array() # per category: absolute height for black pixels, or -INF
var _bevel: Array = []
var _bevel_strong: Array = [] # "bevel" option on: stronger edge bevels
var vary_h := PackedInt32Array() # per category: max extra height per clump ("vary" option)
var vary_c := PackedFloat32Array() # per category: top colour jitter amplitude ("vary" option)
var _terrace: Array = [] # [step, every, max] or []
var _round := PackedInt32Array()
var _rules: Array = [] # per category: 16 entries of {dh|canopy|colour|keep}
# derived per (cat*16 + ega) lookups for the mesher
var canopy_b := PackedInt32Array()
var canopy_t := PackedInt32Array()
var pix_flags := PackedInt32Array() # bit1 water, bit2 glow, bit3 colour variation
var sprite_pairs: Array = []
var avatar_tile := 31

var _pixels := PackedByteArray() # 256 tiles * 256 px EGA indices
var _have_pixels := false
## True while the pixels come from a tileset pack (voxel colour sampling): a pixel shows its own (EGA-snapped)
## colour and the table's per-pixel "colour" overrides are ignored (heights, water, glow and canopy rules stay).
var pack_colours := false
var _templates := {}
var _lock := Mutex.new()
var true_black := false


func load_table(path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_error("VoxelProfiles: cannot read %s" % path)
		return false
	return load_dict(d)


## Same table as a Dictionary (a game's TileSource.voxel_table(), e.g. a world document's client.voxel).
func load_dict(d: Dictionary) -> bool:
	var cats: Dictionary = d["categories"]
	var index := {}
	for name in cats:
		var c: Dictionary = cats[name]
		index[name] = cat_names.size()
		cat_names.append(name)
		base.append(int(c.get("base", 0)))
		noise.append(int(c.get("noise", 0)))
		opaque.append(1 if c.get("opaque", false) else 0)
		glow.append(1 if c.get("glow", false) else 0)
		water.append(1 if c.get("water", false) else 0)
		var g := Color(String(c.get("ground", "#202020")))
		ground_col.append(g)
		side_col.append(Color(String(c["side"])) if c.has("side") else g.darkened(0.25))
		black_water.append(int(c["black_water"]) if c.has("black_water") else -INF)
		_bevel.append((c.get("bevel", []) as Array).map(func(v): return int(v)))
		_bevel_strong.append((c.get("bevel_strong", c.get("bevel", [])) as Array).map(func(v): return int(v)))
		var vy: Dictionary = c.get("vary", {})
		vary_h.append(int(vy.get("h", 0)))
		vary_c.append(float(vy.get("c", 0.0)))
		var t = c.get("terrace")
		_terrace.append([int(t["step"]), int(t["every"]), int(t["max"])] if t is Dictionary else [])
		_round.append(int(c.get("round", 0)))
		var rules := []
		var px: Dictionary = c.get("pixels", {})
		for e in range(16):
			rules.append(px.get(str(e), px.get("*", {})))
		_rules.append(rules)
	cat_of_tile.resize(256)
	cat_of_tile.fill(index.get("prop", 0))
	for r in d["tiles"]:
		for t in range(int(r[0]), int(r[1]) + 1):
			cat_of_tile[t] = index[String(r[2])]
	opaque_tile.resize(256)
	for t in range(256):
		opaque_tile[t] = opaque[cat_of_tile[t]]
	var wk: Dictionary = d.get("walk", {})
	walkable.resize(256)
	for t in range(256):
		var dflt = (wk.get("categories", {}) as Dictionary).get(cat_names[cat_of_tile[t]], false)
		walkable[t] = 1 if (wk.get("tiles", {}) as Dictionary).get(str(t), dflt) else 0
	var n := cat_names.size()
	canopy_b.resize(n * 16); canopy_t.resize(n * 16); pix_flags.resize(n * 16)
	for c in range(n):
		for e in range(16):
			var rule: Dictionary = _rules[c][e] if e > 0 else {}
			var cp = rule.get("canopy")
			canopy_b[c * 16 + e] = int(cp[0]) if cp else 0
			canopy_t[c * 16 + e] = int(cp[1]) if cp else 0
			var f := 0
			if water[c] or (e == 0 and black_water[c] > -INF):
				f |= 2
			if glow[c]:
				f |= 4
			if vary_c[c] > 0.0 and not (f & 2):
				f |= 8
			pix_flags[c * 16 + e] = f
	var sp: Dictionary = d.get("sprites", {})
	sprite_pairs = sp.get("pairs", [])
	avatar_tile = int(sp.get("avatar", 31))
	return true


## EGA indices of every tile pixel, from the TileSource's CPU atlas (exact palette match).
func set_pixels(atlas: Image, ega: Array) -> void:
	_templates.clear()
	_have_pixels = atlas != null
	_pixels.resize(256 * 256)
	_pixels.fill(0)
	if atlas == null:
		return
	var lut := {}
	for i in ega.size():
		lut[(ega[i] as Color).to_rgba32()] = i
	for t in range(256):
		var ox := (t % 16) * 16
		var oy := (t / 16) * 16
		for y in range(16):
			for x in range(16):
				var c := atlas.get_pixel(ox + x, oy + y)
				_pixels[t * 256 + y * 16 + x] = lut.get(c.to_rgba32(), _nearest(c, ega))
	_have_pixels = true


func _nearest(c: Color, ega: Array) -> int:
	var best := 0
	var bd := 1e9
	for i in ega.size():
		var e: Color = ega[i]
		var dd := (e.r - c.r) ** 2 + (e.g - c.g) ** 2 + (e.b - c.b) ** 2
		if dd < bd:
			bd = dd; best = i
	return best


## Colour of a top/side face for (category, EGA index): index 0 = the category's ground colour.
func top_color(cat: int, e: int, ega: Array) -> Color:
	if e == 0:
		return Color.BLACK if true_black and not water[cat] else ground_col[cat]
	var rule: Dictionary = _rules[cat][e]
	if rule.has("colour") and not pack_colours:
		return Color(String(rule["colour"]))
	return ega[e]


func is_lower(cat: int, other_tile: int) -> bool:
	return other_tile >= 0 and base[cat_of_tile[other_tile]] < base[cat]


## 8-neighbour mask of LOWER neighbours + the fill category (lowest edge neighbour) for convex rounding.
func context(tile: int, nb_tiles: PackedInt32Array) -> int:
	var cat := cat_of_tile[tile]
	var mask := 0
	var fill := cat
	var fill_base := INF
	for k in range(8):
		var o := nb_tiles[k]
		if is_lower(cat, o):
			mask |= 1 << k
			var oc := cat_of_tile[o]
			if k < 4 and base[oc] < fill_base:
				fill_base = base[oc]; fill = oc
	return tile | (mask << 8) | (fill << 16)


## Template image for a context key (thread-safe, cached). strong = use bevel_strong.
func template(key: int, res: int, strong := false) -> Image:
	var ck := key | (res << 24) | (int(strong) << 30)
	_lock.lock()
	var img: Image = _templates.get(ck)
	_lock.unlock()
	if img:
		return img
	img = _build(key & 0xFF, (key >> 8) & 0xFF, (key >> 16) & 0xFF, strong)
	if res != 16:
		img = _downsample(img, res)
	_lock.lock()
	_templates[ck] = img
	_lock.unlock()
	return img


func _build(tile: int, mask: int, fill: int, strong := false) -> Image:
	var cat := cat_of_tile[tile]
	var data := PackedByteArray()
	data.resize(16 * 16 * 4)
	var bev: Array = _bevel_strong[cat] if strong else _bevel[cat]
	var ter: Array = _terrace[cat]
	var r := float(_round[cat])
	var n := mask & 1; var e := mask & 2; var s := mask & 4; var w := mask & 8
	for py in range(16):
		for px in range(16):
			var d := INF
			if n: d = mini(d, py)
			if s: d = mini(d, 15 - py)
			if w: d = mini(d, px)
			if e: d = mini(d, 15 - px)
			# concave corners: a single lower diagonal neighbour -> rounded notch
			if mask & 16 and not n and not e: d = mini(d, int(Vector2(15 - px, py).length()))
			if mask & 32 and not s and not e: d = mini(d, int(Vector2(15 - px, 15 - py).length()))
			if mask & 64 and not s and not w: d = mini(d, int(Vector2(px, 15 - py).length()))
			if mask & 128 and not n and not w: d = mini(d, int(Vector2(px, py).length()))
			# convex corners: two lower edge neighbours -> round the corner off (pixels outside take the fill)
			var filled := false
			if r > 0:
				for cc in [[n, w, r - px - 0.5, r - py - 0.5], [n, e, r - (15 - px) - 0.5, r - py - 0.5],
						[s, w, r - px - 0.5, r - (15 - py) - 0.5], [s, e, r - (15 - px) - 0.5, r - (15 - py) - 0.5]]:
					if cc[0] and cc[1] and cc[2] > 0 and cc[3] > 0:
						var dd: float = r - Vector2(cc[2], cc[3]).length()
						if dd < 0:
							filled = true
						else:
							d = mini(d, int(dd))
			var o := (py * 16 + px) * 4
			if filled:
				data[o] = base[fill] + H_BIAS; data[o + 1] = 0; data[o + 2] = 0; data[o + 3] = fill
				continue
			var h := base[cat]
			if ter.size() == 3:
				h += mini(ter[2], ter[0] * (d / ter[1]))
			if d < bev.size():
				h -= bev[d]
			var ei := int(_pixels[tile * 256 + py * 16 + px]) if _have_pixels else 0
			var canopy := 0
			if ei == 0:
				if black_water[cat] > -INF:
					h = black_water[cat]
			else:
				var rule: Dictionary = _rules[cat][ei]
				if rule.has("canopy"):
					canopy = ei + 1
					ei = 0 # ground under the canopy
				else:
					h += int(rule.get("dh", 0))
			data[o] = clampi(h + H_BIAS, 0, 255); data[o + 1] = ei; data[o + 2] = canopy; data[o + 3] = cat
	return Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, data)


## Lower resolution: each res-pixel takes the highest of its source block (keeps thin walls and peaks).
func _downsample(src: Image, res: int) -> Image:
	var f := 16 / res
	var sd := src.get_data()
	var data := PackedByteArray()
	data.resize(res * res * 4)
	for y in range(res):
		for x in range(res):
			var best := -1
			var bo := 0
			for yy in range(f):
				for xx in range(f):
					var o := ((y * f + yy) * 16 + x * f + xx) * 4
					var v := int(sd[o]) * 32 + int(sd[o + 2] > 0) * 16 + int(sd[o + 1] > 0)
					if v > best:
						best = v; bo = o
			var to := (y * res + x) * 4
			for k in range(4):
				data[to + k] = sd[bo + k]
	return Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, data)
