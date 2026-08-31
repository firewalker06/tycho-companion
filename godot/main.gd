extends Node2D

const StateMapperScript := preload("res://state_mapper.gd")

const STRIP_HEIGHT := 160.0
const INSPECT_SECONDS := 15.0
const DEMO := [
	{"server": "Demo shore", "project": "harbor", "agent": "Harbor keeper", "state": "running", "unread": false, "stale": false},
	{"server": "Demo shore", "project": "lantern", "agent": "Lantern keeper", "state": "idle", "unread": true, "stale": false},
	{"server": "Demo shore", "project": "gate", "agent": "Gate keeper", "state": "awaiting-input", "unread": false, "stale": false},
	{"server": "Demo shore", "project": "weather", "agent": "Weather keeper", "state": "blocked", "unread": false, "stale": false},
]

var inspect_left := 0.0
var tide := 0.0
var focus_label: Label

func _ready() -> void:
	get_window().transparent = true
	get_window().borderless = true
	get_window().always_on_top = false
	get_window().position = DisplayServer.screen_get_usable_rect().position + Vector2i(0, DisplayServer.screen_get_usable_rect().size.y - int(STRIP_HEIGHT))
	get_window().mouse_passthrough = true
	focus_label = Label.new()
	focus_label.position = Vector2(18, 12)
	focus_label.add_theme_font_size_override("font_size", 15)
	focus_label.add_theme_color_override("font_color", Color("eaf7fb"))
	focus_label.hide()
	add_child(focus_label)
	queue_redraw()

func _process(delta: float) -> void:
	if inspect_left > 0.0:
		inspect_left = maxf(0.0, inspect_left - delta)
		if inspect_left == 0.0:
			_leave_inspect()
	if _has_motion():
		tide += delta
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_inspect()
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_enter_inspect()

func _enter_inspect() -> void:
	inspect_left = INSPECT_SECONDS
	get_window().mouse_passthrough = false
	focus_label.text = "Inspect mode — demo state only — %d seconds" % int(ceil(inspect_left))
	focus_label.show()

func _leave_inspect() -> void:
	inspect_left = 0.0
	get_window().mouse_passthrough = true
	focus_label.hide()

func _has_motion() -> bool:
	return DEMO.any(func(agent: Dictionary) -> bool: return StateMapperScript.effective_state(StateMapperScript.normalize_agent(agent)) == "running" and not agent.stale)

func _draw() -> void:
	var width := get_viewport_rect().size.x
	draw_rect(Rect2(0, 116, width, 44), Color("123947b0"))
	draw_rect(Rect2(0, 104, width, 16), Color("a67c4ca8"))
	for wave_x in range(0, int(width), 36):
		draw_arc(Vector2(wave_x + fmod(tide * 12.0, 36.0), 122), 12, PI, TAU, 12, Color("8ac8d080"), 1.4)
	var gap := width / float(DEMO.size() + 1)
	for index in DEMO.size():
		_draw_workshop(Vector2(gap * float(index + 1), 99), StateMapperScript.normalize_agent(DEMO[index]))

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
	if inspect_left > 0.0:
		var text := "%s · %s · %s" % [agent.agent, agent.project, agent.state]
		draw_string(ThemeDB.fallback_font, origin + Vector2(-54, 16), text, HORIZONTAL_ALIGNMENT_LEFT, 130, 11, Color("eff6f7"))

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
