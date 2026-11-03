## Task1578: synthetic native-ID/subscription and saved-session regression.
## Original clean implementation against accepted DIALOGUE-ID-COMPAT D1-D12; no reference code.
extends SceneTree
var failed := 0
var args: PackedStringArray
var net: Node
func check(ok: bool, label: String) -> void:
    if not ok:
        failed += 1
        print("DIALOGUE_LIVE FAIL %s" % label)
func _init() -> void:
    call_deferred("proof")
func proof() -> void:
    args = OS.get_cmdline_user_args()
    create_timer(40).timeout.connect(func(): print("DIALOGUE_LIVE timeout"); quit(2))
    net = root.get_node("Net")
    if "--mismatch" in args:
        net.schema_rejected.connect(func(_s): print("DIALOGUE_MISMATCH refused=1"); quit(0))
        net.session_connected.connect(func(_s): print("DIALOGUE_MISMATCH unsafe=1"); quit(1))
        net.connect_to_server(args[0], args[1], args[3])
        return
    if "--denied" in args:
        net.client.connection_error.connect(func(_code, _reason): print("DIALOGUE_AUTH denied=1"); quit(0))
        net.session_connected.connect(func(_s): print("DIALOGUE_AUTH unsafe=1"); quit(1))
        net.connect_to_server(args[0], args[1], args[3])
        return
    net.connect_to_server(args[0], args[1], args[3])
    var identity: String = await net.session_connected
    print("DIALOGUE_IDENTITY %s" % identity)
    var error: String = await net.join(args[3])
    check(error == "", "join")
    var source := DocSource.new()
    check(source.load_doc(args[2]), "load fixture")
    var expected := [0, 15, 255, 256, 319, 1025, 1430, 65535]
    var hud := Hud.new()
    root.add_child(hud)
    await process_frame
    for slot in expected.size():
        var meta = net.npc_meta(slot)
        check(meta != null, "metadata")
        if meta == null:
            continue
        check(meta.talk == expected[slot], "native ID")
        var talk = source.start_talk(0, meta.talk)
        if meta.talk == 0:
            check(talk == null, "zero sentinel")
        else:
            check(talk != null, "dispatch")
            if talk != null:
                hud.show_talk(talk.title, talk.open(), false)
                check(hud.talk_text().length() > 0, "HUD")
                talk.reply("BYE")
                check(talk.done, "close")
        print("DIALOGUE_DISPATCH slot=%d talk=%d" % [slot, meta.talk])
    await create_timer(3).timeout
    print("DIALOGUE_PEERS count=%d" % net.client.db.player.iter().size())
    if "--reconnect" in args:
        net.client.disconnect_db()
        await net.session_disconnected
        await create_timer(0.25).timeout
        net.connect_to_server(args[0], args[1], args[3])
        var again: String = await net.session_connected
        check(again == identity, "reconnect identity")
        check(await net.join(args[3]) == "", "rejoin")
        check(net.npc_meta(5).talk == 1025, "reconnect ID")
        print("DIALOGUE_RECONNECT same=1 talk=%d" % net.npc_meta(5).talk)
    net.client.disconnect_db()
    await create_timer(0.5).timeout
    print("DIALOGUE_LIVE %s failures=%d" % ["PASS" if failed == 0 else "FAIL", failed])
    quit(0 if failed == 0 else 1)
