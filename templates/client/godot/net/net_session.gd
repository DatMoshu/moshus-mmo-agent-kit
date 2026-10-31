## NetSession: the ONE seam between gameplay code and the SpacetimeDB GDScript SDK.
## Gameplay code calls intent methods (join, send_move) and reads the local cache
## through helpers here. Nothing else in the game touches SpacetimeDB.* directly,
## so an SDK upgrade/fork or a bot client only has to change this file.
##
## AOI: one subscription PER CELL (non-overlapping queries). The GDScript SDK does not
## ref-count overlapping subscriptions, and unsubscribe() does not send dropped rows,
## so we also filter reads by the current cell set (rows from cells we left go stale).
extends Node

signal session_connected(identity_hex: String)
signal session_disconnected
signal joined_world
signal aoi_changed(cells: Array)

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
var _cell_subs := {} # Vector2i -> SpacetimeDBSubscription
var _cell_size := 50.0
var _callbacks_registered := false


func _ready() -> void:
	client = SpacetimeDB.Mmo
	client.connected.connect(_on_connected)
	client.disconnected.connect(func(): session_disconnected.emit())
	client.connection_error.connect(func(code, reason): push_warning("NetSession connection error %s: %s" % [code, reason]))


func connect_to_server(url: String = server_url, db: String = database, p_profile: String = profile) -> void:
	server_url = url
	database = db
	profile = p_profile
	var options := SpacetimeDBConnectionOptions.new()
	options.compression = SpacetimeDBConnectionOptions.CompressionPreference.NONE # no Brotli in this SDK
	options.threading = true
	options.one_time_token = profile.is_empty() # fresh identity per run unless a profile is used
	options.save_token = false # NetSession owns token storage (per profile)
	if not profile.is_empty():
		var path := _token_path()
		if FileAccess.file_exists(path):
			options.token = FileAccess.get_file_as_string(path).strip_edges()
	client.connect_db(server_url, database, options)


func _token_path() -> String:
	return "user://identity_%s.token" % profile


func _on_connected(identity: PackedByteArray, token: String) -> void:
	my_identity = identity
	if not _callbacks_registered: # client.db only exists once the SDK has initialized
		_callbacks_registered = true
		client.db.entity_transform.on_insert(_on_transform)
		client.db.entity_transform.on_update(func(_old, row): _on_transform(row))
	if not profile.is_empty():
		var f := FileAccess.open(_token_path(), FileAccess.WRITE)
		if f:
			f.store_string(token)
			f.close()
	# Small, global tables: config, player roster, server health, and my own transform.
	var hex := identity.hex_encode()
	var sub := client.subscribe(PackedStringArray([
		"SELECT * FROM world_config",
		"SELECT * FROM player",
		"SELECT * FROM tick_health",
		"SELECT * FROM entity_transform WHERE identity = 0x%s" % hex,
	]))
	await sub.wait_for_applied(10)
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


func my_transform() -> MmoEntityTransform:
	return client.db.entity_transform.identity.find(my_identity) if not my_identity.is_empty() else null


## Transforms inside the current AOI (filters stale rows from cells we left).
func visible_transforms() -> Array[MmoEntityTransform]:
	var out: Array[MmoEntityTransform] = []
	for t in client.db.entity_transform.iter():
		if abs(t.cell_x - _cell.x) <= AOI_RADIUS and abs(t.cell_y - _cell.y) <= AOI_RADIUS:
			out.append(t)
	return out


func player_name(identity: PackedByteArray) -> String:
	var p = client.db.player.identity.find(identity)
	return p.name if p else "?"


func is_me(identity: PackedByteArray) -> bool:
	return identity == my_identity


func _on_transform(row: MmoEntityTransform) -> void:
	if row.identity == my_identity:
		_update_aoi(Vector2i(row.cell_x, row.cell_y))


func _update_aoi(cell: Vector2i) -> void:
	if cell == _cell:
		return
	_cell = cell
	var wanted := {}
	for dx in range(-AOI_RADIUS, AOI_RADIUS + 1):
		for dy in range(-AOI_RADIUS, AOI_RADIUS + 1):
			wanted[cell + Vector2i(dx, dy)] = true
	# Subscribe new cells first, then drop cells we left (no flicker).
	for c in wanted.keys():
		if not _cell_subs.has(c):
			_cell_subs[c] = client.subscribe(PackedStringArray([
				"SELECT * FROM entity_transform WHERE cell_x = %d AND cell_y = %d" % [c.x, c.y]]))
	for c in _cell_subs.keys():
		if not wanted.has(c):
			_cell_subs[c].unsubscribe()
			_cell_subs.erase(c)
	aoi_changed.emit(wanted.keys())
