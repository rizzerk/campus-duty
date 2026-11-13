#!/bin/sh
# Boots each day's shift scene headless for a few hundred frames and fails on any script or
# engine error. Catches scene bugs the unit tests can't see (missing nodes, bad connections).
#   sh tests/smoke.sh          every day from first_day to last_day
#   sh tests/smoke.sh 6 7      only these days
# Set GODOT if Godot isn't at the default macOS path. FRAMES sets how long each day runs.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
FRAMES="${FRAMES:-600}"
ERRORS='SCRIPT ERROR|^ERROR:|Parse Error|Invalid call|Invalid access|Nonexistent function'
cd "$(dirname "$0")/.." || exit 1

if [ ! -x "$GODOT" ]; then
	echo "smoke: Godot not found at $GODOT (set GODOT)"
	exit 1
fi

if [ "$#" -gt 0 ]; then
	days="$*"
else
	days=$(python3 -c "import json; d = json.load(open('data/days.json')); print(' '.join(str(n) for n in range(d['first_day'], d['last_day'] + 1)))") || {
		echo "smoke: could not read the day range from data/days.json"
		exit 1
	}
fi
if [ -z "$days" ]; then
	echo "smoke: no days to run"
	exit 1
fi

status=0
for day in $days; do
	case "$day" in
		'' | *[!0-9]*)
			echo "smoke day $day: FAIL (not a day number)"
			status=1
			continue
			;;
	esac
	output=$("$GODOT" --headless --path . --quit-after "$FRAMES" -- --day="$day" --seed=42 2>&1)
	code=$?
	reason=""
	if [ "$code" -ne 0 ]; then
		reason="Godot exited with $code"
	elif echo "$output" | grep -Eq "$ERRORS"; then
		reason="errors in the output"
	elif ! echo "$output" | grep -q "debug_jump: day $day seed 42 -> window"; then
		reason="never reached the day $day shift (debug_jump didn't run)"
	fi
	if [ -n "$reason" ]; then
		echo "smoke day $day: FAIL ($reason)"
		echo "$output" | grep -E -A3 "$ERRORS" | head -40
		status=1
	else
		echo "smoke day $day: PASS"
	fi
done
exit $status
