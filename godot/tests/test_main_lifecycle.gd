extends SceneTree

const Main := preload("res://main.gd")

class FailingClient extends Node:
	func prepare_for_shutdown() -> Dictionary:
		return {"ok": false, "message": "synthetic save failure"}

func _init() -> void:
	var motion_main := Main.new()
	motion_main.companion_scene = preload("res://companion_scene.gd").new()
	motion_main.add_child(motion_main.companion_scene)
	motion_main.agents = [{"state": "running", "stale": true, "blocked": false, "awaiting_input": false}]
	motion_main._sync_companion_scene()
	assert(not motion_main.is_processing(), "an all-stale scene must disable continuous processing")
	motion_main.agents = [{"state": "idle", "stale": false, "blocked": false, "awaiting_input": false}]
	motion_main._sync_companion_scene()
	assert(motion_main.is_processing(), "a permitted ambient loop must enable processing")
	motion_main.agents = [{"state": "stopped", "stale": false, "blocked": false, "awaiting_input": false}]
	motion_main._sync_companion_scene()
	assert(not motion_main.is_processing(), "a stopped scene must disable continuous processing")
	motion_main.free()
	for initial_overlay in ["", "settings"]:
		var main := Main.new()
		main.client = FailingClient.new()
		main.settings_panel = PanelContainer.new()
		main.inspect_panel = PanelContainer.new()
		main.debug_panel = PanelContainer.new()
		main.settings_state = Label.new()
		main.add_child(main.client)
		main.add_child(main.settings_panel)
		main.add_child(main.inspect_panel)
		main.add_child(main.debug_panel)
		main.settings_panel.add_child(main.settings_state)
		main.overlay_kind = initial_overlay
		main.settings_panel.visible = initial_overlay == "settings"
		main._quit()
		assert(main.overlay_kind == "settings")
		assert(main.settings_panel.visible)
		assert(not main.inspect_panel.visible)
		assert(not main.debug_panel.visible)
		assert(main.settings_state.text.contains("synthetic save failure"))
		main._quit()
		assert(main.settings_panel.visible, "repeated shutdown failure must keep Settings open")
		assert(main.settings_state.text.contains("synthetic save failure"), "shutdown error must remain visible")
		main.free()
	print("Main lifecycle tests passed")
	quit(0)
