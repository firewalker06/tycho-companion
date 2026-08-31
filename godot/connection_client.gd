class_name ConnectionClient
extends Node

## Read-only Tycho transport. Tokens live only in this node's private field and are
## deliberately excluded from signals, snapshots, persisted settings, and errors.

signal status_changed(status: String, message: String)
signal snapshot_received(activity: Dictionary, resources: Dictionary, refreshed_at: String)

const SETTINGS_PATH := "user://tycho-companion.cfg"
const MAX_RETRIES := 3
const BASE_BACKOFF_SECONDS := 2.0
const POLL_SECONDS := 15.0

var origin := ""
var _token := ""
var _status := "demo"
var _message := "Demo activity"
var _generation := 0
var _retry_count := 0
var _next_refresh_at := 0
var _pending := 0
var _activity: Dictionary = {}
var _resources: Dictionary = {}

func _ready() -> void:
	_load_origin()
	var env_origin := OS.get_environment("TYCHO_ORIGIN").strip_edges()
	var env_token := OS.get_environment("TYCHO_TOKEN")
	if not env_origin.is_empty() and StateMapper.is_safe_origin(env_origin):
		origin = env_origin
	if not env_token.is_empty():
		_token = env_token
	if not origin.is_empty() and not _token.is_empty():
		connect_live(origin, _token)

func _process(_delta: float) -> void:
	if has_live_configuration() and (_status == "connected" or _status == "retrying") and Time.get_ticks_msec() >= _next_refresh_at:
		refresh()

func initial_origin() -> String:
	return origin

func has_live_configuration() -> bool:
	return not origin.is_empty() and not _token.is_empty()

func connection_status() -> String:
	return _status

func connection_message() -> String:
	return _message

func connect_live(next_origin: String, next_token: String) -> Dictionary:
	var clean_origin := next_origin.strip_edges()
	if not StateMapper.is_safe_origin(clean_origin):
		return {"ok": false, "error": "Use localhost, 127.0.0.1, or a single-label/.ts.net HTTPS Tycho origin."}
	if next_token.strip_edges().is_empty():
		return {"ok": false, "error": "A bearer token is required."}
	origin = clean_origin
	_token = next_token
	_persist_origin()
	_retry_count = 0
	_generation += 1
	_refresh_generation(_generation)
	return {"ok": true}

func disconnect_live() -> void:
	_generation += 1
	_token = ""
	_retry_count = 0
	_pending = 0
	_activity = {}
	_resources = {}
	_set_status("demo", "Disconnected — showing local demo activity")

func refresh() -> void:
	if not has_live_configuration() or _pending > 0:
		return
	_generation += 1
	_refresh_generation(_generation)

func _refresh_generation(generation: int) -> void:
	_pending = 2
	_activity = {}
	_resources = {}
	_set_status("connecting", "Refreshing Tycho")
	_request("/servers/activity", generation, true)
	_request("/servers/resources", generation, false)

func _request(path: String, generation: int, is_activity: bool) -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(request, generation, is_activity))
	var result := request.request(origin + path, authorization_headers(_token), HTTPClient.METHOD_GET)
	if result != OK:
		_on_request_completed(result, 0, PackedStringArray(), PackedByteArray(), request, generation, is_activity)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, generation: int, is_activity: bool) -> void:
	request.queue_free()
	if generation != _generation:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_connection_failed(_generic_http_error(result, response_code))
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		_connection_failed("Tycho returned an unreadable response.")
		return
	if is_activity:
		_activity = json.data
	else:
		_resources = json.data
	_pending -= 1
	if _pending == 0:
		_retry_count = 0
		_next_refresh_at = Time.get_ticks_msec() + int(POLL_SECONDS * 1000.0)
		_set_status("connected", "Live Tycho data")
		snapshot_received.emit(_activity, _resources, Time.get_datetime_string_from_system())

func _connection_failed(reason: String) -> void:
	_generation += 1
	_pending = 0
	_retry_count += 1
	if _retry_count <= MAX_RETRIES:
		var delay := minf(30.0, BASE_BACKOFF_SECONDS * pow(2.0, _retry_count - 1))
		_next_refresh_at = Time.get_ticks_msec() + int(delay * 1000.0)
		_set_status("retrying", "%s Retrying in %d seconds." % [reason, int(delay)])
	else:
		_set_status("offline", "%s Reconnect from Settings." % reason)

func _set_status(next_status: String, next_message: String) -> void:
	_status = next_status
	_message = next_message
	status_changed.emit(_status, _message)

func _generic_http_error(result: int, response_code: int) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Tycho could not be reached."
	if response_code == 401 or response_code == 403:
		return "Tycho rejected the credentials."
	return "Tycho returned HTTP %d." % response_code

func _load_origin() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var saved_origin := str(settings.get_value("connection", "origin", ""))
		if StateMapper.is_safe_origin(saved_origin):
			origin = saved_origin

func _persist_origin() -> void:
	var settings := ConfigFile.new()
	settings.set_value("connection", "origin", origin)
	settings.save(SETTINGS_PATH)

static func authorization_headers(token: String) -> PackedStringArray:
	# Keep construction here: callers receive headers, never a token-bearing request model.
	return PackedStringArray(["Authorization: Bearer " + token])

static func redact_secret(value: String, secret: String) -> String:
	if secret.is_empty():
		return value
	return value.replace(secret, "[redacted]")
