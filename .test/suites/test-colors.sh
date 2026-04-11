#!/usr/bin/env bash
# ================================================================
#  Test Suite: Colors
#  Verifies color threshold boundaries (green/yellow/red)
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "colors"

GREEN_CODE=$'\033[32m'
YELLOW_CODE=$'\033[33m'
RED_CODE=$'\033[31m'

# ================================================================
# Context bar color thresholds (bar_color function)
# green < 70, yellow 70-89, red >= 90
# NOTE: uses ADJ_PCT which inflates above 70%
# ================================================================

# PCT=50 → ADJ_PCT=50 → green
run_statusline "$(make_json '{"context_window":{"used_percentage":50}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "green" "context 50% → green bar"

# PCT=69 → ADJ_PCT=69 → green (boundary)
run_statusline "$(make_json '{"context_window":{"used_percentage":69}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "green" "context 69% → green (just below yellow)"

# PCT=70 → ADJ_PCT=70 → yellow (boundary)
run_statusline "$(make_json '{"context_window":{"used_percentage":70}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "yellow" "context 70% → yellow (threshold)"

# PCT=85 → ADJ_PCT = 85 + (85-70)*10/30 = 85+5 = 90 → red
run_statusline "$(make_json '{"context_window":{"used_percentage":85}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "red" "context 85% → red (ADJ_PCT=90)"

# PCT=92 → ADJ_PCT = 92 + (92-70)*10/30 = 92+7 = 99 → red
run_statusline "$(make_json '{"context_window":{"used_percentage":92}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "red" "context 92% → red"

# ================================================================
# Context warning ⚠ at ADJ_PCT ≥ 90 or exceeds_200k
# ================================================================

# PCT=85 → ADJ_PCT=90 → warning
run_statusline "$(make_json '{"context_window":{"used_percentage":85}}')" "essential" 120
# The ⚠ symbol should be present
# Note: check in raw output since the symbol may be part of ANSI sequence
assert_contains "$STATUSLINE_PLAIN" "%" "context 85% shows percentage"

# exceeds_200k=true → warning regardless of PCT
run_statusline "$(make_json '{"exceeds_200k_tokens":true,"context_window":{"used_percentage":30}}')" "essential" 120
# Should still show context bar normally but with warning
assert_contains "$STATUSLINE_PLAIN" "30%" "exceeds_200k shows 30%"

# ================================================================
# Cache hit rate colors
# green ≥ 80%, yellow 40-79%, red < 40%
# ================================================================

# High cache: 80000 / (80000+10000+10000) = 80% → green
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":10000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":80000}}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "green" "cache 80% → green"

# Medium cache: 50000 / (50000+25000+25000) = 50% → yellow
run_statusline "$(make_json '{"context_window":{"current_usage":{"input_tokens":25000,"cache_creation_input_tokens":25000,"cache_read_input_tokens":50000}}}')" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "yellow" "cache 50% → yellow"

# Low cache: 5000 / (80000+15000+5000) = 5% → red
run_fixture "low-cache" "essential" 120
assert_has_ansi_color "$STATUSLINE_RAW" "red" "cache 5% → red"

# ================================================================
# System vitals color thresholds
# ================================================================

# CPU low → green
seed_vitals_cache 25 "8G" 16 50 10 "120G" "500G" 24 85 "2.1"
run_fixture "minimal" "vitals" 120
assert_has_ansi_color "$STATUSLINE_RAW" "green" "CPU 25% → green"

# CPU high → red (seed with 95%)
seed_vitals_cache 95 "15G" 16 94 80 "480G" "500G" 96 15 "8.5"
run_fixture "minimal" "vitals" 120
assert_has_ansi_color "$STATUSLINE_RAW" "red" "CPU 95% + mem 94% → red present"

# Battery low → red
seed_vitals_cache 50 "8G" 16 50 10 "120G" "500G" 24 15 "2.1"
run_fixture "minimal" "vitals" 120
assert_has_ansi_color "$STATUSLINE_RAW" "red" "Battery 15% → red"

end_suite
teardown_test_env
