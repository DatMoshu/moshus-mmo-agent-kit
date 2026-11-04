## Original task1578 R3 delayed SDK model. No networking or real credentials.
## Models pinned connect_db metadata mutation followed by connection_requested refusal.
extends "res://tests/dialogue_connect_probe.gd"
var sdk_calls := 0
var sdk_refusals := 0
var sdk_pending := false
var sdk_connected := false
var sdk_fields: Array = []
var selected: Array = []
var disconnect_calls := 0
var writes: Dictionary = {}
var accepted: Array = []
func _connect_checked(url: String, db: String, options: SpacetimeDBConnectionOptions) -> void:
    sdk_calls += 1
    sdk_fields = [url, db, options.token]
    if sdk_pending or sdk_connected:
        sdk_refusals += 1
        return
    sdk_pending = true
    selected = sdk_fields.duplicate()
func _disconnect_transport() -> void:
    # Mirrors the supported public disconnect_db guard: cannot cancel pending SDK init.
    if sdk_connected:
        disconnect_calls += 1
func _persist_profile_token(p_profile: String, token: String) -> void:
    writes[p_profile] = token
func _subscribe_connected(_identity: PackedByteArray, owner: Dictionary) -> void:
    accepted.append(owner["profile"])
    session_connected.emit("fabricated-identity")
func initial() -> void:
    sdk_pending = false
    sdk_connected = true
    _on_connected(PackedByteArray([1]), "fabricated-issued-A")
func terminal() -> void:
    # Actual SDK emits disconnected before clearing its requested/connected flags.
    _on_disconnected()
    sdk_pending = false
    sdk_connected = false
