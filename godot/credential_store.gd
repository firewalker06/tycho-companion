class_name CredentialStore
extends RefCounted

## Windows DPAPI binds the encrypted value to the current Windows account.
## Protection input reaches PowerShell through a short-lived inherited
## environment variable. Unprotected plaintext returns only through the captured
## child-process output buffer. Neither value enters argv, logs, or config files.

const TOKEN_ENV := "TYCHO_COMPANION_TOKEN_INPUT"
const CIPHERTEXT_ENV := "TYCHO_COMPANION_TOKEN_CIPHERTEXT"
const SCOPE_ENV := "TYCHO_COMPANION_TOKEN_SCOPE"
const PROTECT_SCRIPT := "$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Security;$value=[Environment]::GetEnvironmentVariable('TYCHO_COMPANION_TOKEN_INPUT');$scope=[Environment]::GetEnvironmentVariable('TYCHO_COMPANION_TOKEN_SCOPE');$bytes=[Text.Encoding]::UTF8.GetBytes($value);$entropy=[Text.Encoding]::UTF8.GetBytes($scope);$protected=[Security.Cryptography.ProtectedData]::Protect($bytes,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser);[Convert]::ToBase64String($protected)"
const UNPROTECT_SCRIPT := "$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Security;$value=[Environment]::GetEnvironmentVariable('TYCHO_COMPANION_TOKEN_CIPHERTEXT');$scope=[Environment]::GetEnvironmentVariable('TYCHO_COMPANION_TOKEN_SCOPE');$protected=[Convert]::FromBase64String($value);$entropy=[Text.Encoding]::UTF8.GetBytes($scope);$bytes=[Security.Cryptography.ProtectedData]::Unprotect($protected,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser);[Text.Encoding]::UTF8.GetString($bytes)"

static func is_supported(platform_name: String = OS.get_name()) -> bool:
	return platform_name == "Windows"

static func protect(token: String, scope: String) -> Dictionary:
	if not is_supported():
		return {"ok": false, "value": "", "message": "Secure token storage is unavailable on this platform."}
	return _run_powershell(PROTECT_SCRIPT, TOKEN_ENV, token, scope)

static func unprotect(ciphertext: String, scope: String) -> Dictionary:
	if not is_supported():
		return {"ok": false, "value": "", "message": "Secure token storage is unavailable on this platform."}
	return _run_powershell(UNPROTECT_SCRIPT, CIPHERTEXT_ENV, ciphertext, scope)

static func _run_powershell(script: String, environment_key: String, value: String, scope: String) -> Dictionary:
	OS.set_environment(environment_key, value)
	OS.set_environment(SCOPE_ENV, scope)
	var output: Array = []
	var exit_code := OS.execute(powershell_executable(), PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script]), output, true, false)
	OS.unset_environment(environment_key)
	OS.unset_environment(SCOPE_ENV)
	return process_result(exit_code, output)

static func powershell_executable(system_root: String = OS.get_environment("SystemRoot")) -> String:
	if system_root.is_empty():
		return "powershell.exe"
	return system_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")

static func process_result(exit_code: int, output: Array) -> Dictionary:
	if exit_code != 0 or output.is_empty():
		return {"ok": false, "value": "", "message": "Windows could not access the protected credential."}
	var result := str(output[0]).strip_edges()
	if result.is_empty():
		return {"ok": false, "value": "", "message": "Windows returned an empty protected credential."}
	return {"ok": true, "value": result, "message": "Credential protected for the current Windows account."}
