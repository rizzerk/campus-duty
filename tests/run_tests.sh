#!/bin/sh
# Runs every test script headless. Fails if any test doesn't print PASS, or if any script error
# shows up (a script that fails to compile can otherwise leave its checks silently skipped).
# Set GODOT if Godot isn't at the default macOS path.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
status=0
for test in tests/test_*.gd; do
	output=$("$GODOT" --headless --path . --script "res://$test" 2>&1)
	echo "$output" | grep -E 'PASS|FAIL|ERROR'
	echo "$output" | grep -q ': PASS$' || status=1
	echo "$output" | grep -q 'SCRIPT ERROR' && status=1
done
exit $status
