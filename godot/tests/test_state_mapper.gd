extends SceneTree

const Mapper := preload("res://state_mapper.gd")

func _init() -> void:
	var intent: Dictionary = Mapper.visual_intent({"key": "a", "server": "s", "status": "running", "awaiting_input": true, "blocked": true, "unread": true, "stale": true})
	assert(intent.cue == "closed-gate")
	assert(intent.unread)
	assert(intent.stale)
	assert(Mapper.is_safe_origin("http://127.0.0.1:7373"))
	assert(Mapper.is_safe_origin("https://tycho.example.ts.net"))
	assert(not Mapper.is_safe_origin("https://example.com"))
	print("StateMapper tests passed")
	quit(0)
