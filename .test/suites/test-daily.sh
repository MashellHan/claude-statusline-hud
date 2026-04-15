#!/usr/bin/env bash
# ================================================================
#  Test Suite: Daily Aggregation
#  Verifies day-total correctness across file mtime and timezone
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
begin_suite "daily"

PROJECTS_DIR="$HOME/.claude/projects/test-project"
mkdir -p "$PROJECTS_DIR"

TODAY_LOCAL=$(date +%Y-%m-%d)

if date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY_LOCAL 00:30:00" "+%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
  TS_TODAY_0030_UTC=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY_LOCAL 00:30:00" "+%Y-%m-%dT%H:%M:%SZ")
  TS_TODAY_0930_UTC=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY_LOCAL 09:30:00" "+%Y-%m-%dT%H:%M:%SZ")
  TS_YDAY_2330_UTC=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY_LOCAL 00:00:00" -v-30M "+%Y-%m-%dT%H:%M:%SZ")
  OLD_TOUCH=$(date -v-2d +%Y%m%d0000)
else
  TS_TODAY_0030_UTC=$(date -u -d "$TODAY_LOCAL 00:30:00" "+%Y-%m-%dT%H:%M:%SZ")
  TS_TODAY_0930_UTC=$(date -u -d "$TODAY_LOCAL 09:30:00" "+%Y-%m-%dT%H:%M:%SZ")
  TS_YDAY_2330_UTC=$(date -u -d "$TODAY_LOCAL 00:00:00 - 30 minutes" "+%Y-%m-%dT%H:%M:%SZ")
  OLD_TOUCH=$(date -d "2 days ago" +%Y%m%d0000)
fi

OLD_FILE="$PROJECTS_DIR/old-session.jsonl"
NEW_FILE="$PROJECTS_DIR/new-session.jsonl"

# Included by timestamp range, but file mtime is intentionally old.
cat > "$OLD_FILE" <<EOF
{"timestamp":"$TS_TODAY_0030_UTC","message":{"usage":{"input_tokens":1000000,"output_tokens":100000,"cache_creation_input_tokens":300000,"cache_read_input_tokens":200000}}}
EOF
touch -t "$OLD_TOUCH" "$OLD_FILE" 2>/dev/null || true

# Included (today local) + excluded (yesterday local)
cat > "$NEW_FILE" <<EOF
{"timestamp":"$TS_TODAY_0930_UTC","message":{"usage":{"input_tokens":500000,"output_tokens":50000,"cache_creation_input_tokens":100000,"cache_read_input_tokens":100000}}}
not-json-but-contains-input_tokens
{"timestamp":"$TS_TODAY_0930_UTC","message":{"usage":{"input_tokens":100000,"output_tokens":10000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":30000}}}
{"timestamp":"$TS_YDAY_2330_UTC","message":{"usage":{"input_tokens":9000000,"output_tokens":900000,"cache_creation_input_tokens":900000,"cache_read_input_tokens":900000}}}
EOF

# Ensure fresh daily cache for this test.
rm -f "$HOME/.cache/claude-statusline/daily_$(id -u).cache" 2>/dev/null || true

run_statusline "$(make_json '{"cost":{"total_cost_usd":1.0}}')" "full" 120

assert_contains "$STATUSLINE_PLAIN" "day-total" "daily row is shown"
assert_contains "$STATUSLINE_PLAIN" "token 2M" "daily token includes old-mtime file and timezone boundary entry"
assert_contains "$STATUSLINE_PLAIN" "in 1M" "daily input aggregated"
assert_contains "$STATUSLINE_PLAIN" "create 420k" "daily cache creation is included and shown"
assert_contains "$STATUSLINE_PLAIN" "cache 330k" "daily cache read aggregated"
assert_contains "$STATUSLINE_PLAIN" "out 160k" "daily output aggregated"
assert_contains "$STATUSLINE_PLAIN" '$8.87' "daily cost includes cache_creation pricing"
assert_contains "$STATUSLINE_PLAIN" "msg 3" "invalid json line is skipped and valid lines still counted"

end_suite
teardown_test_env
