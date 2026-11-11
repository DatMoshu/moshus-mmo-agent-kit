## Synthetic regression for map-change/respawn AOI ownership and delayed town NPCs.
## No server, sockets, tokens, artwork or consumer data. Uses the actual Net and route methods.
## godot --headless --path templates/client/godot-shard -s res://tests/shard_regression_check.gd
extends SceneTree

class CellSubscription extends SpacetimeDBSubscription:
	var on_drop: Callable
	func unsubscribe() -> Error:
		on_drop.call(queries)
		return OK

class ProbeClient extends MmoModuleClient:
	var captured: Array[PackedStringArray] = []
	var handles: Array[CellSubscription] = []
	var dropped := 0
	var own: PackedByteArray
	var cache: LocalDatabase
	func subscribe(query: PackedStringArray) -> SpacetimeDBSubscription:
		captured.append(query)
		var handle := CellSubscription.new()
		handle.queries = query
		handle.on_drop = drop_rows
		handles.append(handle)
		return handle
	func drop_rows(query: PackedStringArray) -> void:
		dropped += 1
		# Model a late cell deletion for a row formerly covered by that query. The pinned
		# SDK has no overlapping-subscription refcount; exclusion must protect the self row.
		if not query[0].contains("identity != 0x" + own.hex_encode()):
			var row = cache.get_row_by_pk("entity_transform", own)
			if row != null:
				var update := TableUpdateData.new()
				update.table_name = "entity_transform"
				update.deletes.append(row)
				cache.emit_db_callbacks([cache.apply_table_update(update)])

var net: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("SHARD_REGRESSION FAIL " + label)

func _init() -> void:
	create_timer(15).timeout.connect(func(): print("SHARD_REGRESSION timeout"); quit(2))
	call_deferred("proof")

func put(cache: LocalDatabase, table: String, row: _ModuleTableType) -> void:
	var update := TableUpdateData.new()
	update.table_name = table
	update.inserts.append(row)
	cache.emit_db_callbacks([cache.apply_table_update(update)])

func proof() -> void:
	net = root.get_node("Net")
	var original: MmoModuleClient = net.client
	var client := ProbeClient.new()
	client.own = PackedByteArray([1, 2, 3])
	var schema := SpacetimeDBSchema.new("Mmo", original.schema_path, false)
	var cache := LocalDatabase.new(schema, client)
	client.cache = cache
	client._init_db(cache)
	net.client = client
	net.my_identity = client.own
	var row := MmoEntityTransform.create(client.own, 1, 12.5, 10.5, 0, 0, false, 0)
	put(cache, "entity_transform", row)
	net._on_transform(row)
	check(client.captured.size() == 9, "town AOI subscribes nine cells")
	for query in client.captured:
		check(query[0].contains("identity != 0x" + client.own.hex_encode()), "cell excludes dedicated self identity")
		check(query[0].contains("map_id = 1"), "cell is map scoped")
	check(net.my_transform() == row, "positive control self row exists before death")
	# Death/respawn changes maps within one authoritative update. Old cell removals
	# arrive after the identity-owned row already contains the new spawn position.
	var respawn := MmoEntityTransform.create(client.own, 0, 20.5, 32.5, 0, 1, false, 5)
	put(cache, "entity_transform", respawn)
	net._on_transform(respawn)
	check(client.dropped == 9, "old town cells actually unsubscribe")
	check(net.my_transform() == respawn, "self survives late old-cell deletes after respawn")
	check(net.current_map() == 0 and net._last_dir == Vector2i.ZERO, "respawn resets map and intent")
	# A subsequent same-map cell crossing must preserve the identity subscription too.
	respawn.cell_x = 1
	net._on_transform(respawn)
	check(client.dropped > 9 and net.my_transform() == respawn, "self survives ordinary cell crossing")
	var route = load("res://tests/shard_route_probe.gd").new()
	root.add_child(route)
	route._route = "play"
	route._phase = "talk_walk"
	route._phase_ms = Time.get_ticks_msec()
	route._play["kills0"] = 0
	var stats := MmoPlayerStats.new()
	stats.identity = client.own
	put(cache, "player_stats", stats)
	for frame in 3:
		route._route_play()
		await process_frame
	check(route._phase == "talk_walk" and route.plans == 0, "empty delayed NPC subscription waits across frames")
	var npc := MmoNpc.new()
	npc.id = 1; npc.map_id = 0; npc.cell_x = 1; npc.cell_y = 1
	npc.x = respawn.x + 4; npc.y = respawn.y; npc.tile = 64
	put(cache, "npc", npc)
	route._route_play()
	check(route._phase == "talk_walk" and route.plans == 0, "NPC before metadata still waits")
	var meta := MmoNpcMeta.new()
	meta.id = 1; meta.map_id = 0; meta.talk = 1
	put(cache, "npc_meta", meta)
	route._route_play()
	check(route._phase == "talk_walk" and route.plans == 1 and route.follows == 1, "delayed talking NPC resumes real route planning")
	cache._tables["npc"].clear()
	route._phase_ms = Time.get_ticks_msec() - 31000
	route._route_play()
	check(route._phase == "leave_town", "missing NPC remains bounded by thirty-second timeout")
	route.free()
	net._cell_subs.clear()
	net.client = original
	net.my_identity = PackedByteArray()
	for handle in client.handles:
		handle.free()
	cache.free()
	client.free()
	print("SHARD_REGRESSION %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
