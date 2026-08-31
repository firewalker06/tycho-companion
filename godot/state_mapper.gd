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
		"server": str(raw.get("server_name", raw.get("server", raw.get("server_key", "")))),
		"server_key": str(raw.get("server_key", raw.get("server", ""))),
		"server_status": str(raw.get("server_status", "")).to_lower(),
		"offline": raw.get("offline", false) == true or raw.get("server_status", "") == "offline",
		"project": str(raw.get("project_key", raw.get("project", ""))),
		"agent": str(raw.get("name", raw.get("agent", ""))),
		"state": state,
		"unread": raw.get("unread", false) == true,
		"awaiting_input": raw.get("awaiting_input", false) == true,
		"blocked": raw.get("blocked", false) == true,
		"stale": raw.get("stale", false) == true or raw.get("offline", false) == true or raw.get("server_status", "") in ["offline", "stale"],
		"prompt_queue_count": raw.get("prompt_queue_count", null),
	}

static func flatten_activity(activity: Dictionary) -> Array[Dictionary]:
	## Tycho's activity snapshot is server-qualified. Keep that identity and its
	## health on every record; the scene must never infer it from agent data.
	var flattened: Array[Dictionary] = []
	var servers: Variant = activity.get("servers", [])
	if not servers is Array:
		return flattened
	for server_value in servers:
		if not server_value is Dictionary:
			continue
		var server: Dictionary = server_value
		var server_key := str(server.get("key", server.get("server_key", "")))
		var server_name := str(server.get("name", server.get("server_name", server_key)))
		var health := str(server.get("health", server.get("status", ""))).to_lower()
		var is_stale: bool = server.get("stale", false) == true or server.get("offline", false) == true or health in ["offline", "stale"]
		var server_agents: Variant = server.get("agents", [])
		if not server_agents is Array:
			continue
		for agent_value in server_agents:
			if not agent_value is Dictionary:
				continue
			var agent: Dictionary = agent_value.duplicate()
			agent["server_key"] = server_key
			agent["server_name"] = server_name
			agent["server_status"] = health
			agent["offline"] = health == "offline" or server.get("offline", false) == true
			agent["stale"] = is_stale or agent.get("stale", false) == true
			flattened.append(agent)
	return flattened

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
	var origin := parse_origin(value)
	if origin.is_empty():
		return false
	var scheme: String = origin.scheme
	var host: String = origin.host
	if scheme == "http":
		return host == "localhost" or host == "127.0.0.1"
	if scheme == "https":
		return _is_single_label(host) or _is_tailscale_host(host)
	return false

static func parse_origin(value: String) -> Dictionary:
	# Godot has no general URL value type. Parse the origin grammar explicitly so callers
	# cannot smuggle a path, credentials, query, or fragment through a string prefix check.
	var parser := RegEx.new()
	if parser.compile("^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)(/?)$") != OK:
		return {}
	var match := parser.search(value)
	if match == null:
		return {}
	var scheme: String = match.get_string(1).to_lower()
	var authority: String = match.get_string(2)
	if authority.contains("@") or authority.contains("%"):
		return {}
	var pieces := authority.split(":", false)
	if pieces.size() > 2 or pieces.is_empty():
		return {}
	var host: String = pieces[0].to_lower()
	if host.is_empty() or not _is_hostname(host):
		return {}
	if pieces.size() == 2 and not _is_valid_port(pieces[1]):
		return {}
	return {"scheme": scheme, "host": host}

static func _is_valid_port(value: String) -> bool:
	if value.is_empty() or not value.is_valid_int():
		return false
	var port := value.to_int()
	return port >= 1 and port <= 65535

static func _is_hostname(host: String) -> bool:
	var label := RegEx.new()
	if label.compile("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$") != OK:
		return false
	for part in host.split(".", false):
		if label.search(part) == null:
			return false
	return true

static func _is_single_label(host: String) -> bool:
	return not host.contains(".")

static func _is_tailscale_host(host: String) -> bool:
	return host.ends_with(".ts.net") and host.length() > ".ts.net".length()
