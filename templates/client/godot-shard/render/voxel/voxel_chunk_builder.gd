## VoxelChunkBuilder: one 32x32-tile chunk -> mesh arrays + a per-voxel data image (runs on a WorkerThreadPool thread).
## 1. assemble: blit each tile's neighbour-aware template (VoxelProfiles) into a (32*res + 2)^2 RGBA8 field
##    (1-voxel border from the neighbouring chunks, toroidally wrapped on the overworld; void outside towns).
##    Optional deterministic height variation ("vary": per-category clumps hashed from world position).
## 2. data: per voxel column (EGA index, category, AO level + shore distance) -> `data` (RGBA8, n x n). The shader colours ground
##    faces from it through the palette texture, so faces need not be split by colour.
## 3. tops: greedy-merge coplanar faces (same height) into rectangles. Every voxel keeps its own colour and AO
##    (texel lookup), so this is a superset of "coplanar same-colour" merging with far fewer quads.
## 4. sides: 1D runs along each edge with the same (low, high, category); tree canopies (top + sides) are
##    vertex-coloured runs of the same canopy colour.
## Vertex layout: COLOR = face shade (textured faces) or colour (canopy); UV = (AO factor | side band y, flags);
## UV2 = data texel coords. Flags: 1 top, 8 textured from data, 16 textured side (water 2 / glow 4 come from the palette).
class_name VoxelChunkBuilder
extends RefCounted

const CHUNK := 32
const SKIRT := -8          # void (outside a town map): sides run down to here
const AO_LEVELS := [1.0, 0.8, 0.66, 0.54]
const SHADE_S := 0.80      # faces toward the camera (+z)
const SHADE_N := 0.58
const SHADE_E := 0.68
const SHADE_W := 0.88
const BAND := 2            # top colour band on cliff sides before the side colour
const F_TOP := 1
const F_TEX := 8
const F_SIDE := 16

var map_id := 0
var cx := 0
var cz := 0
var res := 16
var wrap := false
var map_w := 0
var map_h := 0
var vary := false   # per-position height variation (VoxelProfiles.vary_h)
var strong := false # stronger bevels (VoxelProfiles bevel_strong)
var tiles: TileSource
var prof: VoxelProfiles
var ega: Array
# results
var verts := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var idx := PackedInt32Array()
var data := PackedByteArray() # n*n RGBA8: ega, category, AO level (bits 0-1) | shore (bits 2-3), 255
var data_n := 0
var ms_assemble := 0.0
var ms_mesh := 0.0
var quads := {"top": 0, "canopy": 0, "side": 0} # per-pass quad counts (bench / tuning)

var _kind := "top"
var _g := 0      # field side incl. border
var _n := 0      # inner side
var _top := PackedInt32Array()
var _raw := PackedByteArray()
var _pal := {}   # (cat*16+ega) -> Color cache (canopy vertex colours)


func _tile(x: int, y: int) -> int:
	if wrap:
		return tiles.tile_at(map_id, posmod(x, map_w), posmod(y, map_h))
	return tiles.tile_at(map_id, x, y)


func build() -> void:
	var t0 := Time.get_ticks_usec()
	_assemble()
	var t1 := Time.get_ticks_usec()
	_kind = "top"; _tops()
	_kind = "canopy"; _canopy_tops()
	_kind = "side"; _sides()
	ms_assemble = (t1 - t0) / 1000.0
	ms_mesh = (Time.get_ticks_usec() - t1) / 1000.0
	_top = PackedInt32Array(); _raw = PackedByteArray()


func _assemble() -> void:
	_n = CHUNK * res
	_g = _n + 2
	var img := Image.create_empty(_g, _g, false, Image.FORMAT_RGBA8)
	img.fill(Color8(SKIRT + VoxelProfiles.H_BIAS, 0, 0, VoxelProfiles.VOID))
	var nb := PackedInt32Array(); nb.resize(8)
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var src_rect := Rect2i(0, 0, res, res)
	for tz in range(-1, CHUNK + 1):
		for tx in range(-1, CHUNK + 1):
			var t := _tile(ox + tx, oz + tz)
			if t < 0:
				continue
			for k in range(8):
				var o: Vector2i = VoxelProfiles.NB[k]
				nb[k] = _tile(ox + tx + o.x, oz + tz + o.y)
			img.blit_rect(prof.template(prof.context(t, nb), res, strong), src_rect, Vector2i(tx * res + 1, tz * res + 1))
	_raw = img.get_data()
	var count := _g * _g
	_top.resize(count)
	var clump := maxi(1, res / 4) # 4x4 source pixels, whatever the resolution
	var span := map_w * res
	for i in range(count):
		var h := int(_raw[i * 4]) - VoxelProfiles.H_BIAS
		var c := int(_raw[i * 4 + 3])
		if c != VoxelProfiles.VOID and prof.noise[c] > 0:
			var x := i % _g + ox * res
			var z := i / _g + oz * res
			h += posmod((x * 73856093) ^ (z * 19349663), prof.noise[c] + 1)
		if vary and c != VoxelProfiles.VOID and prof.vary_h[c] > 0:
			# world voxel coords (wrapped on the overworld so the seam matches), hashed per clump
			var wx := i % _g - 1 + ox * res
			var wz := i / _g - 1 + oz * res
			if wrap:
				wx = posmod(wx, span); wz = posmod(wz, map_h * res)
			var hx := (wx + 4096) / clump
			var hz := (wz + 4096) / clump
			h += posmod(((hx * 2654435761) ^ (hz * 40503)) >> 3, prof.vary_h[c] + 1)
		_top[i] = h


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, u: Vector4, flags: float,
		ta: Vector2, tb: Vector2, tc: Vector2, td: Vector2) -> void:
	quads[_kind] += 1
	var base := verts.size()
	verts.append(a); verts.append(b); verts.append(c); verts.append(d)
	cols.append(col); cols.append(col); cols.append(col); cols.append(col)
	uvs.append(Vector2(u.x, flags)); uvs.append(Vector2(u.y, flags))
	uvs.append(Vector2(u.z, flags)); uvs.append(Vector2(u.w, flags))
	uv2s.append(ta); uv2s.append(tb); uv2s.append(tc); uv2s.append(td)
	idx.append(base); idx.append(base + 1); idx.append(base + 2)
	idx.append(base); idx.append(base + 2); idx.append(base + 3)


## Greedy rectangles over a key grid (n*n, -1 = no face). Calls emit(x, z, w, h, key).
## Rectangles never cross a tile boundary: the vertex shader bends the world (curvature), and a long edge
## stays straight between its end vertices while its neighbours' vertices follow the curve, so long quads would
## open T-junction cracks. Within one tile the sag is far below a pixel.
func _greedy(keys: PackedInt32Array, emit: Callable) -> void:
	var n := _n
	var cap := res
	var done := PackedByteArray(); done.resize(n * n)
	for z in range(n):
		var row := z * n
		var zlim := mini(n, (z / cap + 1) * cap)
		var x := 0
		while x < n:
			var i := row + x
			var k := keys[i]
			if done[i] or k < 0:
				x += 1
				continue
			var xlim := mini(n, (x / cap + 1) * cap)
			var w := 1
			while x + w < xlim and keys[i + w] == k and not done[i + w]:
				w += 1
			var h := 1
			var grow := true
			while z + h < zlim and grow:
				var r2 := (z + h) * n + x
				for j in range(w):
					if keys[r2 + j] != k or done[r2 + j]:
						grow = false
						break
				if grow:
					h += 1
			for zz in range(z, z + h):
				var r3 := zz * n + x
				for j in range(w):
					done[r3 + j] = 1
			emit.call(x, z, w, h, k)
			x += w


func _tops() -> void:
	var n := _n
	var g := _g
	data_n = n
	data.resize(n * n * 4)
	var keys := PackedInt32Array(); keys.resize(n * n)
	for z in range(n):
		for x in range(n):
			var i := (z + 1) * g + x + 1
			var o := (z * n + x) * 4
			var c := int(_raw[i * 4 + 3])
			data[o + 3] = 255
			if c == VoxelProfiles.VOID:
				keys[z * n + x] = -1
				data[o + 1] = 0
				continue
			var h := _top[i]
			# AO: higher neighbours (edges count 2, corners 1), 0..3
			var a := 2 * (int(_top[i - 1] > h) + int(_top[i + 1] > h) + int(_top[i - g] > h) + int(_top[i + g] > h)) \
				+ int(_top[i - g - 1] > h) + int(_top[i - g + 1] > h) + int(_top[i + g - 1] > h) + int(_top[i + g + 1] > h)
			data[o] = _raw[i * 4 + 1]
			data[o + 1] = c
			data[o + 2] = mini(3, (a + 1) / 2) | (_shore(i, x, z, c) << 2)
			keys[z * n + x] = h + 64
	_greedy(keys, _emit_top)


## Water voxels next to land: 2 = touching (4-neighbour), 1 = two voxels out, 0 = open water / not water.
func _shore(i: int, x: int, z: int, c: int) -> int:
	if not prof.water[c]:
		return 0
	var g := _g
	if _land(i + 1) or _land(i - 1) or _land(i + g) or _land(i - g):
		return 2
	if x >= 1 and _land(i - 2): return 1
	if x < _n - 1 and _land(i + 2): return 1
	if z >= 1 and _land(i - 2 * g): return 1
	if z < _n - 1 and _land(i + 2 * g): return 1
	return 0


func _land(j: int) -> bool:
	var c := int(_raw[j * 4 + 3])
	return c != VoxelProfiles.VOID and not prof.water[c]


func _emit_top(x: int, z: int, w: int, hh: int, k: int) -> void:
	var s := 1.0 / res
	var y := float(k - 64) / 16.0
	var x0 := x * s; var x1 := (x + w) * s; var z0 := z * s; var z1 := (z + hh) * s
	_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Color.WHITE,
		Vector4(1, 1, 1, 1), float(F_TOP | F_TEX),
		Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + hh), Vector2(x, z + hh))


func _color(cat: int, e: int) -> Color:
	var k := cat * 16 + e
	var c = _pal.get(k)
	if c == null:
		c = prof.top_color(cat, e, ega)
		_pal[k] = c
	return c


func _canopy_tops() -> void:
	var n := _n
	var g := _g
	var keys := PackedInt32Array(); keys.resize(n * n)
	var any := false
	for z in range(n):
		for x in range(n):
			var i := (z + 1) * g + x + 1
			var b := int(_raw[i * 4 + 2])
			if b == 0:
				keys[z * n + x] = -1
				continue
			any = true
			var c := int(_raw[i * 4 + 3])
			var pe := c * 16 + b - 1
			keys[z * n + x] = ((prof.canopy_t[pe] + 64) << 20) | (c << 12) | ((b - 1) << 8)
	if any:
		_greedy(keys, _emit_canopy_top)


func _emit_canopy_top(x: int, z: int, w: int, hh: int, k: int) -> void:
	var s := 1.0 / res
	var y := float((k >> 20) - 64) / 16.0
	var x0 := x * s; var x1 := (x + w) * s; var z0 := z * s; var z1 := (z + hh) * s
	var col := _color((k >> 12) & 0xFF, (k >> 8) & 0xF)
	_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col,
		Vector4(1, 1, 1, 1), float(F_TOP), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## Exposed vertical span of column i toward neighbour j: [lo, hi] ground, plus canopy span when present.
func _sides() -> void:
	var n := _n
	var g := _g
	var s := 1.0 / res
	# dir: 0 +x, 1 -x, 2 +z, 3 -z. Runs advance along the other axis.
	for dir in range(4):
		var step_n: int = [1, -1, g, -g][dir]
		var along_x := dir >= 2
		for a in range(n):
			var run_key := -1
			var run_start := 0
			var run_lo := 0; var run_hi := 0; var run_cat := 0; var run_e := 0
			var crun_key := -1
			var crun_start := 0
			var crun_lo := 0; var crun_hi := 0; var crun_cat := 0; var crun_e := 0
			for b in range(n + 1):
				var key := -1
				var ckey := -1
				var lo := 0; var hi := 0; var cat := 0; var e := 0
				var clo := 0; var chi := 0; var ccat := 0; var ce := 0
				if b < n:
					var x := b if along_x else a
					var z := a if along_x else b
					var i := (z + 1) * g + x + 1
					var j := i + step_n
					cat = int(_raw[i * 4 + 3])
					if cat != VoxelProfiles.VOID:
						hi = _top[i]
						lo = _top[j]
						if hi > lo:
							key = ((hi + 64) << 20) | ((lo + 64) << 12) | cat
						var cb := int(_raw[i * 4 + 2])
						if cb > 0 and int(_raw[j * 4 + 2]) == 0:
							var pe := cat * 16 + cb - 1
							chi = prof.canopy_t[pe]
							clo = maxi(prof.canopy_b[pe], _top[j])
							if chi > clo:
								ccat = cat; ce = cb - 1
								ckey = ((chi + 64) << 20) | ((clo + 64) << 12) | (cat << 4) | ce
				var cell_edge := b % res == 0
				if key != run_key or (cell_edge and run_key >= 0):
					if run_key >= 0:
						_emit_side(dir, a, run_start, b, run_lo, run_hi, run_cat, run_e, false)
					run_key = key; run_start = b; run_lo = lo; run_hi = hi; run_cat = cat; run_e = e
				if ckey != crun_key or (cell_edge and crun_key >= 0):
					if crun_key >= 0:
						_emit_side(dir, a, crun_start, b, crun_lo, crun_hi, crun_cat, crun_e, true)
					crun_key = ckey; crun_start = b; crun_lo = clo; crun_hi = chi; crun_cat = ccat; crun_e = ce


func _emit_side(dir: int, a: int, b0: int, b1: int, lo: int, hi: int, cat: int, e: int, canopy: bool) -> void:
	var shade: float = [SHADE_E, SHADE_W, SHADE_S, SHADE_N][dir]
	if canopy:
		_side_quad(dir, a, b0, b1, lo, hi, _color(cat, e) * shade, Vector4(0.8, 0.8, 1, 1), 0.0)
		return
	# textured: colour from the data texel; below the band the shader switches to the category's side colour
	var band := lo if (hi - lo <= BAND or prof.water[cat]) else hi - BAND
	var bv := band / 16.0
	_side_quad(dir, a, b0, b1, lo, hi, Color(shade, shade, shade), Vector4(bv, bv, bv, bv), float(F_TEX | F_SIDE))


## Quad on the face of column (a, b0..b1) toward dir; u = per-vertex UV.x in order (bottom, bottom, top, top) of the run.
func _side_quad(dir: int, a: int, b0: int, b1: int, lo: int, hi: int, col: Color, u: Vector4, flags: float) -> void:
	var s := 1.0 / res
	var y0 := lo / 16.0
	var y1 := hi / 16.0
	var fa := a + 0.5
	match dir:
		0: # +x face at plane x = a + 1, along z
			var X := (a + 1) * s
			_quad(Vector3(X, y0, b0 * s), Vector3(X, y0, b1 * s), Vector3(X, y1, b1 * s), Vector3(X, y1, b0 * s),
				col, Vector4(u.x, u.y, u.z, u.w), flags, Vector2(fa, b0), Vector2(fa, b1), Vector2(fa, b1), Vector2(fa, b0))
		1: # -x face at plane x = a
			var X := a * s
			_quad(Vector3(X, y0, b0 * s), Vector3(X, y1, b0 * s), Vector3(X, y1, b1 * s), Vector3(X, y0, b1 * s),
				col, Vector4(u.x, u.z, u.w, u.y), flags, Vector2(fa, b0), Vector2(fa, b0), Vector2(fa, b1), Vector2(fa, b1))
		2: # +z face at plane z = a + 1, along x
			var Z := (a + 1) * s
			_quad(Vector3(b0 * s, y0, Z), Vector3(b0 * s, y1, Z), Vector3(b1 * s, y1, Z), Vector3(b1 * s, y0, Z),
				col, Vector4(u.x, u.z, u.w, u.y), flags, Vector2(b0, fa), Vector2(b0, fa), Vector2(b1, fa), Vector2(b1, fa))
		3: # -z face at plane z = a
			var Z := a * s
			_quad(Vector3(b0 * s, y0, Z), Vector3(b1 * s, y0, Z), Vector3(b1 * s, y1, Z), Vector3(b0 * s, y1, Z),
				col, Vector4(u.x, u.y, u.z, u.w), flags, Vector2(b0, fa), Vector2(b1, fa), Vector2(b1, fa), Vector2(b0, fa))
