extends SceneTree
## Run: godot --headless --path . --script res://tests/test_freedom_wall.gd
## The Freedom Wall must be repeatable, 3 to 6 posts long, and only say what really happened.

var _failures: int = 0


func _init() -> void:
	_test_data_is_well_formed()
	_test_same_day_same_posts()
	_test_post_count()
	_test_posts_match_the_day()
	_test_regulars_post_about_their_visit()
	_test_likes_stay_in_range()
	_test_posts_fit_the_exact_moment()
	print("freedom_wall: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _summary(stars: int, extra: Dictionary = {}) -> Dictionary:
	var summary := { "reason": "clear", "stars": stars, "walked_out": 0, "bends": 0, "false_alarms": 0 }
	summary.merge(extra, true)
	return summary


func _whens(posts: Array) -> Array:
	return posts.map(func(post: Dictionary) -> String: return post["when"])


func _test_data_is_well_formed() -> void:
	var data: Dictionary = GameData.json("freedom_wall")
	var regulars: Array = GameData.json("events")["regulars"].map(func(r: Dictionary) -> String: return r["id"])
	var days: Dictionary = GameData.json("days")
	var first := int(days["first_day"])
	var last := int(days["last_day"])
	var known := ["any", "line_lost", "great_day", "rough_day", "walked_out", "favor", "wrong_office", "false_alarms", "turned_away", "found_section"]
	# The kinds a "base:kind" when may name, from the data files the game uses for them.
	var kinds := {
		"favor": GameData.json("favors").keys(),
		"turned_away": GameData.json("reject_reasons").keys(),
		"closed_office": GameData.json("offices").keys(),
	}
	var ids := {}
	for post: Dictionary in data["posts"]:
		var when := String(post.get("when", ""))
		var ok_when := known.has(when) or regulars.any(func(id: String) -> bool: return when == id + "_good" or when == id + "_bad")
		if when.begins_with("day_"):
			var number := when.trim_prefix("day_")
			ok_when = number.is_valid_int() and int(number) >= first and int(number) <= last
		elif when.contains(":"):
			ok_when = kinds.has(when.get_slice(":", 0)) and kinds[when.get_slice(":", 0)].has(when.get_slice(":", 1))
		_check(ok_when, "%s has a when the picker understands (%s)" % [post.get("id", "?"), when])
		for number: Variant in post.get("days", []):
			_check(int(number) >= first and int(number) <= last, "%s only lists real days" % post.get("id", "?"))
		_check(String(post.get("ceb", "")) != "" and String(post.get("en", "")) != "", "%s has Bisaya and English" % post.get("id", "?"))
		_check(post.get("author", "") == "anon" or regulars.has(post.get("author", "")), "%s is by anon or a regular" % post.get("id", "?"))
		var likes: Array = post.get("likes", [])
		_check(likes.size() == 2 and int(likes[0]) <= int(likes[1]), "%s has a [min, max] like range" % post.get("id", "?"))
		_check(not ids.has(post.get("id", "")), "%s is unique" % post.get("id", "?"))
		ids[post.get("id", "")] = true
	_check(data["posts"].filter(func(p: Dictionary) -> bool: return p["when"] == "any").size() >= FreedomWall.MIN_POSTS, "enough filler for the quietest day")
	for key: String in ["title", "subtitle", "anonymous", "reactions", "next_day", "evaluation"]:
		_check(String(data["screen"].get(key, "")) != "", "screen text has %s" % key)


func _test_same_day_same_posts() -> void:
	var summary := _summary(2, { "walked_out": 1 })
	var first := FreedomWall.posts(summary, [], 4, 1234)
	_check(first == FreedomWall.posts(summary, [], 4, 1234), "same day and seed give the same posts")
	var differs := false
	for seed_value in range(1, 30):
		if FreedomWall.posts(summary, [], 4, seed_value) != first:
			differs = true
			break
	_check(differs, "another seed can give other posts")
	_check(FreedomWall.seed_for(5, 3) == FreedomWall.seed_for(5, 3) and FreedomWall.seed_for(5, 3) != FreedomWall.seed_for(5, 4), "each day of a season has its own seed")


func _test_post_count() -> void:
	var quiet := FreedomWall.posts(_summary(2), [], 4, 7)
	_check(quiet.size() == FreedomWall.MIN_POSTS, "a quiet day still has %d posts (got %d)" % [FreedomWall.MIN_POSTS, quiet.size()])
	var busy_history: Array = [
		{ "action": "route:cashier", "correct": false, "bent": false, "regular_id": "jericho_112" },
		{ "action": "reject", "correct": true, "regular_id": "mae_118" },
		{ "action": "fix", "correct": true, "problem": "closed_section", "regular_id": "carlo_104" },
	]
	var busy := FreedomWall.posts(_summary(3, { "walked_out": 2, "bends": 1, "false_alarms": 3 }), busy_history, 6, 7)
	_check(busy.size() == FreedomWall.MAX_POSTS, "a busy day stops at %d posts (got %d)" % [FreedomWall.MAX_POSTS, busy.size()])
	var ids := busy.map(func(post: Dictionary) -> String: return post["id"])
	for id: String in ids:
		_check(ids.count(id) == 1, "no post shows twice (%s)" % id)


func _test_posts_match_the_day() -> void:
	for seed_value in range(1, 40):
		var good := _whens(FreedomWall.posts(_summary(3), [], 4, seed_value))
		_check(not good.has("rough_day") and not good.has("line_lost") and not good.has("favor"), "a clean 3-star day says nothing bad (seed %d: %s)" % [seed_value, good])
		var bad := _whens(FreedomWall.posts(_summary(1), [], 4, seed_value))
		_check(not bad.has("great_day"), "a 1-star day isn't called great (seed %d)" % seed_value)
	var lost := FreedomWall.posts(_summary(0, { "reason": "patience" }), [], 4, 3)
	_check(lost[0]["when"] == "line_lost", "when the line gave up, that's the first post")
	_check(not _whens(lost).has("rough_day") and not _whens(lost).has("great_day"), "a lost shift isn't also a rough or great day")
	_check(_whens(FreedomWall.posts(_summary(2, { "bends": 1 }), [], 4, 3)).has("favor"), "a favor done gets a post")
	_check(_whens(FreedomWall.posts(_summary(2, { "walked_out": 1 }), [], 4, 3)).has("walked_out"), "a walkout gets a post")
	var routed: Array = [{ "action": "route:dean", "correct": false, "bent": false }]
	_check(_whens(FreedomWall.posts(_summary(2), routed, 4, 3)).has("wrong_office"), "a wrong route gets a post")
	var right_route: Array = [{ "action": "route:dean", "correct": true }]
	_check(not _whens(FreedomWall.posts(_summary(2), right_route, 4, 3)).has("wrong_office"), "a right route doesn't")
	_check(_whens(FreedomWall.posts(_summary(2), [], 6, 3)).has("day_6"), "open market day gets its own post")
	_check(not _whens(FreedomWall.posts(_summary(2), [], 5, 3)).has("day_6"), "other days don't")


func _test_regulars_post_about_their_visit() -> void:
	var helped: Array = [{ "action": "fix", "correct": true, "regular_id": "jericho_112" }]
	var posts := FreedomWall.posts(_summary(2), helped, 3, 9)
	_check(_whens(posts).has("jericho_112_good") and posts.any(func(post: Dictionary) -> bool: return post["author"] == "jericho_112"), "a regular helped right posts a happy post as themselves")
	var bounced: Array = [{ "action": "approve", "correct": false, "regular_id": "jericho_112" }, { "action": "fix", "correct": true, "regular_id": "jericho_112" }]
	_check(_whens(FreedomWall.posts(_summary(2), bounced, 3, 9)).has("jericho_112_bad"), "one wrong call on their visit makes it a bad post")
	_check(not _whens(FreedomWall.posts(_summary(2), [], 3, 9)).any(func(when: String) -> bool: return when.begins_with("jericho")), "a regular who didn't come today doesn't post")
	var all_three: Array = [
		{ "correct": true, "regular_id": "jericho_112" }, { "correct": true, "regular_id": "carlo_104" }, { "correct": true, "regular_id": "mae_118" },
	]
	var regular_posts := _whens(FreedomWall.posts(_summary(2), all_three, 3, 9)).filter(func(when: String) -> bool: return when.ends_with("_good"))
	_check(regular_posts.size() == FreedomWall.MAX_REGULARS, "at most %d regulars post in one day" % FreedomWall.MAX_REGULARS)


func _test_likes_stay_in_range() -> void:
	var ranges := {}
	for post: Dictionary in GameData.json("freedom_wall")["posts"]:
		ranges[post["id"]] = post["likes"]
	for seed_value in range(1, 60):
		for post: Dictionary in FreedomWall.posts(_summary(seed_value % 4, { "walked_out": seed_value % 2 }), [], 2 + seed_value % 9, seed_value):
			var span: Array = ranges[post["id"]]
			_check(post["likes"] >= int(span[0]) and post["likes"] <= int(span[1]), "%s likes %d within %s" % [post["id"], post["likes"], span])


func _ids(posts: Array) -> Array:
	return posts.map(func(post: Dictionary) -> String: return post["id"])


## Posts written about one particular moment only show for that moment.
func _test_posts_fit_the_exact_moment() -> void:
	var merienda: Array = [{ "action": "favor", "correct": false, "bent": true, "favor": "merienda" }]
	var closed_dean: Array = [{ "action": "route:dean", "correct": false, "bent": false, "office_open": false }]
	var open_wrong: Array = [{ "action": "route:dean", "correct": false, "bent": false, "office_open": true }]
	var prereq: Array = [{ "action": "reject", "correct": true, "reason_id": "failed_prereq" }]
	var identity: Array = [{ "action": "reject", "correct": true, "reason_id": "identity_mismatch" }]
	var jericho: Array = [{ "correct": true, "regular_id": "jericho_112" }]
	var mae: Array = [{ "correct": true, "regular_id": "mae_118" }]
	for seed_value in range(1, 40):
		var favor_ids := _ids(FreedomWall.posts(_summary(2, { "bends": 1 }), merienda, 5, seed_value))
		_check(not favor_ids.has("favor_02"), "a merienda favor never shows the Dean's nephew post (seed %d)" % seed_value)
		_check(favor_ids.has("favor_01") or favor_ids.has("favor_03"), "a merienda favor shows a favor post (seed %d)" % seed_value)
		var closed_ids := _ids(FreedomWall.posts(_summary(2), closed_dean, 8, seed_value))
		_check(closed_ids.has("wrong_office_03") and not closed_ids.has("wrong_office_01"), "a closed Dean's office gets the Dean post, not Consultation's (seed %d)" % seed_value)
		_check(not _ids(FreedomWall.posts(_summary(2), open_wrong, 8, seed_value)).has("wrong_office_03"), "an open wrong office never says it was closed (seed %d)" % seed_value)
		var prereq_ids := _ids(FreedomWall.posts(_summary(2), prereq, 6, seed_value))
		_check(prereq_ids.has("turned_away_02") or prereq_ids.has("turned_away_04"), "a 5.0 turned away gets the 5.0 post or the general one (seed %d)" % seed_value)
		_check(not prereq_ids.has("turned_away_03") and not prereq_ids.has("turned_away_01"), "and not a signature or clearance post (seed %d)" % seed_value)
		var identity_ids := _ids(FreedomWall.posts(_summary(2), identity, 5, seed_value)).filter(func(id: String) -> bool: return id.begins_with("turned_away"))
		_check(identity_ids == ["turned_away_04"], "a turn-away with no post of its own gets the general one, not another reason's (seed %d)" % seed_value)
		var day3 := _ids(FreedomWall.posts(_summary(2), jericho, 3, seed_value))
		_check(day3.has("jericho_112_good_01") and not day3.has("jericho_112_good_02"), "Jericho's day 3 post is about camping out (seed %d)" % seed_value)
		var day8 := _ids(FreedomWall.posts(_summary(2), jericho, 8, seed_value))
		_check(day8.has("jericho_112_good_02") and not day8.has("jericho_112_good_01"), "and on day 8 it isn't (seed %d)" % seed_value)
		_check(not _ids(FreedomWall.posts(_summary(2), mae, 2, seed_value)).any(func(id: String) -> bool: return id.begins_with("mae")),
				"a regular never posts a visit-only post on a day it doesn't fit (seed %d)" % seed_value)
	# Every visit each regular makes, good or bad, gets a post that names a day it fits.
	var posts_by_id := {}
	for post: Dictionary in GameData.json("freedom_wall")["posts"]:
		posts_by_id[post["id"]] = post
	for regular: Dictionary in GameData.json("events")["regulars"]:
		for key: String in regular["appearances"]:
			var visit_day := int(key)
			for mood: Array in [[true, "good"], [false, "bad"]]:
				var history: Array = [{ "correct": mood[0], "action": "approve", "regular_id": regular["id"] }]
				var theirs := FreedomWall.posts(_summary(2), history, visit_day, 11).filter(func(post: Dictionary) -> bool: return post["author"] == regular["id"])
				_check(theirs.size() == 1, "%s posts once after a %s visit on day %d" % [regular["id"], mood[1], visit_day])
				if theirs.size() == 1:
					var days: Array = posts_by_id[theirs[0]["id"]].get("days", [])
					_check(days.is_empty() or days.has(visit_day) or days.has(float(visit_day)), "%s's day %d post fits that day" % [regular["id"], visit_day])
	var busy_day9 := FreedomWall.posts(_summary(3, { "walked_out": 1, "bends": 1, "false_alarms": 2 }), merienda + open_wrong + prereq + jericho, 9, 5)
	_check(_whens(busy_day9).has("day_9"), "the day's own post survives a busy day")
