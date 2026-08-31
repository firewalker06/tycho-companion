class_name StateMapper
extends RefCounted

const STATES := ["idle", "running", "awaiting-input", "blocked", "succeeded", "failed", "partial", "stopped"]

static func normalize_agent(raw: Dictionary) -> Dictionary:
	var state := str(raw.get("status", raw.get("state", "idle"))).to_lower()
	if state == "awaiting_input":
		state = "awaiting-input"
	if not STATES.has(state):
		state = "idle"
	return {
		"key": str(raw.get("key", "")),
		"server": str(raw.get("server", "")),
		"project": str(raw.get("project_key", raw.get("project", ""))),
		"agent": str(raw.get("name", raw.get("agent", ""))),
		"state": state,
		"unread": raw.get("unread", false) == true,
		"awaiting_input": raw.get("awaiting_input", false) == true,
		"blocked": raw.get("blocked", false) == true,
		"stale": raw.get("stale", false) == true or raw.get("server_status", "") == "offline",
		"prompt_queue_count": raw.get("prompt_queue_count", null),
	}

static func effective_state(agent: Dictionary) -> String:
	if agent.blocked:
		return "blocked"
	if agent.awaiting_input:
		return "awaiting-input"
	return agent.state

static func visual_intent(raw: Dictionary) -> Dictionary:
	var agent := normalize_agent(raw)
	var state := effective_state(agent)
	var cue: String = {
		"idle": "rest", "running": "workbench", "awaiting-input": "question-lantern", "blocked": "closed-gate",
		"succeeded": "warm-lamp", "failed": "rain-cloud", "partial": "cracked-sign", "stopped": "stopped-tool",
	}.get(state, "rest")
	return {"id": "%s/%s" % [agent.server, agent.key], "cue": cue, "unread": agent.unread, "stale": agent.stale, "queue_count": agent.prompt_queue_count}

static func is_safe_origin(value: String) -> bool:
	var lower := value.to_lower()
	return lower.begins_with("http://localhost") or lower.begins_with("http://127.0.0.1") or lower.begins_with("https://") and (lower.contains(".ts.net") or not lower.substr(8).contains("."))
