## VoxelRenderer3D: the "diorama" view. Tiles from the TileSource atlas (the player's own art) are voxelized at runtime (16x16 px ->
## voxel columns) with per-category height profiles from the game's voxel table (docs/VOXEL_TABLE.md), meshed per 32x32 chunk on worker threads
## (greedy tops, run-merged sides, baked AO) and cached; only the focus chunk and its 8 neighbours are built.
## Overworld chunks wrap toroidally ((c + 256) % 256); towns are a floating diorama with sides down to a base.
## Players and NPCs are camera-facing billboards (2-frame animation where the tile list has pairs).
## Reads only MapViewState + TileSource, like every MapRenderer; it never touches networking or game state.
##
## Keys while active: F4 grid, F5 tilt-shift, F6 curvature, F7 AO, F8 line of sight, F9 true EGA black,
## F10 variation, F11 shore foam, F12 haze + town base, [ and ] camera pitch (35-50 deg).
## Options can also be preset with configure() / --voxel k=v,... (see OPTION_DEFAULTS):
##   vary   deterministic height/colour variation (amounts in the voxel table)
##   bevel  stronger neighbour-aware edge bevels (bevel_strong in the voxel table)
##   foam   shore foam where water meets land
##   tags   name tags stack instead of overlapping and fade with distance
##   fog    distance haze toward the background colour (soft curved horizon)
##   base   towns stand on a plinth on a tabletop instead of floating in the void
##   clamp  in towns the camera stops at the map edge (the overworld wraps, so never clamped there)
##   curve_k curvature strength, dof tilt-shift blur radius (px)
class_name VoxelRenderer3D
extends MapRenderer

const TABLE := "res://render/voxel/tile_profiles.json"
const CHUNK := 32
const CACHE_MAX := 18 # 9 visible + 9 recently left (a res-16 chunk is ~0.5M vertices)
const LOS_RADIUS := 22 # covers the visible ground at every pitch (35-50 deg); ~4 ms per focus-tile change
const CURVE_K := 0.0035
const FOG_COLOR := Color("#62738a")
const BG_PLAIN := Color("#141a26")
const PLINTH := Color("#3d3128")
const TABLE_TOP := Color("#2c2a2b")
const TAG_FADE := Vector2(10.0, 17.0) # name tags fade out between these distances (tiles) from the camera focus
# res 8 (2x2 tile pixels per voxel) is the default: res 16 meshes are ~2.5x bigger and their one-frame upload
# (~15-28 ms on an RTX 4090) breaks the 60 fps budget on a chunk crossing; res 16 (one voxel per pixel) stays available via --voxel res=16.
const OPTION_DEFAULTS := {"grid": false, "tilt": true, "curve": true, "ao": true, "los": true, "black": false,
	"pitch": 42.0, "res": 8, "distance": 26.0, "vary": true, "bevel": true, "foam": true, "tags": true, "fog": true,
	"base": true, "clamp": true, "curve_k": CURVE_K, "dof": 14.0}

var opts := OPTION_DEFAULTS.duplicate()
var prof := VoxelProfiles.new()
var _ok := false
var _root := Node3D.new()
var _chunks_node := Node3D.new()
var _sprites_node := Node3D.new()
var _cam := Camera3D.new()
var _mat := ShaderMaterial.new()
var _post := CanvasLayer.new()
var _post_rect := ColorRect.new()
var _sprite_tex: ImageTexture
var _los_img: Image
var _los_tex: ImageTexture
var _los_key := ""
var _active := true
var _map := -1
var _focus := Vector2.ZERO
var _cam_target := Vector3.ZERO
var _cache := {}        # chunk key -> {mesh: ArrayMesh, mat: ShaderMaterial} (insertion order = LRU)
var _pal_tex: ImageTexture
var _pending := {}      # chunk key -> {"task": id, "b": VoxelChunkBuilder}
var _instances := {}    # placement key -> MeshInstance3D
var _wanted: Array = []
var _sprites: Array[Sprite3D] = []
var _labels: Array[Label3D] = []
var _env := Environment.new()
var _base_node := Node3D.new()
var _base_mat := ShaderMaterial.new()
var _plinth_mat: ShaderMaterial
var _base_map := -1
var _cam_snap := false
var build_log: Array = [] # {key, ms_assemble, ms_mesh, ms_upload, verts}


func _ready() -> void:
	add_child(_root)
	_root.add_child(_chunks_node)
	_root.add_child(_sprites_node)
	_root.add_child(_cam)
	_cam.fov = 30.0
	_cam.far = 400.0
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_PLAIN
	var we := WorldEnvironment.new()
	we.environment = _env
	_root.add_child(we)
	_root.add_child(_base_node)
	_mat.shader = load("res://render/voxel/voxel.gdshader")
	_mat.set_shader_parameter("fog_color", FOG_COLOR)
	_base_mat.shader = load("res://render/voxel/voxel_base.gdshader")
	_base_mat.set_shader_parameter("fog_color", FOG_COLOR)
	_base_mat.set_shader_parameter("albedo", TABLE_TOP)
	_plinth_mat = _base_mat.duplicate() as ShaderMaterial
	_plinth_mat.set_shader_parameter("albedo", PLINTH)
	_post.layer = 5
	add_child(_post)
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://render/voxel/tilt_shift.gdshader")
	_post_rect.material = pm
	_post.add_child(_post_rect)
	_los_img = Image.create_empty(LOS_RADIUS * 2 + 1, LOS_RADIUS * 2 + 1, false, Image.FORMAT_L8)
	_los_img.fill(Color.WHITE)
	_los_tex = ImageTexture.create_from_image(_los_img)
	_mat.set_shader_parameter("los_tex", _los_tex)
	_mat.set_shader_parameter("pal_tex", _pal_tex)
	_apply_opts()
	set_active(_active)


func attach(source: TileSource) -> void:
	super.attach(source)
	var vt: Dictionary = source.voxel_table() if source else {}
	_ok = prof.load_dict(vt) if not vt.is_empty() else prof.load_table(TABLE)
	var img := source.atlas_image() if source else null
	if _ok:
		prof.set_pixels(img, Palette.EGA)
		_pal_tex = ImageTexture.create_from_image(_palette_image())
	if img:
		var s := img.duplicate() as Image
		for y in s.get_height():
			for x in s.get_width():
				if s.get_pixel(x, y).to_rgba32() == 0x000000ff:
					s.set_pixel(x, y, Color(0, 0, 0, 0))
		_sprite_tex = ImageTexture.create_from_image(s)


## Category x EGA colour table for the shader: rgb = colour (black pixels recoloured per category), a = pixel
## flags (2 water, 4 glow, 8 colour variation); column 16 = the category's cliff-side colour, alpha = its
## colour-variation amplitude.
func _palette_image() -> Image:
	var nc := 1
	for c in prof.cat_of_tile:
		nc = maxi(nc, c + 1)
	var tb := prof.true_black
	prof.true_black = false
	var im := Image.create_empty(17, nc, false, Image.FORMAT_RGBA8)
	for c in nc:
		for e in 16:
			var col := prof.top_color(c, e, Palette.EGA)
			col.a = prof.pix_flags[c * 16 + e] / 255.0
			im.set_pixel(e, c, col)
		var sc := prof.side_col[c]
		sc.a = clampf(prof.vary_c[c], 0.0, 1.0)
		im.set_pixel(16, c, sc)
	prof.true_black = tb
	return im


## Shader parameters shared by every chunk material (and the town base, for curvature and haze).
func _param(name: String, v) -> void:
	_mat.set_shader_parameter(name, v)
	for k in _cache:
		_cache[k]["mat"].set_shader_parameter(name, v)
	if name in ["curve_center", "curve_k", "fog_on"]:
		_base_mat.set_shader_parameter(name, v)
		_plinth_mat.set_shader_parameter(name, v)


func set_active(on: bool) -> void:
	_active = on
	if not is_inside_tree():
		return
	_root.visible = on
	_cam.current = on
	_post.visible = on and bool(opts["tilt"])
	set_process_unhandled_input(on)


func configure(o: Dictionary) -> void:
	for k in o:
		if opts.has(k):
			var v = o[k]
			match typeof(OPTION_DEFAULTS[k]):
				TYPE_BOOL: opts[k] = str(v) in ["1", "true", "on", "yes"] if v is String else bool(v)
				TYPE_FLOAT: opts[k] = float(v)
				TYPE_INT: opts[k] = int(v)
	opts["pitch"] = clampf(opts["pitch"], 35.0, 50.0)
	opts["curve_k"] = clampf(opts["curve_k"], 0.0, 0.02)
	opts["dof"] = clampf(opts["dof"], 0.0, 40.0)
	if not (int(opts["res"]) in [4, 8, 16]):
		opts["res"] = 8
	if is_inside_tree():
		_apply_opts()


func describe() -> String:
	return ("3D voxel  F4 grid:%s F5 tilt:%s F6 curve:%s F7 ao:%s F8 los:%s F9 black:%s F10 vary:%s F11 foam:%s "
		+ "F12 haze:%s  [ ] pitch %d  res %d") % [
		_on(opts["grid"]), _on(opts["tilt"]), _on(opts["curve"]), _on(opts["ao"]), _on(opts["los"]), _on(opts["black"]),
		_on(opts["vary"]), _on(opts["foam"]), _on(opts["fog"]), int(opts["pitch"]), int(opts["res"])]


func _on(v) -> String:
	return "on" if v else "off"


func _apply_opts() -> void:
	_param("grid_on", opts["grid"])
	_param("curve_k", float(opts["curve_k"]) if opts["curve"] else 0.0)
	_param("ao_strength", 1.0 if opts["ao"] else 0.0)
	_param("los_on", opts["los"])
	_param("true_black", opts["black"])
	_param("vary_on", opts["vary"])
	_param("foam_on", opts["foam"])
	_param("fog_on", opts["fog"])
	_env.background_color = FOG_COLOR if opts["fog"] else BG_PLAIN
	_base_node.visible = bool(opts["base"])
	(_post_rect.material as ShaderMaterial).set_shader_parameter("strength", float(opts["dof"]))
	_post.visible = _active and bool(opts["tilt"]) and float(opts["dof"]) > 0.0


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var flip := {KEY_F4: "grid", KEY_F5: "tilt", KEY_F6: "curve", KEY_F7: "ao", KEY_F8: "los", KEY_F9: "black",
		KEY_F10: "vary", KEY_F11: "foam", KEY_F12: "fog"}
	if flip.has(ev.keycode):
		opts[flip[ev.keycode]] = not opts[flip[ev.keycode]]
	elif ev.keycode == KEY_BRACKETLEFT:
		opts["pitch"] = clampf(opts["pitch"] - 3.0, 35.0, 50.0)
	elif ev.keycode == KEY_BRACKETRIGHT:
		opts["pitch"] = clampf(opts["pitch"] + 3.0, 35.0, 50.0)
	else:
		return
	_apply_opts()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k]["task"])
	_pending.clear()


## ---------------------------------------------------------------- per frame
func render(state: MapViewState) -> void:
	if not _active or not _ok or tiles == null:
		return
	if state.map_id != _map:
		_map = state.map_id
		for k in _instances:
			_instances[k].queue_free()
		_instances.clear()
		_los_key = ""
		_cam_target = Vector3(state.focus.x, 0.0, state.focus.y)
		_cam_snap = true
	_focus = state.focus
	var size := tiles.map_size(_map)
	if size == Vector2i.ZERO:
		return
	var wrap := _map == 0
	_update_chunks(size, wrap)
	_update_base(size, wrap)
	_update_camera()
	_update_los(state, wrap)
	_update_sprites(state, size, wrap)


## Build-affecting options (res, variation, bevels) are part of the key, so toggling them rebuilds.
func _chunk_key(wx: int, wz: int) -> String:
	return "%d:%d:%d:%d:%d%d" % [_map, wx, wz, int(opts["res"]), int(opts["vary"]), int(opts["bevel"])]


func _update_chunks(size: Vector2i, wrap: bool) -> void:
	var per := Vector2i(ceili(size.x / float(CHUNK)), ceili(size.y / float(CHUNK)))
	var fc := Vector2i(floori(_focus.x / CHUNK), floori(_focus.y / CHUNK))
	_collect_builds()
	_wanted.clear()
	var place := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var u := fc + Vector2i(dx, dz) # unwrapped chunk coords (placement)
			var w := u
			if wrap:
				w = Vector2i(posmod(u.x, per.x), posmod(u.y, per.y))
			elif u.x < 0 or u.y < 0 or u.x >= per.x or u.y >= per.y:
				continue
			var key := _chunk_key(w.x, w.y)
			_wanted.append(key)
			var pk := "%s@%d,%d" % [key, u.x, u.y]
			place[pk] = true
			if _cache.has(key):
				var hit = _cache[key] # refresh LRU order
				_cache.erase(key)
				_cache[key] = hit
				if not _instances.has(pk):
					var mi := MeshInstance3D.new()
					mi.mesh = _cache[key]["mesh"]
					mi.material_override = _cache[key]["mat"]
					mi.position = Vector3(u.x * CHUNK, 0, u.y * CHUNK)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_chunks_node.add_child(mi)
					_instances[pk] = mi
			elif not _pending.has(key):
				var b := VoxelChunkBuilder.new()
				b.map_id = _map; b.cx = w.x; b.cz = w.y; b.res = int(opts["res"]); b.wrap = wrap
				b.vary = bool(opts["vary"]); b.strong = bool(opts["bevel"])
				b.map_w = size.x; b.map_h = size.y; b.tiles = tiles; b.prof = prof; b.ega = Palette.EGA
				_pending[key] = {"task": WorkerThreadPool.add_task(b.build, false, "voxel chunk"), "b": b}
	for pk in _instances.keys():
		if not place.has(pk):
			_instances[pk].queue_free()
			_instances.erase(pk)


## Turn finished worker builds into meshes: at most one upload per frame so a chunk-border crossing does
## not stack several uploads into one long frame.
func _collect_builds() -> void:
	for key in _pending.keys():
		var p: Dictionary = _pending[key]
		if not WorkerThreadPool.is_task_completed(p["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(p["task"])
		_pending.erase(key)
		var b: VoxelChunkBuilder = p["b"]
		var t0 := Time.get_ticks_usec()
		var mesh := ArrayMesh.new()
		if b.verts.size() > 0:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = b.verts
			arr[Mesh.ARRAY_COLOR] = b.cols
			arr[Mesh.ARRAY_TEX_UV] = b.uvs
			arr[Mesh.ARRAY_TEX_UV2] = b.uv2s
			arr[Mesh.ARRAY_INDEX] = b.idx
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := _mat.duplicate() as ShaderMaterial
		if b.data_n > 0:
			mat.set_shader_parameter("data_tex", ImageTexture.create_from_image(
				Image.create_from_data(b.data_n, b.data_n, false, Image.FORMAT_RGBA8, b.data)))
			mat.set_shader_parameter("data_n", b.data_n)
		mat.set_shader_parameter("wrap_span", float(b.map_w) if b.wrap else 4096.0)
		var up := (Time.get_ticks_usec() - t0) / 1000.0
		build_log.append({"key": key, "ms_assemble": b.ms_assemble, "ms_mesh": b.ms_mesh, "ms_upload": up,
			"verts": b.verts.size(), "tris": b.idx.size() / 3, "quads": b.quads})
		_cache[key] = {"mesh": mesh, "mat": mat}
		while _cache.size() > CACHE_MAX:
			var oldest = _cache.keys()[0]
			if oldest in _wanted:
				break
			_cache.erase(oldest)
		return


## True when every chunk around the focus is built and placed (used by screenshots and benches).
func is_ready() -> bool:
	if not _active or _map < 0:
		return true
	for k in _wanted:
		if not _cache.has(k):
			return false
	return _pending.is_empty() and _instances.size() == _wanted.size()


func visible_stats() -> Dictionary:
	var v := 0
	var t := 0
	for pk in _instances:
		var m: ArrayMesh = _instances[pk].mesh
		if m.get_surface_count() > 0:
			v += m.surface_get_array_len(0)
			t += m.surface_get_array_index_len(0) / 3
	return {"chunks": _instances.size(), "verts": v, "tris": t}


func _ground_y(tile: int) -> float:
	if tile < 0:
		return 0.0
	var c := prof.cat_of_tile[tile]
	var b := prof.base[c]
	if prof.water[c]:
		return b / 16.0
	return (b if b <= 4 else -1) / 16.0 # walls/doors/signs: stand at floor level


## Towns stand on a plinth (just below the skirt the chunk sides run down to) on a wide tabletop, so the space
## past the map edge reads as a miniature instead of a void. Built once per town; the overworld has none.
func _update_base(size: Vector2i, wrap: bool) -> void:
	if _base_map == _map:
		return
	_base_map = _map
	for c in _base_node.get_children():
		c.queue_free()
	if wrap:
		return
	var skirt := VoxelChunkBuilder.SKIRT / 16.0
	var centre := Vector3(size.x / 2.0, 0.0, size.y / 2.0)
	var plinth := BoxMesh.new()
	plinth.size = Vector3(size.x + 1.2, 0.45, size.y + 1.2)
	plinth.subdivide_width = size.x
	plinth.subdivide_depth = size.y
	var pm := MeshInstance3D.new()
	pm.mesh = plinth
	pm.material_override = _plinth_mat
	pm.position = centre + Vector3(0, skirt - 0.225 + 0.02, 0)
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_base_node.add_child(pm)
	var table := PlaneMesh.new()
	table.size = Vector2(240, 240)
	table.subdivide_width = 96
	table.subdivide_depth = 96
	var tm := MeshInstance3D.new()
	tm.mesh = table
	tm.material_override = _base_mat
	tm.position = centre + Vector3(0, skirt - 0.45, 0)
	tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_base_node.add_child(tm)


func _update_camera() -> void:
	var size := tiles.map_size(_map)
	var t := tiles.tile_at(_map, posmod(int(floor(_focus.x)), maxi(1, size.x)), posmod(int(floor(_focus.y)), maxi(1, size.y)))
	var goal := Vector3(_focus.x, _ground_y(t), _focus.y)
	if _map != 0 and opts["clamp"]:
		goal = _clamp_to_map(goal, size)
	if _cam_snap or _cam_target.distance_to(goal) > 6.0:
		_cam_target = goal
		_cam_snap = false
	_cam_target = _cam_target.lerp(goal, 0.2)
	_place_camera()
	_param("curve_center", _cam_target)
	if opts["tilt"]: # keep the tilt-shift's sharp band on the player even when the clamped camera is off-centre
		var vp := get_viewport().get_visible_rect().size
		var pp := Vector3(_focus.x, goal.y, _focus.y)
		if vp.y > 0 and not _cam.is_position_behind(pp):
			var fy := clampf(_cam.unproject_position(pp).y / vp.y, 0.3, 0.75)
			(_post_rect.material as ShaderMaterial).set_shader_parameter("focus_y", fy)


func _place_camera() -> void:
	var p := deg_to_rad(float(opts["pitch"]))
	var dist := float(opts["distance"])
	_cam.position = _cam_target + Vector3(0, sin(p) * dist, cos(p) * dist)
	_cam.look_at(_cam_target, Vector3.UP)


## Keep a town's ground footprint (viewport corners cast onto the ground plane) inside the map, so the camera
## never drifts past the edge; a map smaller than the view stays centred. The overworld wraps and is never clamped.
func _clamp_to_map(goal: Vector3, size: Vector2i) -> Vector3:
	var saved := _cam_target
	_cam_target = goal
	_place_camera()
	var vp := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		var o := _cam.project_ray_origin(c)
		var d := _cam.project_ray_normal(c)
		if d.y >= -0.01:
			continue
		var hit := o + d * ((goal.y - o.y) / d.y) - goal
		lo = Vector2(minf(lo.x, hit.x), minf(lo.y, hit.z))
		hi = Vector2(maxf(hi.x, hit.x), maxf(hi.y, hit.z))
	_cam_target = saved
	if lo.x == INF:
		return goal
	const MARGIN := 0.6 # let the plinth edge show
	var g := goal
	for ax in [0, 1]:
		var span := float(size.x if ax == 0 else size.y)
		var v: float = g.x if ax == 0 else g.z
		var a := -MARGIN - lo[ax]
		var b := span + MARGIN - hi[ax]
		v = (a + b) / 2.0 if a > b else clampf(v, a, b)
		if ax == 0: g.x = v
		else: g.z = v
	return g


func _update_los(state: MapViewState, wrap: bool) -> void:
	var r := LOS_RADIUS
	var origin := Vector2i(int(floor(_focus.x)), int(floor(_focus.y)))
	var mask: PackedByteArray
	var vis = state.visibility
	if vis is Dictionary and vis.has("mask"): # server LOS: {origin: Vector2i (top-left), size: int, mask: PackedByteArray}
		_los_key = "srv"
		var s := int(vis["size"])
		if _los_img.get_width() != s:
			_los_img = Image.create_empty(s, s, false, Image.FORMAT_L8)
		_los_img.set_data(s, s, false, Image.FORMAT_L8, vis["mask"])
		_los_tex.set_image(_los_img)
		_param("los_origin", Vector2(vis["origin"]))
		_param("los_size", float(s))
		return
	var key := "%d:%d:%d" % [_map, origin.x, origin.y]
	if key == _los_key:
		return
	_los_key = key
	mask = VoxelLos.compute(tiles, prof, _map, origin, r, wrap)
	var side := r * 2 + 1
	if _los_img.get_width() != side:
		_los_img = Image.create_empty(side, side, false, Image.FORMAT_L8)
	_los_img.set_data(side, side, false, Image.FORMAT_L8, mask)
	_los_tex.set_image(_los_img)
	_param("los_origin", Vector2(origin.x - r, origin.y - r))
	_param("los_size", float(side))


func los_visible(p: Vector2) -> bool:
	if not opts["los"]:
		return true
	var o: Vector2 = _mat.get_shader_parameter("los_origin")
	var s := _los_img.get_width()
	var q := Vector2i(int(floor(p.x - o.x)), int(floor(p.y - o.y)))
	if q.x < 0 or q.y < 0 or q.x >= s or q.y >= s:
		return false
	return _los_img.get_pixel(q.x, q.y).r > 0.5


func _frame_tile(t: int) -> int:
	var phase := int(Time.get_ticks_msec() / 500) & 1
	for pr in prof.sprite_pairs:
		if t >= int(pr[0]) and t <= int(pr[1]):
			return (t & ~1) + phase
	return t


func _sprite(i: int) -> Sprite3D:
	while _sprites.size() <= i:
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.pixel_size = 1.0 / 16.0
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.shaded = false
		s.region_enabled = true
		s.texture = _sprite_tex
		s.offset = Vector2(0, 8)
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.0045
		l.font_size = 40
		l.outline_size = 10
		l.no_depth_test = true
		l.position = Vector3(0, 1.35, 0)
		s.add_child(l)
		_sprites_node.add_child(s)
		_sprites.append(s)
		_labels.append(l)
	return _sprites[i]


func _update_sprites(state: MapViewState, size: Vector2i, wrap: bool) -> void:
	var k := float(opts["curve_k"]) if opts["curve"] else 0.0
	var n := 0
	var items: Array = []
	# [pos, tile, label, is_me, moving, label colour, scale]
	for it in state.items:
		items.append([it["pos"], int(it["tile"]), "", false, false, Color.WHITE, 0.6])
	for npc in state.npcs:
		if int(npc["tile"]) != 0:
			items.append([npc["pos"], int(npc["tile"]), "", false, false, Color.WHITE, 1.0])
	for m in state.monsters:
		var tgt: bool = m["id"] == state.target_id
		items.append([m["pos"], int(m["tile"]), "%s %d/%d" % [m["name"], m["hp"], m["max_hp"]], false, false,
			Color(1.0, 0.35, 0.3) if tgt else Color(1.0, 0.75, 0.6), 1.0])
	for e in state.entities:
		var hp := " %d/%d" % [e["hp"], e["max_hp"]] if int(e.get("max_hp", 0)) > 0 else ""
		items.append([e["pos"], prof.avatar_tile, String(e["name"]) + hp, bool(e["is_me"]), bool(e["moving"]),
			Color.GOLD if e["is_me"] else Color(0.75, 0.9, 1.0), 1.0])
	for it in items:
		var pos: Vector2 = it[0]
		if wrap: # nearest copy around the focus
			pos.x = _focus.x + wrapf(pos.x - _focus.x, -size.x / 2.0, size.x / 2.0)
			pos.y = _focus.y + wrapf(pos.y - _focus.y, -size.y / 2.0, size.y / 2.0)
		var s := _sprite(n)
		var l := _labels[n]
		n += 1
		var vis: bool = it[3] or los_visible(pos)
		s.visible = vis
		if not vis:
			continue
		var tt := tiles.tile_at(_map, posmod(int(floor(pos.x)), size.x), posmod(int(floor(pos.y)), size.y))
		var d := Vector2(pos.x - _cam_target.x, pos.y - _cam_target.z)
		var bob := 0.06 * absf(sin(Time.get_ticks_msec() / 90.0)) if it[4] else 0.0
		s.position = Vector3(pos.x, _ground_y(tt) - d.length_squared() * k + bob, pos.y)
		s.scale = Vector3.ONE * float(it[6])
		var tile := _frame_tile(int(it[1]))
		s.region_rect = Rect2((tile % 16) * 16, (tile / 16) * 16, 16, 16)
		s.texture = _sprite_tex
		l.text = it[2]
		l.visible = it[2] != ""
		l.modulate = it[5]
		l.outline_modulate = Color.BLACK
		l.position = Vector3(0, 1.35, 0)
		l.set_meta("me", it[3])
		l.set_meta("dist", d.length())
	for i in range(n, _sprites.size()):
		_sprites[i].visible = false
	if opts["tags"]:
		_layout_tags(n)


## Name tags: fade with distance from the camera focus (your own tag never fades), then, nearest first, lift a tag
## above any tag it would overlap on screen (up to 4 rows), so a crowd on one tile stays readable.
func _layout_tags(n: int) -> void:
	var font: Font = ThemeDB.fallback_font
	var order: Array = []
	for i in range(n):
		var l := _labels[i]
		if not (_sprites[i].visible and l.visible):
			continue
		var me: bool = l.get_meta("me", false)
		var dist: float = l.get_meta("dist", 0.0)
		var a := 1.0 if me else 1.0 - smoothstep(TAG_FADE.x, TAG_FADE.y, dist)
		if a < 0.03:
			l.visible = false
			continue
		l.modulate.a = a
		l.outline_modulate.a = a
		order.append([0.0 if me else dist + 0.001, i])
	order.sort()
	var placed: Array[Rect2] = []
	for e in order:
		var i: int = e[1]
		var l := _labels[i]
		var p: Vector3 = _sprites[i].position + l.position
		if _cam.is_position_behind(p):
			continue
		var sp := _cam.unproject_position(p)
		var up := (_cam.unproject_position(p + Vector3.UP) - sp).length() # px per world unit, vertical
		var ppu := (_cam.unproject_position(p + _cam.global_transform.basis.x) - sp).length()
		var w := (font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x + l.outline_size) * l.pixel_size * ppu
		var h := (l.font_size + l.outline_size) * l.pixel_size * up
		var r := Rect2(sp - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
		var rows := 0
		while rows < 4 and placed.any(func(o: Rect2): return o.intersects(r)):
			r.position.y -= h + 2.0
			rows += 1
		if up > 0.0:
			l.position.y = 1.35 + (sp.y - (r.position.y + h / 2.0)) / up
		placed.append(r)
