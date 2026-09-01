class_name CompanionScene
extends Node2D

const StateMapperScript := preload("res://state_mapper.gd")
const DesktopLayoutScript := preload("res://desktop_layout.gd")
const WORKSHOP := preload("res://assets/coastal-workshop.png")
const CARETAKER := preload("res://assets/caretaker-poses.png")

const WORKSHOP_REGION := Rect2(0, 0, 2048, 500)
const CARETAKER_CELL := Vector2(512, 512)
const CARETAKER_SIZE := Vector2(120, 120)

var tide := 0.0
var overlay_kind := ""
var agents: Array[Dictionary] = []

func replace_agents(next_agents: Array[Dictionary]) -> void:
	agents = next_agents.duplicate(true)
	queue_redraw()

func _draw() -> void:
	var viewport := get_viewport_rect()
	var strip := DesktopLayoutScript.strip_rect(viewport.size.x, overlay_kind)
	var scene := workshop_rect(viewport.size.x, strip, WORKSHOP.get_size())
	draw_texture_rect_region(WORKSHOP, scene, WORKSHOP_REGION)
	if agents.is_empty():
		return
	var gap := scene.size.x / float(agents.size() + 1)
	for index in agents.size():
		_draw_caretaker(Vector2(scene.position.x + gap * float(index + 1), scene.position.y + scene.size.y * 0.70), agents[index])

static func workshop_rect(viewport_width: float, strip: Rect2, texture_size: Vector2) -> Rect2:
	var height := strip.size.y
	var width := height * texture_size.x / texture_size.y
	if width > viewport_width:
		width = viewport_width
		height = width * texture_size.y / texture_size.x
	return Rect2(
		Vector2((viewport_width - width) * 0.5, strip.end.y - height),
		Vector2(width, height),
	)

func _draw_caretaker(position: Vector2, agent: Dictionary) -> void:
	var state := StateMapperScript.effective_state(agent)
	var cell := Vector2(StateMapperScript.caretaker_pose_cell(state, agent.stale))
	var motion := idle_motion(state, agent.stale, tide, position.x * 0.01)
	draw_set_transform(position + motion.offset, motion.rotation, motion.scale)
	var target := Rect2(Vector2(-60, -123), CARETAKER_SIZE)
	var source := Rect2(cell * CARETAKER_CELL, CARETAKER_CELL)
	var tint := Color("ffffff") if not agent.stale else Color("82939a")
	draw_texture_rect_region(CARETAKER, target, source, tint)
	draw_circle(Vector2(50, -96), 6, _cue_color(state))
	if agent.unread:
		draw_rect(Rect2(Vector2(-62, -78), Vector2(12, 10)), Color("f2b948"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func idle_motion(state: String, stale: bool, animation_time: float, phase: float) -> Dictionary:
	var wave := sin(animation_time * 1.4 + phase)
	if stale:
		var stale_wave := sin(animation_time * 0.55 + phase)
		return {
			"offset": Vector2(0.0, stale_wave * 0.7),
			"rotation": stale_wave * 0.008,
			"scale": Vector2(1.0 + stale_wave * 0.004, 1.0 - stale_wave * 0.004),
		}
	match state:
		"idle":
			return {"offset": Vector2(0.0, wave * 0.8), "rotation": wave * 0.006, "scale": Vector2(1.0 - wave * 0.006, 1.0 + wave * 0.009)}
		"running":
			var work_wave := sin(animation_time * 2.4 + phase)
			return {"offset": Vector2(0.0, work_wave * 2.5), "rotation": work_wave * 0.012, "scale": Vector2.ONE}
		"awaiting-input":
			var alert_wave := sin(animation_time * 2.0 + phase)
			return {"offset": Vector2(alert_wave * 1.2, absf(alert_wave) * -1.0), "rotation": alert_wave * 0.018, "scale": Vector2.ONE}
		"succeeded":
			var proud_wave := sin(animation_time * 1.65 + phase)
			return {"offset": Vector2(0.0, proud_wave * 1.6), "rotation": proud_wave * -0.01, "scale": Vector2(1.0 + proud_wave * 0.006, 1.0 - proud_wave * 0.004)}
		"failed", "blocked":
			var tired_wave := sin(animation_time * 0.75 + phase)
			return {"offset": Vector2(0.0, tired_wave * 0.6), "rotation": tired_wave * 0.011, "scale": Vector2(1.0 + tired_wave * 0.003, 1.0 - tired_wave * 0.006)}
		_:
			var rest_wave := sin(animation_time * 0.9 + phase)
			return {"offset": Vector2(rest_wave * 0.5, rest_wave * 0.5), "rotation": rest_wave * 0.007, "scale": Vector2.ONE}

func _cue_color(state: String) -> Color:
	match state:
		"idle", "running": return Color("4cb5ae")
		"awaiting-input", "succeeded": return Color("e5a942")
		"blocked", "failed": return Color("c95f58")
		_: return Color("8c9595")
