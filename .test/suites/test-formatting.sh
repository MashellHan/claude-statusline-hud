#!/usr/bin/env bash
# ================================================================
#  Test Suite: Formatting Functions
#  Tests fmt_tok, fmt_dur, fmt_cost, make_bar, mini_bar output
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "formatting"

# ================================================================
# fmt_tok: token formatting
# ================================================================

# Small tokens: exact number
run_statusline "$(make_json '{"context_window":{"used_percentage":50,"total_output_tokens":500,"current_usage":{"input_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "100k" "fmt_tok: ctx_tokens at 50% of 200k = 100k"

# Thousands: "Nk"
run_statusline "$(make_json '{"context_window":{"used_percentage":10,"total_output_tokens":5000,"current_usage":{"input_tokens":15000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":3000},"context_window_size":200000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "20k" "fmt_tok: ctx_tokens at 10% of 200k = 20k"

# Millions: "NM"
run_statusline "$(make_json '{"context_window":{"used_percentage":75,"total_output_tokens":500000,"current_usage":{"input_tokens":800000,"cache_creation_input_tokens":100000,"cache_read_input_tokens":200000},"context_window_size":2000000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "1M" "fmt_tok: ctx_tokens at 75% of 2M = 1.5M → 1M"

# ================================================================
# fmt_dur: duration formatting
# ================================================================

# Seconds only
run_statusline "$(make_json '{"cost":{"total_duration_ms":45000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "45s" "fmt_dur: 45000ms = 45s"

# Minutes and seconds
run_statusline "$(make_json '{"cost":{"total_duration_ms":125000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "2m 5s" "fmt_dur: 125000ms = 2m 5s"

# Hours and minutes
run_statusline "$(make_json '{"cost":{"total_duration_ms":3720000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "1h 2m" "fmt_dur: 3720000ms = 1h 2m"

# Zero duration
run_statusline "$(make_json '{"cost":{"total_duration_ms":0}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "0s" "fmt_dur: 0ms = 0s"

# ================================================================
# fmt_cost: cost formatting
# ================================================================

# Zero cost
run_statusline "$(make_json '{"cost":{"total_cost_usd":0}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '$0.00' "fmt_cost: 0 = \$0.00"

# Normal cost
run_statusline "$(make_json '{"cost":{"total_cost_usd":1.5}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '$1.50' "fmt_cost: 1.5 = \$1.50"

# Large cost
run_statusline "$(make_json '{"cost":{"total_cost_usd":99.999}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '$100.00' "fmt_cost: 99.999 rounds to \$100.00"

# Small fractional cost
run_statusline "$(make_json '{"cost":{"total_cost_usd":0.01}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '$0.01' "fmt_cost: 0.01 = \$0.01"

# ================================================================
# make_bar: progress bars (ASCII mode)
# ================================================================

# 0% → all empty
run_statusline "$(make_json '{"context_window":{"used_percentage":0}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "0%" "bar at 0% shows 0%"
assert_matches "$STATUSLINE_PLAIN" "[-]{10}" "bar at 0% is all empty dashes"

# 50% → half filled
run_statusline "$(make_json '{"context_window":{"used_percentage":50}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "50%" "bar at 50% shows 50%"
assert_matches "$STATUSLINE_PLAIN" "#####-----" "bar at 50% is half filled"

# 100% → all filled
run_statusline "$(make_json '{"context_window":{"used_percentage":100}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "100%" "bar at 100% shows 100%"
assert_matches "$STATUSLINE_PLAIN" "##########" "bar at 100% is all filled"

# ================================================================
# Code line indicators
# ================================================================

# Net positive: ▲
run_statusline "$(make_json '{"cost":{"total_lines_added":100,"total_lines_removed":20}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "+100" "shows +100 added"
assert_contains "$STATUSLINE_PLAIN" "-20" "shows -20 removed"

# Net negative: ▼
run_statusline "$(make_json '{"cost":{"total_lines_added":10,"total_lines_removed":50}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "+10" "shows +10 added"
assert_contains "$STATUSLINE_PLAIN" "-50" "shows -50 removed"

# Balanced: ═
run_statusline "$(make_json '{"cost":{"total_lines_added":50,"total_lines_removed":50}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "+50" "balanced shows +50"
assert_contains "$STATUSLINE_PLAIN" "-50" "balanced shows -50"

# No lines changed: no code section
run_statusline "$(make_json '{"cost":{"total_lines_added":0,"total_lines_removed":0}}')" "full" 120
assert_not_contains "$STATUSLINE_PLAIN" "code" "no lines changed → no code section"

# ================================================================
# ASCII vs Unicode mode
# ================================================================

# ASCII mode (default in tests)
export CLAUDE_SL_ASCII=1
run_statusline "$(make_json '{"context_window":{"used_percentage":50}}')" "essential" 120
assert_matches "$STATUSLINE_PLAIN" "#" "ASCII mode uses # for bar fill"
assert_matches "$STATUSLINE_PLAIN" "[-]" "ASCII mode uses - for bar empty"

# Unicode mode
export CLAUDE_SL_ASCII=0
export CLAUDE_SL_UNICODE=1
run_statusline "$(make_json '{"context_window":{"used_percentage":50}}')" "essential" 120
assert_contains "$STATUSLINE_RAW" "█" "Unicode mode uses █ for bar fill"
assert_contains "$STATUSLINE_RAW" "░" "Unicode mode uses ░ for bar empty"

# Reset
export CLAUDE_SL_ASCII=1
unset CLAUDE_SL_UNICODE

end_suite
teardown_test_env
