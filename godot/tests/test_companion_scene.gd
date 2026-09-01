extends SceneTree

const Scene := preload("res://companion_scene.gd")

func _init() -> void:
	assert(ProjectSettings.get_setting("display/window/size/transparent", false) == true)
	assert(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false) == true)
	assert(ProjectSettings.get_setting("rendering/viewport/transparent_background", false) == true)
	assert(Scene.WORKSHOP.get_size() == Vector2(2048, 500))
	assert(Scene.CARETAKER.get_size() == Vector2(1536, 1024))
	var scene_rect := Scene.workshop_rect(2048.0, Rect2(0, 0, 2048, 300), Scene.WORKSHOP.get_size())
	assert(is_equal_approx(scene_rect.size.x, 1228.8))
	assert(scene_rect.size.y == 300.0)
	assert(is_equal_approx(scene_rect.position.x, 409.6))
	var motions: Array[Dictionary] = []
	for state in ["idle", "running", "awaiting-input", "succeeded", "blocked", "failed", "partial", "stopped"]:
		var start: Dictionary = Scene.idle_motion(state, false, 0.0, 0.37)
		var later: Dictionary = Scene.idle_motion(state, false, 0.71, 0.37)
		assert(start.offset != later.offset or start.rotation != later.rotation or start.scale != later.scale, "%s pose must animate" % state)
		motions.append(later)
	var stale_start: Dictionary = Scene.idle_motion("stopped", true, 0.0, 0.37)
	var stale_later: Dictionary = Scene.idle_motion("stopped", true, 0.71, 0.37)
	assert(stale_start != stale_later, "stale pose must animate")
	var layer := CanvasLayer.new()
	var scene := Scene.new()
	get_root().add_child(layer)
	layer.add_child(scene)
	assert(scene.get_parent() is CanvasLayer, "ambient rendering must use an explicit canvas on Windows")
	assert(scene.agents.is_empty())
	scene.replace_agents([{"state": "idle", "stale": false, "unread": false}])
	assert(scene.agents.size() == 1)
	layer.free()
	print("Companion scene tests passed")
	quit(0)
