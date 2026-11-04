## NetSession: the ONE seam between gameplay code and the SpacetimeDB GDScript SDK.
## Gameplay code calls intent methods (join, send_move) and reads the local cache
## through helpers here. Nothing else in the game touches SpacetimeDB.* directly,
## so an SDK upgrade/fork or a bot client only has to change this file.
##
## AOI: one subscription PER (map_id, cell) (non-overlapping queries). A cell is one 32x32
## map chunk; players on another map are never in your AOI even at the same x/y. The GDScript SDK does not
## ref-count overlapping subscriptions, and unsubscribe() does not send dropped rows,
## so we also filter reads by the current cell set (rows from cells we left go stale).
extends Node

signal session_connected(identity_hex: String)
signal schema_rejected(reason: String)
signal session_disconnected
signal joined_world
signal aoi_changed(cells: Array)
signal map_changed(map_id: int)
signal action_result(action: String, error: String) # error "" = ok (say / attack / pick_up / use_item)

const AOI_RADIUS := 1 # 3x3 cells

var server_url := "http://127.0.0.1:3000"
var database := "mmo-dev"
var profile := "" # non-empty = persistent identity stored in user://identity_<profile>.token

var client: MmoModuleClient
var my_identity := PackedByteArray()
var is_joined := false

var _seq := 0
var _last_dir := Vector2i.ZERO
var _cell := Vector2i(2147483647, 2147483647)
var _map := -1
var _cell_subs := {} # Vector3i(map, cx, cy) -> SpacetimeDBSubscription
var _cell_size := 32.0
var _callbacks_registered := false
var _connect_generation := 0
var _transport_generation := -1
var _connected_profile := ""
var _schema_request: HTTPRequest


func _ready() -> void:
	client = SpacetimeDB.Mmo
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.connection_error.connect(_on_connection_error)


# Bind endpoint/profile/options and generation before any asynchronous response.
func connect_to_server(url: String = server_url, db: String = database, p_profile: String = profile) -> void:
	_invalidate_connect()
	var generation := _connect_generation
	server_url = url
	database = db
	profile = p_profile
	var options := SpacetimeDBConnectionOptions.new()
	options.compression = SpacetimeDBConnectionOptions.CompressionPreference.NONE
	options.threading = true
	options.one_time_token = true
	options.save_token = false
	options.token = _read_profile_token(p_profile)
	var request := _new_schema_request()
	_schema_request = request
	request.timeout = 10.0
	request.body_size_limit = 4 * 1024 * 1024
	add_child(request)
	request.request_completed.connect(_on_schema_completed.bind(generation, request, url, db, p_profile, options), CONNECT_ONE_SHOT)
	var schema_url := url.replace("wss://", "https://").replace("ws://", "http://")
	var err := _start_schema_request(request, schema_url.trim_suffix("/") + "/v1/database/" + db.uri_encode() + "/schema?version=10")
	if err != OK and generation == _connect_generation:
		_reject_schema("Dialogue schema unavailable")


func _new_schema_request() -> HTTPRequest:
	return HTTPRequest.new()


func _start_schema_request(request: HTTPRequest, url: String) -> Error:
	return request.request(url)


func _read_profile_token(p_profile: String) -> String:
	if p_profile.is_empty():
		return ""
	var path := "user://identity_%s.token" % p_profile
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


func _invalidate_connect() -> void:
	_connect_generation += 1
	if is_instance_valid(_schema_request):
		_schema_request.cancel_request()
		_schema_request.queue_free()
	_schema_request = null


func _reject_schema(reason: String) -> void:
	_invalidate_connect()
	schema_rejected.emit(reason)


func _on_schema_completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray,
		generation: int, request: HTTPRequest, url: String, db: String, p_profile: String,
		options: SpacetimeDBConnectionOptions) -> void:
	if generation != _connect_generation or request != _schema_request or not is_inside_tree():
		return
	_schema_request = null
	request.queue_free()
	# Error pages/failed transports must never reach the JSON parser.
	if result != HTTPRequest.RESULT_SUCCESS or status != 200 or body.is_empty():
		_reject_schema("Dialogue schema unavailable")
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		_reject_schema("Dialogue schema unavailable")
		return
	var expected: StringName = MmoNpcMeta.BSATN_TYPES[&"talk"]
	if not DialogueSchema.matches(parser.data, expected):
		print("SCHEMA_REJECT dialogue expected=%s" % expected)
		_reject_schema("Dialogue schema and client bindings differ; use a matching build")
		return
	_transport_generation = generation
	_connected_profile = p_profile
	_connect_checked(url, db, options)


func _connect_checked(url: String, db: String, options: SpacetimeDBConnectionOptions) -> void:
	client.connect_db(url, db, options)


func _disconnect_transport() -> void:
	if is_instance_valid(client) and client.is_connected_db():
		client.disconnect_db()


## Cancel even if the schema request has not opened a socket yet.
func disconnect_from_server() -> void:
	_invalidate_connect()
	is_joined = false
	_disconnect_transport()
	_emit_disconnected.call_deferred(_connect_generation)


func _emit_disconnected(generation: int) -> void:
	if generation == _connect_generation and is_inside_tree():
		session_disconnected.emit()


func _on_disconnected() -> void:
	# A prior transport closing during a newer schema check cannot cancel it.
	if _transport_generation != _connect_generation:
		return
	_invalidate_connect()
	is_joined = false
	session_disconnected.emit()


func _on_connection_error(code: int, reason: String) -> void:
	if _transport_generation != _connect_generation:
		return
	_invalidate_connect()
	is_joined = false
	push_warning("NetSession connection error %s: %s" % [code, reason])


func _exit_tree() -> void:
	_invalidate_connect()
	_disconnect_transport()


func _on_connected(identity: PackedByteArray, token: String) -> void:
	var generation := _transport_generation
	if generation != _connect_generation:
		return
	var token_profile := _connected_profile
	my_identity = identity
	if not _callbacks_registered: # client.db only exists once the SDK has initialized
		_callbacks_registered = true
		client.db.entity_transform.on_insert(_on_transform)
		client.db.entity_transform.on_update(func(_old, row): _on_transform(row))
	if not token_profile.is_empty():
		var f := FileAccess.open("user://identity_%s.token" % token_profile, FileAccess.WRITE)
		if f:
			f.store_string(token)
			f.close()
	# Small, global tables: config, player roster, server health, and my own transform.
	var hex := identity.hex_encode()
	var sub := client.subscribe(PackedStringArray([
		"SELECT * FROM world_config",
		"SELECT * FROM player",
		"SELECT * FROM tick_health",
		"SELECT * FROM world_seed",
		"SELECT * FROM map_info",
		"SELECT * FROM portal",
		"SELECT * FROM map_exit",
		"SELECT * FROM npc_meta",
		"SELECT * FROM chat_message",
		"SELECT * FROM chat_channel",
		"SELECT * FROM player_stats",
		"SELECT * FROM monster_kind",
		"SELECT * FROM item_kind",
		"SELECT * FROM my_inventory",
		"SELECT * FROM entity_transform WHERE identity = 0x%s" % hex,
	]))
	await sub.wait_for_applied(10)
	if generation != _connect_generation or not is_inside_tree():
		return
	for cfg in client.db.world_config.iter():
		_cell_size = float(cfg.cell_size)
	session_connected.emit(hex)


## Intent: join the world with a display name (server validates + spawns).
## Returns "" on success or the server's error text (e.g. "name taken").
func join(display_name: String) -> String:
	var call := client.reducers.join(display_name)
	var result: Array = [""]
	call.on_error.connect(func(err: String): result[0] = err)
	call.on_internal_error.connect(func(err: String): result[0] = "internal: " + err)
	await call.response
	if result[0] == "":
		is_joined = true
		joined_world.emit()
	return result[0]


## Intent: movement direction (-1..1 per axis). Sent only when it changes.
func send_move(dir: Vector2i) -> void:
	dir = dir.clamp(Vector2i(-1, -1), Vector2i(1, 1))
	if dir == _last_dir or not is_joined:
		return
	_last_dir = dir
	_seq += 1
	client.reducers.set_input(dir.x, dir.y, _seq)


## Gameplay intents. Results arrive on `action_result` (the server is the only authority).
func say(text: String) -> void:
	_call("say", client.reducers.say(text))


## Say on a channel: 0 local (nearby), 1 world.
func say_in(channel: int, text: String) -> void:
	_call("say_in", client.reducers.say_in(channel, text))


func attack(monster_id: int) -> void:
	_call("attack", client.reducers.attack(monster_id))


func pick_up(item_id: int) -> void:
	_call("pick_up", client.reducers.pick_up(item_id))


func use_item(kind: int) -> void:
	_call("use_item", client.reducers.use_item(kind))


func _call(action: String, call: SpacetimeDBReducerCall) -> void:
	if not is_joined:
		return
	var err: Array = [""]
	call.on_error.connect(func(e: String): err[0] = e)
	call.on_internal_error.connect(func(e: String): err[0] = "internal: " + e)
	await call.response
	action_result.emit(action, err[0])


func my_transform() -> MmoEntityTransform:
	return client.db.entity_transform.identity.find(my_identity) if not my_identity.is_empty() else null


## Transforms inside the current AOI (filters stale rows from cells/maps we left).
func visible_transforms() -> Array[MmoEntityTransform]:
	var out: Array[MmoEntityTransform] = []
	for t in client.db.entity_transform.iter():
		if t.map_id == _map and abs(t.cell_x - _cell.x) <= AOI_RADIUS and abs(t.cell_y - _cell.y) <= AOI_RADIUS:
			out.append(t)
	return out


## NPC slots inside the current AOI.
func visible_npcs() -> Array[MmoNpc]:
	var out: Array[MmoNpc] = []
	for n in client.db.npc.iter():
		if n.map_id == _map and abs(n.cell_x - _cell.x) <= AOI_RADIUS and abs(n.cell_y - _cell.y) <= AOI_RADIUS:
			out.append(n)
	return out


func _in_aoi(map_id: int, cx: int, cy: int) -> bool:
	return map_id == _map and abs(cx - _cell.x) <= AOI_RADIUS and abs(cy - _cell.y) <= AOI_RADIUS


func visible_monsters() -> Array[MmoMonster]:
	var out: Array[MmoMonster] = []
	for m in client.db.monster.iter():
		if _in_aoi(m.map_id, m.cell_x, m.cell_y):
			out.append(m)
	return out


func visible_items() -> Array[MmoGroundItem]:
	var out: Array[MmoGroundItem] = []
	for g in client.db.ground_item.iter():
		if _in_aoi(g.map_id, g.cell_x, g.cell_y):
			out.append(g)
	return out


func npc_meta(id: int) -> MmoNpcMeta:
	return client.db.npc_meta.id.find(id)


func stats(identity: PackedByteArray = my_identity) -> MmoPlayerStats:
	return client.db.player_stats.identity.find(identity) if not identity.is_empty() else null


func inventory() -> Array:
	return client.db.my_inventory.iter()


func monster_kind(kind: int) -> MmoMonsterKind:
	return client.db.monster_kind.kind.find(kind)


func item_kind(kind: int) -> MmoItemKind:
	return client.db.item_kind.kind.find(kind)


## Recent chat lines, oldest first (the server keeps the last 100).
func chat_lines(n: int = 8) -> Array:
	var rows: Array = client.db.chat_message.iter()
	rows.sort_custom(func(a, b): return a.id < b.id)
	return rows.slice(maxi(0, rows.size() - n))


## Channel of a chat_message row id (side table chat_channel): 0 local, 1 world (no row = world).
func chat_channel(msg_id: int) -> int:
	var row = client.db.chat_channel.id.find(msg_id)
	return int(row.channel) if row else 1


func map_infos() -> Array:
	return client.db.map_info.iter()


func current_map() -> int:
	return _map


func world_seed() -> MmoWorldSeed:
	return client.db.world_seed.id.find(0)


## The surface portal that leads into `to_map` (or the first surface portal when -1).
func portal_into(to_map: int = -1) -> MmoPortal:
	for p in client.db.portal.iter():
		if p.from_map == 0 and (to_map < 0 or p.to_map == to_map):
			return p
	return null


func player_name(identity: PackedByteArray) -> String:
	var p = client.db.player.identity.find(identity)
	return p.name if p else "?"


func is_me(identity: PackedByteArray) -> bool:
	return identity == my_identity


func _on_transform(row: MmoEntityTransform) -> void:
	if row.identity == my_identity:
		if row.map_id != _map:
			_map = row.map_id
			_cell = Vector2i(2147483647, 2147483647)
			# The server zeroes our intent on a map change; resend whatever we want next.
			_last_dir = Vector2i.ZERO
			map_changed.emit(_map)
		_update_aoi(Vector2i(row.cell_x, row.cell_y))


func _update_aoi(cell: Vector2i) -> void:
	if cell == _cell:
		return
	_cell = cell
	var wanted := {}
	for dx in range(-AOI_RADIUS, AOI_RADIUS + 1):
		for dy in range(-AOI_RADIUS, AOI_RADIUS + 1):
			wanted[Vector3i(_map, cell.x + dx, cell.y + dy)] = true
	# Subscribe new cells first, then drop cells we left (no flicker).
	for c in wanted.keys():
		if not _cell_subs.has(c):
			var where := "map_id = %d AND cell_x = %d AND cell_y = %d" % [c.x, c.y, c.z]
			_cell_subs[c] = client.subscribe(PackedStringArray([
				"SELECT * FROM entity_transform WHERE " + where,
				"SELECT * FROM npc WHERE " + where,
				"SELECT * FROM monster WHERE " + where,
				"SELECT * FROM ground_item WHERE " + where]))
	for c in _cell_subs.keys():
		if not wanted.has(c):
			_cell_subs[c].unsubscribe()
			_cell_subs.erase(c)
	aoi_changed.emit(wanted.keys())
