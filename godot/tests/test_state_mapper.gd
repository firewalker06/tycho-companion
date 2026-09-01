extends SceneTree

const Mapper := preload("res://state_mapper.gd")

func _init() -> void:
	var activity := {
		"servers": [{
			"key": "north", "name": "North shore", "health": "offline",
			"agents": [{"key": "a", "name": "Aster", "project_key": "harbor", "status": "running"}],
		}, {
			"key": "south", "name": "South shore", "agents": [{"key": "b", "name": "Bramble", "status": "idle"}],
		}],
	}
	var flattened := Mapper.flatten_activity(activity)
	assert(flattened.size() == 2, "server-qualified activity must not silently render zero agents")
	var north := Mapper.normalize_agent(flattened[0])
	assert(north.server == "North shore" and north.server_key == "north" and north.stale and north.offline and north.server_status == "offline")
	assert(Mapper.normalize_agent(flattened[1]).server == "South shore")
	assert(Mapper.caretaker_pose_cell("partial", false) == Vector2i(2, 0))
	assert(Mapper.caretaker_pose_cell("awaiting-input", false) == Vector2i(2, 0))
	assert(Mapper.caretaker_pose_cell("stopped", false) == Vector2i(2, 1))
	assert(Mapper.caretaker_pose_cell("running", true) == Vector2i(2, 1))
	assert(Mapper.caretaker_pose_cell("offline", false) == Vector2i(2, 1))
	var intent: Dictionary = Mapper.visual_intent({"key": "a", "server": "s", "status": "running", "awaiting_input": true, "blocked": true, "unread": true, "stale": true})
	assert(intent.cue == "closed-gate")
	assert(intent.unread)
	assert(intent.stale)
	var shared_name_activity := {"servers": [
		{"key": "east", "name": "Shared shore", "agents": [{"key": "a", "status": "idle"}]},
		{"key": "west", "name": "Shared shore", "agents": [{"key": "a", "status": "idle"}]},
	]}
	var shared_name_agents := Mapper.flatten_activity(shared_name_activity)
	assert(Mapper.visual_intent(shared_name_agents[0]).id == "east/a")
	assert(Mapper.visual_intent(shared_name_agents[1]).id == "west/a")
	assert(Mapper.visual_intent({"key": "a", "server": "legacy-name", "status": "idle"}).id == "legacy-name/a", "legacy fixtures deliberately fall back to display identity")
	for valid in ["http://127.0.0.1:7373", "http://localhost", "https://tycho.example.ts.net", "https://tycho"]:
		assert(Mapper.is_safe_origin(valid), "expected safe origin: %s" % valid)
	for unsafe in [
		"http://localhost.evil.com", "https://example.ts.net.evil.com", "https://user@tycho",
		"https://tycho/path", "https://tycho?query=value", "https://tycho#fragment",
		"http://127.0.0.2", "ftp://localhost", "https://example.com",
	]:
		assert(not Mapper.is_safe_origin(unsafe), "expected rejected origin: %s" % unsafe)
	print("StateMapper tests passed")
	quit(0)
