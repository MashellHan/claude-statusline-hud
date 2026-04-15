#!/usr/bin/env bash
# ================================================================
#  Test Suite: Codex CLI Statusline HUD
#  Tests the standalone Codex version that reads from disk
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

# Override script path for Codex version
CODEX_SCRIPT="$PROJECT_DIR/plugins/codex-statusline-hud/scripts/statusline.sh"

setup_test_env

# ================================================================
# Codex-specific helpers
# ================================================================

# Create a mock Codex session directory structure
# Uses today's real date so the script can find the files
setup_codex_session() {
  local session_id="${1:-test-session-001}"
  local model="${2:-gpt-5.3-codex}"
  local cwd="${3:-/tmp/test-project}"

  CODEX_HOME="$_TEST_HOME/.codex"
  local today_dir="$(date +%Y/%m/%d)"
  CODEX_SESSIONS_DIR="$CODEX_HOME/sessions/$today_dir"
  mkdir -p "$CODEX_SESSIONS_DIR"

  # Clean out any previous test session files
  rm -f "$CODEX_SESSIONS_DIR"/rollout-*.jsonl 2>/dev/null || true

  # Create config.toml
  cat > "$CODEX_HOME/config.toml" <<EOF
model = "$model"
model_provider = "superset"
EOF

  SESSION_FILE="$CODEX_SESSIONS_DIR/rollout-$(date +%Y-%m-%d)T00-00-00-${session_id}.jsonl"
}

# Write a session_meta event
write_session_meta() {
  local file="$1" model="$2" cwd="$3" version="${4:-0.120.0}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"test-id","timestamp":"%s","cwd":"%s","model":"%s","cli_version":"%s"}}\n' \
    "$ts" "$ts" "$cwd" "$model" "$version" >> "$file"
}

# Write a task_started event
write_task_started() {
  local file="$1" turn_id="$2" ctx_window="${3:-200000}"
  local ts started_at
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  started_at=$(date +%s)
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_started","turn_id":"%s","started_at":%d,"model_context_window":%d,"collaboration_mode_kind":"default"}}\n' \
    "$ts" "$turn_id" "$started_at" "$ctx_window" >> "$file"
}

# Write a token_count event
write_token_count() {
  local file="$1" input="$2" cached="$3" output="$4" reasoning="$5" ctx_window="${6:-200000}"
  local total ts
  total=$((input + output))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%d,"cached_input_tokens":%d,"output_tokens":%d,"reasoning_output_tokens":%d,"total_tokens":%d},"model_context_window":%d}}}\n' \
    "$ts" "$input" "$cached" "$output" "$reasoning" "$total" "$ctx_window" >> "$file"
}

# Write a task_complete event
write_task_complete() {
  local file="$1" turn_id="$2" duration_ms="$3"
  local ts completed_at
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  completed_at=$(date +%s)
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_complete","turn_id":"%s","last_agent_message":"done","completed_at":%d,"duration_ms":%d}}\n' \
    "$ts" "$turn_id" "$completed_at" "$duration_ms" >> "$file"
}

# Write an exec_command_end event (tool usage)
write_exec_command() {
  local file="$1" cmd_type="${2:-search}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"exec_command_end","call_id":"call_test","process_id":"1234","turn_id":"turn-1","command":["/bin/bash","-c","echo test"],"cwd":"/tmp","parsed_cmd":[{"type":"%s","cmd":"echo test","path":"."}],"source":"test","stdout":"","stderr":"","aggregated_output":"test","exit_code":0,"duration":{"secs":0,"nanos":1000},"formatted_output":"","status":"completed"}}\n' \
    "$ts" "$cmd_type" >> "$file"
}

# Write a null-info token_count event (first event often has null info)
write_null_token_count() {
  local file="$1"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex"}}}\n' \
    "$ts" >> "$file"
}

# Run the Codex statusline script
run_codex() {
  local preset="${1:-vitals}" columns="${2:-120}"

  # Clear caches
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/codex-statusline"
  rm -f "$cache_dir"/*.cache 2>/dev/null || true

  export CODEX_STATUSLINE_PRESET="$preset"
  export CODEX_HOME="$CODEX_HOME"
  export COLUMNS="$columns"
  export CODEX_SL_ASCII=1

  STATUSLINE_RAW=$(bash "$CODEX_SCRIPT" 2>/dev/null) || true
  STATUSLINE_PLAIN=$(printf '%s' "$STATUSLINE_RAW" | strip_ansi)
}

begin_suite "codex"

# ================================================================
# Test 1: No session — shows "no active session"
# ================================================================

CODEX_HOME="$_TEST_HOME/.codex-empty"
mkdir -p "$CODEX_HOME"
run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "no active session" "no session shows message"

# ================================================================
# Test 2: Basic session with token data
# ================================================================

setup_codex_session "basic-001" "gpt-5.3-codex" "/tmp/my-project"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/my-project"
write_null_token_count "$SESSION_FILE"
write_task_started "$SESSION_FILE" "turn-1" 200000
write_token_count "$SESSION_FILE" 50000 40000 5000 2000 200000
write_task_complete "$SESSION_FILE" "turn-1" 30000
# Touch the file to make it recent
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "gpt-5.3-codex" "shows model name"
assert_contains "$STATUSLINE_PLAIN" "my-project" "shows directory name"
assert_contains "$STATUSLINE_PLAIN" "context" "shows context"

# ================================================================
# Test 3: Essential preset shows turn info
# ================================================================

run_codex "essential" 120
assert_contains "$STATUSLINE_PLAIN" "turn" "essential shows turn info"
assert_contains "$STATUSLINE_PLAIN" "in" "turn shows input tokens"
assert_contains "$STATUSLINE_PLAIN" "cache" "turn shows cache tokens"
assert_contains "$STATUSLINE_PLAIN" "reason" "turn shows reasoning tokens"
assert_contains "$STATUSLINE_PLAIN" "out" "turn shows output tokens"

# ================================================================
# Test 4: Full preset shows session and daily
# ================================================================

run_codex "full" 120
assert_contains "$STATUSLINE_PLAIN" "session" "full shows session row"
assert_contains "$STATUSLINE_PLAIN" "token" "session shows tokens"
assert_contains "$STATUSLINE_PLAIN" "cost" "session shows cost"
assert_contains "$STATUSLINE_PLAIN" "turns" "session shows turn count"

# ================================================================
# Test 5: Context percentage calculation
# ================================================================

setup_codex_session "ctx-001" "gpt-4.1" "/tmp/ctx-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-4.1" "/tmp/ctx-test"
write_token_count "$SESSION_FILE" 100000 80000 10000 5000 200000
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "55%" "context pct = 110k/200k = 55%"

# ================================================================
# Test 6: High context percentage triggers warning
# ================================================================

setup_codex_session "ctx-high-001" "gpt-4.1" "/tmp/ctx-high"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-4.1" "/tmp/ctx-high"
# 190k / 200k = 95%
write_token_count "$SESSION_FILE" 180000 100000 10000 5000 200000
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "95%" "high context shows 95%"
assert_contains "$STATUSLINE_PLAIN" "!" "high context shows warning"

# ================================================================
# Test 7: Cache hit rate display
# ================================================================

setup_codex_session "cache-001" "gpt-5.3-codex" "/tmp/cache-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/cache-test"
write_token_count "$SESSION_FILE" 100000 90000 5000 1000 258400
touch "$SESSION_FILE"

run_codex "essential" 120
assert_contains "$STATUSLINE_PLAIN" "cache" "shows cache hit rate"
assert_contains "$STATUSLINE_PLAIN" "90%" "90k/100k = 90% cache"

# ================================================================
# Test 8: Session status badges
# ================================================================

# ENDED session (file is old)
setup_codex_session "ended-001" "gpt-5.3-codex" "/tmp/ended"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/ended"
write_token_count "$SESSION_FILE" 10000 5000 1000 500 200000
# Make it old (> 120s)
touch -t 202601010000 "$SESSION_FILE" 2>/dev/null || true

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "ENDED" "old session shows ENDED"

# ================================================================
# Test 9: Preset row counts
# ================================================================

setup_codex_session "rows-001" "gpt-5.3-codex" "/tmp/row-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/row-test"
write_token_count "$SESSION_FILE" 50000 40000 5000 2000 200000
write_task_complete "$SESSION_FILE" "turn-1" 30000
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_line_count "$STATUSLINE_PLAIN" "1" "minimal = 1 row"

run_codex "essential" 120
assert_line_count "$STATUSLINE_PLAIN" "2" "essential = 2 rows"

# ================================================================
# Test 10: Model from config.toml fallback
# ================================================================

# Create session without session_meta line
setup_codex_session "nometadata-001" "gpt-5.4" "/tmp/nometa"
: > "$SESSION_FILE"
# No session_meta, just token events
write_null_token_count "$SESSION_FILE"
write_token_count "$SESSION_FILE" 10000 5000 1000 500 200000
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "gpt-5.4" "falls back to model from config.toml"

# ================================================================
# Test 11: Cost calculation (OpenAI pricing)
# ================================================================

setup_codex_session "cost-001" "gpt-5.3-codex" "/tmp/cost-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/cost-test"
# 1M input (800k cached), 100k output
# Cost = (200k * 2.50 + 800k * 1.25 + 100k * 10.00) / 1M
#      = (500000 + 1000000 + 1000000) / 1000000 = $2.50
write_token_count "$SESSION_FILE" 1000000 800000 100000 50000 200000
write_task_complete "$SESSION_FILE" "turn-1" 120000
touch "$SESSION_FILE"

run_codex "full" 120
assert_contains "$STATUSLINE_PLAIN" "cost" "shows cost"
assert_contains "$STATUSLINE_PLAIN" "$2.50" "cost = $2.50 for gpt-5.3-codex"

# ================================================================
# Test 12: Tool count display
# ================================================================

setup_codex_session "tools-001" "gpt-5.3-codex" "/tmp/tools-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/tools-test"
write_task_started "$SESSION_FILE" "turn-1" 200000
write_exec_command "$SESSION_FILE" "search"
write_exec_command "$SESSION_FILE" "search"
write_exec_command "$SESSION_FILE" "edit"
write_token_count "$SESSION_FILE" 50000 40000 5000 2000 200000
write_task_complete "$SESSION_FILE" "turn-1" 30000
touch "$SESSION_FILE"

run_codex "full" 120
assert_contains "$STATUSLINE_PLAIN" "tools" "shows tools count"

# ================================================================
# Test 13: Daily aggregation with multiple sessions
# ================================================================

setup_codex_session "daily-001" "gpt-5.3-codex" "/tmp/daily-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/daily-test"
write_token_count "$SESSION_FILE" 100000 80000 10000 3000 200000
write_task_complete "$SESSION_FILE" "turn-1" 60000
touch "$SESSION_FILE"

# Create a second session file
SESSION_FILE2="$CODEX_SESSIONS_DIR/rollout-$(date +%Y-%m-%d)T01-00-00-daily-002.jsonl"
: > "$SESSION_FILE2"
write_session_meta "$SESSION_FILE2" "gpt-5.3-codex" "/tmp/daily-test"
write_token_count "$SESSION_FILE2" 200000 150000 20000 8000 200000
write_task_complete "$SESSION_FILE2" "turn-1" 90000
touch "$SESSION_FILE2"

run_codex "full" 120
assert_contains "$STATUSLINE_PLAIN" "day-total" "shows daily summary"
assert_contains "$STATUSLINE_PLAIN" "sessions" "shows session count"

# ================================================================
# Test 14: Compact tier (narrow terminal)
# ================================================================

setup_codex_session "compact-001" "gpt-5.3-codex" "/tmp/compact-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/compact-test"
write_token_count "$SESSION_FILE" 50000 40000 5000 2000 200000
touch "$SESSION_FILE"

run_codex "minimal" 60
assert_contains "$STATUSLINE_PLAIN" "ctx" "compact shows ctx label"

# ================================================================
# Test 15: Reasoning tokens display
# ================================================================

setup_codex_session "reason-001" "gpt-5.3-codex" "/tmp/reason-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/reason-test"
# Large reasoning tokens
write_token_count "$SESSION_FILE" 50000 40000 5000 15000 258400
touch "$SESSION_FILE"

run_codex "essential" 120
assert_contains "$STATUSLINE_PLAIN" "reason" "shows reasoning tokens"
assert_contains "$STATUSLINE_PLAIN" "15k" "reason shows 15k"

# ================================================================
# Test 16: Budget alert
# ================================================================

setup_codex_session "budget-001" "gpt-5.3-codex" "/tmp/budget-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/budget-test"
write_token_count "$SESSION_FILE" 1000000 800000 100000 50000 200000
write_task_complete "$SESSION_FILE" "turn-1" 120000
touch "$SESSION_FILE"

export CODEX_SL_DAILY_BUDGET=5
run_codex "full" 120
assert_contains "$STATUSLINE_PLAIN" "budget" "shows budget alert"
unset CODEX_SL_DAILY_BUDGET

# ================================================================
# Test 17: Vitals preset shows system info
# ================================================================

setup_codex_session "vitals-001" "gpt-5.3-codex" "/tmp/vitals-test"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/vitals-test"
write_token_count "$SESSION_FILE" 50000 40000 5000 2000 200000
write_task_complete "$SESSION_FILE" "turn-1" 30000
touch "$SESSION_FILE"

run_codex "vitals" 120
assert_contains "$STATUSLINE_PLAIN" "cpu" "vitals shows CPU"
assert_contains "$STATUSLINE_PLAIN" "mem" "vitals shows memory"
assert_contains "$STATUSLINE_PLAIN" "gpu" "vitals shows GPU"

# ================================================================
# Test 18: Context size label formatting
# ================================================================

setup_codex_session "ctxlabel-001" "gpt-5.3-codex" "/tmp/ctx-label"
: > "$SESSION_FILE"
write_session_meta "$SESSION_FILE" "gpt-5.3-codex" "/tmp/ctx-label"
write_token_count "$SESSION_FILE" 10000 5000 1000 500 258400
touch "$SESSION_FILE"

run_codex "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "258k" "shows context size as 258k"

end_suite
teardown_test_env
