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

	var client := Client.new()
	assert(client.connection_status() == "setup")
	var bad_origin := client.connect_live("https://example.com", fixture_token)
	assert(not bad_origin.ok)
	assert(not str(bad_origin.error).contains(fixture_token))
	var missing_token := client.connect_live("http://localhost", "")
	assert(not missing_token.ok)
	assert(client.connection_status() == "setup")
	client.disconnect_live()
	assert(client.connection_status() == "setup")
	client.free()

	assert(Mapper.effective_state(Mapper.normalize_agent({"state": "failed", "awaiting_input": true})) == "awaiting-input")
	assert(Mapper.effective_state(Mapper.normalize_agent({"state": "running", "blocked": true})) == "blocked")
	print("ConnectionClient security and state tests passed")
	quit(0)
