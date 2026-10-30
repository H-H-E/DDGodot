extends Control
## Session coordinator. Educational evidence, simulation, and drawing stay separate.
const Learning = preload("res://scripts/learning.gd")
const Store = preload("res://scripts/save_store.gd")
const Course = preload("res://scripts/course.gd")
const RunnerView = preload("res://scripts/runner_view.gd")
const Sound = preload("res://scripts/sound.gd")
const BG := Color("0a1226")
const TEXT := Color("edf3ed")
const MUTED := Color("a8b9cd")
const ACCENT := Color("d5ed81")
const TEAL := Color("72e4cc")
const PANEL := Color("16243d")
var learning = Learning.new()
var store = Store.new()
var course = Course.new()
var sound: Node
var view: Control
var scroll: ScrollContainer
var ui: Control
var controls: Dictionary = {}
var labels: Dictionary = {}
var screen := "menu"
var mode := "practice"
var operation := "addition"
var number_range := 10
var target := 12
var pace := 0
var auto_jump := true
var reduced_motion := false
var high_contrast := false
var audio_enabled := true
var volume := 0.35
var color_index := 0
var learner_id := "player-1"
var seed_value := 73
var forced_seed := -1
var session_id := ""
var completed := 0
var active_seconds := 0.0
var question_elapsed := 0.0
var last_attempt_elapsed := 0.0
var input_text := ""
var feedback := ""
var feedback_kind := "neutral"
var feedback_age := 0.0
var gate_solved := false
var timed_out := false
var transition_seconds := 0.0
var question: Dictionary = {}
var last_result: Dictionary = {}
var last_tick := 0
var checkpoint_age := 0.0
var bridge_age := 0.0
var last_beat := -1
var started_at := ""
var save_notice := ""
var js_callback
var js_resize_callback
var qa_enabled := false
var ui_ready := false
var exported_result := false

func _ready() -> void:
	name = "Main"
	_configure_web_scale()
	var game_theme := Theme.new()
	game_theme.default_font = preload("res://assets/fonts/DejaVuSans.ttf")
	game_theme.default_font_size = 18
	theme = game_theme
	store.load_data()
	_load_settings()
	sound = Sound.new()
	add_child(sound)
	_update_preferences()
	course.reset(seed_value)
	last_tick = Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dd-seed="):
			forced_seed = int(argument.get_slice("=", 1))
	resized.connect(_resize_ui)
	get_tree().root.focus_exited.connect(_focus_lost)
	if OS.has_feature("web"):
		# Canvas backing-buffer resizes can preserve the old logical viewport,
		# so Control.resized alone cannot detect every browser viewport change.
		js_resize_callback = JavaScriptBridge.create_callback(_web_resize)
		JavaScriptBridge.get_interface("window").addEventListener("resize", js_resize_callback)
		qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('qa') === '1'"))
		if qa_enabled:
			js_callback = JavaScriptBridge.create_callback(_web_qa_command)
			JavaScriptBridge.get_interface("window").ddCommand = js_callback
		var prefers_reduced = JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches")
		if prefers_reduced:
			reduced_motion = true
	ui_ready = true
	_build_ui()

func _resize_ui() -> void:
	_configure_web_scale()
	if ui_ready:
		_build_ui()

func _web_resize(_args: Array) -> void:
	# Defer until the browser has updated its canvas and viewport dimensions.
	call_deferred("_resize_ui")

func _configure_web_scale() -> void:
	if not OS.has_feature("web"): return
	# WebGL's backing buffer follows devicePixelRatio. Layout is in CSS pixels
	# so a 390px phone never becomes a tiny desktop UI on a 780px buffer.
	var css = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify({w:window.innerWidth,h:window.innerHeight})", true)))
	if not css is Dictionary: return
	var window := get_tree().root
	var logical_size := Vector2i(maxi(320, int(css.w)), maxi(240, int(css.h)))
	if window.content_scale_size != logical_size:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_size = logical_size

func _focus_lost() -> void:
	if screen == "playing":
		_pause()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and screen == "playing":
		_pause()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and screen in ["playing", "paused"]:
		_save_checkpoint()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := maxf(0, float(now - last_tick) / 1000000.0)
	last_tick = now
	# A hidden tab / suspended app must never turn into an arithmetic timeout.
	if elapsed > 1.5 and screen == "playing":
		_pause()
		elapsed = 0
	if screen == "playing":
		active_seconds += elapsed
		feedback_age += elapsed
		if gate_solved:
			transition_seconds += elapsed
			if transition_seconds >= 0.8:
				if completed >= target:
					_finish()
				else:
					_new_question()
		else:
			question_elapsed += elapsed
			if mode != "practice" and not timed_out and question_elapsed >= _gate_duration():
				learning.timeout(question_elapsed)
				last_attempt_elapsed = question_elapsed
				timed_out = true
				course.waiting = true
				feedback = "Time for a reset. " + learning.use_hint()
				feedback_kind = "hint"
				feedback_age = 0
				_save_checkpoint()
		if mode == "cadence":
			var beat := int(active_seconds / 0.6)
			if beat != last_beat:
				last_beat = beat
				sound.play_tone("beat")
		checkpoint_age += elapsed
		if checkpoint_age >= 1:
			_save_checkpoint()
		_update_hud()
	if is_instance_valid(view):
		view.active = screen in ["playing", "paused", "results"]
		view.reduced_motion = reduced_motion or screen == "paused"
		view.pulse = maxf(0, 1 - fmod(active_seconds, 0.6) / 0.3) if mode == "cadence" and screen == "playing" else 0
	bridge_age += delta
	if OS.has_feature("web") and bridge_age >= 0.1:
		bridge_age = 0
		_publish_web_state()

func _physics_process(delta: float) -> void:
	if screen != "playing":
		return
	if course.step(delta, _gate_duration(), mode == "practice", auto_jump):
		feedback = "Caught the edge. You're back in — your maths record is unchanged."
		feedback_kind = "hint"
		feedback_age = 0
		sound.play_tone("wrong")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_ESCAPE or (key == KEY_P and screen in ["playing", "paused"]):
		if screen == "playing": _pause()
		elif screen == "paused": _resume()
		elif screen != "menu": _show("menu")
		get_viewport().set_input_as_handled()
		return
	if screen != "playing":
		return
	if key >= KEY_0 and key <= KEY_9:
		_digit(str(key - KEY_0))
	elif key >= KEY_KP_0 and key <= KEY_KP_9:
		_digit(str(key - KEY_KP_0))
	elif key == KEY_BACKSPACE or key == KEY_DELETE:
		_backspace()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		_submit()
	elif key == KEY_SPACE or key == KEY_UP:
		_jump()
	elif key == KEY_H:
		_hint()
	else:
		return
	get_viewport().set_input_as_handled()

func _show(next_screen: String) -> void:
	screen = next_screen
	last_tick = Time.get_ticks_usec()
	if screen != "playing": sound.hush()
	_build_ui()

func _start_run() -> void:
	if not store.get_checkpoint(learner_id).is_empty():
		save_notice = "Resume or discard your saved run before starting a new one."
		_show("menu")
		return
	seed_value = 73 + int(Time.get_ticks_msec() % 100000)
	if forced_seed >= 0: seed_value = forced_seed
	session_id = "%s-%s-%s" % [learner_id, int(Time.get_unix_time_from_system() * 1000), randi()]
	started_at = Time.get_datetime_string_from_system(true)
	var profile: Dictionary = store.get_profile(learner_id)
	var evidence: Dictionary = profile.get("evidence", {}).get(_bucket_key(), {})
	learning.configure(operation, number_range, seed_value, evidence.duplicate(true), {"practice": mode == "practice"})
	course.reset(seed_value)
	completed = 0
	active_seconds = 0
	last_beat = -1
	last_result = {}
	exported_result = false
	save_notice = ""
	screen = "playing"
	_new_question()
	last_tick = Time.get_ticks_usec()
	_build_ui()
	_save_checkpoint()

func _new_question() -> void:
	question = learning.next_question()
	input_text = ""
	question_elapsed = 0
	last_attempt_elapsed = 0
	transition_seconds = 0
	gate_solved = false
	timed_out = false
	feedback = "Type your answer, then press Enter." if completed == 0 else "Next gate. Find your rhythm."
	feedback_kind = "neutral"
	feedback_age = 0
	course.new_gate()
	_update_hud()

func _digit(digit: String) -> void:
	if screen != "playing" or gate_solved or input_text.length() >= 4:
		return
	input_text = digit if input_text == "0" else input_text + digit
	_update_hud()
	_save_checkpoint()

func _backspace() -> void:
	if screen != "playing" or gate_solved: return
	input_text = input_text.left(maxi(0, input_text.length() - 1))
	_update_hud()
	_save_checkpoint()

func _submit() -> void:
	if screen != "playing" or gate_solved or input_text.is_empty():
		return
	var result: Dictionary = learning.submit(int(input_text), maxf(0, question_elapsed - last_attempt_elapsed))
	last_attempt_elapsed = question_elapsed
	if result.get("correct", false):
		completed += 1
		gate_solved = true
		transition_seconds = 0
		feedback = "Gate open. Nicely worked." if result.get("first_try", false) else "You got there. Keep that fact for next time."
		feedback_kind = "correct"
		course.clear_gate(auto_jump)
		if is_instance_valid(view): view.effect = 1
		sound.play_tone("correct")
	else:
		feedback = str(result.get("feedback", "Not quite. Try again — the gate is still yours."))
		feedback_kind = "wrong"
		input_text = ""
		sound.play_tone("wrong")
	feedback_age = 0
	_update_hud()
	_save_checkpoint()

func _hint() -> void:
	if screen != "playing" or gate_solved: return
	feedback = learning.use_hint()
	feedback_kind = "hint"
	feedback_age = 0
	_update_hud()
	_save_checkpoint()

func _jump() -> void:
	if screen != "playing": return
	course.jump()
	sound.play_tone("jump")

func _pause() -> void:
	if screen != "playing": return
	screen = "paused"
	_save_checkpoint()
	_show("paused")

func _resume() -> void:
	if screen != "paused": return
	_show("playing")

func _finish() -> void:
	if screen not in ["playing", "paused"]: return
	screen = "results"
	last_result = learning.summary().duplicate(true)
	last_result.merge({"session_id": session_id, "learner_id": learner_id, "mode": mode, "operation": operation, "range": number_range, "target": target, "completed": completed, "active_seconds": snappedf(active_seconds, 0.001), "created_at": started_at, "collisions": course.collisions, "seed": seed_value})
	var profile: Dictionary = store.get_profile(learner_id)
	profile["evidence"][_bucket_key()] = learning.export_evidence()
	var profile_saved: bool = store.save_profile(learner_id, profile)
	var result_saved: bool = store.complete_session(learner_id, last_result) if profile_saved else false
	save_notice = "Saved on this device for " + _learner_name() + "." if result_saved else "Saving is unavailable. Export this result before closing."
	if result_saved:
		store.discard_checkpoint(learner_id)
	sound.play_tone("finish")
	_build_ui()

func _gate_duration() -> float:
	return [14.0, 10.0, 7.0][pace]

func _bucket_key() -> String:
	return "%s:%d" % [operation, number_range]

func _learner_name() -> String:
	return learner_id.replace("player-", "Player ")

func _save_checkpoint() -> void:
	checkpoint_age = 0
	if screen not in ["playing", "paused"]: return
	var checkpoint := {"version": 1, "session_id": session_id, "learner_id": learner_id, "started_at": started_at, "mode": mode, "operation": operation, "range": number_range, "target": target, "pace": pace, "seed": seed_value, "completed": completed, "active_seconds": active_seconds, "question_elapsed": question_elapsed, "last_attempt_elapsed": last_attempt_elapsed, "input": input_text, "gate_solved": gate_solved, "timed_out": timed_out, "transition_seconds": transition_seconds, "question": question, "learning": learning.export_state(), "course": course.snapshot(), "feedback": feedback, "feedback_kind": feedback_kind}
	if not store.save_checkpoint(learner_id, checkpoint):
		save_notice = "This device could not save progress. Keep the game open."

func _restore_checkpoint() -> void:
	var c: Dictionary = store.get_checkpoint(learner_id)
	if c.is_empty(): return
	if not _valid_run_checkpoint(c) or not learning.restore_state(c.get("learning", {})):
		save_notice = "That saved run could not be restored. Discard it to start again."
		_build_ui()
		return
	if int(learning.summary().get("eventual_correct", 0)) != int(c.completed):
		save_notice = "That saved run has inconsistent results. Discard it to start again."
		_build_ui()
		return
	session_id = str(c.session_id)
	started_at = str(c.started_at)
	mode = str(c.mode)
	operation = str(c.operation)
	number_range = int(c.range)
	target = int(c.target)
	pace = clampi(int(c.pace), 0, 2)
	seed_value = int(c.seed)
	completed = int(c.completed)
	active_seconds = float(c.active_seconds)
	question_elapsed = float(c.question_elapsed)
	last_attempt_elapsed = float(c.get("last_attempt_elapsed", 0))
	input_text = str(c.input)
	gate_solved = bool(c.gate_solved)
	timed_out = bool(c.timed_out)
	transition_seconds = float(c.transition_seconds)
	question = c.question
	feedback = str(c.feedback)
	feedback_kind = str(c.feedback_kind)
	course.restore(c.course)
	_show("paused")

func _discard_checkpoint() -> void:
	store.discard_checkpoint(learner_id)
	save_notice = ""
	_build_ui()

func _load_settings() -> void:
	var s: Dictionary = store.get_profile(learner_id).get("settings", {})
	auto_jump = s.get("auto_jump", true) == true
	reduced_motion = s.get("reduced_motion", false) == true
	high_contrast = s.get("high_contrast", false) == true
	audio_enabled = s.get("audio_enabled", true) == true
	volume = clampf(float(s.get("volume", 0.35)), 0, 1) if s.get("volume", 0.35) is float or s.get("volume", 0.35) is int else 0.35
	color_index = clampi(int(s.get("color_index", 0)), 0, 3) if s.get("color_index", 0) is float or s.get("color_index", 0) is int else 0

func _save_settings() -> void:
	var p: Dictionary = store.get_profile(learner_id)
	p["settings"] = {"auto_jump": auto_jump, "reduced_motion": reduced_motion, "high_contrast": high_contrast, "audio_enabled": audio_enabled, "volume": volume, "color_index": color_index}
	store.save_profile(learner_id, p)
	_update_preferences()

func _update_preferences() -> void:
	if is_instance_valid(sound):
		sound.enabled = audio_enabled
		sound.volume = volume
		if not audio_enabled: sound.hush()
	if is_instance_valid(view):
		view.reduced_motion = reduced_motion
		view.high_contrast = high_contrast
		view.runner_color = [ACCENT, TEAL, Color("b9b3ff"), Color("ffbd8a")][color_index % 4]

func _build_ui() -> void:
	if not ui_ready: return
	if is_instance_valid(scroll):
		remove_child(scroll)
		scroll.queue_free()
	controls.clear()
	labels.clear()
	var w := maxf(320, size.x)
	var mobile := w < 700
	var h := maxf(size.y, 700 if mobile else 650)
	scroll = ScrollContainer.new()
	scroll.name = "UIScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	ui = Control.new()
	ui.name = "UI"
	ui.custom_minimum_size = Vector2(w, h)
	ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ui)
	view = RunnerView.new()
	view.name = "RunnerView"
	view.course = course
	ui.add_child(view)
	_update_preferences()
	var margin := 20.0 if mobile else 44.0
	_label("Brand", "DIAGNOSTIC / DASH", Rect2(margin, 18, w - 130, 28), 15, ACCENT)
	_button("Sound", "Sound" if audio_enabled else "Muted", Rect2(w - margin - 74, 14, 74, 38), _toggle_sound, "quiet", 14)
	if screen in ["playing", "paused"]:
		_build_game(w, h, mobile)
	elif screen == "menu":
		_build_menu(w, h, mobile)
	elif screen == "modes":
		_build_modes(w, h, mobile)
	elif screen == "setup":
		_build_setup(w, h, mobile)
	elif screen == "settings":
		_build_settings(w, h, mobile)
	elif screen == "progress":
		_build_progress(w, h, mobile)
	elif screen == "results":
		_build_results(w, h, mobile)
	if not save_notice.is_empty() and screen != "results":
		if not labels.has("SaveNotice"):
			_label("SaveNotice", save_notice, Rect2(margin, ui.custom_minimum_size.y - 36, w - margin * 2, 32), 13, Color("ffd49b"))
	elif screen not in ["playing", "paused"]:
		_label("LocalNote", _learner_name() + " · Saved on this device · No account needed", Rect2(margin, ui.custom_minimum_size.y - 34, w - margin * 2, 28), 13, MUTED)
	call_deferred("_focus_default")

func _build_menu(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else 68.0
	var tw := w - 48 if mobile else w * 0.5
	_label("Eyebrow", "A LITTLE MATHS. A LOT OF MOMENTUM.", Rect2(x, 86, tw, 28), 12, TEAL)
	_label("Title", "Find your\nflow.", Rect2(x, 124, tw, 170), 54 if mobile else 72, TEXT)
	_label("Subtitle", "Think it through. Open the gate.\nMake your next run your own.", Rect2(x, 292 if mobile else 324, tw, 64), 18, MUTED)
	var checkpoint: Dictionary = store.get_checkpoint(learner_id)
	var y := 382.0 if mobile else 412.0
	if not checkpoint.is_empty():
		_button("ResumeSaved", "Resume saved run  →", Rect2(x, y, minf(tw, 350), 58), _restore_checkpoint, "primary")
		_button("DiscardSaved", "Discard saved run", Rect2(x, y + 68, minf(tw, 350), 44), _discard_checkpoint, "quiet", 15)
		y += 124
	if checkpoint.is_empty():
		_button("Play", "Let's play  →", Rect2(x, y, minf(tw, 350), 58), func(): _show("modes"), "primary")
	else:
		y -= 68
	_button("Progress", "Your progress", Rect2(x, y + 72, minf(tw * 0.52, 176), 44), func(): _show("progress"), "quiet", 16)
	_button("Settings", "Settings", Rect2(x + minf(tw * 0.55, 190), y + 72, minf(tw * 0.4, 150), 44), func(): _show("settings"), "quiet", 16)
	if mobile:
		view.view_rect = Rect2(x, maxf(560, y + 130), w - x * 2, 135)
		ui.custom_minimum_size.y = maxf(h, view.view_rect.end.y + 58)
	else:
		view.view_rect = Rect2(w * 0.54, 134, w * 0.43 - 28, 392)
		_label("SideNote", "YOUR PACE. YOUR PATH.", Rect2(w * 0.54 + 16, 548, w * 0.4, 28), 12, MUTED)
	if not store.last_error.is_empty():
		save_notice = store.last_error

func _build_modes(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else 68.0
	_label("Title", "Choose your rhythm.", Rect2(x, 82, w - x * 2, 72), 33 if mobile else 48)
	_label("Subtitle", "Three ways forward. The same room to learn.", Rect2(x, 164, w - x * 2, 54), 18, MUTED)
	var modes := [["Practice", "No clock. All the time you need.", "practice"], ["Classic", "Read the course. Beat the gate.", "classic"], ["Cadence", "Find a steady beat. Keep your flow.", "cadence"]]
	for i in range(3):
		var item: Array = modes[i]
		var mw := w - x * 2 if mobile else (w - x * 2 - 32) / 3
		var mx := x if mobile else x + i * (mw + 16)
		var my := 228.0 + i * 108 if mobile else 248.0
		var selected_mode: String = item[2]
		_button(item[0], item[0] + "  →", Rect2(mx, my, mw, 60), func(): mode = selected_mode; _show("setup"), "primary" if i == 0 else "secondary", 23)
		_label("ModeNote%d" % i, item[1], Rect2(mx + 8, my + 66, mw - 16, 44), 15, MUTED)
	_button("Home", "← Back", Rect2(x, h - 100, 134, 46), func(): _show("menu"), "quiet", 16)
	view.view_rect = Rect2(x, 402, w - x * 2, 154) if not mobile else Rect2()

func _build_setup(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else 68.0
	var cw := w - x * 2 if mobile else minf(550, w * 0.48)
	_label("Eyebrow", mode.to_upper() + " / RUN SETUP", Rect2(x, 79, cw, 26), 12, TEAL)
	_label("Title", "Make it your run.", Rect2(x, 120, cw, 72), 33 if mobile else 46)
	_label("OperationLabel", "What shall we practise?", Rect2(x, 216, cw, 28), 17, MUTED)
	_option("Operation", ["Addition  +", "Subtraction  −", "Multiplication  ×", "Division  ÷", "Mixed operations"], ["addition", "subtraction", "multiplication", "division", "mixed"].find(operation), Rect2(x, 250, cw, 50), func(i): operation = ["addition", "subtraction", "multiplication", "division", "mixed"][i])
	_label("RangeLabel", "Fact family", Rect2(x, 320, cw * 0.48, 28), 17, MUTED)
	_option("NumberRange", ["0–5", "0–10", "0–12"], [5, 10, 12].find(number_range), Rect2(x, 354, cw * 0.47, 50), func(i): number_range = [5, 10, 12][i])
	_label("LengthLabel", "Session length", Rect2(x + cw * 0.53, 320, cw * 0.47, 28), 17, MUTED)
	_option("SessionLength", ["6 gates", "12 gates", "24 gates"], [6, 12, 24].find(target), Rect2(x + cw * 0.53, 354, cw * 0.47, 50), func(i): target = [6, 12, 24][i])
	if mode != "practice":
		_label("PaceLabel", "Gate time · mistakes always get a retry", Rect2(x, 422, cw, 28), 15, MUTED)
		_option("Pace", ["Relaxed · 14 seconds", "Steady · 10 seconds", "Swift · 7 seconds"], pace, Rect2(x, 458, cw, 50), func(i): pace = i)
	else:
		_label("PracticeNote", "The gate waits for you. Hints are always available.", Rect2(x, 430, cw, 64), 17, TEAL)
	_button("StartRun", "Start run  →", Rect2(x, 538, cw, 58), _start_run, "primary")
	_button("Home", "← Modes", Rect2(x, 612, 140, 44), func(): _show("modes"), "quiet", 16)
	if not mobile:
		view.view_rect = Rect2(w * 0.58, 180, w * 0.36, 270)
		_label("SetupGuide", "ANSWER → OPEN → FLY\n\nType numbers. Enter to answer.\nSpace to jump. Esc to pause.\n\nAuto-jump is on by default.\nChange it in Settings.", Rect2(w * 0.6, 475, w * 0.32, 160), 16, MUTED)
	else: view.view_rect = Rect2()

func _build_game(w: float, h: float, mobile: bool) -> void:
	var x := 16.0 if mobile else 38.0
	var cw := w - x * 2
	_label("RunMode", mode.to_upper(), Rect2(x, 66, cw * 0.5, 26), 12, TEAL)
	_label("ProgressText", "", Rect2(w - x - 180, 64, 180, 28), 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var progress_track := ColorRect.new()
	progress_track.position = Vector2(x, 102)
	progress_track.size = Vector2(cw, 4)
	progress_track.color = Color("21324b")
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(progress_track)
	var progress_fill := ColorRect.new()
	progress_fill.name = "RunProgress"
	progress_fill.size = Vector2(cw * completed / target, 4)
	progress_fill.color = ACCENT
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_track.add_child(progress_fill)
	labels["RunProgress"] = progress_fill
	view.view_rect = Rect2(x, 126, cw, 186 if mobile else clampf(h * 0.33, 210, 315))
	view.label_text = "THE GATE WAITS FOR YOU" if mode == "practice" else "SOLVE TO OPEN THE GATE"
	var ay: float = view.view_rect.end.y + 14
	var aw := cw if mobile else cw * 0.59
	_label("Question", "", Rect2(x + 6, ay, aw - 12, 62), 40 if mobile else 51)
	_label("Answer", "", Rect2(x + 6, ay + 66, aw - 12, 47), 29, ACCENT)
	_label("Feedback", "", Rect2(x + 6, ay + 119, aw - 12, 58), 15 if mobile else 17, MUTED)
	var ky: float = ay + 185 if mobile else ay + 4
	var kx := x if mobile else x + cw * 0.65
	var kw := cw if mobile else cw * 0.35
	var bh := 47.0 if mobile else 48.0
	var gap := 7.0
	var bw := (kw - 2 * gap) / 3
	var keys := ["7", "8", "9", "4", "5", "6", "1", "2", "3", "⌫", "0", "→"]
	for i in range(12):
		var key: String = keys[i]
		var rect := Rect2(kx + (i % 3) * (bw + gap), ky + (i / 3) * (bh + gap), bw, bh)
		if i == 9: _button("Backspace", key, rect, _backspace, "secondary", 22)
		elif i == 11: _button("SubmitAnswer", "Enter  →" if not mobile else "→", rect, _submit, "primary", 18)
		else: _button("Digit" + key, key, rect, func(): _digit(key), "secondary", 21)
	var by: float = ky + 4 * (bh + gap) + 10 if mobile else maxf(ay + 190, ky + 4 * (bh + gap) + 10)
	var rw := (cw - 16) / 3 if mobile else 142.0
	_button("Hint", "Hint  H", Rect2(x, by, rw, 44), _hint, "quiet", 15)
	_button("Jump", "Jump  ↑", Rect2(x + rw + 8, by, rw, 44), _jump, "quiet", 15)
	_button("Pause", "Pause  Ⅱ", Rect2(x + (rw + 8) * 2, by, rw, 44), _pause, "quiet", 15)
	ui.custom_minimum_size.y = maxf(h, by + 90)
	if not mobile:
		_label("KeyboardNote", "NUMBERS  answer     ENTER  submit     SPACE  jump     ESC  pause", Rect2(x, by + 52, cw, 28), 12, MUTED)
	_update_hud()
	if screen == "paused":
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.04, 0.09, 0.94)
		shade.position = Vector2(0, 56)
		shade.size = Vector2(w, ui.custom_minimum_size.y - 56)
		ui.add_child(shade)
		var px := maxf(24, (w - 440) * 0.5)
		var pw := minf(440, w - 48)
		_label("PauseTitle", "Take a breath.", Rect2(px, 160, pw, 70), 38)
		_label("PauseNote", "Your timer is paused. Your answer is right where you left it.", Rect2(px, 242, pw, 70), 18, MUTED)
		_button("Resume", "Back to the run  →", Rect2(px, 340, pw, 58), _resume, "primary")
		_button("FinishRun", "Finish & see results", Rect2(px, 414, pw, 50), _finish, "secondary", 18)
		_button("SaveAndHome", "Save & return home", Rect2(px, 480, pw, 46), func(): _save_checkpoint(); _show("menu"), "quiet", 16)
		for id in ["Hint", "Jump", "Pause", "SubmitAnswer", "Backspace", "Digit0", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9"]:
			controls[id].disabled = true

func _build_settings(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else maxf(68, (w - 740) * 0.5)
	var cw := w - x * 2
	_label("Title", "A game that fits you.", Rect2(x, 92, cw, 74), 32 if mobile else 43)
	_label("SettingsNote", "These preferences belong to this device profile.", Rect2(x, 170, cw, 54), 16, MUTED)
	_toggle("AutoJump", "Auto-jump · focus on the maths", auto_jump, Rect2(x, 244, cw, 48), func(v): auto_jump = v; _save_settings())
	_toggle("ReducedMotion", "Reduced motion", reduced_motion, Rect2(x, 300, cw, 48), func(v): reduced_motion = v; _save_settings())
	_toggle("HighContrast", "Brighter course boundaries", high_contrast, Rect2(x, 356, cw, 48), func(v): high_contrast = v; _save_settings())
	_label("VolumeLabel", "Sound volume", Rect2(x, 418, cw * 0.5, 30), 16, MUTED)
	_option("Volume", ["Quiet", "Medium", "Loud"], 0 if volume < 0.3 else (1 if volume < 0.7 else 2), Rect2(x + cw * 0.53, 410, cw * 0.47, 46), func(i): volume = [0.15, 0.35, 0.8][i]; _save_settings())
	_label("ProfileLabel", "Local player", Rect2(x, 482, cw * 0.5, 30), 16, MUTED)
	_option("LearnerProfile", ["Player 1", "Player 2", "Player 3"], int(learner_id.right(1)) - 1, Rect2(x + cw * 0.53, 474, cw * 0.47, 46), func(i): learner_id = "player-%d" % (i + 1); _load_settings(); _update_preferences(); _build_ui())
	_button("RunnerColor", "Runner colour  ◇", Rect2(x, 546, cw, 46), func(): color_index = (color_index + 1) % 4; _save_settings(); _build_ui(), "secondary", 17)
	_button("Home", "← Done", Rect2(x, 612, 150, 46), func(): _show("menu"), "primary", 17)
	view.view_rect = Rect2()
	if not store.last_error.is_empty():
		_button("ResetStorage", "Reset damaged local save", Rect2(x, 680, cw, 46), func(): store.discard_corrupt_storage(); save_notice = ""; _build_ui(), "secondary", 16)
		ui.custom_minimum_size.y = maxf(h, 790)

func _build_progress(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else 68.0
	var cw := w - x * 2
	_label("Title", "Your practice, recorded.", Rect2(x, 94, cw, 84), 31 if mobile else 43)
	var sessions: Array = store.get_profile(learner_id).get("sessions", [])
	_label("ProgressNote", _learner_name() + " · " + str(sessions.size()) + " saved sessions\nFirst try means correct before a mistake, timeout, or hint.", Rect2(x, 190, cw, 72), 17, MUTED)
	var y := 284.0
	if sessions.is_empty():
		_label("EmptyProgress", "A fresh track.\nPlay a run and your record will appear here.", Rect2(x, y, cw, 120), 22, TEAL)
	else:
		for i in range(mini(sessions.size(), 8)):
			var s: Dictionary = sessions[sessions.size() - 1 - i]
			var line := "%s  ·  %s\n%d/%d first try  ·  %d gates solved" % [str(s.get("mode", "practice")).capitalize(), str(s.get("operation", "addition")).capitalize(), s.get("first_try_correct", 0), s.get("first_try_opportunities", 0), s.get("completed", 0)]
			_label("Session%d" % i, line, Rect2(x, y, cw, 70), 18)
			y += 84
	_button("Home", "← Home", Rect2(x, y + 24, 170, 48), func(): _show("menu"), "primary", 18)
	view.view_rect = Rect2()
	ui.custom_minimum_size.y = maxf(h, y + 150)

func _build_results(w: float, h: float, mobile: bool) -> void:
	var x := 24.0 if mobile else 68.0
	var cw := w - x * 2
	_label("Eyebrow", "RUN COMPLETE / " + mode.to_upper(), Rect2(x, 86, cw, 26), 12, TEAL)
	_label("Title", "Look how far you came.", Rect2(x, 126, cw, 96), 33 if mobile else 49)
	var first := int(last_result.get("first_try_correct", 0))
	var opportunities := int(last_result.get("first_try_opportunities", 0))
	_label("ResultHeadline", "%d / %d" % [first, opportunities], Rect2(x, 238, cw, 74), 57, ACCENT)
	_label("ResultExplanation", "correct on the first try, without help" if opportunities > 0 else "No answers recorded. That is okay — start when you're ready.", Rect2(x, 318, cw, 50), 18, MUTED)
	var details := "%d gates solved   ·   %d retries   ·   %d solved with support\n%d timeouts   ·   %.1f seconds of active play" % [completed, int(last_result.get("retries", 0)), int(last_result.get("assisted", 0)), int(last_result.get("timeouts", 0)), active_seconds]
	if mobile:
		details = "%d gates solved  ·  %d retries\n%d solved with support\n%d timeouts\nActive play: %.1f seconds" % [completed, int(last_result.get("retries", 0)), int(last_result.get("assisted", 0)), int(last_result.get("timeouts", 0)), active_seconds]
	_label("ResultDetails", details, Rect2(x, 390, cw if mobile else cw * 0.62, 104), 18)
	_label("ResultSave", save_notice, Rect2(x, 500, cw, 52), 15, TEAL)
	var bw := cw if mobile else minf(cw * 0.33, 310)
	_button("PlayAgain", "One more run  →", Rect2(x, 566, bw, 58), _start_run, "primary")
	_button("Home", "Home", Rect2(x, 636, bw * 0.48, 48), func(): _show("menu"), "quiet", 17)
	_button("ExportResult", "Export result", Rect2(x + bw * 0.52, 636, bw * 0.48, 48), _export_result, "quiet", 16)
	var review_y := 730.0
	_label("ReviewTitle", "FACTS FROM THIS RUN", Rect2(x, review_y, cw, 30), 13, TEAL)
	review_y += 42
	for item in last_result.get("facts", []):
		var fact: Dictionary = item
		var text_value := str(fact.get("key", "")) + "   ·   " + ("first try" if fact.get("first_correct", false) else ("with practice" if fact.get("correct", false) else "not yet solved"))
		_label("Fact" + str(review_y), text_value, Rect2(x, review_y, cw, 36), 16, MUTED)
		review_y += 40
	ui.custom_minimum_size.y = maxf(h, review_y + 70)
	view.view_rect = Rect2(w * 0.64, 250, w * 0.30, 220) if not mobile else Rect2()

func _update_hud() -> void:
	if not labels.has("Question"): return
	labels.Question.text = "%s %s %s = ?" % [question.get("a", 0), question.get("symbol", "+"), question.get("b", 0)]
	labels.Answer.text = "Your answer   " + ("_" if input_text.is_empty() else input_text)
	labels.Feedback.text = feedback
	labels.Feedback.add_theme_color_override("font_color", TEAL if feedback_kind == "correct" else (Color("ffc49d") if feedback_kind in ["wrong", "hint"] else MUTED))
	var timing := "No timer" if mode == "practice" else ("Take your time" if timed_out else "%.0fs" % ceilf(maxf(0, _gate_duration() - question_elapsed)))
	labels.ProgressText.text = "%d / %d gates · %s" % [completed, target, timing]
	labels.RunProgress.size.x = labels.RunProgress.get_parent().size.x * completed / target
	if not save_notice.is_empty():
		if not labels.has("SaveNotice"):
			_label("SaveNotice", save_notice, Rect2(20, ui.custom_minimum_size.y - 34, size.x - 40, 28), 13, Color("ffd49b"))
		else: labels.SaveNotice.text = save_notice

func _valid_run_checkpoint(c: Dictionary) -> bool:
	if c.get("learner_id", "") != learner_id or c.get("version", 0) != 1:
		return false
	for key in ["session_id", "started_at", "mode", "operation", "input", "feedback", "feedback_kind"]:
		if not c.get(key) is String: return false
	if c.session_id.is_empty() or c.mode not in ["practice", "classic", "cadence"] or c.operation not in ["addition", "subtraction", "multiplication", "division", "mixed"]:
		return false
	for key in ["range", "target", "pace", "seed", "completed", "active_seconds", "question_elapsed", "transition_seconds"]:
		var value = c.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	for key in ["range", "target", "pace", "seed", "completed"]:
		if float(c[key]) != floor(float(c[key])): return false
	var attempt_origin = c.get("last_attempt_elapsed", 0)
	if not (attempt_origin is float or attempt_origin is int) or not is_finite(float(attempt_origin)) or attempt_origin < 0 or attempt_origin > c.question_elapsed:
		return false
	if int(c.range) not in [5, 10, 12] or int(c.target) not in [6, 12, 24] or c.completed > c.target or c.pace > 2:
		return false
	if c.input.length() > 4 or (not c.input.is_empty() and not c.input.is_valid_int()): return false
	for key in ["gate_solved", "timed_out"]:
		if not c.get(key) is bool: return false
	for key in ["question", "learning", "course"]:
		if not c.get(key) is Dictionary: return false
	var cs: Dictionary = c.course
	for key in ["y", "velocity", "jump_buffer", "gate_x", "obstacle_x", "obstacle_kind", "scroll", "recovery", "collisions", "jumps"]:
		var value = cs.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return false
	for key in ["obstacle_active", "cleared", "waiting"]:
		if not cs.get(key) is bool: return false
	for key in ["obstacle_kind", "collisions", "jumps"]:
		if float(cs[key]) < 0 or float(cs[key]) != floor(float(cs[key])): return false
	if cs.obstacle_kind > 2: return false
	if c.question != c.learning.get("question", {}): return false
	return true

func _focus_default() -> void:
	var choices := {"menu": "ResumeSaved" if controls.has("ResumeSaved") else "Play", "modes": "Practice", "setup": "StartRun", "paused": "Resume", "results": "PlayAgain", "settings": "AutoJump", "progress": "Home"}
	var id: String = choices.get(screen, "")
	if controls.has(id): controls[id].grab_focus()

func _label(id: String, value: String, rect: Rect2, font_size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.name = id
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(label)
	# Establish wrapping, inherited font and available width before adding text.
	# Text at zero width caches an oversized minimum height; unwrapped text
	# before setting width can similarly expand the minimum width.
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.size = rect.size
	labels[id] = label
	return label

func _style(color: Color, radius := 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(2 if border.a > 0 else 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

func _button(id: String, value: String, rect: Rect2, action: Callable, kind := "secondary", font_size := 20) -> Button:
	var b := Button.new()
	b.name = id
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_size)
	var bg := ACCENT if kind == "primary" else (PANEL if kind == "secondary" else Color("101b30"))
	var fg := BG if kind == "primary" else TEXT
	b.add_theme_stylebox_override("normal", _style(bg))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.08)))
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 10, Color("ffda8c")))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.pressed.connect(action)
	ui.add_child(b)
	controls[id] = b
	return b

func _option(id: String, choices: Array, selected: int, rect: Rect2, action: Callable) -> OptionButton:
	var b := OptionButton.new()
	b.name = id
	b.position = rect.position
	b.size = rect.size
	for choice in choices: b.add_item(choice)
	b.select(maxi(0, selected))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _style(PANEL))
	b.add_theme_stylebox_override("hover", _style(PANEL.lightened(0.1)))
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 10, Color("ffda8c")))
	b.item_selected.connect(action)
	ui.add_child(b)
	controls[id] = b
	return b

func _toggle(id: String, value: String, checked: bool, rect: Rect2, action: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.name = id
	b.text = value
	b.button_pressed = checked
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 8, Color("ffda8c")))
	b.toggled.connect(action)
	ui.add_child(b)
	controls[id] = b
	return b

func _toggle_sound() -> void:
	audio_enabled = not audio_enabled
	_save_settings()
	if controls.has("Sound"): controls.Sound.text = "Sound" if audio_enabled else "Muted"

func _export_result() -> void:
	var bytes := JSON.stringify(last_result, "  ").to_utf8_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, "diagnostic-dash-result.json", "application/json")
		save_notice = "Result download requested. Check your browser downloads."
	else:
		var f := FileAccess.open("user://last-result.json", FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			save_notice = "Exported to " + ProjectSettings.globalize_path("user://last-result.json")
		else: save_notice = "Could not export the result."
	exported_result = true
	_build_ui()

func get_snapshot() -> Dictionary:
	var rects := {}
	for id in controls:
		var c: Control = controls[id]
		var r := c.get_global_rect()
		rects[id] = {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "text": c.text, "visible": c.is_visible_in_tree(), "disabled": c.disabled}
	var label_rects := {}
	for id in labels:
		if labels[id] is Label:
			var l: Label = labels[id]
			var r := l.get_global_rect()
			label_rects[id] = {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "text": l.text, "visible": l.is_visible_in_tree()}
	return {"screen": screen, "seed": seed_value, "mode": mode, "operation": operation, "range": number_range, "question": question, "completed": completed, "target": target, "input": input_text, "elapsed": active_seconds, "question_elapsed": question_elapsed, "paused": screen == "paused", "gate_remaining": maxf(0, _gate_duration() - question_elapsed), "gate_solved": gate_solved, "timed_out": timed_out, "auto_jump": auto_jump, "reduced_motion": reduced_motion, "audio_enabled": audio_enabled, "learner_id": learner_id, "session_id": session_id, "stats": learning.summary(), "result": last_result, "course": course.snapshot(), "controls": rects, "labels": label_rects, "viewport": {"w": size.x, "h": size.y}, "save_error": store.last_error}

func _publish_web_state() -> void:
	var public_state := {"screen": screen, "question": labels.Question.text if labels.has("Question") else "", "feedback": feedback if screen == "playing" else "", "completed": completed, "target": target}
	JavaScriptBridge.eval("window.ddPublicState=" + JSON.stringify(public_state) + ";if(window.ddAnnounce)window.ddAnnounce(window.ddPublicState);", true)
	if qa_enabled:
		JavaScriptBridge.eval("window.ddState=" + JSON.stringify(get_snapshot()) + ";", true)

func _web_qa_command(args: Array) -> void:
	# Explicit opt-in fixture control. Never loaded on normal gameplay URLs.
	if not qa_enabled or args.is_empty(): return
	var c = JSON.parse_string(str(args[0]))
	if not c is Dictionary: return
	if c.get("action", "") == "configure" and screen in ["menu", "setup", "modes"]:
		forced_seed = maxi(0, int(c.get("seed", 73)))
		if c.get("mode", mode) in ["practice", "classic", "cadence"]: mode = c.get("mode", mode)
		if c.get("operation", operation) in ["addition", "subtraction", "multiplication", "division", "mixed"]: operation = c.get("operation", operation)
		if int(c.get("range", number_range)) in [5, 10, 12]: number_range = int(c.get("range", number_range))
		if int(c.get("target", target)) in [6, 12, 24]: target = int(c.get("target", target))
		pace = clampi(int(c.get("pace", pace)), 0, 2)
		_build_ui()
