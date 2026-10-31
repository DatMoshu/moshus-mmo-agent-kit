## Starter scene: WASD/arrow keys move your square; other players appear as they move.
## Run two instances (two windows) to see two players moving.
## Headless check (used by tools/kit.py godot-smoke):
##   godot --headless --path . -- --autopilot --url http://127.0.0.1:3000 --db mmo-dev --dir 1,0 --seconds 4
extends Node2D

const SCALE := 4.0
var _args := {}
var _peer_first := {} # identity hex -> Vector2 first seen
var _peer_moved := {} # identity hex -> true once seen moving
var _started_ms := 0


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	Net.session_connected.connect(_on_connected)
	Net.connect_to_server(_args.get("url", "http://127.0.0.1:3000"), _args.get("db", "mmo-dev"), _args.get("profile", ""))


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


func _on_connected(identity_hex: String) -> void:
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
		Net.send_move(Vector2i(int(d[0]), int(d[1])))


func _process(_delta: float) -> void:
	if not Net.is_joined:
		return
	if _args.has("autopilot"):
		_autopilot_check()
	else:
		var dir := Vector2i(
			int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
			int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up")))
		if Input.is_physical_key_pressed(KEY_D): dir.x = 1
		if Input.is_physical_key_pressed(KEY_A): dir.x = -1
		if Input.is_physical_key_pressed(KEY_S): dir.y = 1
		if Input.is_physical_key_pressed(KEY_W): dir.y = -1
		Net.send_move(dir)
	queue_redraw()


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
	var ok := me != null and _peer_moved.size() >= int(_args.get("expect-peers", "1"))
	print("AUTOPILOT %s me=%s moved_peers=%d visible=%d" % ["PASS" if ok else "FAIL", str(Vector2(me.x, me.y)) if me else "null", _peer_moved.size(), Net.visible_transforms().size()])
	Net.send_move(Vector2i.ZERO)
	get_tree().quit(0 if ok else 1)


func _draw() -> void:
	var center := get_viewport_rect().size / 2.0
	var me := Net.my_transform()
	var origin := Vector2(me.x, me.y) if me else Vector2.ZERO
	for t in Net.visible_transforms():
		var p := center + (Vector2(t.x, t.y) - origin) * SCALE
		var color := Color.GOLD if Net.is_me(t.identity) else Color.SKY_BLUE
		draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), color)
		draw_string(ThemeDB.fallback_font, p + Vector2(-20, -14), Net.player_name(t.identity))
