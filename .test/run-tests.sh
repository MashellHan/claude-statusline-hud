#!/usr/bin/env bash
# ================================================================
#  Claude Statusline HUD — Test Runner
#  Runs all test suites and generates reports
# ================================================================
#
#  Usage:
#    ./run-tests.sh              # Run all suites
#    ./run-tests.sh presets      # Run single suite
#    ./run-tests.sh -q           # Quiet mode (summary only)
#    ./run-tests.sh -l           # List available suites
#
# ================================================================

set -eo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES_DIR="$TEST_DIR/suites"
REPORTS_DIR="$TEST_DIR/reports"

source "$TEST_DIR/framework.sh"

# --- Parse arguments ---
QUIET=false
LIST_ONLY=false
SELECTED_SUITES=()

for arg in "$@"; do
  case "$arg" in
    -q|--quiet)  QUIET=true ;;
    -l|--list)   LIST_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS] [SUITE...]"
      echo ""
      echo "Options:"
      echo "  -q, --quiet   Summary only, suppress per-test output"
      echo "  -l, --list    List available suites and exit"
      echo "  -h, --help    Show this help"
      echo ""
      echo "Available suites:"
      for f in "$SUITES_DIR"/test-*.sh; do
        name=$(basename "$f" .sh | sed 's/^test-//')
        echo "  $name"
      done
      exit 0
      ;;
    *)
      SELECTED_SUITES+=("$arg")
      ;;
  esac
done

if [ "$LIST_ONLY" = true ]; then
  echo "Available test suites:"
  for f in "$SUITES_DIR"/test-*.sh; do
    name=$(basename "$f" .sh | sed 's/^test-//')
    echo "  $name"
  done
  exit 0
fi

# --- Determine which suites to run ---
SUITES_TO_RUN=()
if [ "${#SELECTED_SUITES[@]}" -gt 0 ]; then
  for s in "${SELECTED_SUITES[@]}"; do
    suite_file="$SUITES_DIR/test-${s}.sh"
    if [ -f "$suite_file" ]; then
      SUITES_TO_RUN+=("$suite_file")
    else
      echo "ERROR: Suite not found: $s (looked for $suite_file)" >&2
      exit 1
    fi
  done
else
  for f in "$SUITES_DIR"/test-*.sh; do
    SUITES_TO_RUN+=("$f")
  done
fi

# --- Banner ---
printf '\n\033[1m╔═══════════════════════════════════════════════════╗\033[0m\n'
printf '\033[1m║     Claude Statusline HUD — Test Runner           ║\033[0m\n'
printf '\033[1m╚═══════════════════════════════════════════════════╝\033[0m\n\n'
printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'Suites: %d\n' "${#SUITES_TO_RUN[@]}"
printf 'Script: %s\n\n' "$STATUSLINE_SCRIPT"

# --- Check dependencies ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install: brew install jq" >&2
  exit 1
fi

# --- Run suites and capture output ---
START_TIME=$(date +%s)

_PASS_COUNT=0
_FAIL_COUNT=0
_TOTAL_COUNT=0
_FAILURES=()
_SUITE_RESULTS=()

for suite_file in "${SUITES_TO_RUN[@]}"; do
  suite_name=$(basename "$suite_file" .sh | sed 's/^test-//')
  output=$(bash "$suite_file" 2>&1) || true

  # Display output
  if [ "$QUIET" = true ]; then
    summary=$(printf '%s\n' "$output" | grep -E '(✓|✗).*passed' | tail -1)
    [ -n "$summary" ] && printf '%s\n' "$summary"
  else
    printf '%s\n' "$output"
  fi

  # Count passes and fails from output (strip ANSI first)
  clean_output=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\[[0-9;]*m//g')
  s_pass=$(printf '%s\n' "$clean_output" | grep -c '  ✓' || true)
  s_fail=$(printf '%s\n' "$clean_output" | grep -c '  ✗' || true)

  _PASS_COUNT=$((_PASS_COUNT + s_pass))
  _FAIL_COUNT=$((_FAIL_COUNT + s_fail))
  _TOTAL_COUNT=$((_TOTAL_COUNT + s_pass + s_fail))
  _SUITE_RESULTS+=("${suite_name}:${s_pass}:${s_fail}")

  # Extract failure details
  while IFS= read -r fail_line; do
    if [ -n "$fail_line" ]; then
      test_name=$(printf '%s' "$fail_line" | sed 's/^  ✗ //')
      _FAILURES+=("${suite_name}|${test_name}|see output|see output")
    fi
  done < <(printf '%s\n' "$clean_output" | grep '  ✗' || true)
done

# --- Generate report ---
echo ""
printf '\033[1m═══ Generating Report ═══\033[0m\n'
generate_report "$START_TIME"

# --- Final status ---
echo ""
if [ "$_FAIL_COUNT" -eq 0 ]; then
  printf '\033[32m\033[1m✓ ALL %d TESTS PASSED\033[0m\n\n' "$_TOTAL_COUNT"
  exit 0
else
  printf '\033[31m\033[1m✗ %d/%d TESTS FAILED\033[0m\n\n' "$_FAIL_COUNT" "$_TOTAL_COUNT"
  exit 1
fi
