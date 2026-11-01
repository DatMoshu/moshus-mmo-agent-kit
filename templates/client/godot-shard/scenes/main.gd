## Shard scene (core; identical in the kit's godot-shard template and in every game built on it).
## WASD/arrow keys move; F attack, G pick up, H potion, T talk, Enter chat, F1 help (ui/hud.gd HELP).
## A game can remap input without editing this file: `key_hook` sees each key press first, `move_hook`
## rewrites the walking direction, `wasd_enabled = false` frees W/A/S/D for letter commands (see below).
## Tiles, sprites and NPC dialogue come from the game's TileSource (Game.make_source in client/game/game.gd:
## a world document, or a game's own reader for the player's install); the server only sends
## positions, stats and ids.
## Headless checks:
##   kit smoke:  godot --headless --path . -- --autopilot --url URL --db DB --dir 1,0 --seconds 8
##   Portal route: --autopilot --route portal --url URL --db DB --seconds 30
##               (walk to the portal into map 1, enter, meet peers + NPCs, walk off the edge, return)
##               --expect-npcs N: NPC rows expected on map 1 (default 32)
##   --world FILE: a mmo-core-world/1 document (core/doc_source.gd); game-specific source flags are read by
##               Game.make_source (e.g. a path to the player's install).
##   Renderer:   --renderer 2d|3d (or $SHARD_RENDERER); Tab / F3 switch mid-session (same connection).
##               --voxel grid=0,tilt=1,curve=1,ao=1,los=1,black=0,pitch=42,res=8 presets the 3D toggles.
##               --toggle-every S (autopilot): switch renderer every S seconds to prove the session survives it.
##               --shots DIR (portal route, needs a display): save 2D + 3D frames on map 0 and map 1.
##   Playtest:   --autopilot --route play [--profile P] (chat, enter map 1, talk to an NPC, leave, fight,
##               loot, die and respawn; driven by a play_check harness) and --route resume (reconnect check).
##   Bench:      --bench [--bench-seconds S] (no server): scripted walk, prints frame times + chunk build times.
##   Tilesets:   F4 next / Shift+F3 previous tileset pack (docs/SHARD_CORE.md "Tilesets"); --tileset ID starts
##               with that pack (not saved); the last pack picked with F4 is saved as render/tileset in
##               user://settings.cfg. --tileset-dir DIR adds a folder of packs (besides user://tilesets).
##               --tileset-check [--shots DIR] (no server): cycle every pack on map 0 in the current renderer,
##               print one TILESET_CHECK line per pack and PASS / FAIL (exit code 0 / 1).
## HUD hook: Game.make_hud(main) -> Hud (optional; null = the core HUD) supplies the game's own Hud subclass at
## start; set_hud(h) swaps it later. Tileset API for a game UI: tileset_list(), tileset_id(), set_tileset(id),
## cycle_tileset(step), signal tileset_changed(id); tileset_list() entries carry an optional 4x4 `preview` texture.
##
## Layout: core client = net/ (NetSession: server state + AOI + intents), render/ (MapRenderer; TileRenderer2D,
## VoxelRenderer3D; TileSource = the adapter contract), ui/ (Hud), core/ (Conversation, DocSource,
## KeywordTalk). The game = game/game.gd (+ its own folder beside it). This script only glues them: server
## state -> MapViewState -> renderer, and input -> NetSession intents.
extends Node
var _args := {}
var _peer_first := {} # identity hex -> Vector2 first seen
var _peer_moved := {} # identity hex -> true once seen moving
var _started_ms := 0
var _auto_dir := Vector2i(1, 0)
## Input hooks for a game's own key scheme (set from Game.setup / the game's node; all optional).
## key_hook: Callable(ev: InputEventKey) -> bool, called for every key press before the core keys
##   (Tab/F1/Enter/Esc/F/G/H/T); return true to consume it.
## move_hook: Callable(dir: Vector2i) -> Vector2i, called every frame with the default direction (arrows,
##   plus WASD when wasd_enabled); return the direction to walk (Vector2i.ZERO stands still).
## Neither runs while a HUD text box has focus or in autopilot/bench modes.
var key_hook := Callable()
var move_hook := Callable()
var wasd_enabled := true
var _auto_sign := 1
var src: TileSource # the game adapter's client half, from Game.make_source (client/game/game.gd)
var renderer: MapRenderer
var renderer_kind := ""
var _renderers := {} # kind -> MapRenderer (kept alive while hidden so switching back is instant)
var _renderer_opts := {}
var hud: Hud # built in _ready: Game.make_hud(main), else the core Hud (never created when a game supplies one)
signal hud_changed(hud: Hud)
signal tileset_changed(id: String)
const SETTINGS := "user://settings.cfg"
var tilesets: Array[TilesetPack] = [] # every pack the player can switch to (Tilesets.discover)
var _tileset_id := ""                 # the active pack's id (tileset_id())
var _tileset_live := false            # true after start-up: changes then toast and may be saved
var _talk: Conversation
var _talk_npc := -1
var _target := -1 # last monster attacked (highlighted)
var _last_error := ""
var _toggles := 0
var _last_toggle_ms := 0
var _connects := 0
var _disconnects := 0
var _capturing := false
var _shots_taken := {}
# --route portal state
var _route := ""
var _phase := "to_portal"
var _phase_ms := 0
var _route_log := {"entered_town": false, "returned": false, "town_peers": {}, "npc_rows": 0, "npc_non_empty": 0,
	"surface_peers_moved": {}, "town_arrival_tile": -1, "surface_return_tile": -1}


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	_route = String(_args.get("route", ""))
	src = Game.make_source(_args)
	Net.map_changed.connect(_on_map_changed)
	for kv in String(_args.get("voxel", "")).split(",", false):
		var p: PackedStringArray = kv.split("=")
		_renderer_opts[p[0]] = p[1] if p.size() > 1 else "true"
	_init_tilesets()
	hud = _game_hud()
	if hud == null:
		hud = Hud.new()
	add_child(hud)
	hud.visible = _args.has("hud") or not (_args.has("autopilot") or _args.has("bench") or _args.has("shots") \
		or _args.has("tileset-check"))
	_connect_hud()
	Net.action_result.connect(_on_action_result)
	var kind := String(_args.get("renderer", OS.get_environment("SHARD_RENDERER")))
	use_renderer(kind if kind != "" else "2d")
	Game.extend(self)
	_tileset_live = true
	if _args.has("tileset-check"):
		_tileset_check()
		return
	if _args.has("bench"):
		_bench_start()
		return
	Net.session_connected.connect(_on_connected)
	Net.session_disconnected.connect(func(): _disconnects += 1)
	Net.connect_to_server(_args.get("url", "http://127.0.0.1:3000"), _args.get("db", "mmo-dev"), _args.get("profile", ""))


func _connect_hud() -> void:
	hud.chat_submitted.connect(func(t: String): Net.say(t))
	hud.talk_submitted.connect(_on_talk_line)
	hud.talk_closed.connect(func(): _talk = null; _talk_npc = -1)


## HUD hook: replace the core HUD with a game's own. `h` is a Hud subclass (so main's calls and signals keep
## working: override every method in Hud.FACADE, and skip super._ready() to drop the default widgets). Call it
## from Game.extend(main); the old HUD is freed, the new one takes its visibility and main's signal wiring.
## Emits hud_changed. A game that only adds panels next to the default HUD just adds its own CanvasLayer instead.
## Game.make_hud(main) -> Hud, when the game defines it (games without it keep the core HUD). Checked
## dynamically so a client/game/game.gd from before this hook still compiles.
func _game_hud() -> Hud:
	var gs: Script = Game
	for m in gs.get_script_method_list():
		if String(m["name"]) == "make_hud":
			var h = gs.call("make_hud", self)
			return h as Hud
	return null


func set_hud(h: Hud) -> void:
	if h == null or h == hud:
		return
	var vis := hud.visible
	if is_instance_valid(hud):
		if hud.get_parent() == self:
			remove_child(hud)
		hud.queue_free()
	hud = h
	if hud.get_parent() == null:
		add_child(hud)
	hud.visible = vis
	_connect_hud()
	_update_hud()
	hud_changed.emit(hud)


## ---------------------------------------------------------------- tilesets
func _init_tilesets() -> void:
	var dirs := PackedStringArray([Tilesets.USER_DIR])
	if _args.has("tileset-dir"):
		dirs.append(String(_args["tileset-dir"]))
	tilesets = Tilesets.discover(src, dirs)
	if tilesets.is_empty():
		return
	var want := String(_args.get("tileset", ""))
	if want == "" and not _args.has("tileset-check"):
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			want = String(cfg.get_value("render", "tileset", ""))
	if want == "" or not set_tileset(want, false):
		set_tileset(tilesets[0].id, false)


## Switch to pack `id` (renderers redraw with it at once; the session is untouched). persist = save it as the
## player's choice (render/tileset in user://settings.cfg; never in automated runs). false = unknown id.
func set_tileset(id: String, persist := true) -> bool:
	var p := Tilesets.find(tilesets, id)
	if p == null:
		push_warning("unknown tileset '%s' (have: %s)" % [id, ", ".join(tilesets.map(func(t): return t.id))])
		return false
	_tileset_id = p.id
	src.set_tileset(null if p == src.default_tileset() else p)
	for k in _renderers:
		_renderers[k].refresh_atlas()
	if _tileset_live:
		print("TILESET active=%s" % p.id)
		var who := " - " + p.credit if p.credit != "" else ""
		hud.toast("Tileset: %s%s" % [p.name, who])
		_update_hud()
		if persist and not (_args.has("autopilot") or _args.has("bench") or _args.has("tileset-check")):
			var cfg := ConfigFile.new()
			cfg.load(SETTINGS) # keep other settings; a missing file is fine
			cfg.set_value("render", "tileset", p.id)
			cfg.save(SETTINGS)
	tileset_changed.emit(p.id)
	return true


## Next (step 1) / previous (-1) pack, wrapping; returns the new id ("" when there are no packs).
func cycle_tileset(step := 1, persist := true) -> String:
	if tilesets.is_empty():
		return ""
	var i := 0
	for j in tilesets.size():
		if tilesets[j].id == _tileset_id:
			i = j
	set_tileset(tilesets[posmod(i + step, tilesets.size())].id, persist)
	return _tileset_id


## Id of the active pack ("" before the source has art).
func tileset_id() -> String:
	return _tileset_id


## Every available pack, one dictionary each: {id, name, platform, credit, licence, url, builtin, dir, cell,
## mapped, animated, voxel_colour, active, preview}. `preview` (optional, absent when the pack has no art) is a
## Texture2D of 4x4 tiles: the ids from src.preview_tiles() when the game's TileSource defines it, else 0..15.
func tileset_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiles := PackedInt32Array()
	if src and src.has_method("preview_tiles"):
		tiles = src.call("preview_tiles")
	for p in tilesets:
		var d := p.info()
		d["active"] = p.id == _tileset_id
		var tex := p.preview(tiles)
		if tex:
			d["preview"] = tex
		out.append(d)
	return out


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if i + 1 < args.size() and not args[i + 1].begins_with("--"):
			out[key] = args[i + 1]
			i += 2
		else:
			out[key] = "true"
			i += 1
	return out


## Switch the active renderer. Only the view changes: networking, AOI and game state are untouched.
func use_renderer(kind: String) -> void:
	if not (kind in ["2d", "3d"]):
		push_warning("unknown renderer '%s', using 2d" % kind)
		kind = "2d"
	if renderer and kind == renderer_kind:
		return
	if not _renderers.has(kind):
		var r := MapRenderer.create(kind)
		r.attach(src)
		r.configure(_renderer_opts)
		add_child(r)
		_renderers[kind] = r
	for k in _renderers:
		_renderers[k].set_active(k == kind)
	renderer = _renderers[kind]
	renderer_kind = kind
	_update_hud()


func toggle_renderer() -> void:
	_toggles += 1
	use_renderer("2d" if renderer_kind == "3d" else "3d")


func _update_hud() -> void:
	if renderer == null or not hud.visible:
		return
	var st := Net.stats() if Net.is_joined else null
	var inv := []
	if Net.is_joined:
		for row in Net.inventory():
			var k := Net.item_kind(row.kind)
			inv.append([k.name if k else "item %d" % row.kind, row.qty])
	var chat := []
	if Net.is_joined:
		for c in Net.chat_lines(8):
			chat.append([c.name, c.text, c.map_id == Net.current_map()])
	var mi = Net.client.db.map_info.map_id.find(Net.current_map()) if Net.is_joined else null
	hud.update({"name": Net.player_name(Net.my_identity) if Net.is_joined else "connecting...",
		"hp": st.hp if st else 0, "max_hp": st.max_hp if st else 0, "level": st.level if st else 1,
		"xp": st.xp if st else 0, "gold": st.gold if st else 0, "kills": st.kills if st else 0,
		"deaths": st.deaths if st else 0, "map": String(mi.key).capitalize() if mi else "",
		"renderer": "Tab/F3 " + renderer.describe(), "inventory": inv, "chat": chat,
		"tileset": _tileset_name()})


func _tileset_name() -> String:
	var p := Tilesets.find(tilesets, _tileset_id)
	return p.name if p else ""


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if key_hook.is_valid() and not hud.is_typing() and bool(key_hook.call(ev)):
		get_viewport().set_input_as_handled()
		return
	var handled := true
	match ev.keycode:
		KEY_F3 when ev.shift_pressed:
			cycle_tileset(-1) # Shift+F3: previous tileset
		KEY_TAB, KEY_F3:
			toggle_renderer()
		KEY_F4:
			if ev.shift_pressed:
				handled = false # Shift+F4 is the 3D renderer's grid toggle
			else:
				cycle_tileset(1)
		KEY_F1:
			hud.toggle_help()
		KEY_ENTER, KEY_KP_ENTER:
			Net.send_move(Vector2i.ZERO)
			hud.open_chat()
		KEY_ESCAPE:
			hud.close_inputs()
		KEY_F:
			attack_nearest()
		KEY_G:
			pick_up_near()
		KEY_H:
			drink_potion()
		KEY_T:
			talk_nearest()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## ---------------------------------------------------------------- gameplay actions (keys and autopilot)
func _my_tile() -> Vector2i:
	var me := Net.my_transform()
	return Vector2i(floori(me.x), floori(me.y)) if me else Vector2i(-999, -999)


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The adjacent (8-neighbour) monster with the least HP; false when none is in reach.
func attack_nearest() -> bool:
	var me := _my_tile()
	var best: MmoMonster = null
	for m in Net.visible_monsters():
		if _cheb(me, Vector2i(floori(m.x), floori(m.y))) <= 1 and (best == null or m.hp < best.hp):
			best = m
	if best == null:
		hud.toast("Nothing to attack here.")
		return false
	_target = best.id
	Net.attack(best.id)
	return true


func pick_up_near() -> int:
	var me := _my_tile()
	var n := 0
	for g in Net.visible_items():
		if _cheb(me, Vector2i(g.x, g.y)) <= 1:
			Net.pick_up(g.id)
			n += 1
	if n == 0:
		hud.toast("Nothing to pick up here.")
	return n


func drink_potion() -> bool:
	for row in Net.inventory():
		var k := Net.item_kind(row.kind)
		if k and k.heal > 0:
			Net.use_item(row.kind)
			return true
	hud.toast("No potions.")
	return false


func talk_nearest() -> bool:
	var me := _my_tile()
	var best: MmoNpc = null
	var best_d := 99
	for n in Net.visible_npcs():
		var d := _cheb(me, Vector2i(floori(n.x), floori(n.y)))
		if n.tile != 0 and d <= 1 and d < best_d:
			best = n
			best_d = d
	if best == null:
		hud.toast("Nobody to talk to here.")
		return false
	var meta := Net.npc_meta(best.id)
	_talk = src.start_talk(Net.current_map(), meta.talk if meta else 0)
	if _talk == null:
		hud.toast("They have nothing to say.")
		return false
	_talk_npc = best.id
	Net.send_move(Vector2i.ZERO)
	hud.show_talk(_talk.title, _talk.open(), not _args.has("autopilot"))
	return true


func _on_talk_line(text: String) -> void:
	if _talk == null:
		return
	var answer := _talk.reply(text)
	hud.show_talk(_talk.title, "> %s\n\n%s" % [text.to_upper(), answer], not _talk.done)
	if _talk.done:
		_talk = null
		get_tree().create_timer(1.5).timeout.connect(func(): if _talk == null: hud.end_talk())


func _on_action_result(action: String, err: String) -> void:
	if err != "":
		_last_error = "%s: %s" % [action, err]
		if not (action == "attack" and err == "too soon"):
			hud.toast(err.capitalize())


func _on_connected(identity_hex: String) -> void:
	_connects += 1
	_register_maps()
	# Names are unique and persist with the player row; default to a per-identity name.
	var display_name: String = _args.get("name", "p" + identity_hex.substr(0, 6))
	var err: String = await Net.join(display_name)
	if err != "":
		push_warning("join failed: %s" % err)
		if _args.has("autopilot"):
			print("AUTOPILOT FAIL join: %s" % err)
			get_tree().quit(1)
		return
	_started_ms = Time.get_ticks_msec()
	if _args.has("autopilot"):
		var d: PackedStringArray = String(_args.get("dir", "1,0")).split(",")
		_auto_dir = Vector2i(int(d[0]), int(d[1]))
		if _route != "resume": # the reconnect check must stand still where it logged in
			Net.send_move(_auto_dir)


## Tell the tile source about every map the server announced (it loads each from local data).
func _register_maps() -> void:
	var missing := []
	for mi in Net.map_infos():
		if not src.register_map(mi.map_id, mi.key, mi.width, mi.height):
			missing.append(mi.key)
	if not missing.is_empty():
		push_warning("no local data for maps: %s" % ", ".join(missing))


func _process(_delta: float) -> void:
	if _args.has("tileset-check"):
		return
	if _args.has("bench"):
		_bench_frame()
		return
	if not Net.is_joined:
		return
	if _talk_npc >= 0: # walking away ends the conversation
		var n = Net.client.db.npc.id.find(_talk_npc)
		if n == null or _cheb(_my_tile(), Vector2i(floori(n.x), floori(n.y))) > 2:
			hud.end_talk()
	_update_hud()
	_maybe_screenshot()
	_maybe_toggle()
	if _capturing:
		pass # screenshots: hold still, keep rendering
	elif Game.process(self):
		pass # the game drove this frame (its own route or panel)
	elif _args.has("autopilot") and _route == "portal":
		_route_portal()
	elif _args.has("autopilot") and _route in ["play", "resume"]:
		_route_play()
	elif _args.has("autopilot"):
		# Pace back and forth (flip every second) so autopilot clients stay near spawn and
		# inside each other's area of interest even when they start a few seconds apart.
		var flip := 1 if ((Time.get_ticks_msec() - _started_ms) / 1000) % 2 == 0 else -1
		if flip != _auto_sign:
			_auto_sign = flip
			Net.send_move(_auto_dir * flip)
		_autopilot_check()
	elif hud.is_typing():
		Net.send_move(Vector2i.ZERO)
	else:
		Net.send_move(move_dir())
	renderer.render(_view_state())


## The walking direction from the keyboard this frame: arrows (ui_*), WASD when wasd_enabled, then move_hook.
func move_dir() -> Vector2i:
	var dir := Vector2i(
		int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
		int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up")))
	if wasd_enabled:
		if Input.is_physical_key_pressed(KEY_D): dir.x = 1
		if Input.is_physical_key_pressed(KEY_A): dir.x = -1
		if Input.is_physical_key_pressed(KEY_S): dir.y = 1
		if Input.is_physical_key_pressed(KEY_W): dir.y = -1
	if move_hook.is_valid():
		var d = move_hook.call(dir)
		dir = d if d is Vector2i else Vector2i.ZERO
	return dir


func _autopilot_check() -> void:
	# Record any peer we see move at any point (peers may log off before we finish).
	for t in Net.visible_transforms():
		if Net.is_me(t.identity):
			continue
		var hex := t.identity.hex_encode()
		var pos := Vector2(t.x, t.y)
		if not _peer_first.has(hex):
			_peer_first[hex] = pos
		elif pos.distance_to(_peer_first[hex]) > 1.0:
			_peer_moved[hex] = true
	var seconds := float(_args.get("seconds", "4"))
	if Time.get_ticks_msec() - _started_ms < seconds * 1000.0:
		return
	var me := Net.my_transform()
	var ok := me != null and _peer_moved.size() >= int(_args.get("expect-peers", "1")) and _session_ok()
	print("AUTOPILOT %s me=%s moved_peers=%d visible=%d %s" % ["PASS" if ok else "FAIL", str(Vector2(me.x, me.y)) if me else "null", _peer_moved.size(), Net.visible_transforms().size(), _renderer_summary()])
	Net.send_move(Vector2i.ZERO)
	get_tree().quit(0 if ok else 1)


## --screenshot FILE.png [--screenshot-at SECONDS]: save one frame (needs a real display, not
## --headless). For local visual checks only: the image shows game art, so keep it out of the repo.
var _shot_done := false
func _maybe_screenshot() -> void:
	if _shot_done or not _args.has("screenshot"):
		return
	if Time.get_ticks_msec() - _started_ms < float(_args.get("screenshot-at", "3")) * 1000.0:
		return
	_shot_done = true
	var img := get_viewport().get_texture().get_image()
	var path := String(_args["screenshot"])
	print("SCREENSHOT %s err=%d" % [path, img.save_png(path)])


## --toggle-every S: flip the renderer on a timer (autopilot proof that the session survives switching).
func _maybe_toggle() -> void:
	if not _args.has("toggle-every") or _capturing:
		return
	var every := float(_args["toggle-every"]) * 1000.0
	if Time.get_ticks_msec() - maxi(_last_toggle_ms, _started_ms) >= every:
		_last_toggle_ms = Time.get_ticks_msec()
		toggle_renderer()


## One connection for the whole run, never dropped (renderer switches must not touch the session).
func _session_ok() -> bool:
	return _connects == 1 and _disconnects == 0 and Net.is_joined


func _renderer_summary() -> String:
	return "renderer=%s toggles=%d connects=%d disconnects=%d" % [renderer_kind, _toggles, _connects, _disconnects]


## --shots DIR: save the same moment in every renderer (2D, then 3D once its chunks are built). Local visual
## checks only: the images show the player's own game art, so they must stay out of the repo.
func _capture_pair(tag: String) -> void:
	_shots_taken[tag] = true
	_capturing = true
	Net.send_move(Vector2i.ZERO)
	var back := renderer_kind
	var dir := String(_args["shots"])
	DirAccess.make_dir_recursive_absolute(dir)
	for kind in ["2d", "3d"]:
		use_renderer(kind)
		var t0 := Time.get_ticks_msec()
		while true:
			renderer.render(_view_state())
			await get_tree().process_frame
			if renderer.is_ready() or Time.get_ticks_msec() - t0 > 30000:
				break
		for i in 20:
			renderer.render(_view_state())
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := dir.path_join("%s_%s.png" % [tag, kind])
		var err := img.save_png(path) if img else -1
		print("SHOT %s err=%d ready_ms=%d" % [path, err, Time.get_ticks_msec() - t0])
	use_renderer(back)
	_capturing = false


func _on_map_changed(map_id: int) -> void:
	if map_id >= 0 and not src.maps.has(map_id):
		_register_maps()
	if _talk_npc >= 0:
		hud.end_talk()
	if _route != "portal":
		return
	var me := Net.my_transform()
	if map_id != 0 and _phase == "to_portal":
		_route_log["entered_town"] = true
		_route_log["town_arrival_tile"] = src.tile_at(map_id, int(me.x), int(me.y)) if me else -1
		_set_phase("in_town")
	elif map_id == 0 and _route_log["entered_town"]:
		_route_log["returned"] = true
		_route_log["surface_return_tile"] = src.tile_at(0, int(me.x), int(me.y)) if me else -1
		_set_phase("back")


func _set_phase(p: String) -> void:
	if _route == "play" and p != _phase:
		var me := Net.my_transform()
		print("PLAY phase %s at %s" % [p, "%d:%d,%d" % [me.map_id, floori(me.x), floori(me.y)] if me else "?"])
	_phase = p
	_phase_ms = Time.get_ticks_msec()


## Portal route: walk to the portal into map 1 (the home town), wait there (meet peers, count NPC slots), walk off
## the west edge, then report. Everything observed comes from AOI subscriptions.
func _route_portal() -> void:
	var me := Net.my_transform()
	if me == null:
		return
	for t in Net.visible_transforms():
		if Net.is_me(t.identity):
			continue
		var hex := t.identity.hex_encode()
		if me.map_id == 0:
			var pos := Vector2(t.x, t.y)
			if not _peer_first.has(hex):
				_peer_first[hex] = pos
			elif pos.distance_to(_peer_first[hex]) > 1.0:
				_route_log["surface_peers_moved"][hex] = true
		else:
			_route_log["town_peers"][hex] = true
	var town_seconds := float(_args.get("town-seconds", "6"))
	# stills (--shots): the town 2 s after arrival, the overworld right after walking back out of the town's
	# west edge (so the capture pause never hides the peers' surface movement the route has to observe)
	if _args.has("shots") and me.map_id == 0 and _phase == "back" and not _shots_taken.has("surface"):
		await _capture_pair("surface")
		_set_phase("back")
		return
	if _args.has("shots") and _phase == "in_town" and not _shots_taken.has("town") \
			and Time.get_ticks_msec() - _phase_ms > 2000:
		_capture_pair("town")
		return
	match _phase:
		"to_portal":
			var p := Net.portal_into(1) # map 1 = the home town (stable id, see docs/SHARD_CORE.md)
			if p == null:
				return
			var d := Vector2(p.x + 0.5 - me.x, p.y + 0.5 - me.y)
			Net.send_move(Vector2i(int(sign(snappedf(d.x, 0.25))), int(sign(snappedf(d.y, 0.25)))))
		"in_town":
			Net.send_move(Vector2i.ZERO)
			var npcs := Net.visible_npcs()
			_route_log["npc_rows"] = npcs.size()
			_route_log["npc_non_empty"] = npcs.filter(func(n): return n.tile != 0).size()
			if Time.get_ticks_msec() - _phase_ms > town_seconds * 1000.0 and (_shots_taken.has("town") or not _args.has("shots")):
				_set_phase("leave")
		"leave":
			Net.send_move(Vector2i(-1, 0))
		"back":
			Net.send_move(Vector2i.ZERO)
			if Time.get_ticks_msec() - _phase_ms > 1500:
				_route_finish()
	if Time.get_ticks_msec() - _started_ms > float(_args.get("seconds", "40")) * 1000.0:
		_route_finish()


func _route_finish() -> void:
	var me := Net.my_transform()
	var expect := int(_args.get("expect-peers", "1"))
	var ok: bool = me != null and src.source != "" and _route_log["entered_town"] and _route_log["returned"] \
		and _route_log["npc_rows"] == int(_args.get("expect-npcs", "32")) and _route_log["town_peers"].size() >= expect \
		and _route_log["surface_peers_moved"].size() >= expect and _session_ok()
	print("AUTOPILOT %s route=portal data=%s me=%s entered_town=%s returned=%s town_peers=%d surface_peers_moved=%d npc_rows=%d npc_non_empty=%d arrival_tile=%d return_tile=%d %s" % [
		"PASS" if ok else "FAIL", src.source, str(Vector2(me.x, me.y)) if me else "null",
		_route_log["entered_town"], _route_log["returned"], _route_log["town_peers"].size(),
		_route_log["surface_peers_moved"].size(), _route_log["npc_rows"], _route_log["npc_non_empty"],
		_route_log["town_arrival_tile"], _route_log["surface_return_tile"], _renderer_summary()])
	Net.send_move(Vector2i.ZERO)
	get_tree().quit(0 if ok else 1)


## ---------------------------------------------------------------- playtest route (--route play / resume)
## A scripted player that exercises every MMO feature against the live server: chat, portal into map 1,
## walk to a talking NPC and ask NAME/JOB/BYE, leave town, fight and loot, die and respawn. Things the client
## cannot cause on its own (a monster next to it, lethal monsters) it asks for on stdout ("PLAY need_*"); the
## harness (e.g. a game's play_check.py) answers with admin reducers. --route resume only reports the restored state.
var _walk := PackedByteArray()
var _path: Array[Vector2i] = []
var _path_ms := 0
var _goal_ms := 0
var _play := {"chat_self": false, "chat_peer": false, "talk_open": false, "talk_name": false, "talk_job": false,
	"talk_bye": false, "kills0": -1, "gold0": -1, "inv0": -1, "deaths0": -1, "respawned": false, "requests": 0,
	"looted": false, "town": false, "left_town": false, "killed": false, "hp_full": false}
var _last_attack_ms := 0
var _req_ms := 0
var _death_pos := Vector2.ZERO


func _walkable(map_id: int, t: Vector2i) -> bool:
	if _walk.is_empty():
		_walk = src.walk_table()
	if _walk.is_empty():
		var vp := VoxelProfiles.new()
		vp.load_table(VoxelRenderer3D.TABLE)
		_walk = vp.walkable
	var sz := src.map_size(map_id)
	return t.x >= 0 and t.y >= 0 and t.x < sz.x and t.y < sz.y and _walk[src.tile_at(map_id, t.x, t.y)] == 1


## Breadth-first path (4-neighbour) from my tile to the first tile where goal(tile) is true.
func _plan(goal: Callable, limit := 40000) -> Array[Vector2i]:
	var map_id := Net.current_map()
	var start := _my_tile()
	var prev := {start: start}
	for p in Net.client.db.portal.iter(): # never path through a portal by accident
		if p.from_map == map_id:
			prev[Vector2i(p.x, p.y)] = Vector2i(p.x, p.y)
	var q: Array[Vector2i] = [start]
	var i := 0
	while i < q.size() and i < limit:
		var c := q[i]
		i += 1
		if goal.call(c):
			var out: Array[Vector2i] = []
			while c != start:
				out.push_front(c)
				c = prev[c]
			return out
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not prev.has(n) and _walkable(map_id, n):
				prev[n] = c
				q.append(n)
	return []


## Steer along _path; true once the path is used up.
func _follow() -> bool:
	var me := Net.my_transform()
	while not _path.is_empty() and _my_tile() == _path[0]:
		_path.pop_front()
	if _path.is_empty():
		Net.send_move(Vector2i.ZERO)
		return true
	var d := Vector2(_path[0].x + 0.5 - me.x, _path[0].y + 0.5 - me.y)
	# the path is 4-connected: never cut a corner diagonally (it could clip a wall or a portal tile)
	if absf(d.x) >= 0.15 and absf(d.y) >= 0.15:
		if absf(d.x) < absf(d.y):
			d.y = 0.0
		else:
			d.x = 0.0
	Net.send_move(Vector2i(int(sign(snappedf(d.x, 0.1))), int(sign(snappedf(d.y, 0.1)))))
	return false


func _replan(goal: Callable, every_ms := 600) -> void:
	if _path.is_empty() or Time.get_ticks_msec() - _path_ms > every_ms:
		_path = _plan(goal)
		_path_ms = Time.get_ticks_msec()


func _inv_count() -> int:
	var n := 0
	for row in Net.inventory():
		n += row.qty
	return n


func _route_play() -> void:
	var me := Net.my_transform()
	var st := Net.stats()
	if me == null or st == null:
		return
	var now := Time.get_ticks_msec()
	var since := now - _phase_ms
	if _route == "resume":
		if now - _started_ms > 2500:
			_play_finish(true)
		return
	if _play["kills0"] < 0:
		_play["kills0"] = st.kills; _play["deaths0"] = st.deaths
		_set_phase("chat")
		Net.say("hello from %s" % Net.player_name(Net.my_identity))
	for c in Net.chat_lines(20):
		if c.text.begins_with("hello from"):
			_play["chat_self" if Net.is_me(c.sender) else "chat_peer"] = true
	# monsters wander in on their own outside safe zones: always fight back (except while being killed on purpose)
	if _phase in ["hunt", "fight", "loot"] and now - _last_attack_ms > 550:
		for m in Net.visible_monsters():
			if _cheb(_my_tile(), Vector2i(floori(m.x), floori(m.y))) <= 1:
				_last_attack_ms = now
				attack_nearest()
				break
	if _args.has("shots") and _phase == "fight" and not _shots_taken.has("fight"):
		for m in Net.visible_monsters():
			if m.hp < m.max_hp and m.hp > 0:
				_capture_pair("fight")
				return
	match _phase:
		"chat":
			Net.send_move(Vector2i.ZERO)
			var expect := int(_args.get("expect-peers", "1"))
			if _play["chat_self"] and (_play["chat_peer"] or expect == 0 or since > 10000):
				_set_phase("to_portal")
		"to_portal":
			var p := Net.portal_into(1)
			if p == null:
				return
			if me.map_id != 0:
				_play["town"] = true
				_path.clear()
				_set_phase("talk_walk")
				return
			var d := Vector2(p.x + 0.5 - me.x, p.y + 0.5 - me.y)
			Net.send_move(Vector2i(int(sign(snappedf(d.x, 0.25))), int(sign(snappedf(d.y, 0.25)))))
		"talk_walk":
			var target: MmoNpc = null
			var best := 1 << 30
			for n in Net.visible_npcs():
				var meta := Net.npc_meta(n.id)
				if n.tile == 0 or meta == null or meta.talk <= 0:
					continue
				var dd := _cheb(_my_tile(), Vector2i(floori(n.x), floori(n.y)))
				if dd < best:
					best = dd
					target = n
			if target == null or since > 30000:
				_set_phase("leave_town")
				return
			if best <= 1:
				Net.send_move(Vector2i.ZERO)
				if talk_nearest():
					_play["talk_open"] = true
					_on_talk_line("name")
					_play["talk_name"] = _talk != null and _talk.title != ""
					_on_talk_line("job")
					_play["talk_job"] = _talk != null and hud.talk_text().length() > 12
					_set_phase("talking")
				return
			var tt := Vector2i(floori(target.x), floori(target.y))
			_replan(func(c: Vector2i): return _cheb(c, tt) == 1, 800)
			_follow()
		"talking":
			Net.send_move(Vector2i.ZERO)
			if _args.has("shots") and not _shots_taken.has("town_talk"):
				_capture_pair("town_talk")
				return
			if since > 1500:
				_on_talk_line("bye")
				_play["talk_bye"] = _talk == null
				_path.clear()
				_set_phase("leave_town")
		"leave_town":
			if me.map_id == 0:
				_play["left_town"] = true
				_path.clear()
				_set_phase("hunt")
				return
			var sz := src.map_size(me.map_id)
			_replan(func(c: Vector2i): return c.x == 0 or c.y == 0 or c.x == sz.x - 1 or c.y == sz.y - 1, 2000)
			if _follow():
				var t := _my_tile()
				Net.send_move(Vector2i(-1 if t.x == 0 else (1 if t.x == sz.x - 1 else 0),
					-1 if t.y == 0 else (1 if t.y == sz.y - 1 else 0)))
		"hunt":
			if me.map_id != 0:
				_path.clear()
				_set_phase("leave_town")
				return
			# get clear of the town entrance's safe zone, then ask for a monster on a free neighbouring tile
			# --hunt-dir X,Y picks the side of town (two scripted players must not share a killing field)
			var p := Net.portal_into(1)
			var hd: PackedStringArray = String(_args.get("hunt-dir", "-1,0")).split(",")
			var dir := Vector2i(int(hd[0]), int(hd[1]))
			var far := func(c: Vector2i):
				if p == null:
					return true
				var o := c - Vector2i(p.x, p.y)
				return (dir.x == 0 or o.x * dir.x >= 14) and (dir.y == 0 or o.y * dir.y >= 14)
			if not far.call(_my_tile()):
				_replan(far, 3000)
				if _path.is_empty() and since > 4000:
					_args["hunt-dir"] = "-1,0" if String(_args.get("hunt-dir", "")) != "-1,0" else "0,1"
					_set_phase("hunt")
					return
				_follow()
				return
			Net.send_move(Vector2i.ZERO)
			_request("monster", int(_args.get("monster-kind", "1")))
			_set_phase("fight")
		"fight":
			Net.send_move(Vector2i.ZERO)
			if st.kills > _play["kills0"]:
				_play["killed"] = true
				_play["gold0"] = st.gold
				_play["inv0"] = _inv_count()
				_set_phase("loot")
			elif since > 8000 and _play["requests"] < 5:
				_request("monster", int(_args.get("monster-kind", "1")))
				_set_phase("fight")
			elif since > 8000:
				_set_phase("die")
		"loot":
			if st.gold > _play["gold0"] or _inv_count() > _play["inv0"]:
				_play["looted"] = true
				_play["requests"] = 0
				_set_phase("die")
				return
			var items := Net.visible_items()
			if (items.is_empty() and since > 1500) or since > 12000:
				if _play["requests"] < 5: # rats may drop nothing: fight another one
					_play["kills0"] = st.kills
					_request("monster", int(_args.get("monster-kind", "1")))
					_set_phase("fight")
				else:
					_set_phase("die")
				return
			if items.is_empty():
				Net.send_move(Vector2i.ZERO)
				return
			var near := false
			for g in items:
				if _cheb(_my_tile(), Vector2i(g.x, g.y)) <= 1:
					near = true
			if near:
				Net.send_move(Vector2i.ZERO)
				if now - _last_attack_ms > 500:
					_last_attack_ms = now
					pick_up_near()
			else:
				var gt := Vector2i(items[0].x, items[0].y)
				_replan(func(c: Vector2i): return _cheb(c, gt) <= 1, 1000)
				_follow()
		"die":
			Net.send_move(Vector2i.ZERO)
			if st.deaths > _play["deaths0"]:
				_play["respawned"] = Vector2(me.x, me.y).distance_to(_death_pos) > 2.0
				_play["hp_full"] = st.hp == st.max_hp # respawn heals fully (checked before roaming monsters can hit us)
				_set_phase("after")
				return
			if st.hp < st.max_hp or _death_pos == Vector2.ZERO: # last place we were hurt (respawn heals fully)
				_death_pos = Vector2(me.x, me.y)
			if _play.get("death_req", 0) == 0 or (since > 6000 and _play["death_req"] < 5):
				_play["death_req"] = _play.get("death_req", 0) + 1
				_request("death", 8)
				_set_phase("die")
		"after":
			Net.send_move(Vector2i.ZERO)
			if since > 1500:
				_play["hp_full"] = _play["hp_full"] or st.hp == st.max_hp
				_play_finish(false)
	if now - _started_ms > float(_args.get("seconds", "150")) * 1000.0:
		_play_finish(false)


## Ask the harness for a monster of `kind` on a walkable neighbour tile (printed; play_check.py spawns it).
func _request(what: String, kind: int) -> void:
	var t := _my_tile()
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
		if _walkable(Net.current_map(), t + d):
			t += d
			break
	_play["requests"] += 1
	print("PLAY need_%s %d %d %d %d" % [what, Net.current_map(), t.x, t.y, kind])


func _play_finish(resume: bool) -> void:
	var me := Net.my_transform()
	var st := Net.stats()
	var inv := []
	for row in Net.inventory():
		inv.append("%d:%d" % [row.kind, row.qty])
	inv.sort()
	print("PLAY state map=%d x=%d y=%d hp=%d max_hp=%d gold=%d level=%d kills=%d deaths=%d inv=%s" % [
		me.map_id if me else -1, floori(me.x) if me else -1, floori(me.y) if me else -1, st.hp if st else -1,
		st.max_hp if st else -1, st.gold if st else -1, st.level if st else -1, st.kills if st else -1,
		st.deaths if st else -1, ",".join(inv)])
	var ok := me != null and st != null and _session_ok()
	if not resume:
		for k in ["chat_self", "town", "talk_open", "talk_name", "talk_job", "talk_bye", "left_town", "killed",
				"looted", "respawned", "hp_full"]:
			ok = ok and _play[k]
		if int(_args.get("expect-peers", "1")) > 0:
			ok = ok and _play["chat_peer"]
	var flags := []
	for k in _play:
		if _play[k] is bool:
			flags.append("%s=%s" % [k, _play[k]])
	print("AUTOPILOT %s route=%s %s last_error=%s %s" % ["PASS" if ok else "FAIL", _route, " ".join(flags),
		_last_error.replace(" ", "_"), _renderer_summary()])
	Net.send_move(Vector2i.ZERO)
	get_tree().quit(0 if ok else 1)


## Server state (AOI rows) -> the renderer-neutral view.
func _view_state() -> MapViewState:
	var st := MapViewState.new()
	var me := Net.my_transform()
	st.map_id = Net.current_map()
	st.focus = Vector2(me.x, me.y) if me else Vector2.ZERO
	for t in Net.visible_transforms():
		var ps := Net.stats(t.identity)
		st.entities.append({"id": t.identity.hex_encode(), "name": Net.player_name(t.identity),
			"pos": Vector2(t.x, t.y), "is_me": Net.is_me(t.identity), "moving": t.moving,
			"hp": ps.hp if ps else 0, "max_hp": ps.max_hp if ps else 0})
	for n in Net.visible_npcs():
		st.npcs.append({"id": n.id, "tile": n.tile, "pos": Vector2(n.x, n.y)})
	for m in Net.visible_monsters():
		var k := Net.monster_kind(m.kind)
		st.monsters.append({"id": m.id, "tile": m.tile, "pos": Vector2(m.x, m.y), "name": k.name if k else "monster",
			"hp": m.hp, "max_hp": m.max_hp})
	for g in Net.visible_items():
		var ik := Net.item_kind(g.kind)
		st.items.append({"id": g.id, "tile": ik.tile if ik else 60, "pos": Vector2(g.x + 0.5, g.y + 0.5),
			"name": ik.name if ik else "item", "qty": g.qty})
	st.target_id = _target
	Game.decorate_view(self, st)
	return st


## ---------------------------------------------------------------- --bench (offline, no server)
## Scripted walk on the local data: overworld loop around Game.bench_start (crossing chunk borders), then
## map 1. Prints per-phase frame-time stats (vsync off) and the renderer's chunk build times. "border" stats are
## the frames that follow a chunk-border crossing or a chunk upload (where hitches would show).
var _bench := {}


func _bench_start() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var start := Game.bench_start(src)
	_bench = {"phase": "warm_world", "t0": Time.get_ticks_usec(), "start": start, "frames": PackedFloat64Array(),
		"gpu": PackedFloat64Array(), "last": Time.get_ticks_usec(), "seconds": float(_args.get("bench-seconds", "10"))}
	print("BENCH start renderer=%s data=%s at=%s size=%s" % [renderer_kind, src.source, str(start), str(get_viewport().get_visible_rect().size)])


func _bench_state(map_id: int, t: float) -> MapViewState:
	var st := MapViewState.new()
	st.map_id = map_id
	var me := Vector2.ZERO
	if map_id == 0: # 40x40-tile square loop at 5 tiles/s from the start point
		var s := fmod(t * 5.0, 160.0)
		var o: Vector2 = _bench["start"]
		var off := Vector2(minf(s, 40.0), 0) if s < 40 else (Vector2(40, s - 40) if s < 80 else (Vector2(40 - (s - 80), 40) if s < 120 else Vector2(0, 40 - (s - 120))))
		me = Vector2(posmod(int(o.x + off.x - 20), 256), posmod(int(o.y + off.y - 20), 256)) + Vector2(fmod(off.x, 1.0), fmod(off.y, 1.0))
	else:
		me = Vector2(16, 16) + Vector2(cos(t * 0.5), sin(t * 0.5)) * 9.0
		for k in 32: # NPC-like billboards spread over the town
			st.npcs.append({"id": k, "tile": 80 + (k % 8) * 2, "pos": Vector2(3.5 + (k * 7) % 26, 3.5 + (k * 11) % 26)})
	st.focus = me
	st.entities.append({"id": "me", "name": "Bench", "pos": me, "is_me": true, "moving": true})
	st.entities.append({"id": "peer", "name": "Peer", "pos": me + Vector2(2, 1), "is_me": false, "moving": false})
	return st


func _bench_frame() -> void:
	var now := Time.get_ticks_usec()
	var t: float = (now - int(_bench["t0"])) / 1e6
	var phase: String = _bench["phase"]
	var map_id := 0 if phase.ends_with("world") else 1
	var st := _bench_state(map_id, t if phase.begins_with("run") else 0.0)
	var log_n: int = (renderer.get("build_log") as Array).size() if renderer.get("build_log") != null else 0
	renderer.render(st)
	var chunk := Vector2i(floori(st.focus.x / 32.0), floori(st.focus.y / 32.0))
	var log_n2: int = (renderer.get("build_log") as Array).size() if renderer.get("build_log") != null else 0
	var mark: bool = log_n2 != log_n or chunk != _bench.get("chunk", chunk)
	_bench["chunk"] = chunk
	if phase.begins_with("warm"):
		# ready for 3 consecutive frames: the viewport image lags the scene by a frame, so a chunk placed
		# this frame would otherwise be missing from the shot
		_bench["ready_frames"] = int(_bench.get("ready_frames", 0)) + 1 if renderer.is_ready() else 0
		if int(_bench["ready_frames"]) >= 3 and t > 0.5:
			_bench["ready_frames"] = 0
			print("BENCH %s ready_ms=%d" % [phase, int(t * 1000)])
			if _args.has("shots"): # optional still of the warmed-up view (local check only, never in git)
				DirAccess.make_dir_recursive_absolute(String(_args["shots"]))
				var path := String(_args["shots"]).path_join("bench_%s_%s.png" % [phase.trim_prefix("warm_"), renderer_kind])
				var img := get_viewport().get_texture().get_image()
				print("SHOT %s err=%d" % [path, img.save_png(path) if img else -1])
			_bench["phase"] = phase.replace("warm", "run")
			_bench["t0"] = now
			_bench["frames"] = PackedFloat64Array()
			_bench["gpu"] = PackedFloat64Array()
			_bench["border"] = PackedFloat64Array()
		_bench["last"] = now
		return
	var ft := (now - int(_bench["last"])) / 1000.0
	if _bench.get("mark_next", false): # this frame's measurement covers the marked frame's work
		_bench["border"].append(ft)
	_bench["mark_next"] = mark
	_bench["frames"].append(ft)
	_bench["gpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_bench["last"] = now
	if t < _bench["seconds"]:
		return
	var f: PackedFloat64Array = _bench["frames"]
	var sorted := f.duplicate(); sorted.sort()
	var sum := 0.0
	for v in f: sum += v
	var gsum := 0.0
	for v in _bench["gpu"]: gsum += v
	var n := maxi(1, f.size())
	var vs: Dictionary = renderer.call("visible_stats") if renderer.has_method("visible_stats") else {}
	print("BENCH %s renderer=%s frames=%d avg_ms=%.2f fps=%.1f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f gpu_avg_ms=%.2f visible=%s" % [
		phase, renderer_kind, f.size(), sum / n, 1000.0 * n / maxf(sum, 0.001), sorted[int(n * 0.95)], sorted[int(n * 0.99)],
		sorted[n - 1], gsum / n, str(vs)])
	var bf: PackedFloat64Array = _bench.get("border", PackedFloat64Array())
	if bf.size() > 0:
		var bs := bf.duplicate(); bs.sort()
		print("BENCH %s border frames=%d p95_ms=%.2f max_ms=%.2f" % [phase, bs.size(), bs[int(bs.size() * 0.95)], bs[bs.size() - 1]])
	else:
		print("BENCH %s border frames=0" % phase)
	if phase == "run_world":
		_bench["phase"] = "warm_town"
		_bench["t0"] = now
		return
	if renderer.get("build_log") != null:
		var log: Array = renderer.get("build_log")
		var agg := {"ms_assemble": [], "ms_mesh": [], "ms_upload": [], "verts": [], "tris": []}
		for b in log:
			for k in agg:
				agg[k].append(float(b[k]))
		var parts := []
		for k in agg:
			var a: Array = agg[k]
			if a.is_empty():
				continue
			var tot := 0.0
			for v in a: tot += v
			parts.append("%s avg=%.1f max=%.1f" % [k, tot / a.size(), a.max()])
		print("BENCH chunks built=%d threads=%d res=%s | %s" % [log.size(), OS.get_processor_count(),
			str(renderer.get("opts")["res"]), " | ".join(parts)])
	get_tree().quit(0)


## UI hook sanity (part of --tileset-check): for screen offsets on both axes the focus tile must project to the
## offset viewport centre, screen_to_world must invert it, and points around the view must round-trip.
func _hooks_check(st: MapViewState, fails: Array[String]) -> void:
	var vp := get_viewport().get_visible_rect().size
	var tol_px := 3.0
	# 2D: height 0 is the bottom edge of a sprite drawn at p and 0.5 its centre = the point drawn at p; 3D: 0 = ground.
	var h0 := 0.5 if renderer is TileRenderer2D else 0.0
	# 3D: world_to_screen stands walls/doors at floor level (where a sprite on them is drawn) while screen_to_world
	# hits their top, so one probe landing on a tall tile may miss.
	var allow := 0 if renderer is TileRenderer2D else 1
	for off: Vector2 in [Vector2.ZERO, Vector2(200, -120), Vector2(-150, 90)]:
		renderer.set_screen_offset(off)
		for _f in 8:
			renderer.render(st)
			await get_tree().process_frame
		var want := vp / 2.0 + off
		var w := renderer.world_to_screen(st.focus, h0)
		var back := renderer.screen_to_world(w) if w.is_finite() else Vector2(NAN, NAN)
		var trips := 0
		var bad := 0
		for fx: float in [0.3, 0.5, 0.7]:
			for fy: float in [0.35, 0.5, 0.65]:
				var px := Vector2(vp.x * fx, vp.y * fy) + off * 0.5
				var t := renderer.screen_to_world(px)
				if not t.is_finite():
					continue
				var q := renderer.world_to_screen(t, h0)
				if not q.is_finite(): # 3D: the point is outside line of sight (tags are hidden there)
					continue
				trips += 1
				if q.distance_to(px) > tol_px:
					bad += 1
					print("TILESET_CHECK hooks miss px=%s world=%s back_px=%s" % [px, t, q])
		var ok := w.is_finite() and w.distance_to(want) <= tol_px and back.is_finite() and back.distance_to(st.focus) < 0.35 \
			and trips >= 5 and bad <= allow
		print("TILESET_CHECK hooks renderer=%s offset=%s focus_px=%s want=%s back=%s roundtrip=%d/%d %s" % [
			renderer_kind, off, w.round(), want, back, trips - bad, trips, "ok" if ok else "BAD"])
		if not ok:
			fails.append("UI hooks off at offset %s" % off)
		if off == Vector2(200, -120) and _args.has("shots") and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(String(_args["shots"]).path_join(
				"hooks_offset_%s.png" % renderer_kind))
	renderer.set_screen_offset(Vector2.ZERO)


func _key(code: Key, shift: bool) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.shift_pressed = shift
	k.pressed = true
	return k


## ---------------------------------------------------------------- --tileset-check (offline, no server)
## Cycles every pack on map 0 around Game.bench_start in the current renderer: each pack must resolve all 256
## tiles at its cell size and become the renderers' atlas; the default pack must be the source's own atlas byte for
## byte; F4-style cycling must visit every pack once and come back, Shift+F3 / F4 must step back / forward, every
## tileset_list() entry must carry a 4x4-tile preview; an unknown id must be refused.
## --shots DIR saves tileset_<id>_<renderer>.png per pack (needs a display; local evidence only, never in git).
## --tileset-expect a,b: ids that must be present.
func _tileset_check() -> void:
	var fails: Array[String] = []
	_bench = {"start": Game.bench_start(src)}
	print("TILESET_CHECK start renderer=%s packs=%d source=%s" % [renderer_kind, tilesets.size(), src.source])
	if tilesets.is_empty():
		fails.append("no packs (the source has no atlas)")
	for want in String(_args.get("tileset-expect", "")).split(",", false):
		if Tilesets.find(tilesets, want) == null:
			fails.append("expected pack %s missing" % want)
	var base := src.default_tileset()
	if base and src.atlas_image():
		var own := src.atlas_image().duplicate() as Image
		own.convert(Image.FORMAT_RGBA8)
		if base.image.get_data() != own.get_data():
			fails.append("default pack differs from the source's atlas")
	var first := _tileset_id
	var seen := {}
	var digests := {}
	var st := _bench_state(0, 0.0)
	for i in tilesets.size():
		var p := Tilesets.find(tilesets, _tileset_id)
		if p == null or seen.has(p.id):
			fails.append("cycle revisited %s before covering every pack" % _tileset_id)
			break
		seen[p.id] = true
		if p.image == null or p.image.get_width() != 16 * p.cell or p.image.get_height() < 16 * p.cell or p.mapped.size() != 256:
			fails.append("%s: atlas does not hold 256 tiles" % p.id)
		elif src.view_atlas_image() != p.image and p != base:
			fails.append("%s: not the renderers' atlas after set_tileset" % p.id)
		var t0 := Time.get_ticks_msec()
		while true:
			renderer.render(st)
			await get_tree().process_frame
			if renderer.is_ready() or Time.get_ticks_msec() - t0 > 30000:
				break
		for _f in 5:
			renderer.render(st)
			await get_tree().process_frame
		var shot := "-"
		var img := get_viewport().get_texture().get_image() if DisplayServer.get_name() != "headless" else null
		if img and _args.has("shots"):
			DirAccess.make_dir_recursive_absolute(String(_args["shots"]))
			shot = String(_args["shots"]).path_join("tileset_%s_%s.png" % [p.id, renderer_kind])
			if img.save_png(shot) != OK:
				fails.append("%s: cannot save %s" % [p.id, shot])
		var view := "-"
		if img:
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(img.get_data())
			view = ctx.finish().hex_encode().substr(0, 12)
		digests[p.id] = view
		print("TILESET_CHECK pack id=%s platform=%s cell=%d mapped=%d anim=%d atlas=%s view=%s ready=%s shot=%s" % [
			p.id, p.platform, p.cell, p.mapped_count(), p.anims.size(), p.digest(), view, renderer.is_ready(), shot])
		cycle_tileset(1, false)
	if _tileset_id != first:
		fails.append("cycling did not return to %s (at %s)" % [first, _tileset_id])
	if seen.size() != tilesets.size():
		fails.append("cycle visited %d of %d packs" % [seen.size(), tilesets.size()])
	if tilesets.size() > 1:
		var back := cycle_tileset(-1, false)
		if back != tilesets[-1].id:
			fails.append("cycle_tileset(-1) from the first pack gave %s, expected %s" % [back, tilesets[-1].id])
		cycle_tileset(1, false)
		# the player keys: Shift+F3 = previous, F4 = next (settings are never saved in this mode)
		var kind0 := renderer_kind
		_unhandled_input(_key(KEY_F3, true))
		var prev := _tileset_id
		_unhandled_input(_key(KEY_F4, false))
		var ok_keys := prev == tilesets[-1].id and _tileset_id == first and renderer_kind == kind0 # Shift+F3 must not switch view
		print("TILESET_CHECK keys shift_f3=%s f4=%s %s" % [prev, _tileset_id, "ok" if ok_keys else "BAD"])
		if not ok_keys:
			fails.append("Shift+F3 / F4 gave %s / %s, expected %s / %s" % [prev, _tileset_id, tilesets[-1].id, first])
	var previews := 0
	for d in tileset_list():
		var pv = d.get("preview")
		var pk := Tilesets.find(tilesets, String(d.id))
		if pv is Texture2D and pk and pv.get_width() == 4 * pk.cell and pv.get_height() == 4 * pk.cell:
			previews += 1
		else:
			fails.append("%s: tileset_list() preview missing or not 4x4 tiles" % d.id)
	print("TILESET_CHECK preview packs=%d/%d" % [previews, tilesets.size()])
	if set_tileset("no-such-pack", false) or _tileset_id != first:
		fails.append("an unknown id was accepted")
	await _hooks_check(st, fails)
	if DisplayServer.get_name() != "headless" and tilesets.size() > 1:
		var uniq := {}
		for k in digests:
			uniq[digests[k]] = true
		if uniq.size() < 2:
			fails.append("every pack rendered the same frame")
	for f in fails:
		print("TILESET_CHECK fail: " + f)
	print("TILESET_CHECK %s renderer=%s packs=%d" % ["PASS" if fails.is_empty() else "FAIL", renderer_kind, tilesets.size()])
	get_tree().quit(0 if fails.is_empty() else 1)
