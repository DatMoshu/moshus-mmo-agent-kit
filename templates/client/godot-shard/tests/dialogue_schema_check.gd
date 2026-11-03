## Original synthetic task1578 wire-schema regression; accepted DIALOGUE-ID-COMPAT D11.
extends SceneTree
var count := 0
func check(value: bool) -> void:
    assert(value)
    count += 1
func schema(table: String, reducer: String) -> Dictionary:
    return {"sections": [
        {"Typespace": {"types": [{"Product": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {table: []}}]}}]}},
        {"Tables": [{"source_name": "npc_meta", "product_type_ref": 0}]},
        {"Reducers": [{"source_name": "seed_npcs", "params": {"elements": [{"name": {"some": "talk"}, "algebraic_type": {"Array": {reducer: []}}}]}}]}
    ]}
func _init() -> void:
    check(DialogueSchema.matches(schema("U16", "U16"), &"U16"))
    check(DialogueSchema.matches(schema("U8", "U8"), &"U8"))
    check(not DialogueSchema.matches(schema("U8", "U8"), &"U16"))
    check(not DialogueSchema.matches(schema("U16", "U16"), &"U8"))
    check(not DialogueSchema.matches(schema("U16", "U8"), &"U16"))
    check(not DialogueSchema.matches(schema("U8", "U16"), &"U16"))
    for bad in [null, [], {}, {"sections": []}, {"sections": [null]}]:
        check(not DialogueSchema.matches(bad, &"U16"))
    var fractional := schema("U16", "U16")
    fractional["sections"][1]["Tables"][0]["product_type_ref"] = 0.5
    check(not DialogueSchema.matches(fractional, &"U16"))
    check(MmoNpcMeta.BSATN_TYPES[&"talk"] == &"U16")
    print("DIALOGUE_SCHEMA PASS checks=%d" % count)
    quit(0)
