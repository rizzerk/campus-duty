#!/bin/sh
# Runs every test script headless and fails if any test doesn't print PASS.
# Set GODOT if Godot isn't at the default macOS path.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
status=0
for test in tests/test_*.gd; do
	output=$("$GODOT" --headless --path . --script "res://$test" 2>&1)
	echo "$output" | grep -E 'PASS|FAIL|ERROR'
	echo "$output" | grep -q ': PASS$' || status=1
done
exit $status
