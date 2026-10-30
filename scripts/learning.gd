class_name DashLearning
extends RefCounted
## Engine-independent arithmetic, adaptive scheduling and occurrence evidence.
## Scheduler equations ported from geometrymash f43bf817; see docs/LEARNING-PARITY.md.
## The caller supplies ACTIVE response time: pausing and animation never enter here.

const OPERATIONS := ["addition", "subtraction", "multiplication", "division"]
const SYMBOLS := {"addition": "+", "subtraction": "-", "multiplication": "×", "division": "÷"}
const STATE_VERSION := 1

var operation := "mixed"
var max_number := 12
var seed_value := 73
var random_state: int = 73
var pool: Array = []
var by_key: Dictionary = {}
var bucket: Dictionary = {}
var sweep: Array = []
var recent: Array = []
var requeue: Array = []
var session_miss: Dictionary = {}
var session_seen: Dictionary = {}
var q_index := 0
var question: Dictionary = {}
var occurrence: Dictionary = {}
var ledger: Array = []
var last_error := ""
var configured_options: Dictionary = {}
var clock_override_ms := -1 # Deterministic replay; -1 uses the real epoch clock.

func configure(op: String = "mixed", limit: int = 12, initial_seed: int = 73, evidence: Dictionary = {}, options: Dictionary = {}) -> void:
	operation = op if op in OPERATIONS or op == "mixed" else "mixed"
	max_number = clampi(limit, 0, 100)
	seed_value = initial_seed
	random_state = initial_seed & 0xffffffff
	configured_options = options.duplicate(true)
	pool = build_fact_pool(operation, max_number, options)
	by_key.clear()
	for fact in pool:
		by_key[fact.key] = fact
	bucket = sanitize_evidence(evidence)
	sweep.clear()
	recent.clear()
	requeue.clear()
	session_miss.clear()
	session_seen.clear()
	q_index = 0
	question = {}
	occurrence = {}
	ledger.clear()
	last_error = ""
	var shuffled: Array = pool.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := int(floor(_random() * (i + 1)))
		var temporary: Dictionary = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = temporary
	var canonical: Dictionary = {}
	var rule_samples: Dictionary = {}
	for fact in shuffled:
		if int(bucket.get(fact.key, {}).get("att", 0)) > 0:
			continue
		var pattern := classify_fact(fact.opType, fact.a, fact.b)
		if canonical.has(pattern.canonical_key):
			continue
		canonical[pattern.canonical_key] = true
		if pattern.core:
			sweep.append(fact.key)
		else:
			var rule_key: String = fact.opType + ":" + pattern.rule
			rule_samples[rule_key] = int(rule_samples.get(rule_key, 0)) + 1
			if int(rule_samples[rule_key]) <= 2:
				sweep.append(fact.key)

static func build_fact_pool(op: String, limit: int, options: Dictionary = {}) -> Array:
	var output: Array = []
	if limit < 0 or limit > 100:
		return output
	var cap := mini(limit, 12)
	if op == "mixed":
		var chosen: Array = []
		var selected: Variant = options.get("operations", OPERATIONS)
		if not selected is Array: return []
		for item in selected:
			if item in OPERATIONS and item not in chosen:
				chosen.append(item)
		if chosen.is_empty():
			chosen = OPERATIONS.duplicate()
		for item in chosen:
			output.append_array(build_fact_pool(item, limit, options))
		return output
	if op == "addition":
		for a in range(limit + 1):
			for b in range(limit + 1):
				output.append(_fact(a, b, a + b, op))
	elif op == "subtraction":
		for b in range(limit + 1):
			for difference in range(limit + 1):
				output.append(_fact(b + difference, b, difference, op))
	elif op == "multiplication":
		for a in range(cap + 1):
			for b in range(cap + 1):
				output.append(_fact(a, b, a * b, op))
	elif op == "division":
		for b in range(1, cap + 1):
			for quotient in range(cap + 1):
				output.append(_fact(b * quotient, b, quotient, op))
	if options.has("answer_range"):
		if not options.answer_range is Array: return []
		var bounds: Array = options.answer_range
		if bounds.size() != 2:
			return []
		for bound in bounds:
			if not (bound is int or bound is float) or not is_finite(float(bound)): return []
		if bounds[0] > bounds[1]:
			return []
		output = output.filter(func(f: Dictionary) -> bool: return f.answer >= bounds[0] and f.answer <= bounds[1])
	return output

static func _fact(a: int, b: int, answer: int, op: String) -> Dictionary:
	return {"a": a, "b": b, "answer": answer, "symbol": SYMBOLS[op], "opType": op, "key": "%d%s%d" % [a, SYMBOLS[op], b]}

static func classify_fact(op: String, a: int, b: int) -> Dictionary:
	var x := a
	var y := b
	var addition := op == "addition" or op == "subtraction"
	if op == "subtraction":
		x = b
		y = a - b
	elif op == "division":
		x = b
		y = int(a / b) if b != 0 else 0
	var low := mini(x, y)
	var high := maxi(x, y)
	var rule := ""
	if high <= 10:
		if addition:
			if low == 0: rule = "identity"
			elif x == 10 or y == 10: rule = "ten"
			elif x == 9 or y == 9: rule = "nine"
			elif low <= 2: rule = "counton"
			elif x == y: rule = "doubles"
			elif x + y == 10: rule = "maketen"
		else:
			if low <= 1: rule = "identity"
			elif x == 10 or y == 10: rule = "ten"
			elif x == 9 or y == 9: rule = "nine"
			elif low == 2: rule = "two"
			elif x == y: rule = "square"
	var key := "%d%s%d" % [a, SYMBOLS.get(op, "+"), b]
	var mirror := ""
	if (op == "addition" or op == "multiplication") and a != b:
		mirror = "%d%s%d" % [b, SYMBOLS[op], a]
	elif op == "subtraction" and a - b != b:
		mirror = "%d-%d" % [a, a - b]
	elif op == "division" and b != 0 and int(a / b) != b and a != 0:
		mirror = "%d÷%d" % [a, int(a / b)]
	return {"rule": rule, "core": rule == "", "mirror": mirror, "canonical_key": mirror if mirror != "" and mirror < key else key}

func _random() -> float:
	random_state = (random_state * 1664525 + 1013904223) & 0xffffffff
	return float(random_state) / 4294967296.0

func next_question() -> Dictionary:
	question = scheduler_next()
	occurrence = {"id": q_index, "key": question.get("key", ""), "observed": false, "first_correct": false, "correct": false, "assisted": false, "attempts": 0, "retries": 0, "timeouts": 0, "latencies": [], "timeout_latencies": [], "first_latency": 0.0, "resolved": false}
	return question.duplicate(true)

func scheduler_next() -> Dictionary:
	if pool.is_empty():
		return {}
	q_index += 1
	for i in range(requeue.size()):
		if int(requeue[i].dueAt) <= q_index:
			var key: String = requeue[i].key
			requeue.remove_at(i)
			if by_key.has(key) and _recent_count(key) < 2:
				return _present(key)
			break
	while not sweep.is_empty():
		var key: String = sweep.pop_front()
		if by_key.has(key):
			return _present(key)
	var target := fluency_target()
	var best: Dictionary = {}
	var best_score := -INF
	for fact in pool:
		if int(session_miss.get(fact.key, 0)) >= 3 or _recent_count(fact.key) >= 2:
			continue
		if not recent.is_empty() and recent.back() == fact.key:
			continue
		var score := priority_score(fact, target)
		if score > best_score:
			best = fact
			best_score = score
	if best.is_empty():
		best = pool[int(floor(_random() * pool.size()))]
	return _present(best.key)

func _present(key: String) -> Dictionary:
	recent.append(key)
	if recent.size() > 12: recent.pop_front()
	session_seen[key] = int(session_seen.get(key, 0)) + 1
	return by_key[key].duplicate(true)

func _recent_count(key: String) -> int:
	return recent.slice(maxi(0, recent.size() - 6)).count(key)

func _stat(key: String) -> Dictionary:
	if not bucket.has(key):
		bucket[key] = {"att": 0, "cor": 0, "lats": [], "streak": 0, "interval": 0, "lastIdx": -999, "lastTs": 0}
	return bucket[key]

func avg_latency(stat: Dictionary) -> Variant:
	var latencies: Array = stat.get("lats", [])
	if latencies.is_empty(): return null
	var total := 0.0
	for value in latencies: total += float(value)
	return total / latencies.size()

func fluency_target() -> float:
	var fast: Array = []
	for stat in bucket.values():
		if int(stat.get("att", 0)) >= 2 and stat.get("cor", 0) == stat.att:
			var average: Variant = avg_latency(stat)
			if average != null: fast.append(average)
	if fast.is_empty(): return 3.5
	fast.sort()
	return clampf(float(fast[int(fast.size() / 2)]) * 1.15, 1.8, 5.0)

func tier(key: String, target: float = -1.0) -> String:
	var stat: Dictionary = bucket.get(key, {})
	if int(stat.get("att", 0)) == 0: return "new"
	if float(stat.get("cor", 0)) / float(stat.att) < 0.7 or int(stat.get("streak", 0)) == 0: return "shaky"
	if target < 0.0: target = fluency_target()
	var average: Variant = avg_latency(stat)
	var latencies: Array = stat.get("lats", [])
	var quick_recent := latencies.size() >= 3
	for value in latencies.slice(maxi(0, latencies.size() - 3)):
		if float(value) > target: quick_recent = false
	# A hint/retry cannot bridge two independent-success streaks into fluency.
	if int(stat.get("streak", 0)) >= 3 and quick_recent and average != null and float(average) <= target:
		return "fluent"
	return "learning"

func is_inferred(fact: Dictionary, target: float = -1.0) -> bool:
	var mirror: String = classify_fact(fact.opType, fact.a, fact.b).mirror
	return mirror != "" and tier(mirror, target) in ["learning", "fluent"]

func rule_known(rule: String, op: String, target: float) -> bool:
	var counted: Dictionary = {}
	for fact in pool:
		if fact.opType != op: continue
		var pattern := classify_fact(op, fact.a, fact.b)
		if pattern.rule != rule or counted.has(pattern.canonical_key): continue
		var stat: Dictionary = bucket.get(fact.key, {})
		if int(stat.get("att", 0)) == 0 or tier(fact.key, target) not in ["learning", "fluent"]: continue
		var average: Variant = avg_latency(stat)
		if average == null or float(average) > target or int(stat.get("assisted", 0)) >= int(stat.get("cor", 0)): continue
		counted[pattern.canonical_key] = true
	return counted.size() >= 3

func priority_score(fact: Dictionary, target: float, now_ms: int = -1) -> float:
	var stat: Dictionary = bucket.get(fact.key, {})
	var pattern := classify_fact(fact.opType, fact.a, fact.b)
	if int(stat.get("att", 0)) == 0:
		if not pattern.core and rule_known(pattern.rule, fact.opType, target): return 0.4
		if is_inferred(fact, target): return 1.5
		return 6.0 if pattern.core else 4.0
	var accuracy := float(stat.cor) / float(stat.att)
	var average: Variant = avg_latency(stat)
	if average == null: average = target
	var since := q_index - int(stat.get("lastIdx", -999))
	var interval := maxi(1, int(stat.get("interval", 1)))
	var overdue := minf(2.5, float(since) / interval)
	if now_ms < 0: now_ms = _now_ms()
	var days := float(now_ms - int(stat.get("lastTs", 0))) / 86400000.0 if int(stat.get("lastTs", 0)) > 0 else 0.0
	return (1.0 - accuracy) * 4.0 + maxf(0.0, (float(average) - target) / target) * 2.2 + overdue * 1.6 + minf(1.2, days * 0.35) - _recent_count(fact.key) * 3.0

func record_evidence(fact: Dictionary, correct: bool, latency: float, assisted: bool = false, now_ms: int = -1) -> void:
	var key: String = fact.get("key", "%d%s%d" % [fact.get("a", 0), fact.get("symbol", "+"), fact.get("b", 0)])
	if not by_key.has(key): return
	if not is_finite(latency): return
	var stat := _stat(key)
	var measured := clampf(latency, 0.1, 60.0)
	stat.att = int(stat.att) + 1
	if correct: stat.cor = int(stat.cor) + 1
	stat.lats.append(snappedf(measured, 0.01))
	if stat.lats.size() > 5: stat.lats.pop_front()
	stat.lastIdx = q_index
	stat.lastTs = _now_ms() if now_ms < 0 else now_ms
	var target := fluency_target()
	if correct and assisted:
		stat.assisted = int(stat.get("assisted", 0)) + 1
		stat.interval = 2
		stat.streak = 0
		stat.run2 = 0
	elif correct:
		stat.streak = int(stat.streak) + 1
		var previous := maxi(1, int(stat.interval))
		stat.interval = int(floor(previous * (2.2 if measured <= target else 1.2) + (2 if measured <= target else 1) + 0.5))
	else:
		stat.streak = 0
		stat.interval = 2
		session_miss[key] = int(session_miss.get(key, 0)) + 1
		if int(session_miss[key]) < 3:
			requeue.append({"key": key, "dueAt": q_index + 2 + int(floor(_random() * 3))})
	stat.interval = mini(int(stat.interval), 400)
	stat.stage = maxi(1, int(stat.get("stage", 1)))
	if correct and not assisted:
		stat.run2 = int(stat.get("run2", 0)) + 1
		if int(stat.run2) >= 2:
			stat.stage = mini(5, int(stat.stage) + 1)
			stat.run2 = 0
	elif not correct:
		stat.stage = maxi(1, int(stat.stage) - 1)
		stat.run2 = 0

func submit(answer: int, latency_seconds: float, assisted: bool = false) -> Dictionary:
	if question.is_empty() or occurrence.is_empty() or occurrence.resolved:
		return {"accepted": false, "correct": false, "first_try": false, "completed": false}
	if not is_finite(latency_seconds) or latency_seconds < 0.0:
		return {"accepted": false, "correct": false, "first_try": false, "completed": false}
	var first := not bool(occurrence.observed)
	var correct: bool = answer == int(question.answer)
	var helped: bool = assisted or bool(occurrence.assisted) or int(occurrence.attempts) > 0 or int(occurrence.timeouts) > 0
	if int(occurrence.attempts) == 0: occurrence.first_latency = latency_seconds
	occurrence.observed = true
	if int(occurrence.attempts) > 0 or int(occurrence.timeouts) > 0: occurrence.retries = int(occurrence.retries) + 1
	occurrence.attempts = int(occurrence.attempts) + 1
	occurrence.assisted = helped
	occurrence.latencies.append(latency_seconds)
	occurrence.first_correct = first and correct and not helped
	occurrence.correct = correct
	occurrence.resolved = correct
	record_evidence(question, correct, latency_seconds, helped)
	_commit_occurrence()
	return {"accepted": true, "correct": correct, "first_try": bool(occurrence.first_correct), "completed": correct, "assisted": helped, "feedback": "Correct." if correct else error_feedback(answer)}

func timeout(latency_seconds: float) -> Dictionary:
	if question.is_empty() or occurrence.is_empty() or occurrence.resolved or int(occurrence.get("timeouts", 0)) > 0 or not is_finite(latency_seconds) or latency_seconds < 0.0:
		return {"accepted": false, "completed": false}
	occurrence.observed = true
	occurrence.timeouts = int(occurrence.timeouts) + 1
	occurrence.timeout_latencies.append(latency_seconds)
	occurrence.assisted = true
	var before_latencies: Array = bucket.get(question.key, {}).get("lats", []).duplicate()
	record_evidence(question, false, latency_seconds)
	# Nonresponse duration is an event clock, never a submitted response sample.
	bucket[question.key].lats = before_latencies
	bucket[question.key].timeout_count = int(bucket[question.key].get("timeout_count", 0)) + 1
	_commit_occurrence()
	return {"accepted": true, "completed": false, "correct": false}

func _commit_occurrence() -> void:
	for i in range(ledger.size()):
		if int(ledger[i].id) == int(occurrence.id):
			ledger[i] = occurrence.duplicate(true)
			return
	ledger.append(occurrence.duplicate(true))

func use_hint() -> String:
	if question.is_empty() or occurrence.get("resolved", false): return ""
	occurrence.assisted = true
	if occurrence.get("observed", false): _commit_occurrence()
	var a := int(question.a)
	var b := int(question.b)
	match question.opType:
		"addition": return "Start at %d and count on %d. %d + %d = %d." % [maxi(a, b), mini(a, b), a, b, question.answer]
		"subtraction": return "Think: %d + ? = %d. Count up from %d to %d: %d." % [b, a, b, a, question.answer]
		"multiplication": return "%d groups of %d. %d × %d = %d." % [a, b, a, b, question.answer]
		"division": return "Think: %d × ? = %d. %d × %d = %d." % [b, a, b, question.answer, a]
	return ""

func error_feedback(answer: int) -> String:
	if question.is_empty(): return "Try again."
	var difference := answer - int(question.answer)
	if abs(difference) == 1: return "One away. Take another look."
	if abs(difference) == 10: return "Check the tens place."
	if question.opType == "multiplication" and answer == int(question.a) + int(question.b): return "This one multiplies; you added."
	if question.opType == "subtraction" and answer == int(question.a) + int(question.b): return "This one takes away; you added."
	return "Try another answer. The gate is still yours."

func summary() -> Dictionary:
	var result := {"first_try_metric_version": 1, "first_try_opportunities": 0, "first_try_correct": 0, "eventual_correct": 0, "attempts": 0, "submitted_answers": 0, "retries": 0, "assisted": 0, "timeouts": 0, "accuracy": 0.0, "mean_response_seconds": 0.0, "response_samples": 0, "facts": [], "questions_presented": q_index}
	var response_sum := 0.0
	for entry in ledger:
		if not entry.observed: continue
		result.first_try_opportunities += 1
		if entry.first_correct: result.first_try_correct += 1
		if entry.correct: result.eventual_correct += 1
		if entry.assisted and entry.correct: result.assisted += 1
		result.attempts += int(entry.attempts) + int(entry.timeouts)
		result.submitted_answers += int(entry.attempts)
		result.retries += int(entry.retries)
		result.timeouts += int(entry.timeouts)
		if int(entry.attempts) > 0:
			response_sum += float(entry.first_latency)
			result.response_samples += 1
		result.facts.append(entry.duplicate(true))
	if result.first_try_opportunities > 0:
		result.accuracy = float(result.first_try_correct) / result.first_try_opportunities
	if result.response_samples > 0:
		result.mean_response_seconds = response_sum / result.response_samples
	return result

func stats() -> Dictionary:
	var result := {"new": 0, "shaky": 0, "learning": 0, "fluent": 0, "inferred": 0, "direct": 0, "total": pool.size()}
	var target := fluency_target()
	for fact in pool:
		var label := tier(fact.key, target)
		result[label] += 1
		if label != "new": result.direct += 1
		elif is_inferred(fact, target): result.inferred += 1
	return result

func export_evidence() -> Dictionary:
	return bucket.duplicate(true)

func _now_ms() -> int:
	return clock_override_ms if clock_override_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)

func export_state() -> Dictionary:
	return {"version": STATE_VERSION, "operation": operation, "max_number": max_number, "seed": seed_value, "random_state": random_state, "options": configured_options.duplicate(true), "bucket": export_evidence(), "sweep": sweep.duplicate(), "recent": recent.duplicate(), "requeue": requeue.duplicate(true), "session_miss": session_miss.duplicate(), "session_seen": session_seen.duplicate(), "q_index": q_index, "question": question.duplicate(true), "occurrence": occurrence.duplicate(true), "ledger": ledger.duplicate(true)}

func restore_state(state: Dictionary) -> bool:
	if not _whole_number(state.get("version")) or int(state.version) != STATE_VERSION or state.get("operation", "") not in OPERATIONS + ["mixed"]:
		last_error = "Unsupported learning checkpoint."
		return false
	for field in ["max_number", "seed", "random_state", "q_index"]:
		if not _whole_number(state.get(field)):
			last_error = "Checkpoint counters are damaged."
			return false
	if int(state.max_number) < 0 or int(state.max_number) > 100 or int(state.q_index) < 0 or not state.get("options", {}) is Dictionary:
		last_error = "Checkpoint settings are damaged."
		return false
	if not state.get("bucket") is Dictionary or not state.get("ledger") is Array or not state.get("question") is Dictionary or not state.get("occurrence") is Dictionary:
		last_error = "Invalid learning checkpoint."
		return false
	var test_pool := build_fact_pool(state.operation, int(state.get("max_number", -1)), state.get("options", {}))
	var valid_keys: Dictionary = {}
	for fact in test_pool: valid_keys[fact.key] = fact
	var saved_question: Dictionary = state.question
	if not saved_question.is_empty():
		if not valid_keys.has(saved_question.get("key", "")) or not _question_matches(saved_question, valid_keys[saved_question.key]):
			last_error = "Checkpoint arithmetic does not match the selected facts."
			return false
	for field in ["sweep", "recent", "requeue"]:
		if not state.get(field) is Array:
			last_error = "Checkpoint scheduling data is damaged."
			return false
	for key in state.sweep + state.recent:
		if not key is String or not valid_keys.has(key):
			last_error = "Checkpoint contains an unknown scheduled fact."
			return false
	for pending in state.requeue:
		if not pending is Dictionary or not valid_keys.has(pending.get("key", "")) or not _whole_number(pending.get("dueAt")):
			last_error = "Checkpoint retry queue is damaged."
			return false
	for field in ["session_miss", "session_seen"]:
		if not state.get(field) is Dictionary:
			last_error = "Checkpoint session data is damaged."
			return false
		for key in state[field]:
			if not valid_keys.has(key) or not _whole_number(state[field][key]) or int(state[field][key]) < 0:
				last_error = "Checkpoint session counts are damaged."
				return false
	var occurrence_ids: Dictionary = {}
	for entry in state.ledger:
		if not _valid_occurrence(entry, valid_keys) or occurrence_ids.has(entry.get("id")) or int(entry.id) > int(state.q_index):
			last_error = "Checkpoint learning evidence is inconsistent."
			return false
		occurrence_ids[entry.id] = true
	if not state.occurrence.is_empty() and not _valid_occurrence(state.occurrence, valid_keys):
		last_error = "Checkpoint question evidence is inconsistent."
		return false
	if not state.occurrence.is_empty():
		if int(state.occurrence.id) != int(state.q_index) or state.occurrence.key != saved_question.get("key", ""):
			last_error = "Checkpoint question identity is inconsistent."
			return false
		var matching: Dictionary = {}
		for entry in state.ledger:
			if int(entry.id) == int(state.occurrence.id): matching = entry
		if (state.occurrence.observed and matching != state.occurrence) or (not state.occurrence.observed and not matching.is_empty()):
			last_error = "Checkpoint current answer and ledger disagree."
			return false
	elif not saved_question.is_empty():
		last_error = "Checkpoint is missing current question evidence."
		return false
	configure(state.operation, int(state.max_number), int(state.get("seed", 73)), state.bucket, state.get("options", {}))
	random_state = int(state.get("random_state", 0)) & 0xffffffff
	sweep = state.sweep.duplicate()
	recent = state.recent.duplicate()
	requeue = state.requeue.duplicate(true)
	session_miss = state.session_miss.duplicate()
	session_seen = state.session_seen.duplicate()
	q_index = int(state.get("q_index", 0))
	question = valid_keys[state.question.key].duplicate(true) if not state.question.is_empty() else {}
	occurrence = state.occurrence.duplicate(true)
	ledger = state.ledger.duplicate(true)
	return true

static func _question_matches(saved: Dictionary, expected: Dictionary) -> bool:
	for field in ["a", "b", "answer"]:
		if not (saved.get(field) is int or saved.get(field) is float): return false
		if not is_finite(float(saved[field])) or float(saved[field]) != float(expected[field]): return false
	for field in ["key", "symbol", "opType"]:
		if str(saved.get(field, "")) != str(expected[field]): return false
	return true

static func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _valid_occurrence(value: Variant, valid_keys: Dictionary) -> bool:
	if not value is Dictionary: return false
	for field in ["id", "attempts", "retries", "timeouts", "first_latency"]:
		if not (value.get(field) is float or value.get(field) is int): return false
		if not is_finite(float(value[field])) or float(value[field]) < 0.0: return false
	for field in ["id", "attempts", "retries", "timeouts"]:
		if not _whole_number(value[field]): return false
	for field in ["observed", "first_correct", "correct", "assisted", "resolved"]:
		if not value.get(field) is bool: return false
	if not valid_keys.has(value.get("key", "")) or not value.get("latencies") is Array or not value.get("timeout_latencies") is Array: return false
	if int(value.retries) > int(value.attempts) or int(value.timeouts) > 1: return false
	if (int(value.retries) > 0 or int(value.timeouts) > 0) and not value.assisted: return false
	if value.correct and (not value.resolved or int(value.attempts) < 1): return false
	if value.resolved and not value.correct: return false
	if value.first_correct and (not value.correct or value.assisted or int(value.attempts) != 1 or int(value.timeouts) != 0): return false
	if value.observed != (int(value.attempts) + int(value.timeouts) > 0): return false
	if value.latencies.size() != int(value.attempts) or value.timeout_latencies.size() != int(value.timeouts): return false
	for latency in value.latencies + value.timeout_latencies:
		if not (latency is float or latency is int) or not is_finite(float(latency)) or float(latency) < 0.0: return false
	if int(value.attempts) > 0 and float(value.first_latency) != float(value.latencies[0]): return false
	if int(value.attempts) == 0 and float(value.first_latency) != 0.0: return false
	return true

static func sanitize_evidence(evidence: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in evidence:
		var value: Variant = evidence[key]
		if not value is Dictionary: continue
		var stat: Dictionary = value.duplicate(true)
		var valid := true
		for field in ["att", "cor", "streak", "interval", "lastTs", "stage", "run2", "assisted", "timeout_count"]:
			if not (stat.get(field, 0) is int or stat.get(field, 0) is float) or not is_finite(float(stat.get(field, 0))) or float(stat.get(field, 0)) < 0.0: valid = false
		if not valid or int(stat.get("cor", 0)) > int(stat.get("att", 0)): continue
		if not _whole_number(stat.get("lastIdx", -999)): continue
		if not stat.get("lats", []) is Array: stat.lats = []
		var clean: Array = []
		for latency in stat.get("lats", []):
			if (latency is int or latency is float) and is_finite(float(latency)) and float(latency) >= 0.0: clean.append(float(latency))
		stat.lats = clean.slice(maxi(0, clean.size() - 5))
		if not stat.has("stage"):
			# An aggregate or legacy import cannot establish consecutive fast answers.
			stat.streak = 0
			stat.run2 = 0
			stat.lats = []
			stat.stage = 1
		stat.att = int(stat.get("att", 0))
		stat.cor = int(stat.get("cor", 0))
		stat.streak = int(stat.get("streak", 0))
		stat.interval = int(stat.get("interval", 0))
		stat.lastIdx = int(stat.get("lastIdx", -999))
		stat.lastTs = int(stat.get("lastTs", 0))
		result[str(key)] = stat
	return result
