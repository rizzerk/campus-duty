class_name LineDirector
extends RefCounted
## Paces a shift. The generator makes the day's students; the director decides who comes when:
## an easy first student, then the day's new problem on its own so it can be learned, pressure
## that builds toward the busy part of the morning and eases after, and never a long run of the
## same problem. It only reorders the students it is given, so the day's mix stays the same, except
## when the new problem is missing: then one student who has it alone is swapped in. (Regulars can
## also bring in a generated student for their story beat: see ShiftEvents._bring_problem_to.)
##
## Settings: data/balance.json "director", overridable per day with a "director" key in days.json.

## Seeds for the extra students searched when the new problem is missing. Each new problem gets
## its own range, so two searches never make the same student. Far from the shift's own seeds
## (base * 100000 + day * 1000 + i, with i under 100): 500 + k * 30 stays under 1000 while a day
## introduces at most 10 new problems (the season has at most 2 per day). Ranges from
## REGULAR_RANGE up are for regulars whose problem is missing from the line (one per regular).
const SEARCH_OFFSET := 500
const SEARCH_LIMIT := 30
const REGULAR_RANGE := 10


## The students in the order they should arrive. arrivals_rush[i] is true when slot i is part of a
## rush wave. Pure and seeded: the same inputs give the same order.
static func order(students: Array, day: int, seed_value: int, arrivals_rush: Array = []) -> Array:
	var settings := settings_for(day)
	if students.size() < 3 or not bool(settings.get("enabled", true)):
		return students.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 131 + day * 17 + 5
	var pool: Array = students.duplicate()
	var reserved: Array = []
	var problems := new_problems(day)
	# 1. One student per new problem, with that problem alone (plus anything it requires).
	for k in problems.size():
		var problem: String = problems[k]
		var index := _find_teacher(pool, problem)
		if index == -1:
			var found := search_student(problem, day, seed_value, k)
			if found.is_empty():
				continue
			index = _most_replaceable(pool, problems)
			pool[index] = found
		reserved.append(pool.pop_at(index))
	# 2. An easy warm-up first, so the first call is a confident one. On a crowded day (one known
	# problem outnumbering everyone else) the warm-up is an easy case of that problem instead, so the
	# few other students are kept to break up the runs.
	var max_streak := int(settings.get("max_streak", 2))
	var crowded := _crowded_beyond(pool, max_streak)
	var warmup_index := -1
	if crowded != "" and not problems.has(crowded):
		warmup_index = _easiest_of(pool, crowded)
	if warmup_index == -1:
		warmup_index = _easiest(pool, problems)
	var opening: Array = [pool.pop_at(warmup_index)] if warmup_index != -1 else []
	opening.append_array(reserved)
	# 3. Everyone else, one slot at a time: the student closest to the slot's target difficulty,
	# never extending a run of the same problem past the cap while anyone else could go there.
	# When the mix makes runs unavoidable, the cap rises just enough to spread them evenly.
	var rest_slots := students.size() - opening.size()
	var targets := _intensity_curve(rest_slots, opening.size(), students.size(), arrivals_rush, settings, rng)
	var desired := _desired_difficulty(pool, targets)
	_shuffle(rng, pool)
	var line := opening.duplicate()
	var cap := _effective_cap(pool, max_streak)
	for i in rest_slots:
		var choice := _pick(pool, line, desired[i], cap)
		line.append(pool.pop_at(choice))
	return line


## Problems that appear for the first time on this day.
static func new_problems(day: int) -> Array:
	var days: Dictionary = GameData.json("days")
	var found: Array = []
	for id: String in GameData.day(day).get("problems", {}):
		var first := -1
		for number in range(int(days["first_day"]), int(days["last_day"]) + 1):
			if GameData.day(number).get("problems", {}).has(id):
				first = number
				break
		if first == day:
			found.append(id)
	found.sort_custom(func(a: String, b: String) -> bool: return float(GameData.day(day)["problems"][a]) > float(GameData.day(day)["problems"][b]))
	return found


## How hard a student is to handle: problems, plus the things that slow a call down.
static func difficulty(student: Dictionary) -> float:
	var score := 0.0
	for problem: String in student.get("problems", []):
		score += 1.0
		if int(GameData.problem(problem).get("tier", 1)) == 1:
			score += 0.25
	if String(student.get("trait", "")) != "":
		score += 0.5
	if String(student.get("favor", "")) != "":
		score += 0.5
	if student.get("no_id", false):
		score += 0.3
	score += 0.2 * student.get("harmless", []).size()
	return score


## The problem that decides a student's call, or "" for a student with nothing wrong.
static func problem_class(student: Dictionary) -> String:
	return RulesCheck.top_problem(student) if not student.get("problems", []).is_empty() else ""


static func settings_for(day: int) -> Dictionary:
	var settings: Dictionary = GameData.json("balance").get("director", {}).duplicate()
	settings.merge(GameData.day(day).get("director", {}), true)
	return settings


## A student whose only problem is this one (and what it requires), or -1. One with nothing
## else going on (no trait, favor or harmless mismatch) is preferred, so the lesson is clear.
static func _find_teacher(pool: Array, problem: String) -> int:
	var fallback := -1
	for i in pool.size():
		if _teaches(pool[i], problem):
			if _plain(pool[i]):
				return i
			if fallback == -1:
				fallback = i
	return fallback


static func _teaches(student: Dictionary, problem: String) -> bool:
	var wanted: Array = [problem] + GameData.problem(problem).get("requires", [])
	var has: Array = student.get("problems", [])
	if has.size() != wanted.size():
		return false
	for id: String in wanted:
		if not has.has(id):
			return false
	return not student.get("no_id", false)


## Nothing else going on: no trait, favor or harmless mismatch.
static func _plain(student: Dictionary) -> bool:
	return String(student.get("trait", "")) == "" and String(student.get("favor", "")) == "" and student.get("harmless", []).is_empty()


## A student generated with exactly this problem (and what it requires), preferring a plain one.
## Usually the first seed works; a few problems need a fitting course request, so a handful of
## seeds are tried. range_index picks this problem's own block of seeds.
static func search_student(problem: String, day: int, seed_value: int, range_index: int = 0) -> Dictionary:
	var forced: Array = [problem] + GameData.problem(problem).get("requires", [])
	var first := seed_value * 100000 + day * 1000 + SEARCH_OFFSET + range_index * SEARCH_LIMIT
	var fallback := {}
	for j in SEARCH_LIMIT:
		var student := StudentGen.make(first + j, day, forced)
		if _teaches(student, problem):
			if _plain(student):
				return student
			if fallback.is_empty():
				fallback = student
	return fallback


## The student to give up for a missing teacher: a clean one if possible, else one from the most
## common problem class. Never one who already carries a new problem.
static func _most_replaceable(pool: Array, protected: Array) -> int:
	var counts := {}
	for student: Dictionary in pool:
		var key := problem_class(student)
		counts[key] = int(counts.get(key, 0)) + 1
	var best := -1
	var best_count := -1
	for i in pool.size():
		var key := problem_class(pool[i])
		if protected.has(key):
			continue
		var count: int = 1000 if key == "" else int(counts[key])
		if count > best_count:
			best = i
			best_count = count
	return best if best != -1 else pool.size() - 1


## The easiest student without a new problem, or -1.
static func _easiest(pool: Array, protected: Array) -> int:
	var best := -1
	for i in pool.size():
		if protected.has(problem_class(pool[i])):
			continue
		if best == -1 or difficulty(pool[i]) < difficulty(pool[best]):
			best = i
	return best


## The easiest student whose deciding problem is this one, or -1.
static func _easiest_of(pool: Array, key: String) -> int:
	var best := -1
	for i in pool.size():
		if problem_class(pool[i]) != key:
			continue
		if best == -1 or difficulty(pool[i]) < difficulty(pool[best]):
			best = i
	return best


## Target intensity for each remaining slot: rising to a peak, easing after, higher in a rush,
## with a little seeded noise so no two days feel mechanical.
static func _intensity_curve(count: int, offset: int, total: int, arrivals_rush: Array, settings: Dictionary, rng: RandomNumberGenerator) -> Array:
	var peak := clampf(float(settings.get("peak_at", 0.7)), 0.1, 0.95)
	var jitter := float(settings.get("jitter", 0.35))
	var rush_boost := float(settings.get("rush_boost", 0.5))
	var targets: Array = []
	for i in count:
		var slot := offset + i
		var t := float(slot) / maxf(1.0, total - 1)
		var level := t / peak if t <= peak else 1.0 - 0.5 * (t - peak) / (1.0 - peak)
		if slot < arrivals_rush.size() and arrivals_rush[slot]:
			level += rush_boost
		targets.append(level + rng.randf_range(-jitter, jitter))
	return targets


## Turns the curve into a wanted difficulty per slot: the hardest slot wants the hardest student.
static func _desired_difficulty(pool: Array, targets: Array) -> Array:
	var levels: Array = pool.map(func(s: Dictionary) -> float: return difficulty(s))
	levels.sort()
	var slot_order: Array = range(targets.size())
	slot_order.sort_custom(func(a: int, b: int) -> bool: return targets[a] < targets[b])
	var desired: Array = []
	desired.resize(targets.size())
	for rank in slot_order.size():
		desired[slot_order[rank]] = levels[mini(rank, levels.size() - 1)]
	return desired


## Index in pool of the student for the next slot.
static func _pick(pool: Array, line: Array, wanted: float, max_streak: int) -> int:
	var allowed: Array = []
	for i in pool.size():
		if max_streak < 1 or _run_if_added(line, problem_class(pool[i])) <= max_streak:
			allowed.append(i)
	if allowed.is_empty():
		allowed = range(pool.size())
	# When one problem would otherwise run out of separators, place it whenever it's allowed.
	var crowded := _crowded_class(pool, max_streak)
	if crowded != "":
		var placeable := allowed.filter(func(i: int) -> bool: return problem_class(pool[i]) == crowded)
		if not placeable.is_empty():
			allowed = placeable
	var best: int = allowed[0]
	for i: int in allowed:
		if absf(difficulty(pool[i]) - wanted) < absf(difficulty(pool[best]) - wanted):
			best = i
	return best


## How long the run at the end of the line would be if a student of this class came next.
static func _run_if_added(line: Array, key: String) -> int:
	if key == "":
		return 0
	var run := 1
	var k := line.size() - 1
	while k >= 0 and problem_class(line[k]) == key:
		run += 1
		k -= 1
	return run


## The most common problem when there are too few other students to keep its runs at the cap.
static func _crowded_beyond(pool: Array, max_streak: int) -> String:
	if max_streak < 1:
		return ""
	var counts := _class_counts(pool)
	for key: String in counts:
		if int(counts[key]) > max_streak * (pool.size() - int(counts[key]) + 1):
			return key
	return ""


## The run cap to aim for: the configured one, or the shortest longest-run the mix allows.
static func _effective_cap(pool: Array, max_streak: int) -> int:
	if max_streak < 1:
		return max_streak
	var cap := max_streak
	var counts := _class_counts(pool)
	for key: String in counts:
		var others: int = pool.size() - int(counts[key])
		cap = maxi(cap, ceili(float(counts[key]) / float(others + 1)))
	return cap


static func _class_counts(pool: Array) -> Dictionary:
	var counts := {}
	for student: Dictionary in pool:
		var key := problem_class(student)
		if key != "":
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


## A problem with so many students left that every other student is needed to separate them.
static func _crowded_class(pool: Array, max_streak: int) -> String:
	if max_streak < 1:
		return ""
	var counts := _class_counts(pool)
	for key: String in counts:
		var others: int = pool.size() - int(counts[key])
		if int(counts[key]) >= max_streak * others:
			return key
	return ""


static func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
