class_name DashSaveStore
extends RefCounted
## Local-only learner slots; these are not authenticated accounts.
## JSON is verified before replacing a valid file. A backup retains the previous
## valid revision. Failed writes never report successful persistence.

const VERSION := 1
const MAX_BYTES := 16777216
var path := "user://diagnostic_dash.json"
var data: Dictionary = {"version": VERSION, "profiles": {}}
var last_error := ""
var blocked_on_corruption := false
var loaded := false

func _init(save_path: String = "user://diagnostic_dash.json") -> void:
	path = save_path

func load_data() -> Dictionary:
	last_error = ""
	blocked_on_corruption = false
	loaded = true
	data = {"version": VERSION, "profiles": {}}
	if OS.has_feature("web"):
		var raw := _web_read_raw(path)
		if not raw.get("ok", false):
			last_error = "Browser storage is unavailable. Keep the game open and export results."
			return data.duplicate(true)
		if not raw.get("exists", false): return data.duplicate(true)
		var browser_data := _parse_saved_text(str(raw.get("raw", "")))
		if browser_data.is_empty():
			blocked_on_corruption = true
			return data.duplicate(true)
		data = browser_data
		return data.duplicate(true)
	if not FileAccess.file_exists(path): return data.duplicate(true)
	var parsed := _read(path)
	if parsed.is_empty():
		blocked_on_corruption = true
		if last_error == "": last_error = "Saved data is damaged or from a newer version. It has not been overwritten."
		return data.duplicate(true)
	data = parsed
	return data.duplicate(true)

func _read(source: String) -> Dictionary:
	if OS.has_feature("web"):
		var raw := _web_read_raw(source)
		if not raw.get("ok", false) or not raw.get("exists", false):
			last_error = "Saved browser data could not be read."
			return {}
		return _parse_saved_text(str(raw.get("raw", "")))
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		last_error = "Saved data could not be read (%s)." % error_string(FileAccess.get_open_error())
		return {}
	if file.get_length() > MAX_BYTES:
		last_error = "Saved data exceeds the supported size and was left untouched."
		return {}
	var saved_text := file.get_as_text()
	file.close()
	return _parse_saved_text(saved_text)

func _parse_saved_text(saved_text: String) -> Dictionary:
	if saved_text.to_utf8_buffer().size() > MAX_BYTES:
		last_error = "Saved data exceeds the supported size and was left untouched."
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(saved_text)
	if parse_error != OK:
		last_error = "Saved data is damaged or incomplete. It has not been overwritten."
		return {}
	var parsed: Variant = parser.data
	if not _valid_data(parsed):
		last_error = "Saved data is damaged or from a newer version. It has not been overwritten."
		return {}
	return parsed

func get_profile(profile_id: String) -> Dictionary:
	if not loaded: load_data()
	if not _valid_id(profile_id):
		last_error = "Choose a nonempty learner slot (up to 80 characters)."
		return _empty_profile()
	return data.profiles.get(profile_id, _empty_profile()).duplicate(true)

func save_profile(profile_id: String, profile: Dictionary) -> bool:
	if not loaded: load_data()
	if not _valid_id(profile_id) or not _valid_profile(profile):
		last_error = "Learner data is invalid; no saved data was changed."
		return false
	var previous: Dictionary = data.duplicate(true)
	data.profiles[profile_id] = profile.duplicate(true)
	if not _write():
		data = previous
		return false
	return true

func get_checkpoint(profile_id: String) -> Dictionary:
	return get_profile(profile_id).get("checkpoint", {}).duplicate(true)

func save_checkpoint(profile_id: String, checkpoint: Dictionary) -> bool:
	var profile := get_profile(profile_id)
	if not _valid_checkpoint(checkpoint):
		last_error = "The interrupted session could not be saved because its data is invalid."
		return false
	profile.checkpoint = checkpoint.duplicate(true)
	return save_profile(profile_id, profile)

func discard_checkpoint(profile_id: String, expected_session_id: String = "") -> bool:
	var profile := get_profile(profile_id)
	if expected_session_id != "" and str(profile.checkpoint.get("session_id", "")) != expected_session_id:
		last_error = "A different interrupted session is now saved; it was not removed."
		return false
	profile.checkpoint = {}
	return save_profile(profile_id, profile)

func complete_session(profile_id: String, result: Dictionary) -> bool:
	var profile := get_profile(profile_id)
	if not _valid_session(result):
		last_error = "Session evidence is inconsistent; the result was not saved."
		return false
	var session_id: String = result.session_id
	var fingerprint := JSON.stringify(_canonical(result)).sha256_text()
	if profile.completed_ids.has(session_id):
		if str(profile.completed_ids[session_id]) != fingerprint:
			last_error = "This session ID already has a different saved result."
			return false
		last_error = ""
		return true
	profile.completed_ids[session_id] = fingerprint
	profile.sessions.append(result.duplicate(true))
	if profile.sessions.size() > 500: profile.sessions.pop_front()
	if str(profile.checkpoint.get("session_id", "")) == session_id:
		profile.checkpoint = {}
	return save_profile(profile_id, profile)

func restore_backup() -> bool:
	# Explicit caller choice only; invalid primary remains inspectable as .corrupt.
	var recovered := _read(path + ".bak")
	if recovered.is_empty(): return false
	if OS.has_feature("web"):
		if not _web_copy(path, path + ".corrupt"): return false
	elif FileAccess.file_exists(path):
		var preserve := DirAccess.copy_absolute(_absolute(path), _absolute(path + ".corrupt"))
		if preserve != OK:
			last_error = "Damaged save could not be preserved; backup restoration was cancelled."
			return false
	data = recovered
	loaded = true
	blocked_on_corruption = false
	return _write(false)

func discard_corrupt_storage() -> bool:
	# The UI must expose this as a deliberate reset, never call it automatically.
	if OS.has_feature("web"):
		if not _web_copy(path, path + ".corrupt"): return false
	elif FileAccess.file_exists(path):
		var preserved := DirAccess.copy_absolute(_absolute(path), _absolute(path + ".corrupt"))
		if preserved != OK:
			last_error = "Damaged save could not be preserved; reset was cancelled."
			return false
	data = {"version": VERSION, "profiles": {}}
	blocked_on_corruption = false
	loaded = true
	return _write(false)

func _write(keep_backup: bool = true) -> bool:
	if blocked_on_corruption:
		last_error = "Saved data is damaged. Choose Restore backup or Reset saved data before saving."
		return false
	if not _valid_data(data):
		last_error = "Saved data failed validation."
		return false
	var text := JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		last_error = "Saved data is full. Export or clear older local learner data."
		return false
	if OS.has_feature("web"):
		# FileAccess on Web acknowledges its in-memory write before IndexedDB
		# finishes. A synchronous browser-storage commit gives this small local
		# ledger an honest reload boundary. setItem is atomic; quota/access errors
		# preserve the previous primary value and are reported to the player.
		var key := JSON.stringify(_web_key(path))
		var encoded := JSON.stringify(text)
		var script := "JSON.stringify((()=>{try{const k=%s,old=localStorage.getItem(k);if(%s&&old!==null)localStorage.setItem(k+'.bak',old);localStorage.setItem(k,%s);return{ok:localStorage.getItem(k)===%s};}catch(e){return{ok:false,error:String(e)};}})())" % [key, "true" if keep_backup else "false", encoded, encoded]
		var result = JSON.parse_string(str(JavaScriptBridge.eval(script, true)))
		if not result is Dictionary or not result.get("ok", false):
			last_error = "Browser storage is full or unavailable. Keep the game open and export this result."
			return false
		last_error = ""
		return true
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Progress could not be saved (%s). Keep this window open." % error_string(FileAccess.get_open_error())
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Progress could not be written. Keep this window open."
		return false
	var verified := _read(temporary)
	if verified.is_empty():
		last_error = "The new save could not be verified. Your previous save was kept."
		return false
	if keep_backup and FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(_absolute(path), _absolute(path + ".bak"))
		if backup_error != OK:
			last_error = "Previous save could not be backed up; it was left unchanged."
			return false
	var error := DirAccess.rename_absolute(_absolute(temporary), _absolute(path))
	if error != OK:
		last_error = "The save could not replace the previous revision (%s)." % error_string(error)
		return false
	last_error = ""
	return true

func _absolute(value: String) -> String:
	return ProjectSettings.globalize_path(value)

func _web_key(source: String) -> String:
	return "ddgodot:v1:" + source

func _web_read_raw(source: String) -> Dictionary:
	var script := "JSON.stringify((()=>{try{const v=localStorage.getItem(%s);return{ok:true,exists:v!==null,raw:v||''};}catch(e){return{ok:false,error:String(e)};}})())" % JSON.stringify(_web_key(source))
	var result = JSON.parse_string(str(JavaScriptBridge.eval(script, true)))
	return result if result is Dictionary else {"ok": false}

func _web_copy(source: String, destination: String) -> bool:
	var script := "JSON.stringify((()=>{try{const v=localStorage.getItem(%s);if(v!==null)localStorage.setItem(%s,v);return{ok:true};}catch(e){return{ok:false,error:String(e)};}})())" % [JSON.stringify(_web_key(source)), JSON.stringify(_web_key(destination))]
	var result = JSON.parse_string(str(JavaScriptBridge.eval(script, true)))
	if not result is Dictionary or not result.get("ok", false):
		last_error = "The original browser save could not be preserved. Reset was cancelled."
		return false
	return true

static func _empty_profile() -> Dictionary:
	return {"evidence": {}, "sessions": [], "checkpoint": {}, "settings": {}, "completed_ids": {}}

static func _valid_id(value: String) -> bool:
	return value.strip_edges() != "" and value.length() <= 80

static func _valid_data(value: Variant) -> bool:
	if not value is Dictionary or not _whole_number(value.get("version")) or int(value.version) != VERSION or not value.get("profiles") is Dictionary: return false
	if not _json_safe(value): return false
	for profile_id in value.profiles:
		if not profile_id is String or not _valid_id(profile_id) or not _valid_profile(value.profiles[profile_id]): return false
	return true

static func _valid_profile(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in ["evidence", "checkpoint", "settings", "completed_ids"]:
		if not value.get(field) is Dictionary: return false
	for scope in value.evidence.values():
		if not scope is Dictionary: return false
		for stat in scope.values():
			if not stat is Dictionary or not _whole_number(stat.get("att")) or not _whole_number(stat.get("cor")): return false
			if int(stat.att) < 0 or int(stat.cor) < 0 or int(stat.cor) > int(stat.att): return false
			for field in ["streak", "interval", "stage", "lastTs", "run2", "assisted", "timeout_count"]:
				if stat.has(field) and (not _whole_number(stat[field]) or int(stat[field]) < 0): return false
			if stat.has("lastIdx") and not _whole_number(stat.lastIdx): return false
			if stat.has("lats"):
				if not stat.lats is Array: return false
				for latency in stat.lats:
					if not (latency is int or latency is float) or not is_finite(float(latency)) or float(latency) < 0.0: return false
	if not value.get("sessions") is Array or value.sessions.size() > 500: return false
	for session in value.sessions:
		if not _valid_session(session): return false
	for session_id in value.completed_ids:
		if not session_id is String or session_id == "" or not value.completed_ids[session_id] is String: return false
	return _valid_checkpoint(value.checkpoint) and _json_safe(value)

static func _valid_checkpoint(value: Variant) -> bool:
	if not value is Dictionary or not _json_safe(value): return false
	if value.is_empty(): return true
	return value.get("session_id") is String and value.session_id != ""

static func _valid_session(value: Variant) -> bool:
	if not value is Dictionary or not value.get("session_id") is String or value.session_id == "" or not _json_safe(value): return false
	for field in ["first_try_opportunities", "first_try_correct", "eventual_correct", "attempts", "retries", "assisted", "timeouts"]:
		if not (value.get(field) is int or value.get(field) is float): return false
		if float(value[field]) < 0.0 or float(value[field]) != floor(float(value[field])): return false
	if int(value.first_try_correct) > int(value.first_try_opportunities) or int(value.eventual_correct) > int(value.first_try_opportunities): return false
	if int(value.first_try_correct) > int(value.eventual_correct) or int(value.assisted) > int(value.eventual_correct): return false
	if int(value.first_try_opportunities) > int(value.attempts) or int(value.retries) + int(value.timeouts) > int(value.attempts): return false
	if value.has("facts"):
		if not value.facts is Array or value.facts.size() != int(value.first_try_opportunities): return false
		var ids: Dictionary = {}
		var first := 0
		var eventual := 0
		var attempts := 0
		var retries := 0
		var timeouts := 0
		var assisted := 0
		for fact in value.facts:
			if not fact is Dictionary or not fact.get("observed", false): return false
			if ids.has(fact.get("id", -1)): return false
			ids[fact.get("id", -1)] = true
			if fact.get("first_correct", false): first += 1
			if fact.get("correct", false): eventual += 1
			if fact.get("assisted", false) and fact.get("correct", false): assisted += 1
			attempts += int(fact.get("attempts", 0)) + int(fact.get("timeouts", 0))
			retries += int(fact.get("retries", 0))
			timeouts += int(fact.get("timeouts", 0))
		if first != int(value.first_try_correct) or eventual != int(value.eventual_correct) or attempts != int(value.attempts) or retries != int(value.retries) or timeouts != int(value.timeouts) or assisted != int(value.assisted): return false
	return true

static func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for child in value:
				if not _json_safe(child, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not (key is String or key is StringName) or not _json_safe(value[key], depth + 1): return false
			return true
	return false

static func _canonical(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_canonical(item))
		return result
	return value
