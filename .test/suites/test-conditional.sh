#!/usr/bin/env bash
# ================================================================
#  Test Suite: Conditional Display Logic
#  Tests when rows/elements appear or hide based on conditions
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "conditional"

# ================================================================
# Token breakdown row: shown at PCT >= 85, TOTAL_INPUT > 0, tier != compact
# ================================================================

# PCT=85, normal width → should show token breakdown
run_fixture "context-85pct" "full" 120
assert_contains "$STATUSLINE_PLAIN" "tokens" "PCT=85 shows token breakdown"

# PCT=84 → should NOT show token breakdown sub-row
run_statusline "$(make_json '{"context_window":{"used_percentage":84,"current_usage":{"input_tokens":150000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":100000},"total_output_tokens":50000}}')" "full" 120
PLAIN_LINES=$(printf '%s\n' "$STATUSLINE_PLAIN" | grep -c "^  tokens" || true)
assert_equals "0" "$PLAIN_LINES" "PCT=84 does NOT show token breakdown sub-row"

# PCT=85, compact tier → should NOT show token breakdown
run_fixture "context-85pct" "full" 60
PLAIN_LINES2=$(printf '%s\n' "$STATUSLINE_PLAIN" | grep -c "^  tokens" || true)
assert_equals "0" "$PLAIN_LINES2" "PCT=85 compact does NOT show token breakdown"

# ================================================================
# Burn rate: shown when DURATION_MS > 60000 AND SESSION_TOKENS > 0
# ================================================================

run_statusline "$(make_json '{"cost":{"total_cost_usd":2.0,"total_duration_ms":120000},"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":10000},"total_output_tokens":10000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "/hr" "burn rate shows $/hr when duration > 60s"

run_statusline "$(make_json '{"cost":{"total_cost_usd":2.0,"total_duration_ms":60000},"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":10000},"total_output_tokens":10000}}')" "full" 120
assert_not_contains "$STATUSLINE_PLAIN" "/hr" "burn rate hidden when duration <= 60s"

run_statusline "$(make_json '{"cost":{"total_cost_usd":2.0,"total_duration_ms":120000},"context_window":{"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"total_output_tokens":0}}')" "full" 120
assert_not_contains "$STATUSLINE_PLAIN" "/hr" "burn rate hidden when no tokens"

# ================================================================
# Code lines
# ================================================================

run_statusline "$(make_json '{"cost":{"total_lines_added":50,"total_lines_removed":10}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "code" "code section shown when lines changed"

run_statusline "$(make_json '{"cost":{"total_lines_added":0,"total_lines_removed":0}}')" "full" 120
assert_not_contains "$STATUSLINE_PLAIN" "code" "code section hidden when no lines"

# ================================================================
# Badges display
# ================================================================

run_fixture "with-badges" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "INSERT" "vim mode badge shows INSERT"
assert_contains "$STATUSLINE_PLAIN" "planner" "agent badge shows name"
assert_contains "$STATUSLINE_PLAIN" "my-worktree" "worktree badge shows name"

run_fixture "long-names" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "super-lo" "agent name truncated at 8 chars"
assert_not_contains "$STATUSLINE_PLAIN" "super-long-agent-name-that-exceeds-limit" "full agent name NOT shown"
assert_contains "$STATUSLINE_PLAIN" "extremely-long-" "worktree name truncated at 15 chars"

# ================================================================
# Throughput
# ================================================================

run_statusline "$(make_json '{"cost":{"total_duration_ms":300000},"context_window":{"total_output_tokens":15000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "speed" "throughput shown when duration & output > 0"
assert_contains "$STATUSLINE_PLAIN" "/min" "throughput shows /min unit"

run_statusline "$(make_json '{"cost":{"total_duration_ms":0},"context_window":{"total_output_tokens":15000}}')" "essential" 120
assert_not_contains "$STATUSLINE_PLAIN" "speed" "throughput hidden when duration = 0"

run_statusline "$(make_json '{"cost":{"total_duration_ms":300000},"context_window":{"total_output_tokens":0}}')" "essential" 120
assert_not_contains "$STATUSLINE_PLAIN" "speed" "throughput hidden when output = 0"

# ================================================================
# API efficiency
# ================================================================

run_statusline "$(make_json '{"cost":{"total_duration_ms":300000,"total_api_duration_ms":180000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "api" "API efficiency shown"
assert_contains "$STATUSLINE_PLAIN" "60%" "API efficiency = 180000/300000 = 60%"

# ================================================================
# Turn-level display on essential preset (Row 2)
# ================================================================

# Turn with input tokens shows on essential
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":30000},"total_output_tokens":8000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "turn" "essential shows turn display"
assert_contains "$STATUSLINE_PLAIN" "in" "essential turn shows input tokens"

# Turn out token visible when > 0
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"total_output_tokens":15000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "out" "essential turn shows out tokens when > 0"

end_suite
teardown_test_env
