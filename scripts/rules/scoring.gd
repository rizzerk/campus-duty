class_name Scoring
extends RefCounted
## Stars for a shift. Pure, so the day report, the pause menu and the tests all agree.


## 3 stars needs 90% weighted accuracy (Evaluation.shift: hard calls count extra, streaks add a
## little), 90% of the line served and no walkouts. A failed shift gets none.
## Each favor Ma'am Lorna caught in the spot check costs a star.
static func stars(summary: Dictionary) -> int:
	if summary["reason"] == "patience":
		return 0
	var score := minf(summary.get("weighted_accuracy", summary["accuracy"]), summary["served_ratio"])
	var earned := 0
	for threshold: float in GameData.json("balance")["star_thresholds"]:
		if score >= threshold:
			earned += 1
	if summary["walked_out"] > 0:
		earned = mini(earned, 2)
	return maxi(earned - int(summary.get("caught_bends", 0)), 0)


## The end of a shift: Ma'am Lorna's spot check (none when the line gave up), the stars, integrity
## and the regulars' visits, added to summary (from ShiftState.summary) and returned. The game, the
## simulator and the save tests all finish a shift through here, so they score it the same way.
static func finish(summary: Dictionary, history: Array, base_seed: int, day: int) -> Dictionary:
	summary["spot_check"] = []
	summary["caught_bends"] = 0
	if summary["reason"] != "patience":
		var check: Dictionary = SpotCheck.run(history, base_seed * 1000 + day, day)
		summary["spot_check"] = check["rows"]
		summary["caught_bends"] = check["caught_bends"]
	summary["stars"] = stars(summary)
	summary["integrity"] = Evaluation.integrity(summary)
	summary["regulars"] = Evaluation.regular_calls(history)
	return summary


## Mid-shift: the stars the calls so far are heading for. Students still to come aren't counted
## as unserved, since the day isn't over.
static func projected(summary: Dictionary) -> int:
	if summary["decisions"] == 0:
		return 0
	var so_far := summary.duplicate()
	so_far["served_ratio"] = 1.0
	so_far["reason"] = ""
	so_far.erase("caught_bends")
	return stars(so_far)
