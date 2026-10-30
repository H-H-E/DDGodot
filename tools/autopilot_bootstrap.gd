extends SceneTree
## Test-only entry point: load the real upstream instrumentation, then the normal
## game. The released game has no Autopilot autoload or remote-control listener.

func _initialize() -> void:
	call_deferred("_start_game")


func _start_game() -> void:
	var bridge_script = load("res://addons/autopilot/playtest.gd")
	if bridge_script == null:
		push_error("Cannot load the vendored Autopilot instrumentation")
		quit(1)
		return
	var bridge = bridge_script.new()
	bridge.name = "AutopilotPlaytest"
	root.add_child(bridge)
	var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if scene_path.is_empty():
		push_error("Project has no main scene")
		quit(1)
		return
	var packed = load(scene_path)
	if packed == null:
		push_error("Cannot load main scene: " + scene_path)
		quit(1)
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
