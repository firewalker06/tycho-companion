extends Node2D

const StateMapperScript := preload("res://state_mapper.gd")
const DesktopLayoutScript := preload("res://desktop_layout.gd")
const WORKSHOP := preload("res://assets/coastal-workshop.png")
const CARETAKER := preload("res://assets/caretaker-poses.png")

# The full-width x=0..1774, y=400..784 source region retains all three lit
# work bays. It is intentionally fitted to the compact strip, with no bars.
const WORKSHOP_REGION := Rect2(0, 400, 1774, 384)
const CARETAKER_CELL := Vector2(512, 512)
const CONTROL_WIDTH := 274.0

@onready var client: ConnectionClient = $ConnectionClient

var tide := 0.0
var agents: Array[Dictionary] = []
var last_refresh := "Never"
var overlay_kind := ""
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
	_apply_window_layout()
	_build_controls()
	client.status_changed.connect(_on_connection_status_changed)
	client.snapshot_received.connect(_on_snapshot_received)
	_on_connection_status_changed(client.connection_status(), client.connection_message())
	get_viewport().size_changed.connect(_on_viewport_size_changed)
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
		_toggle_overlay("inspect")

func _apply_window_layout() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var height := DesktopLayoutScript.window_height(overlay_kind)
	# Keep the canvas' logical size in lockstep with the native window. The
	# project has a 160 px compact default, so changing window size alone would
	# otherwise leave controls laid out in a clipped 160 px viewport.
	get_window().content_scale_size = Vector2i(usable.size.x, height)
	get_window().size = Vector2i(usable.size.x, height)
	get_window().position = DesktopLayoutScript.bottom_anchored_position(usable, height)

func _on_viewport_size_changed() -> void:
	if control_area == null:
		return
	_layout_controls()
	call_deferred("_update_passthrough")
	queue_redraw()

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("4faea8")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _panel_style(Color("102e43e8")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("175063f2")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("0b2536f2")))
	button.add_theme_color_override("font_color", Color("f4dc9b"))

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	control_area = PanelContainer.new()
	control_area.name = "ControlArea"
	control_area.add_theme_stylebox_override("panel", _panel_style(Color("0a2339e8")))
	layer.add_child(control_area)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	control_area.add_child(row)
	connection_label = Label.new()
	connection_label.custom_minimum_size = Vector2(90, 0)
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_label.clip_text = true
	connection_label.add_theme_color_override("font_color", Color("a9ddd2"))
	row.add_child(connection_label)
	for details in [["Settings", "Configure Tycho origin and token"], ["Inspect", "Show compact diagnostics"], ["Quit", "Quit Tycho Companion"]]:
		var button := Button.new()
		button.text = details[0]
		button.tooltip_text = details[1]
		_style_button(button)
		match button.text:
			"Settings": button.pressed.connect(_toggle_overlay.bind("settings"))
			"Inspect": button.pressed.connect(_toggle_overlay.bind("inspect"))
			"Quit": button.pressed.connect(_quit)
		row.add_child(button)
	_build_settings(layer)
	_build_inspect(layer)
	_layout_controls()

func _layout_controls() -> void:
	var width := get_viewport_rect().size.x
	var control := DesktopLayoutScript.control_rect(width, overlay_kind, CONTROL_WIDTH)
	control_area.position = control.position
	control_area.size = control.size
	settings_panel.position = DesktopLayoutScript.overlay_rect(width, "settings").position
	settings_panel.size = DesktopLayoutScript.overlay_rect(width, "settings").size
	inspect_panel.position = DesktopLayoutScript.overlay_rect(width, "inspect").position
	inspect_panel.size = DesktopLayoutScript.overlay_rect(width, "inspect").size

func _build_settings(layer: CanvasLayer) -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsOverlay"
	settings_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b2940fa")))
	layer.add_child(settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	settings_panel.add_child(box)
	var title := Label.new()
	title.text = "Tycho connection"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("f4dc9b"))
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
	_style_button(connect_button)
	connect_button.pressed.connect(_connect)
	actions.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect"
	_style_button(disconnect_button)
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
	inspect_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b2940fa")))
	layer.add_child(inspect_panel)
	inspect_text = Label.new()
	inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_text.add_theme_font_size_override("font_size", 13)
	inspect_text.add_theme_color_override("font_color", Color("d6eee8"))
	inspect_panel.add_child(inspect_text)
	inspect_panel.hide()

func _connect() -> void:
	var result := client.connect_live(origin_field.text, token_field.text)
	if not result.ok:
		settings_state.text = str(result.error)
		return
	token_field.clear() # The client is the only in-memory owner after this point.
	settings_state.text = "Connecting…"
	_update_inspect_text()

func _disconnect() -> void:
	client.disconnect_live()
	token_field.clear()
	settings_state.text = "Disconnected. No token is retained."
	_update_inspect_text()

func _toggle_overlay(kind: String) -> void:
	overlay_kind = "" if overlay_kind == kind else kind
	settings_panel.visible = overlay_kind == "settings"
	inspect_panel.visible = overlay_kind == "inspect"
	if overlay_kind == "settings": settings_state.text = client.connection_message()
	if overlay_kind == "inspect": _update_inspect_text()
	_apply_window_layout()
	call_deferred("_layout_controls")
	call_deferred("_update_passthrough")

func _hide_overlays() -> void:
	if overlay_kind.is_empty(): return
	overlay_kind = ""
	settings_panel.hide()
	inspect_panel.hide()
	_apply_window_layout()
	call_deferred("_layout_controls")
	call_deferred("_update_passthrough")

func _quit() -> void:
	client.disconnect_live()
	get_tree().quit()

func _on_connection_status_changed(status: String, message: String) -> void:
	connection_label.text = status.capitalize()
	if status == "setup":
		agents.clear()
		last_refresh = "Never"
	if status == "retrying":
		for agent in agents: agent.stale = true
	if overlay_kind == "settings": settings_state.text = message
	_update_inspect_text()
	queue_redraw()

func _on_snapshot_received(activity: Dictionary, _resources: Dictionary, refreshed_at: String) -> void:
	agents.clear()
	for raw in StateMapperScript.flatten_activity(activity):
		agents.append(StateMapperScript.normalize_agent(raw))
	last_refresh = refreshed_at
	_update_inspect_text()
	queue_redraw()

func _update_inspect_text() -> void:
	if inspect_text == null: return
	var lines := ["Tycho Inspector", "Connection: %s" % client.connection_status(), "Status: %s" % client.connection_message(), "Last refresh: %s" % last_refresh]
	if agents.is_empty():
		lines.append("No live agents available.")
	else:
		for agent in agents:
			lines.append("%s — %s (%s · %s)" % [agent.agent, StateMapperScript.effective_state(agent), agent.project, agent.server])
	inspect_text.text = "\n".join(lines)

func _has_motion() -> bool:
	for agent in agents:
		if StateMapperScript.effective_state(agent) == "running" and not agent.stale: return true
	return false

func _update_passthrough() -> void:
	get_window().mouse_passthrough = false
	DisplayServer.window_set_mouse_passthrough(DesktopLayoutScript.input_polygon(get_viewport_rect().size.x, overlay_kind, CONTROL_WIDTH))

func _draw() -> void:
	var viewport := get_viewport_rect()
	var strip := DesktopLayoutScript.strip_rect(viewport.size.x, overlay_kind)
	draw_texture_rect_region(WORKSHOP, strip, WORKSHOP_REGION)
	if agents.is_empty(): return
	var gap := viewport.size.x / float(agents.size() + 1)
	for index in agents.size():
		_draw_caretaker(Vector2(gap * float(index + 1), strip.position.y + 126.0), agents[index])

func _draw_caretaker(position: Vector2, agent: Dictionary) -> void:
	var state := StateMapperScript.effective_state(agent)
	var cell := Vector2(StateMapperScript.caretaker_pose_cell(state, agent.stale))
	var bob := sin(tide * 1.35 + position.x * 0.01) * 2.0 if state == "running" and not agent.stale else 0.0
	var target := Rect2(position - Vector2(45, 92) + Vector2(0, bob), Vector2(90, 90))
	var source := Rect2(cell * CARETAKER_CELL, CARETAKER_CELL)
	var tint := Color("ffffff") if not agent.stale else Color("82939a")
	draw_texture_rect_region(CARETAKER, target, source, tint)
	var cue := _cue_color(state)
	draw_circle(position + Vector2(37, -72), 5, cue)
	if agent.unread: draw_rect(Rect2(position + Vector2(-47, -59), Vector2(10, 8)), Color("f2b948"))

func _cue_color(state: String) -> Color:
	match state:
		"idle", "running": return Color("4cb5ae")
		"awaiting-input", "succeeded": return Color("e5a942")
		"blocked", "failed": return Color("c95f58")
		_: return Color("8c9595")
