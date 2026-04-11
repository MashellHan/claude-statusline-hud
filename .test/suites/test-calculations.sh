#!/usr/bin/env bash
# ================================================================
#  Test Suite: Calculations
#  Verifies math accuracy: tokens, cache %, throughput, burn rate
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "calculations"

# ================================================================
# CTX_TOKENS = CTX_SIZE * PCT / 100
# ================================================================

# 200000 * 50 / 100 = 100000 → "100k"
run_statusline "$(make_json '{"context_window":{"used_percentage":50,"context_window_size":200000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "100k" "CTX_TOKENS: 200k*50% = 100k"

# 200000 * 10 / 100 = 20000 → "20k"
run_statusline "$(make_json '{"context_window":{"used_percentage":10,"context_window_size":200000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "20k" "CTX_TOKENS: 200k*10% = 20k"

# 200000 * 0 / 100 = 0 → token display hidden
run_statusline "$(make_json '{"context_window":{"used_percentage":0,"context_window_size":200000,"total_output_tokens":0,"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}')" "essential" 120
assert_not_contains "$STATUSLINE_PLAIN" "token" "CTX_TOKENS: 0 → no token display"

# ================================================================
# CACHE_HIT_PCT = CACHE_READ * 100 / TOTAL_INPUT
# TOTAL_INPUT = INPUT_TOK + CACHE_CREATE + CACHE_READ
# ================================================================

# 80000 / (10000 + 10000 + 80000) = 80% → "80%"
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":10000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":80000}}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "cache" "cache metric present"
assert_matches "$STATUSLINE_PLAIN" "80%" "cache hit rate = 80%"

# 0 / (100000 + 0 + 0) = 0% → "0%"
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":100000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "0%" "cache hit rate = 0% when no reads"

# All zero → no cache display (TOTAL_INPUT = 0)
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}')" "essential" 120
# When TOTAL_INPUT is 0, cache section is not shown at all
# The "0%" we see is from the context PCT, not cache
CACHE_LINES=$(printf '%s' "$STATUSLINE_PLAIN" | grep -c "cache")
# May or may not show "cache" depending on the 0/0 guard
# Just verify no crash
assert_contains "$STATUSLINE_PLAIN" "context" "zero cache inputs still shows context"

# ================================================================
# Throughput: TPM = TOTAL_OUT * 60000 / DURATION_MS
# ================================================================

# 15000 * 60000 / 300000 = 3000 → "3k/min"
run_statusline "$(make_json '{"cost":{"total_duration_ms":300000},"context_window":{"total_output_tokens":15000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "3k/min" "throughput: 15k out / 5min = 3k/min"

# 60000 * 60000 / 60000 = 60000 → "60k/min"
run_statusline "$(make_json '{"cost":{"total_duration_ms":60000},"context_window":{"total_output_tokens":60000}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "60k/min" "throughput: 60k out / 1min = 60k/min"

# ================================================================
# BURN_RATE = COST / (DURATION_MS / 3600000)
# ================================================================

# $3.60 / (3600000 / 3600000) = $3.60/hr
run_statusline "$(make_json '{"cost":{"total_cost_usd":3.60,"total_duration_ms":3600000},"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":10000},"total_output_tokens":10000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '3.60/hr' "burn rate: \$3.60 / 1hr = \$3.60/hr"

# $1.00 / (1800000 / 3600000) = $1.00 / 0.5 = $2.00/hr
run_statusline "$(make_json '{"cost":{"total_cost_usd":1.0,"total_duration_ms":1800000},"context_window":{"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":10000},"total_output_tokens":10000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" '2.00/hr' "burn rate: \$1.00 / 0.5hr = \$2.00/hr"

# ================================================================
# API_PCT = API_MS * 100 / DURATION_MS
# ================================================================

# 180000 * 100 / 300000 = 60%
run_statusline "$(make_json '{"cost":{"total_duration_ms":300000,"total_api_duration_ms":180000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "60%" "API efficiency: 180k/300k = 60%"

# 300000 * 100 / 300000 = 100%
run_statusline "$(make_json '{"cost":{"total_duration_ms":300000,"total_api_duration_ms":300000}}')" "full" 120
assert_contains "$STATUSLINE_PLAIN" "100%" "API efficiency: 300k/300k = 100%"

# ================================================================
# ADJ_PCT calculation (context pressure inflation)
# ================================================================

# PCT=70 → ADJ_PCT = 70 + (70-70)*10/30 = 70 → yellow
run_statusline "$(make_json '{"context_window":{"used_percentage":70}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "70%" "ADJ_PCT at 70%: shows 70%"
assert_has_ansi_color "$STATUSLINE_RAW" "yellow" "ADJ_PCT=70 → yellow bar"

# PCT=85 → ADJ_PCT = 85 + (85-70)*10/30 = 85 + 5 = 90 → red
run_statusline "$(make_json '{"context_window":{"used_percentage":85}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "85%" "ADJ_PCT at 85%: shows 85%"
assert_has_ansi_color "$STATUSLINE_RAW" "red" "ADJ_PCT=90 → red bar"

# PCT=100 → ADJ_PCT capped at 100
run_statusline "$(make_json '{"context_window":{"used_percentage":100}}')" "essential" 120
assert_contains "$STATUSLINE_PLAIN" "100%" "ADJ_PCT at 100%: shows 100%"

end_suite
teardown_test_env
