# Review 003 — Git Operation State & Housekeeping

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** 1743d73 (`feat: add git operation state detection and optimize git status`)  
**Previous Review:** review-002 (commit 9f2eed8)  
**LOC:** 579 (was 545, +34 net)

---

## Changes Summary

| Review Action Item | Status | Notes |
|--------------------|--------|-------|
| P0: Daily token/cost tracking | ❌ Not started | **Still top priority** |
| P2: Fix git cache isolation | ✅ Done | Per-directory hash key |
| P2: Add jq availability check | ✅ Done | Clear error message |
| P2: Consolidate git commands | ✅ Done | Single `git status --porcelain` |
| P2: Git operation state detection | ✅ Done | Feature 5 from roadmap |
| LOW: Clean up stale activity cache | ✅ Done | `find -mtime +1 -delete` |

**5 action items resolved in this commit.** Good velocity on the P2/LOW items, but P0 daily tracking is still missing.

---

## Detailed Review

### 1. jq Dependency Check (Lines 15–18)

```bash
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "[statusline-hud] ERROR: jq is required but not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi
```

**Verdict: Good.** Clear error message with platform-specific install instructions. Uses `command -v` (POSIX-compliant) instead of `which`.

**Minor nitpick:** This check runs on every invocation (~1ms). Since jq won't disappear mid-session, it could be cached. But 1ms is negligible — no action needed.

---

### 2. Stale Cache Cleanup (Line 24)

```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name '.claude_sl_activity_*' -mtime +1 -delete 2>/dev/null
```

**Verdict: Good approach, one concern.**

**Concern (LOW):** `find` with `-delete` runs on every invocation. On systems with many temp files, `find` scanning `/tmp` could take 10-50ms. Consider running this only once per day by checking a sentinel file:
```bash
_CLEANUP="/tmp/.claude_sl_cleanup_$(date +%Y%m%d)"
if [ ! -f "$_CLEANUP" ]; then
  find ... -delete 2>/dev/null
  touch "$_CLEANUP"
fi
```

But realistically, `/tmp` scanning is fast on modern systems. **No action required** unless performance profiling shows otherwise.

---

### 3. Git Cache Isolation (Line 237–238)

```bash
_DIR_HASH=$(printf '%s' "$DIR" | cksum | awk '{print $1}')
GIT_CACHE="/tmp/.claude_sl_git_${_DIR_HASH}"
```

**Verdict: Correct fix.** Exactly what review-002 recommended. Multiple sessions in different directories will now have independent git caches.

**Note:** This also generates stale git cache files over time. The cleanup at line 24 only targets `activity` caches. Consider adding `.claude_sl_git_*` to the cleanup pattern:
```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name '.claude_sl_*' -mtime +1 -delete 2>/dev/null
```
This single pattern covers all statusline cache files.

---

### 4. Git Status Consolidation (Lines 245–253)

**Before:** 3 separate commands: `git diff --cached --numstat`, `git diff --numstat`, `git ls-files --others`  
**After:** Single `git status --porcelain`

```bash
_GS_OUT=$(git -C "$DIR" status --porcelain 2>/dev/null)
gs=$(printf '%s\n' "$_GS_OUT" | grep -c '^[MADRC]')
gu=$(printf '%s\n' "$_GS_OUT" | grep -c '^.[MDRC]')
gq=$(printf '%s\n' "$_GS_OUT" | grep -c '^??')
```

**Verdict: Correct and faster (~60ms saved on uncached calls).**

**Bug (MEDIUM):** The staged file regex `'^[MADRC]'` is correct for most cases but misses:
- `D ` (deleted staged files) — wait, `D` is in the pattern, this is fine
- `R ` (renamed files) — included, fine
- Actually, the pattern looks correct for standard porcelain v1 output

**Potential edge case (LOW):** If `_GS_OUT` is empty, `printf '%s\n' "" | grep -c` returns `0` — correct. But the `if [ -n "$_GS_OUT" ]` guard already handles this. Clean.

**One subtle issue (MEDIUM):** The unstaged regex `'^.[MDRC]'` will match `??` files in the second character position if a file has `?M` status — but that's not a valid git status combination. `??` is untracked. However, untracked files do match `'^.[?]'` not `'^.[MDRC]'`, so this is fine.

Actually wait — `'^.[MDRC]'` also counts the second column of staged files. For example, `MM` (staged with unstaged modifications) would be counted in both `gs` and `gu`. This is **correct behavior** — the file has both staged and unstaged changes.

**Verdict: No bugs found.** The regexes correctly parse porcelain v1 format.

---

### 5. Git Operation State Detection (Lines 257–272)

```bash
_GIT_DIR=$(git -C "$DIR" rev-parse --git-dir 2>/dev/null)
GIT_STATE=""
if [ -d "${_GIT_DIR}/rebase-merge" ]; then
  _RB_CUR=$(cat "${_GIT_DIR}/rebase-merge/msgnum" 2>/dev/null)
  _RB_END=$(cat "${_GIT_DIR}/rebase-merge/end" 2>/dev/null)
  GIT_STATE="REBASING${_RB_CUR:+ ${_RB_CUR}/${_RB_END}}"
elif [ -d "${_GIT_DIR}/rebase-apply" ]; then
  GIT_STATE="REBASING"
elif [ -f "${_GIT_DIR}/MERGE_HEAD" ]; then
  GIT_STATE="MERGING"
elif [ -f "${_GIT_DIR}/CHERRY_PICK_HEAD" ]; then
  GIT_STATE="CHERRY-PICK"
elif [ -f "${_GIT_DIR}/BISECT_LOG" ]; then
  GIT_STATE="BISECTING"
fi
```

**Verdict: Well-implemented.** Covers all 5 major git operations that starship detects. The rebase progress (`3/7`) is a nice touch — only `rebase-merge` has `msgnum`/`end`, `rebase-apply` doesn't, which is correctly handled.

**Display (Line 294):**
```bash
[ -n "$GIT_STATE" ] && GIT_DISPLAY="${GIT_DISPLAY} ${RED}${BOLD}${GIT_STATE}${RST}"
```

RED + BOLD is appropriate — this is an unusual state that needs attention.

**Missing (LOW):** `revert` operations (`REVERT_HEAD` file) are not detected. Rare but could be added trivially.

**Cache integration:** The state is serialized into `GIT_INFO` pipe-delimited format (`GB|GD|GAB|GIT_STATE`) and cached for 10s. This is correct — the state is recovered from cache on subsequent calls.

**Potential issue (LOW):** If a git operation starts/completes within the 10s cache window, the display will be stale. This is acceptable — 10s is short enough. Operations like rebase/merge typically last minutes.

---

### 6. Cache Format Change (Line 282–284)

```bash
GIT_INFO="${GB}|${GD}|${GAB}|${GIT_STATE}"
# ...
GIT_INFO="|||"  # (no git repo fallback)
```

**Verdict: Correct.** Extended from 3 fields to 4. The `cut -d'|' -f4` at line 291 correctly extracts the new field. Empty string when no operation is in progress.

**Backwards compatibility:** If a cached file from before this change is read (3-field format), `cut -d'|' -f4` returns empty string — safe, no git state shown. This is correct graceful degradation.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 6.5/10 | ↑ +0.5 | Git operation state added (Feature 5), but P0 daily tracking still missing |
| Code Quality | 8.5/10 | ↑ +0.5 | Clean implementation, good error handling |
| Performance | 9/10 | — | Git consolidation saves ~60ms uncached; `find` cleanup is minor cost |
| Data Accuracy | 8.5/10 | ↑ +0.5 | Porcelain parsing is correct, rebase progress is accurate |
| UI/UX | 8/10 | — | RED BOLD for git state is appropriate |
| Stability | 8.5/10 | ↑ +0.5 | jq check, cache isolation, cleanup |
| **Overall** | **7.8/10** | **↑ +0.3** | **Solid housekeeping pass, git state is a nice feature** |

---

## Outstanding Action Items

### Critical
1. **P0: Daily token/cost tracking** — 3 review cycles and still not started. This is the user's top-requested feature. See `.review/feature-roadmap.md` Feature 1 for the complete implementation spec.

### High
2. **P1: Token burn rate + trend arrow** — Feature 2 in roadmap
3. **P1: Cost projection + budget guard** — Feature 3 in roadmap  
4. **P1: Autocompact countdown** — Feature 4 in roadmap

### Medium
5. **Broaden cache cleanup pattern** — Change `.claude_sl_activity_*` to `.claude_sl_*` to cover git and system caches too
6. **Add `REVERT_HEAD` detection** — Minor addition to git state block
7. **Update README** — Document the new git operation state feature

### Low
8. **Daily cleanup sentinel** — Avoid running `find` on every invocation (optimization)

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ❌ **NOT STARTED** | **P0** |
| 2 | Token burn rate + trend | ❌ Not started | P1 |
| 3 | Cost projection + budget | ❌ Not started | P1 |
| 4 | Autocompact countdown | ❌ Not started | P1 |
| 5 | Git operation state | ✅ **Done** | P2 |
| 6 | MCP health monitor | ❌ Not started | P2 |
| 7 | Tool success/failure ratio | ❌ Not started | P2 |
| 8 | Project stack detection | ❌ Not started | P2 |
| 9 | Sparkline token history | ❌ Not started | P3 |
| 10 | Message counter + density | ❌ Not started | P3 |
| 11 | Process resource attribution | ❌ Not started | P3 |
| 12 | Config status summary | ❌ Not started | P3 |

**Work agent: Please prioritize Feature 1 (daily token/cost tracking) next. It has been the P0 request for 3 review cycles.**

---

*Next review in ~15 minutes.*
