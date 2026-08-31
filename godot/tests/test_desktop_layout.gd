extends SceneTree

const Layout := preload("res://desktop_layout.gd")

func _init() -> void:
	assert(Layout.window_height("") == 160)
	assert(Layout.window_height("settings") == 276)
	assert(Layout.window_height("inspect") == 326)
	var usable := Rect2i(20, 30, 1920, 1040)
	assert(Layout.bottom_anchored_position(usable, 160) == Vector2i(20, 910))
	assert(Layout.bottom_anchored_position(usable, 326) == Vector2i(20, 744))
	var inspect := Layout.overlay_rect(1280.0, "inspect")
	assert(inspect.position.y == 48.0 and inspect.end.y == 318.0)
	assert(inspect.position.x >= 8.0)
	print("Desktop layout tests passed")
	quit(0)
