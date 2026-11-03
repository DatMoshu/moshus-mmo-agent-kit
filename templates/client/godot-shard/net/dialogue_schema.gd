## Dialogue wire compatibility gate (task1578, DIALOGUE-ID-COMPAT sections3/5 D11).
## Original implementation, ultima-mmo-worker-night9, 2026-11-03; no outside engine sources.
class_name DialogueSchema
extends RefCounted

static func _field(fields: Array, name: String) -> Dictionary:
    for field in fields:
        if field is Dictionary and field.get("name", {}) is Dictionary and field.get("name", {}).get("some", "") == name:
            var kind = field.get("algebraic_type", {})
            return kind if kind is Dictionary else {}
    return {}

static func matches(schema: Variant, expected: StringName) -> bool:
    if not schema is Dictionary or not schema.get("sections", null) is Array:
        return false
    var types: Array = []
    var tables: Array = []
    var reducers: Array = []
    for section in schema["sections"]:
        if not section is Dictionary:
            return false
        if section.get("Typespace", null) is Dictionary:
            var values = section["Typespace"].get("types", [])
            if values is Array:
                types = values
        if section.get("Tables", null) is Array:
            tables = section["Tables"]
        if section.get("Reducers", null) is Array:
            reducers = section["Reducers"]
    var table_ok := false
    var reducer_ok := false
    for table in tables:
        if not table is Dictionary or table.get("source_name", "") != "npc_meta":
            continue
        var ref = table.get("product_type_ref", -1)
        if typeof(ref) != TYPE_FLOAT and typeof(ref) != TYPE_INT:
            return false
        if not is_finite(float(ref)) or float(ref) != float(int(ref)):
            return false
        if int(ref) < 0 or int(ref) >= types.size() or not types[int(ref)] is Dictionary:
            return false
        var product = types[int(ref)].get("Product", {})
        if not product is Dictionary or not product.get("elements", null) is Array:
            return false
        table_ok = _field(product["elements"], "talk").has(String(expected))
    for reducer in reducers:
        if not reducer is Dictionary or reducer.get("source_name", "") != "seed_npcs":
            continue
        var params = reducer.get("params", {})
        if not params is Dictionary or not params.get("elements", null) is Array:
            return false
        var array = _field(params["elements"], "talk").get("Array", {})
        reducer_ok = array is Dictionary and array.has(String(expected))
    return table_ok and reducer_ok
