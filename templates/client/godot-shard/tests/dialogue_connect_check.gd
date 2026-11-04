## Original synthetic task1578 R1 race regression; actual NetSession callback path.
## No sockets/tokens/game data: only fabricated schema bodies and token labels.
extends SceneTree


var checks := 0
var failures := 0
var probes: Array = []
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        print("CONNECT_RACE FAIL " + label)
func fresh():
    var p = load("res://tests/dialogue_connect_probe.gd").new()
    root.add_child(p)
    probes.append(p)
    return p
func body(kind: String = "U16") -> PackedByteArray:
    return JSON.stringify({"sections": [
        {"Typespace": {"types": [{"Product": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {kind: []}}]}}]}},
        {"Tables": [{"source_name": "npc_meta", "product_type_ref": 0}]},
        {"Reducers": [{"source_name": "seed_npcs", "params": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {"Array": {kind: []}}}]}}]}
    ]}).to_utf8_buffer()
func reply(cb: Callable, payload: PackedByteArray, result: int = HTTPRequest.RESULT_SUCCESS, status: int = 200) -> void:
    cb.call(result, status, PackedStringArray(), payload)
func begin(p, label: String) -> Callable:
    p.connect_to_server("http://" + label, "db-" + label, label)
    return p.completion(p.requests.size() - 1)
func _init() -> void:
    create_timer(15).timeout.connect(func(): print("CONNECT_RACE timeout"); quit(2))
    call_deferred("proof")
func proof() -> void:
    # Compatible A finishes while incompatible B is current: A never authorizes B.
    var p = fresh()
    var a := begin(p, "A")
    check(p.requests[0].timeout == 10.0 and p.requests[0].body_size_limit == 4 * 1024 * 1024, "request bounded")
    var b := begin(p, "B")
    check(p.requests[0].is_queued_for_deletion(), "superseded disposed")
    reply(a, body())
    check(p.connected.is_empty() and p.rejected.is_empty(), "late A before B ignored")
    reply(b, body("U8"))
    check(p.connected.is_empty() and p.rejected.size() == 1, "B mismatch only current rejection")
    reply(a, body())
    check(p.connected.is_empty() and p.rejected.size() == 1, "A after B rejection ignored")
    check(p._schema_request == null and p.requests[1].is_queued_for_deletion(), "failed disposed")
    # Reverse completion: B succeeds, late A successes/failures cannot change B or HUD.
    p = fresh(); a = begin(p, "A"); b = begin(p, "B")
    reply(b, body())
    check(p.connected == [["http://B", "db-B", "B", "fabricated-B"]], "B immutable endpoint profile token")
    reply(a, body()); reply(a, "bad error page".to_utf8_buffer(), HTTPRequest.RESULT_CANT_CONNECT, 503)
    check(p.connected.size() == 1 and p.rejected.is_empty(), "stale success and failure ignored")
    reply(b, body())
    check(p.connected.size() == 1, "duplicate completion ignored")
    # Shared defaults may change independently; callback still owns exact context A.
    p = fresh(); a = begin(p, "A")
    p.server_url = "http://other"; p.database = "other"; p.profile = "other"
    reply(a, body())
    check(p.connected == [["http://A", "db-A", "A", "fabricated-A"]], "no mutable defaults after response")
    # A stale failure and prior transport close/error cannot cancel a pending B schema.
    p = fresh(); a = begin(p, "A"); b = begin(p, "B")
    p._on_disconnected(); p._on_connection_error(1, "stale")
    reply(a, body(), HTTPRequest.RESULT_TIMEOUT)
    check(p.notices == 0 and p.rejected.is_empty(), "stale close failure quiet")
    reply(b, body())
    check(p.connected.size() == 1 and p.connected[0][1] == "db-B", "new B survives old events")
    # Explicit disconnect before any socket immediately invalidates pending HTTP.
    p = fresh(); a = begin(p, "A")
    p.disconnect_from_server(); reply(a, body())
    check(p.connected.is_empty() and p.rejected.is_empty(), "disconnect late success ignored")
    check(p._schema_request == null and p.requests[0].is_queued_for_deletion(), "disconnect disposes request")
    b = begin(p, "B"); reply(b, body())
    await process_frame
    check(p.notices == 0 and p.connected.size() == 1, "obsolete deferred disconnect suppressed")
    # Detach/teardown invalidates even a callback already queued for delivery.
    p = fresh(); a = begin(p, "A")
    root.remove_child(p); reply(a, body())
    check(p.connected.is_empty() and p.rejected.is_empty(), "teardown late response ignored")
    check(p._schema_request == null, "teardown invalidated")
    p.free()
    # Current transport/status/body errors fail once and cannot later reopen.
    for vector in [[HTTPRequest.RESULT_TIMEOUT, 200, body()], [HTTPRequest.RESULT_SUCCESS, 503, "<bad>".to_utf8_buffer()], [HTTPRequest.RESULT_SUCCESS, 200, PackedByteArray()], [HTTPRequest.RESULT_SUCCESS, 200, "{bad".to_utf8_buffer()]]:
        p = fresh(); a = begin(p, "A")
        reply(a, vector[2], vector[0], vector[1]); reply(a, body())
        check(p.connected.is_empty() and p.rejected.size() == 1, "current malformed response refuses once")
        check(p._schema_request == null, "current failure clears request")
    p = fresh(); p.start_result = ERR_CANT_CONNECT; a = begin(p, "A")
    reply(a, body())
    check(p.connected.is_empty() and p.rejected.size() == 1, "start failure cannot reconnect late")
    # Complete a disconnect with no superseding call.
    p = fresh(); a = begin(p, "A"); p.disconnect_from_server()
    await process_frame
    check(p.notices == 1 and p.connected.is_empty(), "explicit disconnect notice exactly once")
    for probe in probes:
        if is_instance_valid(probe):
            probe.queue_free()
    await process_frame
    print("CONNECT_RACE %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
    quit(0 if failures == 0 else 1)
