#!/bin/sh
# Headless test run with guards (see TECH_DEBTS.md, TD-6). GUT silently SKIPS a
# test file that fails to parse - it doesn't fail the run - so a broken file can
# quietly vanish from coverage while the suite still reports "all passed". These
# guards catch that: they fail the run on any parse/load error and on a coverage
# drop below tests/.test-baseline (bump that file when you add scripts/tests).
cd "$(dirname "$0")/.." || exit 1

# --import first refreshes Godot's global script-class cache so newly added
# class_name scripts resolve.
godot --headless --import >/dev/null 2>&1 || true

OUT=$(godot --headless -s res://addons/gut/gut_cmdln.gd 2>&1)
echo "$OUT"

fail() { printf '\n\033[31mTEST GUARD FAILED:\033[0m %s\n' "$1"; exit 1; }

# 1) No test script silently dropped by a parse/load error. Match GUT's actual
#    loader failure line (and GDScript's "Parse Error:") - NOT the lowercase
#    "parse error" that can appear inside a test's expected-error description.
if printf '%s\n' "$OUT" | grep -qE 'Failed to load script "res://|SCRIPT ERROR: Parse Error'; then
	fail "a test script failed to parse/load (GUT silently skips these; grep the output above)."
fi

# 2) GUT must actually report success.
printf '%s\n' "$OUT" | grep -q "All tests passed" \
	|| fail "GUT did not report all tests passed."

# 3) Coverage must not drop below the committed baseline.
if [ -f tests/.test-baseline ]; then
	read -r MIN_S MIN_T < tests/.test-baseline
else
	MIN_S=0; MIN_T=0
fi
S=$(printf '%s\n' "$OUT" | grep -a "Scripts" | grep -oE "[0-9]+" | tail -1)
T=$(printf '%s\n' "$OUT" | grep -a "Passing Tests" | grep -oE "[0-9]+" | tail -1)
if [ -n "$S" ] && [ -n "$T" ]; then
	[ "$S" -ge "$MIN_S" ] || fail "script count dropped ($S < baseline $MIN_S) - a test file went missing. If intentional, lower tests/.test-baseline."
	[ "$T" -ge "$MIN_T" ] || fail "passing-test count dropped ($T < baseline $MIN_T). If intentional, lower tests/.test-baseline."
	printf '\033[32mTest guard OK\033[0m - %s scripts, %s passing (baseline %s/%s).\n' "$S" "$T" "$MIN_S" "$MIN_T"
else
	printf '\nTEST GUARD: could not parse Scripts/Passing counts; skipped the coverage check.\n'
fi
