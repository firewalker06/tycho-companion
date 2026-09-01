extends SceneTree

const Store := preload("res://credential_store.gd")

func _init() -> void:
	assert(Store.is_supported("Windows"))
	assert(not Store.is_supported("macOS"))
	assert(Store.PROTECT_SCRIPT.contains(Store.TOKEN_ENV))
	assert(Store.UNPROTECT_SCRIPT.contains(Store.CIPHERTEXT_ENV))
	assert(Store.PROTECT_SCRIPT.contains(Store.SCOPE_ENV))
	assert(Store.UNPROTECT_SCRIPT.contains(Store.SCOPE_ENV))
	assert(not Store.PROTECT_SCRIPT.contains("test-only-token"))
	assert(Store.process_result(0, ["protected-value\r\n"]).value == "protected-value")
	assert(not Store.process_result(1, ["failure"]).ok)
	assert(Store.powershell_executable("") == "powershell.exe")
	assert(Store.powershell_executable("C:/Windows") == "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
	var fixture_token := "test-only-token"
	var fixture_scope := "http://localhost"
	var unavailable := Store.protect(fixture_token, fixture_scope)
	if OS.get_name() == "Windows":
		assert(unavailable.ok)
		assert(unavailable.value != fixture_token)
		var round_trip := Store.unprotect(unavailable.value, fixture_scope)
		assert(round_trip.ok)
		assert(round_trip.value == fixture_token)
		assert(not Store.unprotect(unavailable.value, "https://different").ok)
	else:
		assert(not unavailable.ok)
		assert(not str(unavailable.message).contains(fixture_token))
	print("Credential store tests passed")
	quit(0)
