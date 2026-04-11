#!/usr/bin/env bash
# ================================================================
#  Test Suite: Git Info Display
#  Tests branch name, dirty status, ahead/behind, operation states
# ================================================================

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUITE_DIR/../framework.sh"

setup_test_env
seed_vitals_cache

# Git config for isolated HOME
git config --global user.email "test@test.com" 2>/dev/null || true
git config --global user.name "Test" 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true

begin_suite "git"

# Helper: create a temp git repo
create_test_repo() {
  local repo_dir
  repo_dir=$(mktemp -d "${_TEST_TMPDIR}/test_repo.XXXXXX")
  cd "$repo_dir" || return 1
  git init -q
  git checkout -q -b main 2>/dev/null || true
  echo "initial" > README.md
  git add README.md
  git commit -q -m "initial" --no-gpg-sign
  printf '%s' "$repo_dir"
}

# ================================================================
# Clean repository
# ================================================================
REPO=$(create_test_repo)
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$REPO\"}}")" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "main" "git shows branch name 'main'"
assert_not_contains "$STATUSLINE_PLAIN" "[+" "clean repo has no staged indicator"
assert_not_contains "$STATUSLINE_PLAIN" "[?" "clean repo has no untracked indicator"

# ================================================================
# Dirty: staged files
# ================================================================
echo "new content" > "$REPO/newfile.txt"
cd "$REPO" && git add newfile.txt
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$REPO\"}}")" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "+" "staged file shows +"

# ================================================================
# Dirty: untracked files
# ================================================================
cd "$REPO" && git reset HEAD newfile.txt >/dev/null 2>&1 || true
echo "untracked" > "$REPO/untracked.txt"
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$REPO\"}}")" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "?" "untracked files show ?"

# ================================================================
# MERGING state
# ================================================================
cd "$REPO" || true
git checkout -q -b feature 2>/dev/null
echo "feature change" > "$REPO/conflict.txt"
git add conflict.txt && git commit -q -m "feature" --no-gpg-sign
git checkout -q main
echo "main change" > "$REPO/conflict.txt"
git add conflict.txt && git commit -q -m "main conflict" --no-gpg-sign
git merge feature 2>/dev/null || true
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$REPO\"}}")" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "MERGING" "merge conflict shows MERGING state"
cd "$REPO" && git merge --abort 2>/dev/null || true

# ================================================================
# Non-git directory
# ================================================================
NOGIT_DIR=$(mktemp -d "${_TEST_TMPDIR}/nogit.XXXXXX")
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$NOGIT_DIR\"}}")" "minimal" 120
assert_not_contains "$STATUSLINE_PLAIN" "REBASING" "non-git dir has no git state"

# ================================================================
# HOME directory shown as ~
# ================================================================
run_statusline "$(make_json "{\"workspace\":{\"current_dir\":\"$HOME\"}}")" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "~" "HOME dir displayed as ~"

# ================================================================
# Empty directory
# ================================================================
run_statusline "$(make_json '{"workspace":{"current_dir":""}}')" "minimal" 120
assert_contains "$STATUSLINE_PLAIN" "Sonnet" "empty dir still shows model"

end_suite
teardown_test_env
