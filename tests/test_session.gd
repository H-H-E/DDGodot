extends SceneTree
## Real Main-scene integration with isolated synthetic save files. Core counters
## are never edited to create progress: input and normal scene actions do that.
const MainScene = preload("res://scenes/main.tscn")
const SaveStore = preload("res://scripts/save_store.gd")

var assertions := 0
var failures: Array[String] = []
var scenarios: Array[Dictionary] = []
var sequence := 0
var test_prefix := ""

func _initialize() -> void:
	test_prefix = "user://session-tests-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1280, 800)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 15: printerr("SESSION FAIL: " + message)

func _scenario(label: String, action: Callable) -> void:
	var before := failures.size()
	var checks_before := assertions
	await action.call()
	scenarios.append({"name": label, "passed": failures.size() == before, "assertions": assertions - checks_before})

func _new_game(existing_path: String = ""):
	sequence += 1
	var game = MainScene.instantiate()
	var path := existing_path if not existing_path.is_empty() else "%s-%d.json" % [test_prefix, sequence]
	# Override the adapter before _ready(), so no default learner store is read.
	game.store = SaveStore.new(path)
	root.add_child(game)
	await process_frame
	await process_frame
	return game

func _dispose(game) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.hush()
	# Let the audio server retire stopped playbacks before destroying a scene;
	# otherwise an immediate headless test exit reports pending audio references.
	await create_timer(0.10).timeout
	game.queue_free()
	await process_frame
	await process_frame

func _click(game, name: String) -> void:
	_check(game.controls.has(name), "Visible control must exist: " + name)
	if not game.controls.has(name): return
	var button = game.controls[name]
	_check(not button.disabled, "Control must be enabled: " + name)
	button.emit_signal("pressed")
	await process_frame

func _key(code: int) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.physical_keycode = code
	pressed.pressed = true
	if code >= KEY_0 and code <= KEY_9: pressed.unicode = code
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventKey.new()
	released.keycode = code
	released.physical_keycode = code
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame

func _answer(value: int) -> void:
	for digit in str(value):
		await _key(KEY_0 + int(digit))
	await _key(KEY_ENTER)

func _until(predicate: Callable, limit_seconds: float = 2.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return bool(predicate.call())

func _start(game, chosen_mode: String = "practice", selected_pace: int = -1) -> void:
	await _click(game, "Play")
	await _click(game, chosen_mode.capitalize())
	if selected_pace >= 0:
		game.controls.Pace.emit_signal("item_selected", selected_pace)
		await process_frame
	await _click(game, "StartRun")
	_check(game.screen == "playing", "The real setup flow must start gameplay")

func _run() -> void:
	await _scenario("Real input produces honest first-attempt, retry and hint results", _evidence_journey)
	await _scenario("Pause blocks answer input, simulation and active clocks", _pause)
	await _scenario("Interrupted session restores explicitly without counting time away", _recovery)
	await _scenario("Saved run cannot be overwritten through the start path", _overwrite_guard)
	await _scenario("Corrupted outer checkpoint is rejected without deleting it", _corrupt_checkpoint)
	await _scenario("Local learner preferences and records remain separated", _profiles)
	await _scenario("Finishing an unanswered question never fabricates evidence", _empty_finish)
	await _scenario("A real timed deadline remains retryable without fake response latency", _timeout_recovery)
	print("DDGODOT_SESSION_REPORT=" + JSON.stringify({"suite": "native-session", "engine": Engine.get_version_info().string, "assertions": assertions, "passed": failures.is_empty(), "scenarios": scenarios, "failures": failures}))
	print("Session checks: %d assertions, %d scenarios, %d failures." % [assertions, scenarios.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _evidence_journey() -> void:
	var game = await _new_game()
	await _start(game)
	var first_id: String = game.session_id
	await _answer(int(game.question.answer))
	var first: Dictionary = game.learning.summary()
	_check(game.completed == 1 and first.first_try_opportunities == 1 and first.first_try_correct == 1, "First correct input must solve exactly one first-attempt opportunity")
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	_check(game.completed == 1 and game.learning.summary().attempts == 1, "Repeated Enter during gate release must not submit again")
	_check(await _until(func(): return not game.gate_solved), "The next real question must arrive after gate release")
	var answer: int = int(game.question.answer)
	await _answer(answer + 1)
	_check(game.feedback.contains("One away"), "The scene must expose the learning core's targeted error feedback")
	_check(game.learning.summary().first_try_opportunities == 2 and game.completed == 1, "A wrong answer observes one opportunity without solving a gate")
	await _answer(answer)
	var second: Dictionary = game.learning.summary()
	_check(game.completed == 2 and second.first_try_opportunities == 2 and second.first_try_correct == 1, "Correct retry must retain one opportunity and preserve first-attempt numerator")
	_check(second.retries == 1 and second.assisted == 1, "Retry must be recorded separately as supported eventual success")
	_check(await _until(func(): return not game.gate_solved), "Question three must arrive")
	await _key(KEY_H)
	_check(game.learning.summary().first_try_opportunities == 2, "Requesting a hint alone must not invent a submitted response")
	await _answer(int(game.question.answer))
	_check(await _until(func(): return not game.gate_solved), "An unanswered fourth question must be displayed before early finish")
	await _key(KEY_ESCAPE)
	await _click(game, "FinishRun")
	var result: Dictionary = game.last_result
	_check(game.screen == "results", "The real Finish control must show results")
	_check(result.first_try_opportunities == 3 and result.first_try_correct == 1 and result.eventual_correct == 3, "Final result must reflect three observed solved questions, not the unanswered fourth")
	_check(result.attempts == 4 and result.submitted_answers == 4 and result.retries == 1 and result.assisted == 2 and result.timeouts == 0, "Final attempt, submission, retry, support and timeout counts must agree with real input")
	_check(result.response_samples == 3 and result.mean_response_seconds >= 0, "Response mean must expose its actual response denominator")
	_check(result.session_id == first_id and result.completed == 3 and result.active_seconds > 0, "Final result must keep run identity and observed elapsed progress")
	var profile: Dictionary = game.store.get_profile("player-1")
	_check(profile.sessions.size() == 1 and profile.sessions[0].session_id == first_id, "Finishing must persist one session under the selected learner")
	_check(profile.checkpoint.is_empty() and profile.evidence.has("addition:10"), "Successful completion must clear checkpoint and retain actual learning evidence")
	game._finish()
	_check(game.store.get_profile("player-1").sessions.size() == 1, "Repeated Finish on results must be inert")
	_check(game.store.complete_session("player-1", result.duplicate(true)), "Repeated identical scene result must be idempotently accepted")
	var conflicting: Dictionary = result.duplicate(true)
	conflicting.created_at = "different payload under the same identity"
	_check(not game.store.complete_session("player-1", conflicting), "A conflicting payload under the same finished ID must be rejected")
	_check(game.store.get_profile("player-1").sessions.size() == 1, "Idempotency checks must not append duplicate results")
	await _click(game, "PlayAgain")
	_check(game.screen == "playing" and game.session_id != first_id and game.completed == 0, "Replay must start a fresh identity with zero session progress")
	_check(game.save_notice.is_empty() and not game.labels.has("SaveNotice"), "A new run must not retain a previous completion or export notice")
	# A synthetic save-warning fixture verifies visible scene labels, without
	# changing arithmetic or pretending that a save operation succeeded.
	game.save_notice = "This device could not save progress. Keep the game open."
	game._build_ui()
	var notices := 0
	for child in game.ui.get_children():
		if child is Label and child.text == game.save_notice: notices += 1
	_check(notices == 1, "A save warning must be drawn once when the HUD and screen footer rebuild")
	game._update_hud()
	game._build_ui()
	notices = 0
	for child in game.ui.get_children():
		if child is Label and child.text == game.save_notice: notices += 1
	_check(notices == 1, "Repeated HUD updates and rebuilds must preserve one readable save warning")
	await _dispose(game)

func _pause() -> void:
	var game = await _new_game()
	await _start(game, "classic")
	await create_timer(0.12).timeout
	await _key(KEY_1)
	await _key(KEY_ESCAPE)
	_check(game.screen == "paused", "Escape must pause a running session")
	var elapsed: float = game.active_seconds
	var question_age: float = game.question_elapsed
	var course_before: Dictionary = game.course.snapshot().duplicate(true)
	var input_before: String = game.input_text
	await create_timer(0.20).timeout
	await _key(KEY_9)
	await _key(KEY_BACKSPACE)
	game._submit()
	game._jump()
	_check(game.screen == "paused" and game.input_text == input_before, "Paused answer keys and submit action must not change typed input")
	_check(game.active_seconds == elapsed and game.question_elapsed == question_age, "Paused session and question clocks must remain exactly unchanged")
	_check(game.course.snapshot() == course_before, "Paused logical course must not advance or receive jumps")
	_check(game.learning.summary().first_try_opportunities == 0, "Pause must not manufacture a response or timeout")
	await _key(KEY_ESCAPE)
	await create_timer(0.10).timeout
	_check(game.screen == "playing" and game.active_seconds > elapsed and game.active_seconds - elapsed < 0.20, "Resuming must count new active time without replaying the pause")
	_check(game.input_text == input_before, "Resume must keep the answer for review")
	await _dispose(game)

func _recovery() -> void:
	var game = await _new_game()
	await _start(game)
	await _key(KEY_1)
	await _key(KEY_2)
	await create_timer(0.10).timeout
	await _key(KEY_ESCAPE)
	var checkpoint: Dictionary = game.store.get_checkpoint("player-1")
	var path: String = game.store.path
	var identity: String = game.session_id
	await _dispose(game)
	await create_timer(0.15).timeout
	var resumed = await _new_game(path)
	_check(resumed.screen == "menu" and resumed.controls.has("ResumeSaved"), "Restart must offer recovery without auto-resuming")
	await _click(resumed, "ResumeSaved")
	_check(resumed.screen == "paused" and resumed.session_id == identity, "Explicit restore must preserve identity and wait for resume")
	_check(resumed.input_text == "12" and resumed.question.key == checkpoint.question.key and int(resumed.question.a) == int(checkpoint.question.a) and int(resumed.question.b) == int(checkpoint.question.b) and int(resumed.question.answer) == int(checkpoint.question.answer) and resumed.question.opType == checkpoint.question.opType, "Restore must preserve typed input and exact question")
	_check(absf(resumed.active_seconds - float(checkpoint.active_seconds)) < 0.000001 and absf(resumed.question_elapsed - float(checkpoint.question_elapsed)) < 0.000001, "Time away must not be included in restored active ages")
	_check(resumed.learning.summary().first_try_opportunities == 0, "Restored typed input must not auto-submit")
	await _click(resumed, "Resume")
	await create_timer(0.08).timeout
	_check(resumed.active_seconds > float(checkpoint.active_seconds) and resumed.active_seconds - float(checkpoint.active_seconds) < 0.20, "Resumed active clock must advance only from the new run time")
	await _dispose(resumed)

func _overwrite_guard() -> void:
	var game = await _new_game()
	await _start(game)
	await _key(KEY_4)
	await _key(KEY_ESCAPE)
	await _click(game, "SaveAndHome")
	var before: Dictionary = game.store.get_checkpoint("player-1")
	_check(not game.controls.has("Play") and game.controls.has("ResumeSaved") and game.controls.has("DiscardSaved"), "Saved-run menu must expose the deliberate Resume/Discard choice")
	# The normal menu already prevents it. Also cover stale callbacks calling
	# the start handler after the interrupted session was saved.
	game._start_run()
	await process_frame
	_check(game.screen == "menu" and game.save_notice.contains("Resume or discard"), "Starting over an interrupted run must return to an explicit recovery choice")
	_check(game.store.get_checkpoint("player-1") == before, "Refused start must not overwrite the interrupted run")
	_check(game.session_id == before.session_id, "Refused start must not allocate a replacement run identity")
	await _dispose(game)

func _corrupt_checkpoint() -> void:
	var game = await _new_game()
	var partial := {"session_id": "partial-synthetic-run"}
	_check(game.store.save_checkpoint("player-1", partial), "Storage boundary accepts opaque checkpoint for Main to validate")
	game._restore_checkpoint()
	await process_frame
	_check(game.screen == "menu" and game.save_notice.contains("could not be restored"), "Partial outer checkpoint must be rejected with visible recovery explanation")
	_check(game.store.get_checkpoint("player-1") == partial, "Rejected checkpoint must remain available for deliberate discard")
	game._discard_checkpoint()
	game._start_run()
	game._pause()
	var valid: Dictionary = game.store.get_checkpoint("player-1")
	game._show("menu")
	var variants: Array[Dictionary] = []
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("course")
	variants.append(missing)
	var wrong_type: Dictionary = valid.duplicate(true)
	wrong_type.course.y = "not a number"
	variants.append(wrong_type)
	var wrong_learner: Dictionary = valid.duplicate(true)
	wrong_learner.learner_id = "player-2"
	variants.append(wrong_learner)
	var wrong_count: Dictionary = valid.duplicate(true)
	wrong_count.completed = 1
	variants.append(wrong_count)
	var fractional_count: Dictionary = valid.duplicate(true)
	fractional_count.completed = 0.5
	variants.append(fractional_count)
	var broken_attempt_clock: Dictionary = valid.duplicate(true)
	broken_attempt_clock.last_attempt_elapsed = "broken"
	variants.append(broken_attempt_clock)
	for damaged in variants:
		game._show("menu")
		_check(game.store.save_checkpoint("player-1", damaged), "Synthetic damaged checkpoint fixture must be persisted")
		game._restore_checkpoint()
		await process_frame
		_check(game.screen == "menu" and not game.save_notice.is_empty(), "Outer type, identity or result mismatch must not restore")
		_check(game.store.get_checkpoint("player-1") == damaged, "Rejected damaged checkpoint must not be silently replaced")
	await _dispose(game)

func _profiles() -> void:
	var game = await _new_game()
	game.auto_jump = false
	game.reduced_motion = true
	game.high_contrast = true
	game.audio_enabled = false
	game.volume = 0.8
	game.color_index = 3
	game._save_settings()
	game._show("settings")
	game.controls.LearnerProfile.emit_signal("item_selected", 1)
	await process_frame
	_check(game.learner_id == "player-2", "Actual profile selector must choose the second slot")
	_check(game.auto_jump and not game.reduced_motion and not game.high_contrast and game.audio_enabled, "A fresh learner must receive default booleans, not previous learner preferences")
	_check(is_equal_approx(game.volume, 0.35) and game.color_index == 0, "A fresh learner must receive default volume and colour")
	_check(game.store.get_profile("player-2").evidence.is_empty() and game.store.get_profile("player-2").sessions.is_empty() and game.store.get_checkpoint("player-2").is_empty(), "A fresh learner must have no borrowed evidence or recovery")
	game.controls.LearnerProfile.emit_signal("item_selected", 0)
	await process_frame
	_check(game.learner_id == "player-1" and not game.auto_jump and game.reduced_motion and game.high_contrast and not game.audio_enabled and game.color_index == 3, "Returning to learner one must restore that learner's actual preferences")
	await _dispose(game)

func _empty_finish() -> void:
	var game = await _new_game()
	await _start(game)
	await create_timer(0.05).timeout
	await _key(KEY_ESCAPE)
	await _click(game, "FinishRun")
	var result: Dictionary = game.last_result
	_check(result.first_try_opportunities == 0 and result.first_try_correct == 0 and result.attempts == 0 and result.submitted_answers == 0 and result.timeouts == 0, "Finishing without a response must retain zero evidence")
	_check(result.response_samples == 0 and result.facts.is_empty(), "An unanswered occurrence must not contribute a latency sample or fact row")
	_check(game.store.get_profile("player-1").sessions.size() == 1, "An explicitly ended empty session may save honest zero counts")
	await _dispose(game)

func _timeout_recovery() -> void:
	var game = await _new_game()
	await _start(game, "classic", 2)
	_check(await _until(func(): return game.timed_out, 8.5), "The actual Swift clock must reach its seven-second deadline")
	var timed: Dictionary = game.learning.summary()
	_check(game.screen == "playing" and game.course.waiting and game.completed == 0, "A timeout must leave the real run playable with its gate waiting")
	_check(timed.first_try_opportunities == 1 and timed.first_try_correct == 0 and timed.timeouts == 1 and timed.attempts == 1 and timed.submitted_answers == 0, "Unanswered deadline must create one observed timeout event only")
	_check(timed.response_samples == 0 and timed.mean_response_seconds == 0 and timed.facts[0].latencies.is_empty(), "Timeout duration must not masquerade as measured submitted-response latency")
	_check(timed.facts[0].timeout_latencies.size() == 1 and timed.facts[0].timeout_latencies[0] >= 7, "Actual timeout age must be retained in its separate event field")
	await create_timer(0.2).timeout
	_check(game.learning.summary().timeouts == 1, "Waiting after deadline must not accumulate more timeouts")
	await _answer(int(game.question.answer))
	_check(game.completed == 1 and game.gate_solved, "A real correct retry must clear the timed-out gate")
	await _key(KEY_ESCAPE)
	await _click(game, "FinishRun")
	var result: Dictionary = game.last_result
	_check(result.first_try_opportunities == 1 and result.first_try_correct == 0 and result.eventual_correct == 1 and result.assisted == 1, "Recovery must remain supported eventual success under the original opportunity")
	_check(result.attempts == 2 and result.submitted_answers == 1 and result.timeouts == 1 and result.retries == 1, "Timeout and subsequent submission must retain distinct event counts")
	_check(result.response_samples == 1 and result.mean_response_seconds < 2, "The submitted retry interval must exclude the earlier timeout duration")
	_check(game.store.get_profile("player-1").sessions.size() == 1, "The actual timeout/retry result must pass durable validation")
	await _dispose(game)
