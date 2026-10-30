extends SceneTree
## Native behavioral checks for the real course simulation. Browser/Autopilot
## suites cover UI input and pause clocks; no scene counters are manufactured here.
const Course = preload("res://scripts/course.gd")

var assertions := 0
var failures: Array[String] = []
var scenarios: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 10:
			push_error(message)

func _same_snapshot(first: Dictionary, second: Dictionary) -> bool:
	if first.keys() != second.keys(): return false
	for key in first:
		# JSON's decimal representation can move a float by ~1e-12. Preserve
		# integer/RNG identity exactly while allowing only negligible subpixels.
		if first[key] is float:
			if absf(float(first[key]) - float(second[key])) > 0.00000001: return false
		elif first[key] != second[key]: return false
	return true

func _scenario(label: String, action: Callable) -> void:
	var before := failures.size()
	var checks_before := assertions
	action.call()
	scenarios.append({"name": label, "passed": failures.size() == before, "assertions": assertions - checks_before})

func _fresh(seed_value: int = 73):
	var course = Course.new()
	course.reset(seed_value)
	return course

func _advance(course, seconds: float, hz: int = 60, duration: float = 14.0, practice: bool = false, assist: bool = false) -> void:
	for _frame in range(int(round(seconds * hz))):
		course.step(1.0 / hz, duration, practice, assist)

func _run() -> void:
	_scenario("Seeded routes and inputs reproduce the same simulation", _determinism)
	_scenario("Checkpoint restoration reproduces continuation and future hazards", _restore)
	_scenario("Jump has a usable arc, lands and rejects airborne double jumps", _jump_arc)
	_scenario("A late airborne input is buffered into the next landing", _jump_buffer)
	_scenario("Collision registers once and recovers without clearing a gate", _collision)
	_scenario("Assistance clears hazards across seeds, paces and step rates", _assist)
	_scenario("Manual timely jump clears a hazard at all supported paces", _manual_jump)
	_scenario("Practice waits indefinitely and a solved gate releases the route", _practice)
	_scenario("Waiting stops forward motion; correct clearing removes its hazard", _waiting_and_clear)
	_scenario("Long simulation stays finite and bounded", _stability)
	var report := {"suite": "native-course", "engine": Engine.get_version_info().string, "assertions": assertions, "passed": failures.is_empty(), "scenarios": scenarios, "failures": failures}
	print("DDGODOT_COURSE_REPORT=" + JSON.stringify(report))
	print("Course checks: %d assertions, %d scenarios, %d failures." % [assertions, scenarios.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _determinism() -> void:
	var first_positions: Dictionary = {}
	for seed_value in range(1, 33):
		var first = _fresh(seed_value)
		var second = _fresh(seed_value)
		first_positions[str(snappedf(first.obstacle_x, 0.01))] = true
		for frame in range(360):
			if frame % 73 == 0:
				first.jump()
				second.jump()
			first.step(1.0 / 60, 10, false, false)
			second.step(1.0 / 60, 10, false, false)
			_check(first.snapshot() == second.snapshot(), "Seed %d diverged at frame %d" % [seed_value, frame])
		first.new_gate()
		second.new_gate()
		_check(first.snapshot() == second.snapshot(), "Next hazard differed after identical seeded history")
	_check(first_positions.size() > 20, "Different seeds must produce route variation")

func _restore() -> void:
	var original = _fresh(194)
	original.jump()
	_advance(original, 0.3, 60, 7)
	# JSON roundtrip mirrors persistence, including the RNG state string.
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(original.snapshot()))
	var restored = _fresh(999)
	restored.restore(snapshot)
	_check(_same_snapshot(original.snapshot(), restored.snapshot()), "Stored airborne snapshot did not restore within subpixel precision")
	for frame in range(720):
		if frame % 120 == 0:
			original.new_gate()
			restored.new_gate()
		if frame % 79 == 0:
			original.jump()
			restored.jump()
		original.step(1.0 / 60, 10, false, true)
		restored.step(1.0 / 60, 10, false, true)
		_check(_same_snapshot(original.snapshot(), restored.snapshot()), "Restored course diverged at frame %d" % frame)

func _jump_arc() -> void:
	var peaks: Array[float] = []
	for hz in [60, 120]:
		var course = _fresh()
		course.obstacle_active = false
		course.jump()
		course.step(1.0 / hz, 10, false, false)
		_check(course.y < Course.FLOOR_Y and course.jumps == 1, "A grounded jump must respond on the next step")
		var peak: float = course.y
		for frame in range(hz):
			if frame == int(hz * 0.1): course.jump()
			course.step(1.0 / hz, 10, false, false)
			peak = minf(peak, course.y)
		_check(course.y == Course.FLOOR_Y and course.velocity == 0, "Jump must land within one second")
		_check(course.jumps == 1, "An early airborne input must not create a double jump or a late unwanted jump")
		var height: float = Course.FLOOR_Y - peak
		_check(height > 110 and height < 140, "Jump apex is outside the designed 110–140 logical pixel envelope")
		peaks.append(height)
	# Semi-implicit Euler integration may differ slightly; outcome must stay fair.
	_check(absf(peaks[0] - peaks[1]) < 6, "60/120 Hz jump apex drift exceeds the declared tolerance")

func _jump_buffer() -> void:
	for hz in [60, 120]:
		var course = _fresh()
		course.obstacle_active = false
		course.jump()
		var queued := false
		for _frame in range(hz * 2):
			if not queued and course.velocity > 0 and course.y > Course.FLOOR_Y - 25 and course.y < Course.FLOOR_Y:
				course.jump()
				queued = true
			course.step(1.0 / hz, 14, false, false)
			if course.jumps == 2: break
		_check(queued, "Test must queue the second input shortly before landing")
		_check(course.jumps == 2 and course.velocity < 0, "Buffered late input must fire after landing at %d Hz" % hz)
		_check(Course.BUFFER_SECONDS >= 0.10 and Course.BUFFER_SECONDS <= 0.15, "Jump buffer must remain in the intended short forgiveness window")

func _collision() -> void:
	for hz in [60, 120]:
		var course = _fresh()
		course.obstacle_x = Course.PLAYER_X + 30
		var observed_hit := false
		for _frame in range(hz):
			if course.step(1.0 / hz, 10, false, false):
				observed_hit = true
				break
		_check(observed_hit and course.collisions == 1, "Unjumped hazard must register one actual collision")
		_check(course.recovery > 0 and not course.obstacle_active, "Collision must start recovery and retire the hit hazard")
		_check(not course.cleared, "A motor collision cannot solve the arithmetic gate")
		_advance(course, 2, hz, 10)
		_check(course.collisions == 1 and course.recovery == 0, "Recovery must finish without repeating the same collision")

func _assist() -> void:
	for hz in [60, 120]:
		for duration in [14.0, 10.0, 7.0]:
			for seed_value in range(1, 25):
				var course = _fresh(seed_value)
				_advance(course, duration + 1, hz, duration, false, true)
				_check(course.collisions == 0, "Auto-assist collision: seed=%d, pace=%s, hz=%d" % [seed_value, duration, hz])
				_check(course.jumps == 1, "One hazard should require one assisted jump: seed=%d, pace=%s, hz=%d, jumps=%d" % [seed_value, duration, hz, course.jumps])

func _manual_jump() -> void:
	for hz in [60, 120]:
		for duration in [14.0, 10.0, 7.0]:
			var course = _fresh()
			# Place a hazard with 0.4 seconds to center contact. One manual press
			# must clear it without the assistance policy supplying later input.
			course.obstacle_x = Course.PLAYER_X + (940.0 / duration) * 0.4
			course.jump()
			_advance(course, 1.2, hz, duration)
			_check(course.collisions == 0 and course.jumps == 1, "Timed manual jump must clear hazard at pace=%s/hz=%d" % [duration, hz])

func _practice() -> void:
	for hz in [60, 120]:
		var course = _fresh(51)
		_advance(course, 120, hz, 14, true, true)
		_check(course.gate_x > Course.PLAYER_X + 80, "Untimed Practice must leave the gate ahead after two minutes")
		_check(not course.cleared, "Waiting alone must not clear a Practice gate")
		_check(course.collisions == 0, "Practice assistance must preserve a recoverable obstacle route")
		var before: float = course.gate_x
		course.clear_gate(true)
		_advance(course, 0.4, hz, 14, true, true)
		_check(course.gate_x < before and course.cleared and not course.obstacle_active, "Correct answer must release a waiting Practice gate")

func _waiting_and_clear() -> void:
	var course = _fresh()
	course.waiting = true
	var gate_before: float = course.gate_x
	var obstacle_before: float = course.obstacle_x
	var scroll_before: float = course.scroll
	_advance(course, 10, 60, 7)
	_check(course.gate_x == gate_before and course.obstacle_x == obstacle_before and course.scroll == scroll_before, "Recovery waiting must stop forward motion")
	course.clear_gate(false)
	_check(course.cleared and not course.waiting and not course.obstacle_active, "Clearing must release waiting and retire the associated hazard")
	_advance(course, 1, 60, 7)
	_check(course.collisions == 0 and course.gate_x < Course.PLAYER_X, "A cleared gate must pass harmlessly")
	course.new_gate()
	_check(not course.cleared and not course.waiting and course.obstacle_active and course.gate_x > Course.PLAYER_X, "Next gate must start with fresh logical state")

func _stability() -> void:
	var course = _fresh(5319)
	for frame in range(18000):
		if frame % 180 == 0: course.new_gate()
		if frame % 120 == 0: course.jump()
		course.step(1.0 / 60, 7, frame % 2 == 0, true)
		if frame % 60 == 0:
			_check(is_finite(course.y) and is_finite(course.velocity) and is_finite(course.gate_x) and is_finite(course.scroll), "Five-minute simulation must remain finite")
			_check(course.y <= Course.FLOOR_Y and course.y >= Course.FLOOR_Y - 300, "Player vertical state must remain inside the supported range")
