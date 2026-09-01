extends SceneTree

const Debug := preload("res://debug_system.gd")
const Mapper := preload("res://state_mapper.gd")

func _init() -> void:
	var fixture := Debug.render_fixture()
	assert(fixture.size() == 9)
	var states: Array[String] = []
	for agent in fixture:
		var state := "stale" if agent.stale else Mapper.effective_state(agent)
		states.append(state)
	for expected in Debug.RENDER_STATES:
		assert(states.has(expected), "missing render fixture: %s" % expected)
	var valid := Debug.render_test_report(Vector2i(2048, 500), Vector2i(1536, 1024), Rect2(0, 0, 2048, 500), Vector2i(512, 512))
	assert(valid.ok)
	assert(valid.states.size() == 9)
	assert(not Debug.render_test_report(Vector2i(100, 100), Vector2i(512, 512), Rect2(0, 0, 2048, 500), Vector2i(512, 512)).ok)
	assert(Debug.snapshot_filename("2026-08-31T11:30:45") == "tycho-companion-2026-08-31T11-30-45.png")
	var blank := Image.create(80, 24, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	assert(not Debug.snapshot_has_visible_scene(blank))
	var rendered := Image.create(80, 24, false, Image.FORMAT_RGBA8)
	rendered.fill(Color("17344b"))
	assert(Debug.snapshot_has_visible_scene(rendered))
	print("Debug system tests passed")
	quit(0)
