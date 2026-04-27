#!/usr/bin/env bash
# ================================================================
#  Test Suite: Edge Cases
#  Tests boundary values, missing fields, extreme inputs
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "edge-cases"

# ================================================================
# Empty JSON {} → safe defaults, no crash
# ================================================================

assert_no_error '{}' "vitals" "empty JSON does not crash"
run_statusline '{}' "vitals" 120
assert_contains "$STATUSLINE_PLAIN" "Unknown" "empty JSON shows Unknown model"
assert_contains "$STATUSLINE_PLAIN" "0%" "empty JSON shows 0% context"

# ================================================================
# Completely invalid JSON → fallback defaults
# ================================================================

assert_no_error 'not json at all' "minimal" "invalid JSON does not crash"

# ================================================================
# PCT overflow: > 100 → clamped to 100
# ================================================================

run_statusline "$(make_json '{"context_window":{"used_percentage":150}}')" "essential" 120
# The bar should be fully filled, PCT displays the original value
# but make_bar clamps to 100
assert_matches "$STATUSLINE_PLAIN" "##########" "PCT=150 bar is fully filled (clamped)"

# ================================================================
# PCT negative: < 0 → clamped to 0
# ================================================================

run_statusline "$(make_json '{"context_window":{"used_percentage":-10}}')" "essential" 120
assert_matches "$STATUSLINE_PLAIN" "[-]{10}" "PCT=-10 bar is all empty (clamped)"

# ================================================================
# Zero values everywhere → no division errors
# ================================================================

run_fixture "zero-values" "vitals" 120
assert_contains "$STATUSLINE_PLAIN" '0%' "zero values show 0%"
assert_contains "$STATUSLINE_PLAIN" '$0.00' "zero values show \$0.00"
assert_contains "$STATUSLINE_PLAIN" "0s" "zero duration shows 0s"
assert_not_contains "$STATUSLINE_PLAIN" "speed" "zero values hide speed (no division)"
assert_not_contains "$STATUSLINE_PLAIN" "code" "zero values hide code section"

# ================================================================
# Extreme large values → no overflow errors
# ================================================================

run_fixture "edge-extreme" "full" 120
assert_contains "$STATUSLINE_PLAIN" '$999.99' "extreme cost formatted correctly"
assert_contains "$STATUSLINE_PLAIN" "13h" "extreme API duration = 50000000ms = 13h 53m"

# ================================================================
# exceeds_200k_tokens flag
# ================================================================

run_statusline "$(make_json '{"exceeds_200k_tokens":true,"context_window":{"used_percentage":30}}')" "essential" 120
# Should have the ⚠ warning in output
assert_contains "$STATUSLINE_PLAIN" "30%" "exceeds_200k still shows PCT"

# ================================================================
# Theme: light vs dark
# ================================================================

export CLAUDE_SL_THEME="light"
run_fixture "minimal" "minimal" 120
# Light theme should still produce valid output
assert_contains "$STATUSLINE_PLAIN" "Sonnet" "light theme shows model"

export CLAUDE_SL_THEME="dark"
run_fixture "minimal" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "Sonnet" "dark theme shows model"

unset CLAUDE_SL_THEME

# ================================================================
# COLORFGBG theme detection
# ================================================================

export COLORFGBG="0;15"  # bg=15 → light
run_fixture "minimal" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "Sonnet" "COLORFGBG light bg produces output"
unset COLORFGBG

# ================================================================
# Unicode vs ASCII fallback
# ================================================================

export CLAUDE_SL_ASCII=1
run_fixture "minimal" "essential" 120
assert_matches "$STATUSLINE_PLAIN" "[#-]" "ASCII mode uses # or - in bars"

export CLAUDE_SL_ASCII=0
export CLAUDE_SL_UNICODE=1
run_fixture "minimal" "essential" 120
# Unicode chars appear in raw output
assert_contains "$STATUSLINE_RAW" "│" "Unicode mode uses │ separator"

export CLAUDE_SL_ASCII=1
unset CLAUDE_SL_UNICODE

# ================================================================
# Missing optional fields → graceful handling
# ================================================================

assert_no_error '{"model":{"display_name":"Test"}}' "minimal" "partial JSON (model only) no crash"
assert_no_error '{"workspace":{"current_dir":"/tmp"}}' "minimal" "partial JSON (workspace only) no crash"
assert_no_error '{"context_window":{"used_percentage":50}}' "essential" "partial JSON (context only) no crash"

# ================================================================
# Very long directory name → shows basename only
# ================================================================

run_statusline "$(make_json '{"workspace":{"current_dir":"/very/deeply/nested/directory/structure/with/many/levels/project-name"}}')" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "project-name" "long path shows only basename"
assert_not_contains "$STATUSLINE_PLAIN" "/very/deeply" "long path does NOT show full path"

end_suite
teardown_test_env
