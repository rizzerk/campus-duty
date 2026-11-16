class_name FreedomWall
extends RefCounted
## The Freedom Wall after each day: 3 to 6 anonymous student posts about Window 3, picked from
## data/freedom_wall.json by what actually happened today. Pure and seeded, so the same day,
## results and seed always give the same posts, and the tests can check them headless.
##
## Each post has a "when" saying when it may show up (see conditions()): an outcome of the day,
## possibly narrowed to one kind ("turned_away:failed_prereq", "closed_office:dean",
## "favor:merienda"), a day number like "day_6", a regular's visit like "jericho_112_good", or
## "any" for filler. An optional "days" list limits a post to those days, for posts about one
## particular visit or a check that only exists from a certain day.

const MIN_POSTS := 3
const MAX_POSTS := 6
## At most this many regulars post on one day, so they don't crowd out everyone else.
const MAX_REGULARS := 2


## What today's shift makes true, most telling first. Each entry is a list of "when" keys for one
## thing that happened, specific ones first: a favor done with merienda is
## ["favor:merienda", "favor"], so a post written for that exact case and the general ones are
## all candidates for that one slot. summary is the day's summary (after the spot check), history
## the shift's calls.
static func conditions(summary: Dictionary, history: Array, day: int) -> Array:
	var found: Array = []
	var lost: bool = summary.get("reason", "") == "patience"
	if lost:
		found.append(["line_lost"])
	# Regulars who came today, in events.json order: bad if any call on them went wrong.
	var calls := Evaluation.regular_calls(history)
	var regulars := 0
	for regular: Dictionary in GameData.json("events")["regulars"]:
		var id := String(regular["id"])
		if not calls.has(id) or regulars >= MAX_REGULARS:
			continue
		var visit: Dictionary = calls[id]
		var botched := int(visit.get("wrong", 0)) + int(visit.get("bent", 0)) > 0
		found.append(["%s_%s" % [id, "bad" if botched else "good"]])
		regulars += 1
	# The day's own post comes early, so a busy day doesn't crowd it out.
	found.append(["day_%d" % day])
	var stars := int(summary.get("stars", 0))
	if not lost and stars >= 3:
		found.append(["great_day"])
	elif not lost and stars <= 1:
		found.append(["rough_day"])
	if int(summary.get("walked_out", 0)) > 0:
		found.append(["walked_out"])
	if int(summary.get("bends", 0)) > 0:
		found.append(_specific("favor", _values(history, func(entry: Dictionary) -> bool:
				return entry.get("bent", false), "favor")))
	# A trip to a closed office, and a trip to the wrong (open) office, are different stories.
	var routed_wrong := func(entry: Dictionary) -> bool:
		return String(entry.get("action", "")).begins_with("route:") and not entry.get("correct", false) and not entry.get("bent", false)
	var closed := _values(history, func(entry: Dictionary) -> bool:
			return routed_wrong.call(entry) and not entry.get("office_open", true), "action").map(func(action: String) -> String:
			return action.trim_prefix("route:"))
	if not closed.is_empty():
		found.append(closed.map(func(office: String) -> String: return "closed_office:" + office))
	if _any(history, func(entry: Dictionary) -> bool: return routed_wrong.call(entry) and entry.get("office_open", true)):
		found.append(["wrong_office"])
	if int(summary.get("false_alarms", 0)) > 0:
		found.append(["false_alarms"])
	var turned_away := func(entry: Dictionary) -> bool:
		return entry.get("correct", false) and entry.get("action", "") == "reject"
	if _any(history, turned_away):
		found.append(_specific("turned_away", _values(history, turned_away, "reason_id")))
	if _any(history, func(entry: Dictionary) -> bool:
			return entry.get("correct", false) and entry.get("action", "") == "fix" and entry.get("problem", "") == "closed_section"):
		found.append(["found_section"])
	return found


## Today's posts: [{ id, when, author, ceb, en, likes }], 3 to 6 of them. One post per thing that
## happened (see conditions), drawn from every post whose "when" is one of its keys and whose
## "days" (if it has any) include today, then "any" posts to make up the minimum. likes is fixed
## from the post's [min, max] range by the seed.
static func posts(summary: Dictionary, history: Array, day: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var by_when := {}
	for post: Dictionary in GameData.json("freedom_wall")["posts"]:
		var days: Array = post.get("days", [])
		if not days.is_empty() and not days.has(day) and not days.has(float(day)):
			continue
		var when := String(post.get("when", ""))
		if not by_when.has(when):
			by_when[when] = []
		by_when[when].append(post)
	var picked: Array = []
	for keys: Array in conditions(summary, history, day):
		if picked.size() >= MAX_POSTS:
			break
		var options: Array = []
		for key: String in keys:
			options.append_array(by_when.get(key, []))
		if not options.is_empty():
			picked.append(options[rng.randi_range(0, options.size() - 1)])
	# Filler, never the same one twice.
	var filler: Array = by_when.get("any", []).duplicate()
	while picked.size() < MIN_POSTS and not filler.is_empty():
		picked.append(filler.pop_at(rng.randi_range(0, filler.size() - 1)))
	var shown: Array = []
	for post: Dictionary in picked:
		var range_: Array = post.get("likes", [0, 0])
		var low := int(range_[0]) if range_.size() > 0 else 0
		var high := int(range_[1]) if range_.size() > 1 else low
		shown.append({
			"id": String(post.get("id", "")),
			"when": String(post.get("when", "")),
			"author": String(post.get("author", "anon")),
			"ceb": String(post.get("ceb", "")),
			"en": String(post.get("en", "")),
			"likes": rng.randi_range(mini(low, high), maxi(low, high)),
		})
	return shown


## The seed for a day's wall, from the season's seed, so a replayed day shows the same posts.
static func seed_for(base_seed: int, day: int) -> int:
	return base_seed * 7919 + day * 104729


## "base:kind" for each distinct kind, then base itself: the keys for one slot.
static func _specific(base: String, kinds: Array) -> Array:
	var keys: Array = []
	for kind: String in kinds:
		if kind != "" and not keys.has(base + ":" + kind):
			keys.append(base + ":" + kind)
	keys.append(base)
	return keys


## The distinct non-empty values of key in the history entries that pass test, in order.
static func _values(history: Array, test: Callable, key: String) -> Array:
	var values: Array = []
	for entry: Dictionary in history:
		var value := String(entry.get(key, ""))
		if value != "" and test.call(entry) and not values.has(value):
			values.append(value)
	return values


static func _any(history: Array, test: Callable) -> bool:
	for entry: Dictionary in history:
		if test.call(entry):
			return true
	return false
