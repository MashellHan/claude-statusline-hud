# Review 002 — Performance Optimization & Cache Isolation

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** 9f2eed8 (`perf: optimize JSON parsing and improve cache isolation`)  
**Previous Review:** review-001 (commit 712c213)  
**LOC:** 545 (was 527, +18 net)

---

## Changes Summary

The work agent addressed 4 of the action items from review-001:

| Review-001 Action Item | Status | Commit |
|------------------------|--------|--------|
| Consolidate jq calls (19→1) | ✅ Done | 9f2eed8 |
| Remove `eval` in `mini_bar` | ✅ Done | 9f2eed8 |
| Add session-specific cache keys | ✅ Done | 9f2eed8 |
| Add temp file cleanup trap | ✅ Done | 9f2eed8 |
| Add daily token/cost tracking | ❌ Not started | — |

---

## Detailed Review

### 1. JSON Parsing Consolidation (Lines 39–66)

**Before:** 19 separate `jq` invocations (19 process spawns).  
**After:** Single `jq` call with `@sh` formatting + `eval`.

**Verdict: Good implementation with one concern.**

**Positive:**
- Correctly uses `@sh` for shell-safe quoting — prevents injection from malicious JSON values
- Fallback block on jq failure is excellent defensive coding
- `2>/dev/null` on the jq call suppresses stderr noise

**Concern — `eval` usage (MEDIUM):**
The review-001 flagged `eval` in `mini_bar` and it was correctly removed. However, this change introduces a *new* `eval` at line 40. The `@sh` filter makes this safe in practice — jq's `@sh` produces properly escaped shell literals. But:
- If `jq` is compromised or outputs unexpected data, `eval` would execute it
- The fallback block mitigates total failure, but a malformed partial output could still execute

**Recommendation:** This is acceptable. `@sh` is the standard jq-to-shell pattern. The risk is theoretical. No action needed unless targeting security-hardened environments.

**Performance Impact:** Estimated reduction from ~80ms to ~15ms for JSON parsing (18 fewer process spawns). This is the single biggest performance win possible in this script.

---

### 2. `mini_bar` eval Removal (Lines 153–163)

**Before:**
```bash
eval "bar=\"\${bar}\${chars_${remainder}}\""
```

**After:**
```bash
case "$remainder" in
  1) bar="${bar}▏" ;; 2) bar="${bar}▎" ;; 3) bar="${bar}▍" ;; 4) bar="${bar}▌" ;;
  5) bar="${bar}▋" ;; 6) bar="${bar}▊" ;; 7) bar="${bar}▉" ;;
esac
```

**Verdict: Clean fix.** Exactly what review-001 recommended. No `eval`, no indirect expansion, explicit mapping. The `case` statement is also marginally faster than the old variable lookup + eval.

---

### 3. Session ID & Cache Isolation (Lines 215–221, 308, 465)

**Implementation:**
```bash
_SID=$(printf '%s' "$TRANSCRIPT" | cksum | awk '{print $1}')
```

Used for:
- `ACTIVITY_CACHE="/tmp/.claude_sl_activity_${_SID}"` (line 308)
- `SYS_CACHE="${TMPDIR:-/tmp}/.claude_sl_sys_$(id -u)"` (line 465)

**Verdict: Partial implementation — mixed approach.**

**Good:**
- `cksum` is universally available, fast, and deterministic
- Activity cache correctly uses per-session isolation (`_SID`)
- System cache correctly uses user ID (`id -u`) for security isolation

**Issue — Inconsistency (MEDIUM):**
- Activity cache uses `_SID` (per-session) ✓
- System cache uses `$(id -u)` (per-user, shared across sessions) — correct, since vitals are system-wide
- Git cache still uses global `/tmp/.claude_sl_git` (line ~212) — **not isolated**

The git cache (`/tmp/.claude_sl_git`) is shared across all sessions. If two sessions are in different directories, they'd share git status data from whichever session wrote last. This was flagged in review-001 but not fully addressed.

**Fix:** Change git cache to be per-directory:
```bash
_DIR_HASH=$(printf '%s' "$DIR" | cksum | awk '{print $1}')
GIT_CACHE="/tmp/.claude_sl_git_${_DIR_HASH}"
```

**Issue — Stale activity cache files (LOW):**
Activity cache files are session-specific but never cleaned up. Over time, `/tmp/.claude_sl_activity_*` files accumulate. Consider adding cleanup of old files (>1 day) in setup.sh or at script start.

---

### 4. Temp File Cleanup Trap (Lines 17–19)

```bash
EVENTS_FILE="/tmp/.claude_sl_events_$$"
trap 'rm -f "$EVENTS_FILE"' EXIT
```

**Verdict: Good.** Moved `EVENTS_FILE` declaration to top level and added EXIT trap. This prevents orphan temp files from accumulating when the script is killed.

**Minor:** The `EVENTS_FILE` is now declared even when it won't be used (e.g., `minimal` preset exits before transcript parsing). Not a real problem — just a ~5-byte variable allocation.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 6/10 | — | No new features; daily tracking still missing |
| Code Quality | 8/10 | ↑ +1 | eval removed from mini_bar, consolidated jq, good fallback |
| Performance | 9/10 | ↑ +2 | Single jq call is a major win (~65ms saved per invocation) |
| Data Accuracy | 8/10 | — | No changes to calculations |
| UI/UX | 8/10 | — | No visual changes |
| Stability | 8/10 | ↑ +1 | Trap cleanup, jq fallback, cache isolation |
| Bugs | — | — | No bugs introduced |
| **Overall** | **7.5/10** | **↑ +0.5** | **Solid performance + quality pass** |

---

## Outstanding Action Items

### From Review-001 (Still Open)
1. **P0: Add daily token/cost tracking** — Not started. See `.review/feature-roadmap.md` Feature 1 for full spec.
2. **P1: Add burn rate with trend** — Feature 2 in roadmap
3. **P1: Add cost projection + budget guard** — Feature 3 in roadmap
4. **P1: Add autocompact countdown** — Feature 4 in roadmap
5. **P2: Fix git cache isolation** — Use per-directory hash key
6. **P2: Add `jq` availability check at startup** — Clear error if missing
7. **P2: Consolidate git commands** — 3 separate `git diff`/`ls-files` → single `git status --porcelain`

### New from This Review
8. **LOW: Clean up stale activity cache files** — Add TTL-based cleanup for `/tmp/.claude_sl_activity_*`
9. **LOW: Add shellcheck CI** — The new `eval` + `@sh` pattern should pass shellcheck but worth verifying

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ❌ Not started | P0 |
| 2 | Token burn rate + trend | ❌ Not started | P1 |
| 3 | Cost projection + budget | ❌ Not started | P1 |
| 4 | Autocompact countdown | ❌ Not started | P1 |
| 5 | Git operation state | ❌ Not started | P2 |
| 6 | MCP health monitor | ❌ Not started | P2 |
| 7 | Tool success/failure ratio | ❌ Not started | P2 |
| 8 | Project stack detection | ❌ Not started | P2 |
| 9 | Sparkline token history | ❌ Not started | P3 |
| 10 | Message counter + density | ❌ Not started | P3 |
| 11 | Process resource attribution | ❌ Not started | P3 |
| 12 | Config status summary | ❌ Not started | P3 |

**Reminder to work agent:** Feature 1 (daily token/cost tracking) is the top priority. The full implementation spec is in `.review/feature-roadmap.md`.

---

*Next review in ~15 minutes.*
