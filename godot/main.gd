extends Node2D

const StateMapperScript := preload("res://state_mapper.gd")

const STRIP_HEIGHT := 160.0
const DEMO := [
	{"server": "Demo shore", "project": "harbor", "agent": "Harbor keeper", "state": "running", "unread": false, "stale": false},
	{"server": "Demo shore", "project": "lantern", "agent": "Lantern keeper", "state": "idle", "unread": true, "stale": false},
	{"server": "Demo shore", "project": "gate", "agent": "Gate keeper", "state": "awaiting-input", "unread": false, "stale": false},
	{"server": "Demo shore", "project": "weather", "agent": "Weather keeper", "state": "blocked", "unread": false, "stale": false},
]

# Hooks for the later illustration pass. The MVP intentionally draws procedural
# placeholders and never depends on a final artwork file.
const ASSET_SLOTS := {"shoreline": "", "workshop": "", "state_cues": ""}

@onready var client: ConnectionClient = $ConnectionClient

var tide := 0.0
var agents: Array[Dictionary] = []
var last_refresh := "Never"
var inspect_visible := false
var settings_visible := false
var control_area: PanelContainer
var settings_panel: PanelContainer
var inspect_panel: PanelContainer
var origin_field: LineEdit
var token_field: LineEdit
var settings_state: Label
var connection_label: Label
var inspect_text: Label

func _ready() -> void:
	get_window().transparent = true
	get_window().borderless = true
	get_window().always_on_top = false
	var usable := DisplayServer.screen_get_usable_rect()
	get_window().position = usable.position + Vector2i(0, usable.size.y - int(STRIP_HEIGHT))
	_build_controls()
	client.status_changed.connect(_on_connection_status_changed)
	client.snapshot_received.connect(_on_snapshot_received)
	_on_connection_status_changed(client.connection_status(), client.connection_message())
	call_deferred("_update_passthrough")
	queue_redraw()

func _process(delta: float) -> void:
	if _has_motion():
		tide += delta
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_hide_overlays()
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_toggle_inspect()

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	control_area = PanelContainer.new()
	control_area.name = "ControlArea"
	control_area.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	control_area.position = Vector2(-282, 8)
	control_area.size = Vector2(274, 34)
	layer.add_child(control_area)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	control_area.add_child(row)
	connection_label = Label.new()
	connection_label.custom_minimum_size = Vector2(90, 0)
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_label.clip_text = true
	row.add_child(connection_label)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.tooltip_text = "Configure Tycho origin and token"
	settings_button.pressed.connect(_toggle_settings)
	row.add_child(settings_button)
	var inspect_button := Button.new()
	inspect_button.text = "Inspect"
	inspect_button.tooltip_text = "Show compact diagnostics"
	inspect_button.pressed.connect(_toggle_inspect)
	row.add_child(inspect_button)
	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.tooltip_text = "Quit Tycho Companion"
	quit_button.pressed.connect(_quit)
	row.add_child(quit_button)
	_build_settings(layer)
	_build_inspect(layer)

func _build_settings(layer: CanvasLayer) -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsOverlay"
	settings_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings_panel.position = Vector2(-402, 48)
	settings_panel.size = Vector2(394, 190)
	layer.add_child(settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	settings_panel.add_child(box)
	var title := Label.new()
	title.text = "Tycho connection"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var origin_label := Label.new()
	origin_label.text = "Origin (loopback or HTTPS .ts.net / MagicDNS)"
	box.add_child(origin_label)
	origin_field = LineEdit.new()
	origin_field.placeholder_text = "https://tycho.example.ts.net"
	origin_field.text = client.initial_origin()
	box.add_child(origin_field)
	var token_label := Label.new()
	token_label.text = "Bearer token (memory only)"
	box.add_child(token_label)
	token_field = LineEdit.new()
	token_field.secret = true
	token_field.placeholder_text = "Token is never saved"
	box.add_child(token_field)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var connect_button := Button.new()
	connect_button.text = "Connect"
	connect_button.pressed.connect(_connect)
	actions.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect"
	disconnect_button.pressed.connect(_disconnect)
	actions.add_child(disconnect_button)
	settings_state = Label.new()
	settings_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_state.add_theme_color_override("font_color", Color("f2d08a"))
	box.add_child(settings_state)
	settings_panel.hide()

func _build_inspect(layer: CanvasLayer) -> void:
	inspect_panel = PanelContainer.new()
	inspect_panel.name = "InspectOverlay"
	inspect_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inspect_panel.position = Vector2(-402, 48)
	inspect_panel.size = Vector2(394, 250)
	layer.add_child(inspect_panel)
	inspect_text = Label.new()
	inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_text.add_theme_font_size_override("font_size", 13)
	inspect_panel.add_child(inspect_text)
	inspect_panel.hide()

func _connect() -> void:
	var result := client.connect_live(origin_field.text, token_field.text)
	if not result.ok:
		settings_state.text = str(result.error)
		return
	# Drop the UI's second copy immediately. ConnectionClient is the sole in-memory owner.
	token_field.clear()
	settings_state.text = "Connecting…"
	_update_inspect_text()
	call_deferred("_update_passthrough")

func _disconnect() -> void:
	client.disconnect_live()
	token_field.clear()
	settings_state.text = "Disconnected. No token is retained."
	_update_inspect_text()

func _toggle_settings() -> void:
	settings_visible = not settings_visible
	if settings_visible:
		inspect_visible = false
		settings_state.text = client.connection_message()
	settings_panel.visible = settings_visible
	inspect_panel.hide()
	call_deferred("_update_passthrough")

func _toggle_inspect() -> void:
	inspect_visible = not inspect_visible
	if inspect_visible:
		settings_visible = false
		_update_inspect_text()
	inspect_panel.visible = inspect_visible
	settings_panel.hide()
	call_deferred("_update_passthrough")

func _hide_overlays() -> void:
	settings_visible = false
	inspect_visible = false
	settings_panel.hide()
	inspect_panel.hide()
	call_deferred("_update_passthrough")

func _quit() -> void:
	client.disconnect_live()
	get_tree().quit()

func _on_connection_status_changed(status: String, message: String) -> void:
	connection_label.text = status.capitalize()
	if status == "retrying" or status == "offline":
		for agent in agents:
			agent.stale = true
	if settings_visible:
		settings_state.text = message
	_update_inspect_text()
	queue_redraw()

func _on_snapshot_received(activity: Dictionary, _resources: Dictionary, refreshed_at: String) -> void:
	agents.clear()
	for raw in _activity_agents(activity):
		agents.append(StateMapperScript.normalize_agent(raw))
	last_refresh = refreshed_at
	_update_inspect_text()
	queue_redraw()

func _activity_agents(activity: Dictionary) -> Array:
	var raw_agents: Variant = activity.get("agents", [])
	if raw_agents is Array:
		return raw_agents
	return []

func _update_inspect_text() -> void:
	if inspect_text == null:
		return
	var lines := [
		"Tycho Inspector",
		"Connection: %s" % client.connection_status(),
		"Status: %s" % client.connection_message(),
		"Last refresh: %s" % last_refresh,
	]
	var visible_agents := _visible_agents()
	if visible_agents.is_empty():
		lines.append("No live agents available.")
	else:
		for agent in visible_agents:
			lines.append("%s — %s (%s)" % [agent.agent, StateMapperScript.effective_state(agent), agent.project])
	inspect_text.text = "\n".join(lines)

func _visible_agents() -> Array:
	if client.has_live_configuration():
		return agents
	var normalized: Array = []
	for raw in DEMO:
		normalized.append(StateMapperScript.normalize_agent(raw))
	return normalized

func _has_motion() -> bool:
	return _visible_agents().any(func(agent: Dictionary) -> bool: return StateMapperScript.effective_state(agent) == "running" and not agent.stale)

func _update_passthrough() -> void:
	# Godot's explicit polygon is supported on Windows transparent borderless windows:
	# only this rectangle accepts input; every ambient pixel passes clicks to the desktop.
	var rect := control_area.get_global_rect()
	if settings_visible:
		rect = rect.merge(settings_panel.get_global_rect())
	elif inspect_visible:
		rect = rect.merge(inspect_panel.get_global_rect())
	var polygon := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	get_window().mouse_passthrough = false
	DisplayServer.window_set_mouse_passthrough(polygon)

func _draw() -> void:
	var width := get_viewport_rect().size.x
	draw_rect(Rect2(0, 116, width, 44), Color("123947b0"))
	draw_rect(Rect2(0, 104, width, 16), Color("a67c4ca8"))
	for wave_x in range(0, int(width), 36):
		draw_arc(Vector2(wave_x + fmod(tide * 12.0, 36.0), 122), 12, PI, TAU, 12, Color("8ac8d080"), 1.4)
	var visible_agents := _visible_agents()
	if visible_agents.is_empty():
		return
	var gap := width / float(visible_agents.size() + 1)
	for index in visible_agents.size():
		_draw_workshop(Vector2(gap * float(index + 1), 99), visible_agents[index])

func _draw_workshop(origin: Vector2, agent: Dictionary) -> void:
	var dim := 0.48 if agent.stale else 1.0
	draw_rect(Rect2(origin + Vector2(-20, -29), Vector2(40, 28)), Color("5c3d29").darkened(1.0 - dim), true)
	var roof := PackedVector2Array([origin + Vector2(-25, -29), origin + Vector2(0, -48), origin + Vector2(25, -29)])
	draw_colored_polygon(roof, Color("c45b3d").darkened(1.0 - dim))
	draw_rect(Rect2(origin + Vector2(-4, -16), Vector2(8, 15)), Color("1a2223"), true)
	var cue := _cue_color(StateMapperScript.effective_state(agent))
	draw_circle(origin + Vector2(18, -16), 7, cue.darkened(1.0 - dim))
	draw_arc(origin + Vector2(18, -16), 8, 0, TAU, 16, Color("f7f3e5"), 1.2)
	if agent.unread:
		draw_rect(Rect2(origin + Vector2(-29, -12), Vector2(10, 8)), Color("f2b948"), true)
	if agent.state == "blocked":
		draw_line(origin + Vector2(-17, -5), origin + Vector2(17, -23), Color("d66a5e"), 3.0)

func _cue_color(state: String) -> Color:
	match state:
		"idle": return Color("4cb5ae")
		"running": return Color("4d9fd6")
		"awaiting-input": return Color("e5a942")
		"blocked": return Color("c95f58")
		"succeeded": return Color("f1c85b")
		"failed": return Color("6d78b6")
		"partial": return Color("9b75b9")
		"stopped": return Color("8c9595")
		_: return Color("4cb5ae")
