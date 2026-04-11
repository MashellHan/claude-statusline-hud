#!/usr/bin/env bash
# ================================================================
#  Test Suite: Width Tiers
#  Verifies compact/normal/wide layouts differ correctly
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

begin_suite "widths"

JSON=$(cat "$FIXTURES_DIR/full-session.json")

# ================================================================
# Model label truncation per tier
# ================================================================

# compact (<70): model label = first word only ("Claude")
run_statusline "$JSON" "minimal" 60
assert_contains "$STATUSLINE_PLAIN" "Claude" "compact: model label starts with first word"
# In compact, the full name with parens should not appear
assert_not_contains "$STATUSLINE_PLAIN" "(1M context)" "compact: no parenthetical in model label"

# normal (70-99): model label without parenthetical
run_statusline "$JSON" "minimal" 80
assert_contains "$STATUSLINE_PLAIN" "Opus" "normal: model label includes model name"
assert_not_contains "$STATUSLINE_PLAIN" "(1M context)" "normal: no parenthetical in model label"

# wide (>=100): full model label
run_statusline "$JSON" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "Opus 4.5" "wide: full model label shown"
assert_contains "$STATUSLINE_PLAIN" "(1M context)" "wide: parenthetical included"

# ================================================================
# Hidden elements in compact
# ================================================================

run_statusline "$JSON" "vitals" 60
# Compact hides: cache%, speed, disk, bat, load
assert_not_contains "$STATUSLINE_PLAIN" "disk" "compact: disk hidden"
assert_not_contains "$STATUSLINE_PLAIN" "bat" "compact: battery hidden"
assert_not_contains "$STATUSLINE_PLAIN" "load" "compact: load hidden"
# But cpu, mem, gpu should still show
assert_contains "$STATUSLINE_PLAIN" "cpu" "compact: cpu still shown"
assert_contains "$STATUSLINE_PLAIN" "mem" "compact: mem still shown"

# ================================================================
# Normal width shows everything
# ================================================================

run_statusline "$JSON" "vitals" 80
assert_contains "$STATUSLINE_PLAIN" "disk" "normal: disk shown"
assert_contains "$STATUSLINE_PLAIN" "load" "normal: load shown"

# ================================================================
# Wide shows everything with wider bars
# ================================================================

run_statusline "$JSON" "vitals" 120
assert_contains "$STATUSLINE_PLAIN" "disk" "wide: disk shown"
assert_contains "$STATUSLINE_PLAIN" "load" "wide: load shown"
assert_contains "$STATUSLINE_PLAIN" "cpu" "wide: cpu shown"

end_suite
teardown_test_env
