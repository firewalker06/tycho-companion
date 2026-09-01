extends Node2D

const StateMapperScript := preload("res://state_mapper.gd")
const DesktopLayoutScript := preload("res://desktop_layout.gd")
const DebugSystemScript := preload("res://debug_system.gd")
const CompanionSceneScript := preload("res://companion_scene.gd")
const CONTROL_WIDTH := 394.0

@onready var client: Node = $ConnectionClient

var tide := 0.0
var animation_accumulator := 0.0
var agents: Array[Dictionary] = []
var last_refresh := "Never"
var overlay_kind := ""
var control_area: PanelContainer
var settings_panel: PanelContainer
var inspect_panel: PanelContainer
var debug_panel: PanelContainer
var origin_field: LineEdit
var token_field: LineEdit
var settings_state: Label
var connection_label: Label
var inspect_text: Label
var debug_text: Label
var render_test_button: Button
var debug_render_active := false
var debug_agents: Array[Dictionary] = []
var snapshot_busy := false
var last_snapshot_path := ""
var last_snapshot_error := OK
var companion_scene: Node2D
var quit_pending := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_viewport().transparent_bg = true
	get_window().transparent = true
	get_window().borderless = true
	get_window().always_on_top = false
	_apply_window_layout()
	_build_companion_scene()
	_build_controls()
	client.status_changed.connect(_on_connection_status_changed)
	client.snapshot_received.connect(_on_snapshot_received)
	client.connection_test_completed.connect(_on_connection_test_completed)
	_on_connection_status_changed(client.connection_status(), client.connection_message())
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_update_passthrough")
	_sync_companion_scene()
	if OS.get_cmdline_user_args().has("--debug-render-snapshot"):
		call_deferred("_run_cli_render_snapshot")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()

func _process(delta: float) -> void:
	if _has_motion():
		tide += delta
		animation_accumulator += delta
		if animation_accumulator >= 1.0 / 12.0:
			animation_accumulator = fmod(animation_accumulator, 1.0 / 12.0)
			companion_scene.tide = tide
			companion_scene.queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_hide_overlays()
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_toggle_overlay("inspect")

func _apply_window_layout() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var height := DesktopLayoutScript.window_height(overlay_kind)
	# Keep the canvas' logical size in lockstep with the native window. The
	# project has a 300 px compact default, so changing window size alone would
	# otherwise leave controls laid out in a clipped 300 px viewport.
	get_window().content_scale_size = Vector2i(usable.size.x, height)
	get_window().size = Vector2i(usable.size.x, height)
	get_window().position = DesktopLayoutScript.bottom_anchored_position(usable, height)
	if companion_scene != null:
		companion_scene.overlay_kind = overlay_kind
		companion_scene.queue_redraw()

func _build_companion_scene() -> void:
	# Keep ambient art on an explicit canvas. Windows reliably composites the
	# CanvasLayer used by the controls, while the implicit root canvas can vanish
	# in a transparent borderless window after its startup resize.
	var ambient_layer := CanvasLayer.new()
	ambient_layer.name = "AmbientLayer"
	ambient_layer.layer = -10
	add_child(ambient_layer)
	companion_scene = CompanionSceneScript.new()
	companion_scene.name = "CompanionScene"
	ambient_layer.add_child(companion_scene)

func _on_viewport_size_changed() -> void:
	if control_area == null:
		return
	_layout_controls()
	call_deferred("_update_passthrough")
	companion_scene.queue_redraw()

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
	for details in [["Settings", "Configure Tycho origin and token"], ["Inspect", "Show compact diagnostics"], ["Debug", "Test connection and rendering"], ["Save & Quit", "Preserve the protected token and quit safely"]]:
		var button := Button.new()
		button.text = details[0]
		button.tooltip_text = details[1]
		_style_button(button)
		match button.text:
			"Settings": button.pressed.connect(_toggle_overlay.bind("settings"))
			"Inspect": button.pressed.connect(_toggle_overlay.bind("inspect"))
			"Debug": button.pressed.connect(_toggle_overlay.bind("debug"))
			"Save & Quit": button.pressed.connect(_quit)
		row.add_child(button)
	_build_settings(layer)
	_build_inspect(layer)
	_build_debug(layer)
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
	debug_panel.position = DesktopLayoutScript.overlay_rect(width, "debug").position
	debug_panel.size = DesktopLayoutScript.overlay_rect(width, "debug").size

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
	token_label.text = "Bearer token (secured by your Windows account)"
	box.add_child(token_label)
	token_field = LineEdit.new()
	token_field.secret = true
	token_field.placeholder_text = "Saved token active — enter only to replace" if client.has_saved_credential() else "Saved securely after connecting"
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

func _build_debug(layer: CanvasLayer) -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugOverlay"
	debug_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b2940fa")))
	layer.add_child(debug_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	debug_panel.add_child(box)
	var title := Label.new()
	title.text = "Tycho debug tools"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("f4dc9b"))
	box.add_child(title)
	debug_text = Label.new()
	debug_text.text = "Run explicit checks without changing live polling or saving credentials."
	debug_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_text.add_theme_color_override("font_color", Color("d6eee8"))
	box.add_child(debug_text)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	box.add_child(actions)
	for details in [["Test connection", "Probe activity and resources without changing the live scene"], ["Test rendering", "Validate image regions and preview every lifecycle state"], ["Snapshot rendering", "Save a clean compact PNG under user data"]]:
		var button := Button.new()
		button.text = details[0]
		button.tooltip_text = details[1]
		_style_button(button)
		match button.text:
			"Test connection": button.pressed.connect(_test_connection)
			"Test rendering":
				render_test_button = button
				button.pressed.connect(_test_rendering)
			"Snapshot rendering": button.pressed.connect(_snapshot_rendering)
		actions.add_child(button)
	debug_panel.hide()

func _connect() -> void:
	var result: Dictionary = client.connect_live(origin_field.text, token_field.text)
	if not result.ok:
		settings_state.text = str(result.error)
		return
	token_field.clear() # The client is the only in-memory owner after this point.
	settings_state.text = "Connecting… Token secured." if result.credential_saved else "Connecting… %s" % result.warning
	_update_inspect_text()

func _disconnect() -> void:
	var result: Dictionary = client.disconnect_live()
	token_field.clear()
	settings_state.text = "Disconnected. The saved token was removed." if result.ok else "Disconnected, but the saved token could not be removed.\n%s" % result.message
	_update_inspect_text()

func _toggle_overlay(kind: String) -> void:
	overlay_kind = "" if overlay_kind == kind else kind
	settings_panel.visible = overlay_kind == "settings"
	inspect_panel.visible = overlay_kind == "inspect"
	debug_panel.visible = overlay_kind == "debug"
	if overlay_kind == "settings":
		settings_state.text = "%s\n%s" % [client.connection_message(), client.credential_message()]
		token_field.placeholder_text = "Saved token active — enter only to replace" if client.has_saved_credential() else "Saved securely after connecting"
	if overlay_kind == "inspect": _update_inspect_text()
	_apply_window_layout()
	call_deferred("_layout_controls")
	call_deferred("_update_passthrough")

func _hide_overlays() -> void:
	if overlay_kind.is_empty(): return
	overlay_kind = ""
	settings_panel.hide()
	inspect_panel.hide()
	debug_panel.hide()
	_apply_window_layout()
	call_deferred("_layout_controls")
	call_deferred("_update_passthrough")

func _quit() -> void:
	if quit_pending:
		return
	var save_result: Dictionary = client.prepare_for_shutdown()
	if not save_result.ok:
		_toggle_overlay("settings")
		settings_state.text = "Could not save the token, so Tycho Companion remains open.\n%s" % save_result.message
		return
	quit_pending = true
	client.disconnect_live(false)
	get_tree().quit()

func _on_connection_status_changed(status: String, message: String) -> void:
	connection_label.text = status.capitalize()
	if status == "setup":
		agents.clear()
		last_refresh = "Never"
	if status == "retrying":
		for agent in agents: agent.stale = true
	if overlay_kind == "settings": settings_state.text = "%s\n%s" % [message, client.credential_message()]
	_update_inspect_text()
	_sync_companion_scene()

func _on_snapshot_received(activity: Dictionary, _resources: Dictionary, refreshed_at: String) -> void:
	agents.clear()
	for raw in StateMapperScript.flatten_activity(activity):
		agents.append(StateMapperScript.normalize_agent(raw))
	last_refresh = refreshed_at
	_update_inspect_text()
	_sync_companion_scene()

func _test_connection() -> void:
	debug_text.text = "Testing connection…"
	var result: Dictionary = client.test_connection()
	if not result.started:
		debug_text.text = result.message

func _on_connection_test_completed(report: Dictionary) -> void:
	var lines := [str(report.message)]
	var endpoints: Dictionary = report.get("endpoints", {})
	for path in ["/servers/activity", "/servers/resources"]:
		if endpoints.has(path):
			var result: Dictionary = endpoints[path]
			lines.append("%s — %s · HTTP %d · %d ms" % [path, "pass" if result.ok else "fail", result.status_code, result.duration_ms])
	debug_text.text = "\n".join(lines)

func _test_rendering() -> void:
	if debug_render_active:
		debug_render_active = false
		debug_agents.clear()
		render_test_button.text = "Test rendering"
		debug_text.text = "Synthetic render preview stopped; live rendering restored."
		_sync_companion_scene()
		return
	var report := DebugSystemScript.render_test_report(
		CompanionSceneScript.WORKSHOP.get_size(),
		CompanionSceneScript.CARETAKER.get_size(),
		CompanionSceneScript.WORKSHOP_REGION,
		Vector2i(CompanionSceneScript.CARETAKER_CELL),
	)
	debug_render_active = report.ok
	debug_agents = DebugSystemScript.render_fixture() if report.ok else []
	if report.ok:
		render_test_button.text = "Return to live rendering"
	debug_text.text = "%s\nPreview: %s" % [report.message, ", ".join(report.states)]
	_sync_companion_scene()

func _snapshot_rendering() -> void:
	if snapshot_busy:
		return
	snapshot_busy = true
	debug_text.text = "Capturing a clean compact frame…"
	_hide_overlays()
	control_area.hide()
	_sync_companion_scene()
	await get_tree().process_frame
	# Flush synchronously so capture does not depend on a desktop compositor or
	# frame_post_draw timing. A truly headless dummy renderer has no texture; the
	# explicit null check below reports that as unsupported instead of hanging.
	RenderingServer.force_draw(false, 0.0)
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		var texture := get_viewport().get_texture()
		image = texture.get_image() if texture != null else null
	var directory := "user://snapshots"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	var timestamp := "%s-%03d" % [Time.get_datetime_string_from_system(), Time.get_ticks_msec() % 1000]
	var relative_path := "%s/%s" % [directory, DebugSystemScript.snapshot_filename(timestamp)]
	var save_error := ERR_UNAVAILABLE
	if image != null and not image.is_empty():
		if not DebugSystemScript.snapshot_has_visible_scene(image):
			save_error = ERR_INVALID_DATA
		else:
			var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
			save_error = directory_error if directory_error != OK else image.save_png(relative_path)
	last_snapshot_path = ProjectSettings.globalize_path(relative_path) if save_error == OK else ""
	last_snapshot_error = save_error
	control_area.show()
	overlay_kind = "debug"
	debug_panel.show()
	_apply_window_layout()
	call_deferred("_layout_controls")
	call_deferred("_update_passthrough")
	debug_text.text = "Snapshot saved: %s" % last_snapshot_path if save_error == OK else "Snapshot failed with error %d." % save_error
	snapshot_busy = false

func _run_cli_render_snapshot() -> void:
	## Deterministic smoke path for local diagnostics. It uses only the
	## synthetic render fixture and never loads a Tycho origin or token.
	_test_rendering()
	await get_tree().process_frame
	await _snapshot_rendering()
	if last_snapshot_error == OK:
		print("Debug render snapshot saved: %s" % last_snapshot_path)
		get_tree().quit(0)
	else:
		printerr("Debug render snapshot failed with error %d." % last_snapshot_error)
		get_tree().quit(1)

func _update_inspect_text() -> void:
	if inspect_text == null: return
	var lines := ["Tycho Inspector", "Connection: %s" % client.connection_status(), "Status: %s" % client.connection_message(), "Credential: %s" % client.credential_message(), "Last refresh: %s" % last_refresh]
	if agents.is_empty():
		lines.append("No live agents available.")
	else:
		for agent in agents:
			lines.append("%s — %s (%s · %s)" % [agent.agent, StateMapperScript.effective_state(agent), agent.project, agent.server])
	inspect_text.text = "\n".join(lines)

func _has_motion() -> bool:
	return not (debug_agents if debug_render_active else agents).is_empty()

func _sync_companion_scene() -> void:
	if companion_scene == null:
		return
	companion_scene.overlay_kind = overlay_kind
	companion_scene.tide = tide
	companion_scene.replace_agents(debug_agents if debug_render_active else agents)

func _update_passthrough() -> void:
	get_window().mouse_passthrough = false
	DisplayServer.window_set_mouse_passthrough(DesktopLayoutScript.platform_input_polygon(get_viewport_rect().size.x, overlay_kind, CONTROL_WIDTH))
