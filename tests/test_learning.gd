extends SceneTree

const Learning = preload("res://scripts/learning.gd")
const SaveStore = preload("res://scripts/save_store.gd")
var assertions := 0
var failures: Array = []
var scenarios := 0

func _initialize() -> void:
	_test_pools()
	_test_original_parity()
	_test_occurrences()
	_test_assistance()
	_test_determinism_and_recovery()
	_test_storage()
	print("LEARNING_TEST_RESULT " + JSON.stringify({"scenarios": scenarios, "assertions": assertions, "failures": failures.size(), "details": failures}))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 15: printerr("FAIL: " + message)

func same(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) < 0.000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not same(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in range(left.size()):
			if not same(left[index], right[index]): return false
		return true
	return left == right

func _test_pools() -> void:
	scenarios += 1
	var counts := {"addition": 441, "subtraction": 441, "multiplication": 169, "division": 156, "mixed": 1207}
	for op in counts:
		var pool: Array = Learning.build_fact_pool(op, 20)
		check(pool.size() == counts[op], op + " original pool count")
		var keys: Dictionary = {}
		for fact in pool:
			check(not keys.has(fact.key), "unique " + fact.key)
			keys[fact.key] = true
			var expected := 0
			match fact.opType:
				"addition": expected = int(fact.a) + int(fact.b)
				"subtraction": expected = int(fact.a) - int(fact.b)
				"multiplication": expected = int(fact.a) * int(fact.b)
				"division":
					check(int(fact.b) != 0, "division has nonzero denominator")
					expected = int(fact.a) / int(fact.b)
			check(int(fact.answer) == expected and expected >= 0, "arithmetic " + fact.key)
	check(Learning.build_fact_pool("addition", -1).is_empty(), "negative range rejected")
	check(Learning.build_fact_pool("addition", 101).is_empty(), "unbounded allocation rejected")
	check(Learning.build_fact_pool("division", 0).is_empty(), "range zero never invents division by zero")
	check(Learning.build_fact_pool("addition", 0).size() == 1, "zero addition pool remains valid")
	var restricted: Array = Learning.build_fact_pool("mixed", 12, {"operations": ["addition", "division"], "answer_range": [1, 10]})
	check(not restricted.is_empty(), "restricted pool populated")
	for fact in restricted:
		check(fact.opType in ["addition", "division"] and int(fact.answer) >= 1 and int(fact.answer) <= 10, "restricted operations and answers")

func _test_original_parity() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/learning_original.json"))
	for example in fixture.classification:
		var key: String = example.key
		var operation := "addition"
		var symbol := "+"
		for candidate in Learning.SYMBOLS:
			if key.contains(Learning.SYMBOLS[candidate]):
				operation = candidate
				symbol = Learning.SYMBOLS[candidate]
				break
		var parts := key.split(symbol)
		var actual: Dictionary = Learning.classify_fact(operation, int(parts[0]), int(parts[1]))
		check(actual.rule == ("" if example.rule == null else example.rule), "pattern rule " + key)
		check(actual.mirror == ("" if example.mirror == null else example.mirror), "pattern mirror " + key)
		check(actual.canonical_key == example.canonicalKey and actual.core == example.core, "pattern identity " + key)
	for scenario in fixture.scenarios:
		scenarios += 1
		var learner = Learning.new()
		learner.configure(scenario.operation, int(scenario.range), int(scenario.seed))
		check(same(learner.sweep, scenario.initialSweep), "original initial sweep " + scenario.operation)
		for step in scenario.trace:
			learner.clock_override_ms = int(step.now)
			var fact: Dictionary = learner.scheduler_next()
			check(fact.key == step.key, "original next question %s #%d expected %s got %s" % [scenario.operation, learner.q_index, step.key, fact.key])
			learner.record_evidence(fact, step.correct, step.latency, false, int(step.now))
			check(same(learner.bucket[fact.key], step.stat), "original evidence %s #%d" % [scenario.operation, learner.q_index])
			check(learner.tier(fact.key) == step.tier, "original tier %s #%d" % [scenario.operation, learner.q_index])
			check(same(learner.requeue, step.requeue), "original requeue %s #%d" % [scenario.operation, learner.q_index])

func _test_occurrences() -> void:
	scenarios += 1
	var learner = Learning.new()
	learner.configure("addition", 10, 72)
	var q: Dictionary = learner.next_question()
	check(learner.summary().first_try_opportunities == 0, "unanswered question contributes no invented observation")
	var first: Dictionary = learner.submit(int(q.answer) + 1, 2.0)
	check(first.accepted and not first.correct, "wrong answer remains open")
	check(learner.summary().first_try_opportunities == 1, "first wrong creates one opportunity")
	learner.submit(int(q.answer) + 2, 1.5)
	var solved: Dictionary = learner.submit(int(q.answer), 3.0)
	check(solved.correct and not solved.first_try and solved.assisted, "correct retry is assisted and never first-try")
	var stats: Dictionary = learner.summary()
	check(stats.first_try_opportunities == 1 and stats.first_try_correct == 0 and stats.eventual_correct == 1, "occurrence denominator survives retries")
	check(stats.attempts == 3 and stats.retries == 2 and stats.assisted == 1, "attempts and retries measured independently")
	check(stats.mean_response_seconds == 2.0, "first response time excludes later retry intervals")
	var duplicate: Dictionary = learner.submit(int(q.answer), 0.0)
	check(not duplicate.accepted and learner.summary().attempts == 3, "rapid duplicate submit does not create evidence")
	q = learner.next_question()
	learner.submit(int(q.answer), 4.0)
	stats = learner.summary()
	check(stats.first_try_correct == 1 and stats.first_try_opportunities == 2 and stats.accuracy == 0.5, "unassisted first response is measured")
	q = learner.next_question()
	learner.submit(int(q.answer) + 1, 5.0)
	learner.timeout(7.0)
	stats = learner.summary()
	check(stats.first_try_opportunities == 3 and stats.timeouts == 1, "wrong then timeout is one opportunity")
	check(stats.attempts == 6, "timeout contributes an event, not a submitted retry")
	check(not learner.timeout(7.0).accepted, "duplicate timeout ignored")
	learner.next_question()
	learner.timeout(8.0)
	check(learner.summary().first_try_opportunities == 4 and learner.summary().timeouts == 2, "unanswered timeout is an observation")
	learner.next_question()
	check(learner.summary().first_try_opportunities == 4, "ending with displayed question invents no timeout")
	check(not learner.submit(0, NAN).accepted and not learner.submit(0, -1.0).accepted, "invalid timing never enters evidence")
	scenarios += 1
	var recovery = Learning.new()
	recovery.configure("addition", 10, 44)
	q = recovery.next_question()
	check(recovery.timeout(9.0).accepted, "deadline creates one nonresponse observation")
	check(recovery.summary().response_samples == 0 and recovery.summary().mean_response_seconds == 0.0, "unanswered timeout is not a response-time sample")
	check(recovery.bucket[q.key].lats.is_empty(), "timeout does not invent latency samples for fluency")
	check(not recovery.timeout(10.0).accepted, "waiting at timed-out gate never creates repeated timeouts")
	var recovered: Dictionary = recovery.submit(int(q.answer), 3.0)
	check(recovered.correct and recovered.assisted and not recovered.first_try, "timed-out gate remains open for assisted recovery")
	var recovered_stats: Dictionary = recovery.summary()
	check(recovered_stats.first_try_opportunities == 1 and recovered_stats.eventual_correct == 1 and recovered_stats.first_try_correct == 0, "timeout recovery preserves the same opportunity")
	check(recovered_stats.attempts == 2 and recovered_stats.submitted_answers == 1 and recovered_stats.retries == 1, "timeout recovery counts events and submissions separately")
	check(recovered_stats.mean_response_seconds == 3.0 and recovered_stats.response_samples == 1, "recovery response uses observed submitted interval")
	check(recovered_stats.facts[0].latencies == [3.0] and recovered_stats.facts[0].timeout_latencies == [9.0], "event durations and response samples remain separate")
	check(recovery.use_hint() == "" and recovery.summary().first_try_correct == 0, "resolved hint cannot mutate an answer record")

func _test_assistance() -> void:
	scenarios += 1
	var learner = Learning.new()
	learner.configure("multiplication", 12, 20)
	var question: Dictionary = learner.next_question()
	var hint: String = learner.use_hint()
	check(hint != "" and learner.summary().first_try_opportunities == 0, "hint is not fabricated answer evidence")
	learner.submit(int(question.answer), 1.0)
	check(learner.summary().first_try_correct == 0 and learner.summary().assisted == 1, "hint before first correct is assisted")
	var fact := {"a": 3, "b": 7, "answer": 21, "symbol": "×", "opType": "multiplication", "key": "3×7"}
	for i in range(3): learner.record_evidence(fact, true, 1.0, true, 123456)
	check(learner.bucket[fact.key].stage == 1 and learner.bucket[fact.key].streak == 0, "assistance never promotes stage or streak")
	check(learner.tier(fact.key) != "fluent", "assisted repetition cannot claim fluency")
	learner.record_evidence(fact, true, 1.0, false, 123457)
	learner.record_evidence(fact, true, 1.0, false, 123458)
	learner.record_evidence(fact, true, 1.0, true, 123459)
	learner.record_evidence(fact, true, 1.0, false, 123460)
	check(learner.tier(fact.key) != "fluent", "hint breaks independent success sequence")
	learner.record_evidence(fact, true, 1.0, false, 123461)
	learner.record_evidence(fact, true, 1.0, false, 123462)
	check(learner.tier(fact.key) == "fluent", "three subsequent independent fast answers support measured fluency")
	check(not learner.bucket.has("7×3") and learner.is_inferred(learner.by_key["7×3"]), "mirror familiarity is inferred without copied evidence")
	var legacy = Learning.new()
	legacy.configure("multiplication", 12, 20, {"3×7": {"att": 8, "cor": 8, "streak": 8, "lats": [1, 1, 1], "interval": 9, "lastTs": 1}})
	check(legacy.bucket["3×7"].att == 8 and legacy.bucket["3×7"].cor == 8, "legacy aggregate values preserved")
	check(legacy.bucket["3×7"].streak == 0 and legacy.bucket["3×7"].lats.is_empty() and legacy.tier("3×7") != "fluent", "aggregate hydration does not fabricate recent samples")

func _test_determinism_and_recovery() -> void:
	scenarios += 1
	var first = Learning.new()
	var second = Learning.new()
	first.configure("mixed", 12, 213)
	second.configure("mixed", 12, 213)
	for i in range(40):
		first.clock_override_ms = 1000000 + i * 1000
		second.clock_override_ms = first.clock_override_ms
		var a: Dictionary = first.next_question()
		var b: Dictionary = second.next_question()
		check(same(a, b), "seeded sequence %d" % i)
		var answer := int(a.answer) + (1 if i % 3 == 0 else 0)
		first.submit(answer, 2.0)
		second.submit(answer, 2.0)
	check(same(first.export_state(), second.export_state()), "identical seeds and measurements produce identical full state")
	var clone = Learning.new()
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(first.export_state()))
	check(clone.restore_state(serialized), "JSON checkpoint restores")
	check(same(clone.export_state(), first.export_state()), "checkpoint contains exact scheduler/ledger/occurrence state")
	clone.clock_override_ms = first.clock_override_ms
	check(same(clone.next_question(), first.next_question()), "restored RNG yields identical next question")
	var snapshot: Dictionary = first.export_state()
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt.question.answer += 1
	check(not clone.restore_state(corrupt), "wrong arithmetic checkpoint rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.ledger[0].first_correct = true
	corrupt.ledger[0].correct = false
	check(not clone.restore_state(corrupt), "impossible learning checkpoint rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.version = 99
	check(not clone.restore_state(corrupt), "future checkpoint version rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.version = {"bad": 1}
	check(not clone.restore_state(corrupt), "wrongly typed version is rejected without crashing")
	corrupt = snapshot.duplicate(true)
	corrupt.ledger.append(corrupt.ledger[0].duplicate(true))
	check(not clone.restore_state(corrupt), "duplicated occurrence ledger rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.requeue = [{"key": "1+1", "dueAt": {"bad": 1}}]
	check(not clone.restore_state(corrupt), "wrongly typed retry queue rejected")
	check(second.q_index == 40, "independent instances never share question state")
	var external: Dictionary = second.export_evidence()
	external.clear()
	check(not second.bucket.is_empty(), "exported evidence does not expose mutable learning state")

func _test_storage() -> void:
	scenarios += 1
	var file_path := "user://learning_test_%d.json" % OS.get_process_id()
	var store = SaveStore.new(file_path)
	check(store.load_data().profiles.is_empty(), "missing save is clean first launch")
	var profile: Dictionary = store.get_profile("learner_a")
	profile.settings = {"muted": true}
	profile.evidence = {"addition:10": {"3+2": {"att": 1, "cor": 1}}}
	check(store.save_profile("learner_a", profile), "save profile atomically")
	check(store.get_profile("learner_b").evidence.is_empty(), "learner evidence stays separate")
	check(store.save_checkpoint("learner_a", {"session_id": "a-session", "typed": "12", "active_seconds": 23.5}), "checkpoint stored")
	check(store.get_checkpoint("learner_b").is_empty(), "other learner cannot resume checkpoint")
	var reopened = SaveStore.new(file_path)
	check(reopened.load_data().profiles.size() == 1 and reopened.last_error == "", "saved JSON read independently")
	check(reopened.get_checkpoint("learner_a").typed == "12", "interrupted answer restored without submission")
	check(not reopened.discard_checkpoint("learner_a", "different-session"), "identity guard prevents deleting another checkpoint")
	var learner = Learning.new()
	learner.configure("addition", 10, 2)
	var question: Dictionary = learner.next_question()
	learner.submit(int(question.answer), 2.2)
	var result: Dictionary = learner.summary()
	result.session_id = "a-session"
	result.mode = "practice"
	result.active_seconds = 3.0
	check(reopened.complete_session("learner_a", result), "completed observed session saved")
	check(reopened.get_checkpoint("learner_a").is_empty(), "only matching completed checkpoint cleared")
	check(reopened.complete_session("learner_a", result), "same completion is idempotent")
	check(reopened.get_profile("learner_a").sessions.size() == 1, "completion retransmission does not duplicate result")
	var after_reload = SaveStore.new(file_path)
	after_reload.load_data()
	check(after_reload.complete_session("learner_a", JSON.parse_string(JSON.stringify(result))), "idempotency survives JSON numeric normalization")
	var conflict: Dictionary = result.duplicate(true)
	conflict.active_seconds = 8.0
	check(not after_reload.complete_session("learner_a", conflict), "different payload cannot reuse a completed session ID")
	check(after_reload.complete_session("learner_b", result), "same local identifier in separate profile remains scoped")
	check(after_reload.get_profile("learner_b").sessions.size() == 1 and after_reload.get_profile("learner_a").sessions.size() == 1, "profile results separate")
	var impossible: Dictionary = result.duplicate(true)
	impossible.session_id = "impossible"
	impossible.first_try_correct = 100
	check(not after_reload.complete_session("learner_a", impossible), "impossible accuracy rejected before write")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("{BROKEN")
	file.close()
	var damaged = SaveStore.new(file_path)
	damaged.load_data()
	check(damaged.blocked_on_corruption and damaged.last_error != "", "corruption surfaced to UI")
	check(not damaged.save_profile("learner_a", profile), "corrupt storage not silently overwritten")
	check(FileAccess.get_file_as_string(file_path) == "{BROKEN", "original corrupted bytes retained")
	check(damaged.restore_backup(), "explicit backup recovery works")
	check(FileAccess.get_file_as_string(file_path + ".corrupt") == "{BROKEN", "backup recovery preserves damaged source")
	check(damaged.get_profile("learner_a").sessions.size() == 1, "backup preserves earlier valid session")
	for malformed in [{"version": {}, "profiles": {}}, {"version": 1, "profiles": []}, {"version": 1, "profiles": {"a": {"evidence": [], "checkpoint": {}, "settings": {}, "sessions": [], "completed_ids": {}}}}]:
		file = FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(malformed))
		file.close()
		var invalid = SaveStore.new(file_path)
		invalid.load_data()
		check(invalid.blocked_on_corruption and invalid.last_error != "", "wrongly typed save is rejected without crashing")
	var blocked = SaveStore.new("user://missing_parent_%d/no.json" % OS.get_process_id())
	check(not blocked.save_profile("learner_a", profile) and blocked.last_error != "", "failed write produces warning and no success claim")
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path + suffix))
