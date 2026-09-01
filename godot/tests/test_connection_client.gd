extends SceneTree

const Mapper := preload("res://state_mapper.gd")
const Client := preload("res://connection_client.gd")

func _init() -> void:
	# The fixture is deliberately synthetic: no configured or environment token is
	# ever required for tests, snapshots, or test output.
	var fixture_token := "test-only-token"
	var headers := Client.authorization_headers(fixture_token)
	assert(headers.size() == 1)
	assert(headers[0] == "Authorization: Bearer test-only-token")
	assert(Client.redact_secret("request failed: " + fixture_token, fixture_token) == "request failed: [redacted]")
	assert(Client.redact_secret("safe", fixture_token) == "safe")
	assert(Client.select_token("new-token", "saved-token") == "new-token")
	assert(Client.select_token("", "saved-token") == "saved-token")
	assert(Client.select_token("   ", "") == "")
	assert(Client.select_token("", "saved-token", "https://new", "https://old") == "")
	var scoped := Client.new()
	scoped.origin = "https://old"
	scoped._token = "saved-token"
	scoped._credential_saved = true
	scoped._apply_environment_configuration("https://new", "")
	assert(scoped.origin == "https://new")
	assert(scoped._token.is_empty(), "an environment origin must never inherit another origin's token")
	assert(not scoped.has_saved_credential())
	scoped.free()

	assert(Client.MAX_RETRIES == 3)
	assert(Client.retry_decision(1) == {"status": "retrying", "delay_seconds": 2.0})
	assert(Client.retry_decision(2) == {"status": "retrying", "delay_seconds": 4.0})
	assert(Client.retry_decision(3) == {"status": "offline", "delay_seconds": 0.0})
	assert(Client.retry_decision(99).status == "offline")
	var passed_report := Client.connection_test_report({
		"/servers/activity": {"ok": true},
		"/servers/resources": {"ok": true},
	})
	assert(passed_report.ok)
	assert(not passed_report.started)
	assert(not Client.connection_test_report({"/servers/activity": {"ok": true}}).ok)

	var client := Client.new()
	assert(client.connection_status() == "setup")
	assert(not client.has_saved_credential())
	assert(client.credential_message() == "No saved token.")
	assert(not client.test_connection().started)
	var bad_origin := client.connect_live("https://example.com", fixture_token)
	assert(not bad_origin.ok)
	assert(not str(bad_origin.error).contains(fixture_token))
	var missing_token := client.connect_live("http://localhost", "")
	assert(not missing_token.ok)
	assert(client.connection_status() == "setup")
	client.disconnect_live(false)
	assert(client.connection_status() == "setup")
	for attempt in 2:
		client._connection_failed("test failure")
		assert(client.connection_status() == "retrying", "attempt %d should retry" % (attempt + 1))
	client._connection_failed("test failure")
	assert(client.connection_status() == "offline")
	assert(client.connection_message().contains("Reconnect from Settings"))
	client.free()

	var settings_path := "user://connection-client-persistence-test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	var persistent := Client.new()
	persistent.settings_path = settings_path
	persistent.credential_is_supported = func() -> bool: return true
	persistent.credential_protect = func(token: String, _scope: String) -> Dictionary:
		return {"ok": true, "value": "protected:" + token, "message": "saved"}
	persistent.credential_unprotect = func(value: String, _scope: String) -> Dictionary:
		return {"ok": true, "value": value.trim_prefix("protected:"), "message": "loaded"}
	persistent.origin = "http://localhost"
	persistent._token = fixture_token
	assert(persistent._persist_configuration().ok)
	var saved := ConfigFile.new()
	assert(saved.load(settings_path) == OK)
	assert(saved.get_value("connection", "protected_token") == "protected:" + fixture_token)
	assert(saved.get_value("connection", "protected_token_origin") == "http://localhost")
	# A transient secure-store failure must retain the last known-good ciphertext.
	persistent._token = "replacement-token"
	persistent.credential_protect = func(_token: String, _scope: String) -> Dictionary:
		return {"ok": false, "value": "", "message": "temporary failure"}
	assert(not persistent._persist_configuration().ok)
	var after_failure := ConfigFile.new()
	assert(after_failure.load(settings_path) == OK)
	assert(after_failure.get_value("connection", "protected_token") == "protected:" + fixture_token)
	assert(persistent.credential_message().contains("previous saved token was retained"))
	persistent.credential_protect = func(token: String, _scope: String) -> Dictionary:
		return {"ok": true, "value": "protected:" + token, "message": "saved"}
	assert(persistent.prepare_for_shutdown().ok)
	persistent.disconnect_live(false)
	var after_safe_close := ConfigFile.new()
	assert(after_safe_close.load(settings_path) == OK)
	assert(after_safe_close.get_value("connection", "protected_token") == "protected:replacement-token")
	persistent.free()
	var reloaded := Client.new()
	reloaded.settings_path = settings_path
	reloaded.credential_is_supported = func() -> bool: return true
	reloaded.credential_protect = func(token: String, _scope: String) -> Dictionary:
		return {"ok": true, "value": "protected:" + token, "message": "saved"}
	reloaded.credential_unprotect = func(value: String, _scope: String) -> Dictionary:
		return {"ok": true, "value": value.trim_prefix("protected:"), "message": "loaded"}
	reloaded._load_configuration()
	assert(reloaded.origin == "http://localhost")
	assert(reloaded._token == "replacement-token", "a fresh client must load the safely closed token")
	assert(reloaded.has_saved_credential())
	assert(reloaded.disconnect_live().ok)
	reloaded.free()
	var forgotten := ConfigFile.new()
	assert(forgotten.load(settings_path) == OK)
	assert(not forgotten.has_section_key("connection", "protected_token"))
	assert(not forgotten.has_section_key("connection", "protected_token_origin"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

	assert(Mapper.effective_state(Mapper.normalize_agent({"state": "failed", "awaiting_input": true})) == "awaiting-input")
	assert(Mapper.effective_state(Mapper.normalize_agent({"state": "running", "blocked": true})) == "blocked")
	print("ConnectionClient security and state tests passed")
	quit(0)
