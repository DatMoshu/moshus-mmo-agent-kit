## TilesetPack: one switchable set of tile art (manifest format: docs/SHARD_CORE.md "Tilesets").
## A pack becomes a renderer-ready atlas: 16 columns of square `cell`-px tiles, tile id t in cell t, plus
## animation frames in extra rows after the first 256 cells. A tile the pack does not draw is copied from its
## fallback pack (scaled to the cell size), so every pack always resolves all 256 ids.
## Packs are built at runtime from the player's own files; nothing here is ever written to the repo.
class_name TilesetPack
extends RefCounted

const SCHEMA := 1
const TILES := 256
const MAX_CELL := 64
const ID_RX := "^[a-z0-9][a-z0-9-]{1,47}$"
const KINDS := ["install", "pack"]

var id := ""
var name := ""
var platform := ""
var credit := ""
var licence := ""
var url := ""
var fallback := ""          # pack id unmapped tiles come from ("" = the game's default pack)
var voxel_colour := "ega"   # "ega" = voxel terrain keeps the default pack's colours, "sample" = take them from this pack
var dir := ""               # folder the pack was loaded from ("" for built-ins)
var builtin := false
var manifest := {}
var cell := TileSource.TILE_PX
var image: Image            # the composed atlas (see above)
var texture: ImageTexture
var mapped := PackedByteArray()   # per tile id: 1 = drawn by this pack, 0 = taken from the fallback
var anims := {}             # tile id -> PackedInt32Array of cell indices (first = the tile's own cell)
var anim_fps := 0.0
var error := ""
var _small: Image


## Problems with a manifest (empty = valid). `platforms` = the game's allowed platform ids (empty = any slug).
static func validate(m: Dictionary, platforms := PackedStringArray()) -> PackedStringArray:
	var errs := PackedStringArray()
	var rx := RegEx.create_from_string(ID_RX)
	for k in ["schema", "id", "name", "platform", "tile_size", "source"]:
		if not m.has(k):
			errs.append("missing '%s'" % k)
	if not errs.is_empty():
		return errs
	if int(m["schema"]) != SCHEMA:
		errs.append("schema %s (this client reads %d)" % [m["schema"], SCHEMA])
	if not (m["id"] is String) or rx.search(m["id"]) == null:
		errs.append("id must match %s" % ID_RX)
	if not (m["name"] is String) or String(m["name"]).strip_edges() == "":
		errs.append("name must be a non-empty string")
	var plat := String(m["platform"])
	if rx.search(plat) == null or (not platforms.is_empty() and not (plat in platforms)):
		errs.append("platform '%s' not one of %s" % [plat, ", ".join(platforms) if not platforms.is_empty() else ID_RX])
	var ts = m["tile_size"]
	if not (ts is Array and ts.size() == 2 and int(ts[0]) >= 4 and int(ts[1]) >= 4 and int(ts[0]) <= 256 and int(ts[1]) <= 256):
		errs.append("tile_size must be [w, h] with 4..256 px")
	if m.has("fit") and not (String(m["fit"]) in ["stretch", "pad"]):
		errs.append("fit must be stretch or pad")
	if m.has("palette"):
		var p = m["palette"]
		if p is String:
			if not (p in ["embedded", "ega", "cga"]):
				errs.append("palette must be embedded, ega, cga or a list of #rrggbb")
		elif p is Array:
			for c in p:
				if not (c is String and Color.html_is_valid(c)):
					errs.append("palette entry '%s' is not a colour" % str(c))
					break
		else:
			errs.append("palette must be a string or a list")
	var s = m["source"]
	if not (s is Dictionary and String(s.get("kind", "")) in KINDS):
		errs.append("source.kind must be install or pack")
	elif s["kind"] == "install":
		if String(s.get("extractor", "")) == "":
			errs.append("source.extractor missing")
	else:
		var sh = s.get("sheets", [])
		if not (sh is Array) or sh.is_empty():
			errs.append("source.sheets must list at least one sheet")
		else:
			for e in sh:
				var f := String(e.get("file", "")) if e is Dictionary else ""
				if f == "" or f.is_absolute_path() or ".." in f.split("/") or f.begins_with("res:") or f.begins_with("user:"):
					errs.append("sheet file '%s' must be a relative path inside the pack" % f)
				elif e.has("columns") and int(e["columns"]) < 1:
					errs.append("sheet columns must be >= 1")
	if m.has("mapping"):
		var mp = m["mapping"]
		if not (mp is Dictionary and String(mp.get("kind", "")) in ["identity", "table"]):
			errs.append("mapping.kind must be identity or table")
		elif mp["kind"] == "table":
			var t = mp.get("table", {})
			if not (t is Dictionary) or t.is_empty():
				errs.append("mapping.table must be a non-empty object")
			else:
				for key in t:
					if _range(String(key)).is_empty():
						errs.append("mapping key '%s' must be a tile id or range 0-255" % key)
						break
	if m.has("voxel_colour") and not (String(m["voxel_colour"]) in ["ega", "sample"]):
		errs.append("voxel_colour must be ega or sample")
	if m.has("fallback") and rx.search(String(m["fallback"])) == null:
		errs.append("fallback must be a pack id")
	return errs


## Tile ids for a mapping key: "17" or "0-15" (empty = invalid).
static func _range(k: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var parts := k.split("-")
	if parts.size() > 2 or not parts[0].is_valid_int() or (parts.size() == 2 and not parts[1].is_valid_int()):
		return out
	var a := int(parts[0])
	var b := int(parts[1]) if parts.size() == 2 else a
	if a < 0 or b > 255 or b < a:
		return out
	for t in range(a, b + 1):
		out.append(t)
	return out


## A built-in pack from a ready 256-tile atlas image (16 columns of square tiles).
static func from_image(pack_id: String, pack_name: String, img: Image, meta := {}) -> TilesetPack:
	var p := TilesetPack.new()
	p.id = pack_id
	p.name = pack_name
	p.builtin = true
	p.platform = String(meta.get("platform", ""))
	p.credit = String(meta.get("credit", ""))
	p.licence = String(meta.get("licence", ""))
	p.voxel_colour = String(meta.get("voxel_colour", "ega"))
	p.manifest = meta
	if img == null:
		p.error = "no image"
		return p
	p.cell = clampi(img.get_width() / 16, 4, MAX_CELL)
	p.image = img.duplicate() as Image
	if p.image.get_format() != Image.FORMAT_RGBA8:
		p.image.convert(Image.FORMAT_RGBA8)
	p.mapped.resize(TILES)
	p.mapped.fill(1)
	p.texture = ImageTexture.create_from_image(p.image)
	return p


## Build a pack from a manifest. `dir` holds its sheets; `src` supplies install extractors; `fb` is the fallback
## pack (already built) whose tiles fill the gaps. Returns a pack with `error` set when it cannot be used.
static func build(m: Dictionary, pack_dir: String, src: TileSource, fb: TilesetPack) -> TilesetPack:
	var p := TilesetPack.new()
	p.manifest = m
	p.dir = pack_dir
	p.id = String(m.get("id", ""))
	p.name = String(m.get("name", p.id))
	p.platform = String(m.get("platform", ""))
	p.credit = String(m.get("credit", ""))
	p.licence = String(m.get("licence", ""))
	p.url = String(m.get("url", ""))
	p.fallback = String(m.get("fallback", ""))
	p.voxel_colour = String(m.get("voxel_colour", "ega"))
	var ts: Array = m.get("tile_size", [16, 16])
	var tw := int(ts[0])
	var th := int(ts[1])
	p.cell = clampi(maxi(tw, th), TileSource.TILE_PX, MAX_CELL)
	# 1. the raw tiles, in sheet order
	var raw: Array[Image] = []
	var s: Dictionary = m["source"]
	if s["kind"] == "install":
		var img: Image = src.extract_tileset(String(s["extractor"]), String(s.get("path", ""))) if src else null
		if img == null:
			p.error = "extractor '%s' found no data" % s["extractor"]
			return p
		_cut(img, tw, th, 16, raw)
	else:
		for e in s["sheets"]:
			var path := pack_dir.path_join(String(e["file"]))
			var img := Image.new()
			if not FileAccess.file_exists(path) or img.load(path) != OK:
				p.error = "cannot read sheet %s" % e["file"]
				return p
			_cut(img, tw, th, int(e.get("columns", 16)), raw)
	if raw.is_empty():
		p.error = "no tiles in the sheets"
		return p
	# 2. palette snapping
	var pal := _palette(m.get("palette", "embedded"))
	if not pal.is_empty():
		for t in raw:
			_snap(t, pal)
	# 3. tile id -> raw indices (frames)
	var frames := {}
	var mp: Dictionary = m.get("mapping", {"kind": "identity"})
	if String(mp.get("kind", "identity")) == "identity":
		for t in mini(TILES, raw.size()):
			frames[t] = PackedInt32Array([t])
	else:
		var tbl: Dictionary = mp["table"]
		for key in tbl:
			var ids := _range(String(key))
			var v = tbl[key]
			for j in ids.size():
				var fr := PackedInt32Array()
				if v is Array:
					for x in v: # "128-143": [0, 16] -> tile 128+j animates raw j, 16+j
						fr.append(int(x) + j)
				else:
					fr.append(int(v) + j) # "0-15": 3 -> tiles 0..15 take raw 3..18
				var ok := PackedInt32Array()
				for x in fr:
					if x >= 0 and x < raw.size():
						ok.append(x)
				if not ok.is_empty():
					frames[ids[j]] = ok
		p.anim_fps = float(mp.get("fps", 0.0))
	# 4. compose the atlas
	var extra := 0
	for t in frames:
		extra += frames[t].size() - 1
	var rows := 16 + ceili(extra / 16.0)
	p.image = Image.create_empty(16 * p.cell, rows * p.cell, false, Image.FORMAT_RGBA8)
	p.image.fill(Color.BLACK)
	p.mapped.resize(TILES)
	p.mapped.fill(0)
	var fit := String(m.get("fit", "stretch"))
	var next := TILES
	for t in TILES:
		var at := Vector2i((t % 16) * p.cell, (t / 16) * p.cell)
		if frames.has(t):
			p.mapped[t] = 1
			var fr: PackedInt32Array = frames[t]
			p.image.blit_rect(_fit(raw[fr[0]], p.cell, fit), Rect2i(0, 0, p.cell, p.cell), at)
			if fr.size() > 1:
				var cells := PackedInt32Array([t])
				for i in range(1, fr.size()):
					p.image.blit_rect(_fit(raw[fr[i]], p.cell, fit), Rect2i(0, 0, p.cell, p.cell),
						Vector2i((next % 16) * p.cell, (next / 16) * p.cell))
					cells.append(next)
					next += 1
				p.anims[t] = cells
		elif fb and fb.image:
			var fc := fb.cell
			var one := fb.image.get_region(Rect2i((t % 16) * fc, (t / 16) * fc, fc, fc))
			p.image.blit_rect(_fit(one, p.cell, "stretch"), Rect2i(0, 0, p.cell, p.cell), at)
		else:
			_placeholder(p.image, at, p.cell)
	if p.anim_fps <= 0.0 and not p.anims.is_empty():
		p.anim_fps = 4.0
	p.texture = ImageTexture.create_from_image(p.image)
	return p


static func _cut(img: Image, tw: int, th: int, cols: int, out: Array[Image]) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	cols = mini(cols, img.get_width() / tw)
	if cols < 1:
		return
	var rows := img.get_height() / th
	for r in rows:
		for c in cols:
			out.append(img.get_region(Rect2i(c * tw, r * th, tw, th)))


static func _fit(t: Image, cell: int, fit: String) -> Image:
	var w := t.get_width()
	var h := t.get_height()
	if w == cell and h == cell:
		return t
	var interp := Image.INTERPOLATE_NEAREST if (cell % w == 0 and cell % h == 0) else Image.INTERPOLATE_BILINEAR
	if fit == "pad" and w != h:
		var f := float(cell) / maxi(w, h)
		var sw := maxi(1, roundi(w * f))
		var sh := maxi(1, roundi(h * f))
		var sc := t.duplicate() as Image
		sc.resize(sw, sh, interp)
		var out := Image.create_empty(cell, cell, false, Image.FORMAT_RGBA8)
		out.fill(Color.BLACK)
		out.blit_rect(sc, Rect2i(0, 0, sw, sh), Vector2i((cell - sw) / 2, (cell - sh) / 2))
		return out
	var r := t.duplicate() as Image
	r.resize(cell, cell, interp)
	return r


static func _palette(p) -> Array:
	if p is Array:
		var out := []
		for c in p:
			out.append(Color(String(c)))
		return out
	match String(p):
		"ega":
			return Palette.EGA
		"cga":
			return [Color8(0, 0, 0), Color8(85, 255, 255), Color8(255, 85, 255), Color8(255, 255, 255)]
	return []


static func _snap(img: Image, pal: Array) -> void:
	var cache := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var k := c.to_rgba32()
			if not cache.has(k):
				var best: Color = pal[0]
				var bd := 1e9
				for e: Color in pal:
					var dd: float = (e.r - c.r) ** 2 + (e.g - c.g) ** 2 + (e.b - c.b) ** 2
					if dd < bd:
						bd = dd; best = e
				cache[k] = best
			img.set_pixel(x, y, cache[k])


## Magenta/black checker for a tile nobody draws (only when there is no fallback art at all).
static func _placeholder(img: Image, at: Vector2i, cell: int) -> void:
	var h := maxi(1, cell / 2)
	img.fill_rect(Rect2i(at, Vector2i(cell, cell)), Color.BLACK)
	img.fill_rect(Rect2i(at, Vector2i(h, h)), Color.MAGENTA)
	img.fill_rect(Rect2i(at + Vector2i(h, h), Vector2i(cell - h, cell - h)), Color.MAGENTA)


## Cell index currently shown for tile id t (animation frames advance at anim_fps).
func cell_of(t: int, msec: int) -> int:
	var a = anims.get(t)
	if a == null:
		return t
	return a[int(msec * anim_fps / 1000.0) % a.size()]


func rect(t: int, msec := -1) -> Rect2:
	var c := t if msec < 0 else cell_of(t, msec)
	return Rect2((c % 16) * cell, (c / 16) * cell, cell, cell)


## The first 256 cells at 16 px (what the voxel mesher samples when voxel_colour is "sample").
func image_16() -> Image:
	if _small == null and image:
		_small = image.get_region(Rect2i(0, 0, 16 * cell, 16 * cell))
		if cell != TileSource.TILE_PX:
			_small.resize(16 * TileSource.TILE_PX, 16 * TileSource.TILE_PX, Image.INTERPOLATE_BILINEAR)
	return _small


func mapped_count() -> int:
	var n := 0
	for v in mapped:
		n += v
	return n


## Short hash of the composed atlas (checks compare packs and detect a change).
func digest() -> String:
	if image == null:
		return "none"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(image.get_data())
	return ctx.finish().hex_encode().substr(0, 12)


func info() -> Dictionary:
	return {"id": id, "name": name, "platform": platform, "credit": credit, "licence": licence, "url": url,
		"builtin": builtin, "dir": dir, "cell": cell, "mapped": mapped_count(), "animated": anims.size(),
		"voxel_colour": voxel_colour}
