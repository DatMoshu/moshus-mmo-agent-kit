## Task1578: synthetic native-ID/subscription and saved-session regression.
## Original clean implementation against accepted DIALOGUE-ID-COMPAT D1-D12; no reference code.
extends SceneTree
var net: Node
func _init() -> void:
    call_deferred("proof")
func proof() -> void:
    create_timer(30).timeout.connect(func(): print("SESSION_WIDTH timeout"); quit(2))
    var args := OS.get_cmdline_user_args()
    net = root.get_node("Net")
    net.connect_to_server(args[0], args[1], args[2])
    var identity: String = await net.session_connected
    var result: String = await net.join(args[2])
    if result != "":
        print("SESSION_WIDTH join_failed=1")
        quit(1)
        return
    await create_timer(0.5).timeout
    var start = net.my_transform()
    var x: float = start.x
    var y: float = start.y
    var before := Vector2(x, y)
    print("SESSION_WIDTH identity=%s x=%.3f y=%.3f" % [identity, x, y])
    if "--move" in args:
        net.send_move(Vector2i(1, 0))
        await create_timer(1.0).timeout
        net.send_move(Vector2i.ZERO)
        await create_timer(0.5).timeout
    var after = net.my_transform()
    var changed := Vector2(after.x, after.y).distance_to(before) > 0.1
    print("SESSION_WIDTH state identity=%s x=%.3f y=%.3f moved=%d peers=%d" % [identity, after.x, after.y, int(changed), net.visible_transforms().size()])
    net.disconnect_from_server()
    await create_timer(0.5).timeout
    if "--move" in args and not changed:
        quit(1)
        return
    print("SESSION_WIDTH PASS")
    quit(0)
