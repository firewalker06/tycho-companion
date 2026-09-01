class_name DebugSystem
extends RefCounted

const StateMapperScript := preload("res://state_mapper.gd")

## Pure fixtures and checks used by the runtime Debug panel and headless tests.
## Debug data is synthetic and never contains live Tycho payloads or credentials.

const RENDER_STATES := [
	"idle", "running", "awaiting-input", "blocked", "succeeded",
	"failed", "partial", "stopped", "stale",
]

static func render_fixture() -> Array[Dictionary]:
	var fixture: Array[Dictionary] = []
	for index in RENDER_STATES.size():
		var state: String = RENDER_STATES[index]
		var raw := {
			"key": "debug-%02d" % index,
			"server_name": "Debug shore",
			"project_key": "render-test",
			"name": state.capitalize(),
			"status": state if state not in ["awaiting-input", "blocked", "stale"] else "running",
			"awaiting_input": state == "awaiting-input",
			"blocked": state == "blocked",
			"stale": state == "stale",
			"unread": state == "awaiting-input",
		}
		fixture.append(StateMapperScript.normalize_agent(raw))
	return fixture

static func render_test_report(workshop_size: Vector2i, caretaker_size: Vector2i, workshop_region: Rect2, caretaker_cell: Vector2i) -> Dictionary:
	var issues: Array[String] = []
	if workshop_region.position.x < 0.0 or workshop_region.position.y < 0.0 or workshop_region.end.x > workshop_size.x or workshop_region.end.y > workshop_size.y:
		issues.append("Workshop crop is outside the source texture.")
	if caretaker_cell.x <= 0 or caretaker_cell.y <= 0 or caretaker_size.x < caretaker_cell.x * 3 or caretaker_size.y < caretaker_cell.y * 2:
		issues.append("Caretaker atlas does not contain a complete 3x2 pose grid.")
	for agent in render_fixture():
		var cell: Vector2i = StateMapperScript.caretaker_pose_cell(StateMapperScript.effective_state(agent), agent.stale)
		if cell.x < 0 or cell.y < 0 or (cell.x + 1) * caretaker_cell.x > caretaker_size.x or (cell.y + 1) * caretaker_cell.y > caretaker_size.y:
			issues.append("Pose for %s is outside the caretaker atlas." % agent.agent)
	var ok := issues.is_empty()
	return {
		"ok": ok,
		"message": "All nine lifecycle fixtures and image regions are renderable." if ok else " ".join(issues),
		"states": RENDER_STATES.duplicate(),
	}

static func snapshot_filename(timestamp: String) -> String:
	var safe := timestamp.replace(":", "-").replace(" ", "T")
	return "tycho-companion-%s.png" % safe

static func snapshot_has_visible_scene(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var visible_samples := 0
	var columns := 32
	var rows := 8
	for row in rows:
		var sample_y := mini(image.get_height() - 1, int((float(row) + 0.5) * image.get_height() / rows))
		for column in columns:
			var sample_x := mini(image.get_width() - 1, int((float(column) + 0.5) * image.get_width() / columns))
			if image.get_pixel(sample_x, sample_y).a > 0.5:
				visible_samples += 1
	# A centered transparent cutout need not cover the viewport edges, but a
	# handful of opaque samples distinguishes it sharply from the blank-window bug.
	return visible_samples >= 8
