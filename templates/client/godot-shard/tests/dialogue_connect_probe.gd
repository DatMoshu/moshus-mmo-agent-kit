## Synthetic delayed-HTTP probe loaded after autoload initialization.
extends "res://net/net_session.gd"
var requests: Array[HTTPRequest] = []
var urls: Array[String] = []
var connected: Array = []
var rejected: Array[String] = []
var notices := 0
var start_result: Error = OK
func _ready() -> void:
    schema_rejected.connect(func(reason): rejected.append(reason))
    session_disconnected.connect(func(): notices += 1)
func _new_schema_request() -> HTTPRequest:
    var request := HTTPRequest.new()
    requests.append(request)
    return request
func _start_schema_request(_request: HTTPRequest, url: String) -> Error:
    urls.append(url)
    return start_result
func _read_profile_token(p_profile: String) -> String:
    return "fabricated-" + p_profile
func _connect_checked(url: String, db: String, options: SpacetimeDBConnectionOptions) -> void:
    connected.append([url, db, _connected_profile, options.token])
func _disconnect_transport() -> void:
    pass
func completion(index: int) -> Callable:
    return requests[index].get_signal_connection_list("request_completed")[0]["callable"]
