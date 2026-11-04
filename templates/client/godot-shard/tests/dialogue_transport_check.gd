## Original task1578 R3 deterministic actual NetSession transport-ownership regression.
extends SceneTree
var checks := 0
var failures := 0
var probes: Array = []
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        print("TRANSPORT_OWNER FAIL " + label)
func fresh():
    var p = load("res://tests/dialogue_transport_probe.gd").new()
    root.add_child(p)
    probes.append(p)
    return p
func body() -> PackedByteArray:
    return JSON.stringify({"sections": [
        {"Typespace": {"types": [{"Product": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {"U16": []}}]}}]}},
        {"Tables": [{"source_name": "npc_meta", "product_type_ref": 0}]},
        {"Reducers": [{"source_name": "seed_npcs", "params": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {"Array": {"U16": []}}}]}}]}
    ]}).to_utf8_buffer()
func start(p, label: String) -> void:
    p.connect_to_server("http://" + label, "db-" + label, label)
func schema(p) -> void:
    p.completion(p.requests.size() - 1).call(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body())
func _init() -> void:
    create_timer(15).timeout.connect(func(): print("TRANSPORT_OWNER timeout"); quit(2))
    call_deferred("proof")
func proof() -> void:
    # Exercise the actual unmodified pinned low-level connecting guard without sockets.
    var guard := SpacetimeDBConnection.new(SpacetimeDBConnectionOptions.new(), "synthetic")
    guard._connection_requested = true
    guard._target_url = "fabricated-A"
    guard.connect_to_database("http://B", "db-B", "fake-connection-id", false)
    check(guard._target_url == "fabricated-A" and guard._connection_requested, "actual pinned guard retains pending A")
    guard._connection_requested = false
    guard.free()
    # Model shows why a second connect_db call is forbidden, even before a socket opens.
    var model = fresh()
    var oa := SpacetimeDBConnectionOptions.new(); oa.token = "fabricated-A"
    var ob := SpacetimeDBConnectionOptions.new(); ob.token = "fabricated-B"
    model._connect_checked("http://A", "db-A", oa)
    model._connect_checked("http://B", "db-B", ob)
    check(model.sdk_fields[0] == "http://B" and model.selected[0] == "http://A" and model.sdk_refusals == 1, "model reproduces metadata/socket disagreement")
    # Product seam: B refuses before HTTP/SDK mutation; valid A retains A ownership.
    var p = fresh(); start(p, "A"); schema(p)
    check(p.sdk_pending and p.sdk_calls == 1, "A pending initial message")
    check(p._transport_owner.is_read_only() and p._transport_owner["profile"] == "A", "immutable actual owner")
    start(p, "B")
    check(p.requests.size() == 1 and p.sdk_calls == 1 and p.rejected.size() == 1, "overlap rejected before any B request or SDK mutation")
    check(p.sdk_fields == ["http://A", "db-A", "fabricated-A"] and p.profile == "A", "SDK endpoint token and defaults still A")
    p.initial()
    check(p.writes == {"A": "fabricated-issued-A"} and p.accepted == ["A"], "late A persists only A and authorizes only A")
    check(not p.writes.has("B"), "no cross-profile token file")
    start(p, "B")
    check(p.sdk_calls == 1, "active overlap refused too")
    # Defence if an already queued current B schema callback reaches the SDK boundary.
    p = fresh(); start(p, "A"); schema(p)
    var req := HTTPRequest.new(); p.add_child(req); p._schema_request = req
    p._on_schema_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body(), p._connect_generation, req, "http://B", "db-B", "B", ob)
    check(p.sdk_calls == 1 and p._transport_owner["profile"] == "A", "queued B schema cannot replace owner")
    p.initial()
    check(p.writes.is_empty() and p.accepted.is_empty() and p.disconnect_calls == 1, "invalidated A closed without token/session")
    # Cancel while initializing: no false cancellation/terminal notice; B remains refused.
    p = fresh(); start(p, "A"); schema(p); p.disconnect_from_server()
    check(p.sdk_pending and p.disconnect_calls == 0 and p.notices == 0, "public SDK cannot cancel connecting state")
    start(p, "B")
    check(p.sdk_calls == 1 and p.sdk_fields[0] == "http://A", "cancel pending owner remains latched")
    p.initial()
    check(p.disconnect_calls == 1 and p.writes.is_empty() and p.accepted.is_empty(), "late initial after cancel closes no persistence")
    p.terminal()
    start(p, "A")
    check(p.sdk_calls == 1 and not p._transport_owner.is_empty(), "no reentry in SDK terminal emitting stack")
    await process_frame
    await process_frame
    check(p._transport_owner.is_empty() and p.notices == 1, "observed disconnected plus frame releases owner once")
    start(p, "B")
    check(p.sdk_calls == 1, "fresh process required for SDK cached endpoint/profile change")
    start(p, "A"); schema(p)
    check(p.sdk_calls == 2 and p.sdk_pending, "same binding can reconnect only after terminal")
    # Error alone is not a proven idle boundary; paired disconnected releases later.
    p = fresh(); start(p, "A"); schema(p)
    p._on_connection_error(1, "synthetic pending failure")
    start(p, "B"); p.initial()
    check(p.sdk_calls == 1 and p.writes.is_empty() and p.accepted.is_empty(), "late initial after error never writes or authorizes")
    check(not p._transport_owner.is_empty(), "error alone retains owner")
    p.terminal()
    await process_frame
    await process_frame
    check(p._transport_owner.is_empty(), "error then disconnect terminal release")
    # Bounded user-visible outcome without pretending timeout cancels the pending SDK.
    p = fresh(); start(p, "A"); schema(p)
    p._transport_timed_out(p._transport_owner)
    start(p, "B"); p.initial()
    check(p.sdk_calls == 1 and p.writes.is_empty() and p.accepted.is_empty(), "timeout fail-closed still owns pending A")
    check(p.rejected.size() == 2 and not p._transport_owner.is_empty(), "timeout has explicit restart outcome")
    # Teardown cannot persist a late event's token.
    p = fresh(); start(p, "A"); schema(p)
    root.remove_child(p); p.initial()
    check(p.writes.is_empty() and p.accepted.is_empty() and p.disconnect_calls == 1, "teardown late initialization closes without writes")
    p.free()
    for probe in probes:
        if is_instance_valid(probe): probe.queue_free()
    await process_frame
    print("TRANSPORT_OWNER %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
    quit(0 if failures == 0 else 1)
