#!/usr/bin/env bash
# ================================================================
#  Test Suite: Presets
#  Verifies each preset produces the correct number of output rows
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "presets"

# --- minimal: exactly 1 row (Row 1: Model | Dir | context bar) ---
run_fixture "minimal" "minimal" 120
assert_line_count "$STATUSLINE_PLAIN" "1" "minimal preset outputs 1 row"
assert_contains "$STATUSLINE_PLAIN" "Sonnet" "minimal shows model name"
assert_contains "$STATUSLINE_PLAIN" "project" "minimal shows directory"
assert_contains "$STATUSLINE_PLAIN" "context" "minimal shows context bar on Row 1"
assert_not_contains "$STATUSLINE_PLAIN" "cost" "minimal does NOT show cost row"

# --- essential: 1-3 rows (Row 1 + optional Turn row, optionally token breakdown) ---
run_fixture "minimal" "essential" 120
assert_line_count_range "$STATUSLINE_PLAIN" 1 3 "essential preset outputs 1-3 rows"
assert_contains "$STATUSLINE_PLAIN" "context" "essential shows context on Row 1"
assert_not_contains "$STATUSLINE_PLAIN" "cost" "essential does NOT show cost row"
assert_not_contains "$STATUSLINE_PLAIN" "cpu" "essential does NOT show vitals"

# --- full: 2-5 rows (Row 1 + Turn + Session + Daily, optionally token breakdown) ---
run_fixture "full-session" "full" 120
assert_line_count_range "$STATUSLINE_PLAIN" 2 5 "full preset outputs 2-5 rows"
assert_contains "$STATUSLINE_PLAIN" "context" "full shows context on Row 1"
assert_contains "$STATUSLINE_PLAIN" "cost" "full shows cost row"
assert_not_contains "$STATUSLINE_PLAIN" "cpu" "full does NOT show vitals"

# --- vitals (default): 3-6 rows (all rows including system vitals) ---
run_fixture "full-session" "vitals" 120
assert_line_count_range "$STATUSLINE_PLAIN" 3 6 "vitals preset outputs 3-6 rows"
assert_contains "$STATUSLINE_PLAIN" "context" "vitals shows context on Row 1"
assert_contains "$STATUSLINE_PLAIN" "cost" "vitals shows cost row"
assert_contains "$STATUSLINE_PLAIN" "cpu" "vitals shows CPU vital"
assert_contains "$STATUSLINE_PLAIN" "mem" "vitals shows memory vital"

# --- vitals is the default when no preset specified ---
unset CLAUDE_STATUSLINE_PRESET
run_statusline "$(cat "$FIXTURES_DIR/full-session.json")" "" 120
# Default is vitals — statusline.sh reads from file or defaults to "vitals"
assert_contains "$STATUSLINE_PLAIN" "cpu" "default preset shows vitals (cpu)"

end_suite
teardown_test_env
