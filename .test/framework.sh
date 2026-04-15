#!/usr/bin/env bash
# ================================================================
#  Test Framework for Claude Statusline HUD
#  Pure bash + jq — no external test runners required
# ================================================================

set -eo pipefail

# --- Paths ---
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"
STATUSLINE_SCRIPT="$PROJECT_DIR/plugins/claude-statusline-hud/scripts/statusline.sh"
FIXTURES_DIR="$TEST_DIR/fixtures"
REPORTS_DIR="$TEST_DIR/reports"
SNAPSHOTS_DIR="$TEST_DIR/snapshots"

# --- State ---
_SUITE_NAME=""
_TEST_NAME=""
_PASS_COUNT=0
_FAIL_COUNT=0
_TOTAL_COUNT=0
_FAILURES=()       # array of "suite|test|expected|actual"
_SUITE_PASS=0
_SUITE_FAIL=0
_SUITE_RESULTS=()  # array of "suite:pass:fail"

# --- Isolated environment ---
_ORIG_HOME="$HOME"
_ORIG_TMPDIR="${TMPDIR:-/tmp}"
_TEST_TMPDIR=""
_TEST_HOME=""

# ================================================================
#  Setup / Teardown
# ================================================================

setup_test_env() {
  # Create isolated temp dirs to prevent cache interference
  _TEST_TMPDIR=$(mktemp -d "${_ORIG_TMPDIR}/claude_sl_test.XXXXXX")
  _TEST_HOME=$(mktemp -d "${_ORIG_TMPDIR}/claude_sl_home.XXXXXX")
  mkdir -p "$_TEST_HOME/.claude"

  export HOME="$_TEST_HOME"
  export TMPDIR="$_TEST_TMPDIR"

  # Default to ASCII mode for deterministic bar comparison
  export CLAUDE_SL_ASCII="${CLAUDE_SL_ASCII:-1}"

  # Clear any stale caches
  rm -f /tmp/.claude_sl_* 2>/dev/null || true
}

teardown_test_env() {
  rm -rf "$_TEST_TMPDIR" 2>/dev/null || true
  rm -rf "$_TEST_HOME" 2>/dev/null || true
  export HOME="$_ORIG_HOME"
  export TMPDIR="$_ORIG_TMPDIR"
  unset CLAUDE_STATUSLINE_PRESET 2>/dev/null || true
  unset COLUMNS 2>/dev/null || true
  unset CLAUDE_SL_ASCII 2>/dev/null || true
  unset CLAUDE_SL_UNICODE 2>/dev/null || true
  unset CLAUDE_SL_THEME 2>/dev/null || true
  unset COLORFGBG 2>/dev/null || true
}

# Per-test isolation (clears caches between tests within a suite)
setup_test() {
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
  rm -f "${_TEST_TMPDIR}"/.claude_sl_* 2>/dev/null || true
  rm -f /tmp/.claude_sl_* 2>/dev/null || true
  rm -f "$cache_dir"/daily_*.cache 2>/dev/null || true
  rm -f "$cache_dir"/activity_*.cache 2>/dev/null || true
  rm -f "$cache_dir"/sessmsg_*.cache 2>/dev/null || true
  rm -f "$cache_dir"/git_*.cache 2>/dev/null || true
}

# ================================================================
#  ANSI Utilities
# ================================================================

strip_ansi() {
  # Remove all ANSI escape sequences
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[0-9;]*m//g'
}

# Check if raw output contains a specific ANSI color code
has_color() {
  local raw="$1" color_code="$2"
  printf '%s' "$raw" | grep -qF "$color_code"
}

# ================================================================
#  Run statusline.sh
# ================================================================

# Run the statusline script with given JSON input and environment
# Usage: run_statusline <json_string> [preset] [columns]
# Returns: sets STATUSLINE_RAW and STATUSLINE_PLAIN
run_statusline() {
  local json="$1"
  local preset="${2:-vitals}"
  local columns="${3:-120}"

  setup_test

  export CLAUDE_STATUSLINE_PRESET="$preset"
  export COLUMNS="$columns"

  STATUSLINE_RAW=$(printf '%s' "$json" | bash "$STATUSLINE_SCRIPT" 2>/dev/null) || true
  STATUSLINE_PLAIN=$(printf '%s' "$STATUSLINE_RAW" | strip_ansi)
}

# Run with a fixture file
run_fixture() {
  local fixture_name="$1"
  local preset="${2:-vitals}"
  local columns="${3:-120}"
  local fixture_file="$FIXTURES_DIR/${fixture_name}.json"

  if [ ! -f "$fixture_file" ]; then
    echo "ERROR: Fixture not found: $fixture_file" >&2
    return 1
  fi

  run_statusline "$(cat "$fixture_file")" "$preset" "$columns"
}

# ================================================================
#  Assertions
# ================================================================

# Assert exact string equality
assert_equals() {
  local expected="$1" actual="$2" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  if [ "$expected" = "$actual" ]; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-assert_equals}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-assert_equals}"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    _FAILURES+=("${_SUITE_NAME}|${msg:-assert_equals}|${expected}|${actual}")
    return 1
  fi
}

# Assert output contains substring
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-contains '$needle'}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-contains '$needle'}"
    printf '    expected to contain: %s\n' "$needle"
    printf '    in: %s\n' "$(printf '%s' "$haystack" | head -5)"
    _FAILURES+=("${_SUITE_NAME}|${msg:-contains}|contains:${needle}|not found")
    return 1
  fi
}

# Assert output does NOT contain substring
assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-not contains '$needle'}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-not contains '$needle'}"
    printf '    expected NOT to contain: %s\n' "$needle"
    _FAILURES+=("${_SUITE_NAME}|${msg:-not_contains}|not_contains:${needle}|found")
    return 1
  fi
}

# Assert output matches regex
assert_matches() {
  local haystack="$1" pattern="$2" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  if printf '%s' "$haystack" | grep -qE -- "$pattern"; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-matches '$pattern'}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-matches '$pattern'}"
    printf '    expected to match: %s\n' "$pattern"
    _FAILURES+=("${_SUITE_NAME}|${msg:-matches}|regex:${pattern}|no match")
    return 1
  fi
}

# Assert exact line count
assert_line_count() {
  local text="$1" expected="$2" msg="${3:-}"
  local actual
  if [ -z "$text" ]; then
    actual=0
  else
    actual=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  fi
  assert_equals "$expected" "$actual" "${msg:-line_count=$expected}"
}

# Assert line count within range [min, max]
assert_line_count_range() {
  local text="$1" min="$2" max="$3" msg="${4:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))
  local actual
  if [ -z "$text" ]; then
    actual=0
  else
    actual=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
  fi

  if [ "$actual" -ge "$min" ] 2>/dev/null && [ "$actual" -le "$max" ] 2>/dev/null; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s (got %d lines)\n' "${msg:-line_count in [$min,$max]}" "$actual"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-line_count in [$min,$max]}"
    printf '    expected: %d-%d lines, got: %d\n' "$min" "$max" "$actual"
    _FAILURES+=("${_SUITE_NAME}|${msg:-line_count_range}|${min}-${max}|${actual}")
    return 1
  fi
}

# Assert raw ANSI output contains specific color escape
assert_has_ansi_color() {
  local raw="$1" color_name="$2" msg="${3:-}"
  local color_code
  case "$color_name" in
    green)   color_code=$'\033[32m' ;;
    yellow)  color_code=$'\033[33m' ;;
    red)     color_code=$'\033[31m' ;;
    cyan)    color_code=$'\033[36m' ;;
    magenta) color_code=$'\033[35m' ;;
    blue)    color_code=$'\033[34m' ;;
    bold)    color_code=$'\033[1m' ;;
    dim)     color_code=$'\033[2m' ;;
    *)       color_code="$color_name" ;;
  esac

  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))
  if printf '%s' "$raw" | grep -qF -- "$color_code"; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-has color $color_name}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-has color $color_name}"
    printf '    expected ANSI color: %s\n' "$color_name"
    _FAILURES+=("${_SUITE_NAME}|${msg:-has_color}|color:${color_name}|not found")
    return 1
  fi
}

# Assert numeric comparison
assert_numeric_ge() {
  local actual="$1" threshold="$2" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  if [ "$actual" -ge "$threshold" ] 2>/dev/null; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s (got %s)\n' "${msg:-$actual >= $threshold}" "$actual"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-$actual >= $threshold}"
    printf '    expected: >= %s, got: %s\n' "$threshold" "$actual"
    _FAILURES+=("${_SUITE_NAME}|${msg:-numeric_ge}|>=${threshold}|${actual}")
    return 1
  fi
}

# Assert script exits without error
assert_no_error() {
  local json="$1" preset="${2:-vitals}" msg="${3:-}"
  _TOTAL_COUNT=$((_TOTAL_COUNT + 1))

  setup_test
  export CLAUDE_STATUSLINE_PRESET="$preset"
  export COLUMNS=120

  if printf '%s' "$json" | bash "$STATUSLINE_SCRIPT" >/dev/null 2>&1; then
    _PASS_COUNT=$((_PASS_COUNT + 1))
    _SUITE_PASS=$((_SUITE_PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${msg:-no error}"
    return 0
  else
    _FAIL_COUNT=$((_FAIL_COUNT + 1))
    _SUITE_FAIL=$((_SUITE_FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n' "${msg:-no error}"
    _FAILURES+=("${_SUITE_NAME}|${msg:-no_error}|exit 0|exit non-zero")
    return 1
  fi
}

# ================================================================
#  Suite Management
# ================================================================

begin_suite() {
  _SUITE_NAME="$1"
  _SUITE_PASS=0
  _SUITE_FAIL=0
  printf '\n\033[1m━━━ %s ━━━\033[0m\n' "$_SUITE_NAME"
}

end_suite() {
  local total=$((_SUITE_PASS + _SUITE_FAIL))
  if [ "$_SUITE_FAIL" -eq 0 ]; then
    printf '\033[32m  ✓ %s: %d/%d passed\033[0m\n' "$_SUITE_NAME" "$_SUITE_PASS" "$total"
  else
    printf '\033[31m  ✗ %s: %d/%d passed (%d failed)\033[0m\n' "$_SUITE_NAME" "$_SUITE_PASS" "$total" "$_SUITE_FAIL"
  fi
  _SUITE_RESULTS+=("${_SUITE_NAME}:${_SUITE_PASS}:${_SUITE_FAIL}")
}

# ================================================================
#  Report Generation
# ================================================================

generate_report() {
  local start_time="$1"
  local end_time=$(date +%s)
  local duration_ms=$(( (end_time - start_time) * 1000 ))
  local timestamp=$(date '+%Y%m%d-%H%M%S')
  local report_json="$REPORTS_DIR/report-${timestamp}.json"
  local report_txt="$REPORTS_DIR/report-${timestamp}.txt"

  mkdir -p "$REPORTS_DIR"

  # --- Build JSON report ---
  local suites_json="{"
  local first=true
  for sr in "${_SUITE_RESULTS[@]}"; do
    IFS=':' read -r name pass fail <<< "$sr"
    local total=$((pass + fail))
    [ "$first" = true ] && first=false || suites_json="${suites_json},"
    suites_json="${suites_json}\"${name}\":{\"total\":${total},\"passed\":${pass},\"failed\":${fail}}"
  done
  suites_json="${suites_json}}"

  local failures_json="["
  first=true
  for f in "${_FAILURES[@]}"; do
    IFS='|' read -r suite test expected actual <<< "$f"
    [ "$first" = true ] && first=false || failures_json="${failures_json},"
    # Escape JSON strings
    expected=$(printf '%s' "$expected" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    actual=$(printf '%s' "$actual" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    failures_json="${failures_json}{\"suite\":\"${suite}\",\"test\":\"${test}\",\"expected\":\"${expected}\",\"actual\":\"${actual}\"}"
  done
  failures_json="${failures_json}]"

  # --- Regression detection ---
  local regression_json="{\"detected\":false,\"new_failures\":[],\"fixed\":[]}"
  local prev_report=$(ls -t "$REPORTS_DIR"/report-*.json 2>/dev/null | head -1)
  if [ -n "$prev_report" ] && [ -f "$prev_report" ]; then
    local prev_failures=$(jq -r '.failures[].test' "$prev_report" 2>/dev/null | sort)
    local curr_failures=$(printf '%s\n' "${_FAILURES[@]}" | cut -d'|' -f2 | sort)

    local new_fails=$(comm -13 <(printf '%s\n' "$prev_failures") <(printf '%s\n' "$curr_failures") 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
    local fixed=$(comm -23 <(printf '%s\n' "$prev_failures") <(printf '%s\n' "$curr_failures") 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")

    local has_regression=false
    [ "$new_fails" != "[]" ] && has_regression=true
    regression_json="{\"detected\":${has_regression},\"new_failures\":${new_fails},\"fixed\":${fixed}}"
  fi

  cat > "$report_json" <<EOF
{
  "timestamp": "$(date '+%Y-%m-%dT%H:%M:%S%z')",
  "duration_ms": ${duration_ms},
  "total": ${_TOTAL_COUNT},
  "passed": ${_PASS_COUNT},
  "failed": ${_FAIL_COUNT},
  "suites": ${suites_json},
  "failures": ${failures_json},
  "regression": ${regression_json}
}
EOF

  # --- Human-readable report ---
  {
    printf '═══ Claude Statusline HUD Test Report ═══\n'
    printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Duration: %s.%ss\n\n' "$((duration_ms / 1000))" "$(( (duration_ms % 1000) / 100 ))"
    printf 'Suite Results:\n'
    for sr in "${_SUITE_RESULTS[@]}"; do
      IFS=':' read -r name pass fail <<< "$sr"
      local total=$((pass + fail))
      if [ "$fail" -eq 0 ]; then
        printf '  ✓ %-20s %d/%d\n' "$name" "$pass" "$total"
      else
        printf '  ✗ %-20s %d/%d  (%d FAILED)\n' "$name" "$pass" "$total" "$fail"
      fi
    done
    local pct=0
    [ "$_TOTAL_COUNT" -gt 0 ] && pct=$((_PASS_COUNT * 100 / _TOTAL_COUNT))
    printf '\nTotal: %d/%d PASSED (%d%%)\n' "$_PASS_COUNT" "$_TOTAL_COUNT" "$pct"

    if [ "${#_FAILURES[@]}" -gt 0 ]; then
      printf '\nFAILURES:\n'
      for f in "${_FAILURES[@]}"; do
        IFS='|' read -r suite test expected actual <<< "$f"
        printf '  [%s] %s\n' "$suite" "$test"
        printf '    Expected: %s\n' "$expected"
        printf '    Actual:   %s\n' "$actual"
      done
    fi
  } | tee "$report_txt"

  # --- Prune old reports (keep last 10) ---
  local report_count=$(ls "$REPORTS_DIR"/report-*.json 2>/dev/null | wc -l | tr -d ' ')
  if [ "$report_count" -gt 10 ]; then
    ls -t "$REPORTS_DIR"/report-*.json | tail -n +11 | while read -r old; do
      rm -f "$old" "${old%.json}.txt"
    done
  fi

  echo ""
  echo "Reports saved to:"
  echo "  JSON: $report_json"
  echo "  Text: $report_txt"
}

# ================================================================
#  Fixture Helpers
# ================================================================

# Generate a JSON fixture inline with custom overrides
make_json() {
  local overrides="${1:-}"
  local base='{
    "model": {"display_name": "Claude Sonnet 4.6"},
    "workspace": {"current_dir": "/Users/test/project"},
    "context_window": {
      "used_percentage": 45,
      "current_usage": {
        "input_tokens": 50000,
        "cache_creation_input_tokens": 10000,
        "cache_read_input_tokens": 30000
      },
      "total_output_tokens": 15000,
      "context_window_size": 200000
    },
    "cost": {
      "total_cost_usd": 1.25,
      "total_duration_ms": 300000,
      "total_api_duration_ms": 180000,
      "total_lines_added": 150,
      "total_lines_removed": 30
    },
    "vim": {"mode": ""},
    "agent": {"name": ""},
    "worktree": {"name": "", "branch": ""},
    "exceeds_200k_tokens": false,
    "transcript_path": ""
  }'

  if [ -n "$overrides" ]; then
    printf '%s' "$base" | jq ". * $overrides"
  else
    printf '%s' "$base"
  fi
}

# Seed the system vitals cache with known values
seed_vitals_cache() {
  local cpu="${1:-25}" mem_used="${2:-8.5G}" mem_total="${3:-16}" mem_pct="${4:-53}"
  local gpu="${5:-10}" disk_used="${6:-120G}" disk_total="${7:-500G}" disk_pct="${8:-24}"
  local bv="${9:-85}" load="${10:-2.1}"

  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
  mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
  local cache_file="${cache_dir}/sys_$(id -u).cache"
  printf "CPU_USED=%q\nMEM_USED=%q\nMEM_TOTAL_GB=%q\nMEM_PCT=%q\nGPU_PCT=%q\nDISK_USED=%q\nDISK_TOTAL=%q\nDISK_PCT=%q\nBV=%q\nLOAD_AVG=%q\n" \
    "$cpu" "$mem_used" "$mem_total" "$mem_pct" \
    "$gpu" "$disk_used" "$disk_total" "$disk_pct" \
    "$bv" "$load" > "$cache_file"
}
