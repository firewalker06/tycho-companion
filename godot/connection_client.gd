class_name ConnectionClient
extends Node

const StateMapperScript := preload("res://state_mapper.gd")

## Read-only Tycho transport. Tokens live only in this node's private field and are
## deliberately excluded from signals, snapshots, persisted settings, and errors.

signal status_changed(status: String, message: String)
signal snapshot_received(activity: Dictionary, resources: Dictionary, refreshed_at: String)
signal connection_test_completed(report: Dictionary)

const SETTINGS_PATH := "user://tycho-companion.cfg"
const MAX_RETRIES := 3
const BASE_BACKOFF_SECONDS := 2.0
const MAX_BACKOFF_SECONDS := 30.0
const POLL_SECONDS := 15.0

var origin := ""
var _token := ""
var _status := "setup"
var _message := "No Tycho connection configured"
var _generation := 0
var _retry_count := 0
var _next_refresh_at := 0
var _pending := 0
var _activity: Dictionary = {}
var _resources: Dictionary = {}
var _connection_test_generation := 0
var _connection_test_pending := 0
var _connection_test_results: Dictionary = {}
var _connection_test_requests: Array[HTTPRequest] = []

func _ready() -> void:
	_load_origin()
	var env_origin := OS.get_environment("TYCHO_ORIGIN").strip_edges()
	var env_token := OS.get_environment("TYCHO_TOKEN")
	if not env_origin.is_empty() and StateMapperScript.is_safe_origin(env_origin):
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
	if not StateMapperScript.is_safe_origin(clean_origin):
		return {"ok": false, "error": "Use localhost, 127.0.0.1, or a single-label/.ts.net HTTPS Tycho origin."}
	if next_token.strip_edges().is_empty():
		return {"ok": false, "error": "A bearer token is required."}
	_cancel_connection_test()
	origin = clean_origin
	_token = next_token
	_persist_origin()
	_retry_count = 0
	_generation += 1
	_refresh_generation(_generation)
	return {"ok": true}

func disconnect_live() -> void:
	_cancel_connection_test()
	_generation += 1
	_token = ""
	_retry_count = 0
	_pending = 0
	_activity = {}
	_resources = {}
	_set_status("setup", "Disconnected. Configure Tycho to show live activity.")

func refresh() -> void:
	if not has_live_configuration() or _pending > 0:
		return
	_generation += 1
	_refresh_generation(_generation)

func test_connection() -> Dictionary:
	## Probe both read-only endpoints without changing the live connection state,
	## retry budget, polling generation, or current scene snapshot.
	if not has_live_configuration():
		var unavailable := {"ok": false, "started": false, "message": "Connect to Tycho before running the connection test.", "endpoints": {}}
		connection_test_completed.emit(unavailable)
		return unavailable
	_cancel_connection_test()
	_connection_test_generation += 1
	_connection_test_pending = 2
	_connection_test_results = {}
	var generation := _connection_test_generation
	_connection_test_request("/servers/activity", generation)
	_connection_test_request("/servers/resources", generation)
	return {"ok": true, "started": true, "message": "Testing both read-only Tycho endpoints.", "endpoints": {}}

func _connection_test_request(path: String, generation: int) -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	_connection_test_requests.append(request)
	var started_at := Time.get_ticks_msec()
	request.request_completed.connect(_on_connection_test_request_completed.bind(request, generation, path, started_at))
	var result := request.request(origin + path, authorization_headers(_token), HTTPClient.METHOD_GET)
	if result != OK:
		_on_connection_test_request_completed(result, 0, PackedStringArray(), PackedByteArray(), request, generation, path, started_at)

func _on_connection_test_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, generation: int, path: String, started_at: int) -> void:
	_connection_test_requests.erase(request)
	if is_instance_valid(request):
		request.queue_free()
	if generation != _connection_test_generation:
		return
	var valid_json := false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var json := JSON.new()
		valid_json = json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and valid_json
	var message := "Endpoint returned a JSON object." if ok else _generic_http_error(result, response_code)
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and not valid_json:
		message = "Endpoint returned unreadable JSON."
	_connection_test_results[path] = {
		"ok": ok,
		"status_code": response_code,
		"duration_ms": maxi(0, Time.get_ticks_msec() - started_at),
		"message": message,
	}
	_connection_test_pending -= 1
	if _connection_test_pending == 0:
		connection_test_completed.emit(connection_test_report(_connection_test_results))

func _cancel_connection_test() -> void:
	_connection_test_generation += 1
	_connection_test_pending = 0
	_connection_test_results = {}
	for request in _connection_test_requests:
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_connection_test_requests.clear()

static func connection_test_report(results: Dictionary) -> Dictionary:
	var expected := ["/servers/activity", "/servers/resources"]
	var ok := true
	for path in expected:
		if not results.has(path) or results[path].get("ok", false) != true:
			ok = false
	return {
		"ok": ok,
		"started": false,
		"message": "Connection test passed: both read-only endpoints returned JSON." if ok else "Connection test failed; inspect the endpoint results below.",
		"endpoints": results.duplicate(true),
	}

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
	var decision := retry_decision(_retry_count)
	if decision.status == "offline":
		_set_status("offline", "%s Reconnect from Settings." % reason)
		return
	_next_refresh_at = Time.get_ticks_msec() + int(decision.delay_seconds * 1000.0)
	_set_status("retrying", "%s Retrying in %d seconds." % [reason, int(decision.delay_seconds)])

static func retry_decision(attempt: int) -> Dictionary:
	## Attempts are one-based failed refreshes. The third failure is terminal;
	## reconnect_live is the only path that resets the retry budget.
	if attempt >= MAX_RETRIES:
		return {"status": "offline", "delay_seconds": 0.0}
	var delay := minf(MAX_BACKOFF_SECONDS, BASE_BACKOFF_SECONDS * pow(2.0, maxf(0.0, attempt - 1)))
	return {"status": "retrying", "delay_seconds": delay}

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
		if StateMapperScript.is_safe_origin(saved_origin):
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
