# Review 004 — Daily Token/Cost Tracking (P0 Feature)

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** 27d811f (`feat: add daily token/cost tracking across sessions`)  
**Previous Review:** review-003 (commit 1743d73)  
**LOC:** 636 (was 579, +57 net)

---

## Changes Summary

The P0 feature (daily token/cost tracking) has been implemented. Additionally, two minor fixes from review-003 were addressed.

| Item | Status |
|------|--------|
| **P0: Daily token/cost tracking** | ✅ **Implemented** |
| Broaden cache cleanup pattern | ✅ Fixed (`.claude_sl_*`) |
| Add `REVERT_HEAD` detection | ✅ Fixed |

---

## Detailed Review

### 1. Daily Token/Cost Tracking — Core Logic (Lines 459–506)

#### Architecture
```
~/.claude/statusline-data/daily.jsonl  ← persistent append-only log
/tmp/.claude_sl_daily_$(id -u)         ← cached aggregation (30s TTL)
```

**Verdict: Matches the roadmap spec. Correct architecture choice.**

#### Session Deduplication (Lines 471–489)

The dedup logic only checks the **last line** of the JSONL file:

```bash
_LAST_SID=$(tail -1 "$DAILY_LOG" | jq -r '.sid // ""')
if [ "$_LAST_SID" = "$_SID" ]; then
  # Same session — update in place via sed
else
  # New session — append
fi
```

**Bug (MEDIUM): Dedup only works when the current session is the most recent entry.**

If two sessions (A and B) are running concurrently:
1. Session A writes entry → log: `[A]`
2. Session B writes entry → log: `[A, B]`
3. Session A updates → `tail -1` sees B, thinks A is new → log: `[A, B, A']`
4. Session A updates again → `tail -1` sees A', correctly updates → log: `[A, B, A'']`

Result: Session A has two entries (`A` and `A''`). The daily aggregation sums both, **double-counting session A's tokens**.

**Fix:** Instead of checking only `tail -1`, grep for the session ID:
```bash
if grep -q "\"sid\":\"${_SID}\"" "$DAILY_LOG" 2>/dev/null; then
  # Session exists — use sed to replace the matching line
  sed -i.bak "/\"sid\":\"${_SID}\"/d" "$DAILY_LOG" && rm -f "${DAILY_LOG}.bak"
fi
printf '%s\n' "$_ENTRY" >> "$DAILY_LOG"
```

This handles concurrent sessions correctly. However, it's slower on large files. A pragmatic alternative: accept the edge case and note it as a known limitation, since concurrent Claude sessions sharing the same user are uncommon.

#### sed Portability (Line 478)

```bash
sed -i.bak '$ d' "$DAILY_LOG" 2>/dev/null && rm -f "${DAILY_LOG}.bak"
```

**Issue (LOW):** `sed -i.bak` is the macOS-compatible form (GNU sed uses `sed -i`). This is correct for macOS but creates an unnecessary `.bak` file. The `rm -f` cleanup handles it, so this is fine. On Linux with GNU sed, `-i.bak` also works (just specifies a different backup suffix).

**Verdict: Portable. No issue.**

#### Aggregation (Lines 492–505)

```bash
_AGG=$(jq -rs --arg d "$TODAY" '
  [.[] | select(.date == $d)] |
  {cost: (map(.cost) | add // 0), tokens: (map(.tokens) | add // 0), sessions: length}
' "$DAILY_LOG" 2>/dev/null)
```

**Issue (MEDIUM): This reads and slurps the entire daily.jsonl on every uncached call.**

If the file grows over weeks/months (e.g., 1000+ entries), this becomes slow. The aggregation only needs today's entries.

**Fix options:**
1. **Pre-filter with grep:** `grep "\"$TODAY\"" "$DAILY_LOG" | jq -rs ...` — avoids slurping old entries
2. **Rotation:** Add daily log rotation (delete entries older than 30 days) in setup.sh or at script start
3. **Both (recommended)**

**Recommendation:** Add this one-liner before aggregation:
```bash
# Prune entries older than 30 days (keeps file small)
if [ "$(wc -l < "$DAILY_LOG")" -gt 500 ]; then
  _30_DAYS_AGO=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d 2>/dev/null)
  [ -n "$_30_DAYS_AGO" ] && jq -c --arg d "$_30_DAYS_AGO" 'select(.date >= $d)' "$DAILY_LOG" > "${DAILY_LOG}.tmp" && mv "${DAILY_LOG}.tmp" "$DAILY_LOG"
fi
```

#### Cache Sourcing (Line 494)

```bash
. "$DAILY_CACHE"
```

Same pattern as the system vitals cache. The cache file is written with controlled format (`DAY_COST='...'` and `DAY_TOK='...'`), and the file is in `/tmp` owned by `$(id -u)`. Acceptable risk level, consistent with existing patterns.

#### Guard Conditions (Line 465)

```bash
if [ -n "$TRANSCRIPT" ] && [ "$TOTAL_TOKENS" -gt 0 ]; then
```

**Good.** Skips tracking when no transcript (non-interactive?) or no tokens consumed yet. Prevents empty entries.

---

### 2. Display Integration (Lines 537–547)

#### Cost display:
```bash
R4="${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"
if [ -n "$DAY_COST" ] && [ "$DAY_COST" != "0" ]; then
  R4="${R4} ${DIM}(day${RST} ${VAL}$(fmt_cost "$DAY_COST")${RST}${DIM})${RST}"
fi
```

**Verdict: Clean.** Shows as `cost $1.31 (day $14.82)`. Parenthetical format is compact and doesn't break the separator pattern. The dim parentheses make the daily cost visually subordinate to session cost.

#### Token display:
```bash
if [ -n "$DAY_TOK" ] && [ "$DAY_TOK" != "0" ]; then
  R4="${R4}${SEP}${CYAN}day-tok${RST} ${VAL}$(fmt_tok "$DAY_TOK")${RST}"
fi
```

**Verdict: Correct placement** at end of Row 4. Uses existing `fmt_tok` for consistent formatting.

**UI suggestion (LOW):** On compact terminals, Row 4 may be getting long. Current items: `cost (day) │ time (api) │ code │ cache │ speed │ day-tok`. That's 6 segments. Consider hiding `day-tok` on compact tier since the daily cost already provides budget context.

---

### 3. Bonus Fixes

#### Cache cleanup broadened (Line 27):
```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name '.claude_sl_*' -mtime +1 -delete 2>/dev/null
```
**Good.** Now covers all statusline cache files (git, activity, daily, sys).

#### REVERT_HEAD detection (Lines 270–271):
```bash
elif [ -f "${_GIT_DIR}/REVERT_HEAD" ]; then
  GIT_STATE="REVERTING"
```
**Good.** Fills the gap identified in review-003.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 7.5/10 | ↑ +1.0 | P0 daily tracking implemented! |
| Code Quality | 8/10 | ↓ -0.5 | Concurrent session dedup bug |
| Performance | 8.5/10 | ↓ -0.5 | JSONL file growth concern |
| Data Accuracy | 7.5/10 | ↓ -1.0 | Double-counting in concurrent sessions |
| UI/UX | 8.5/10 | ↑ +0.5 | Clean integration, good dim styling |
| Stability | 8.5/10 | — | sed portability is handled |
| **Overall** | **8.0/10** | **↑ +0.2** | **P0 feature landed, but dedup needs fixing** |

---

## Action Items

### High Priority
1. **Fix concurrent session dedup** — Current `tail -1` approach double-counts when sessions interleave. Use `grep`/`sed` to find and replace by session ID, or accept as known limitation.
2. **Add JSONL rotation/pruning** — File grows indefinitely. Add 30-day pruning or line count cap.
3. **Pre-filter aggregation by date** — `grep "$TODAY"` before `jq -rs` for performance.

### Medium Priority
4. **Update README** — Document daily tracking feature, new display format, data storage location.
5. **Hide `day-tok` on compact tier** — Row 4 has 6 segments now, may overflow.
6. **Add `sessions` count to display** — The aggregation already computes `sessions: length`. Consider showing `day $14.82 (3 sessions)`.

### Low Priority
7. **Add daily reset notification** — Show a brief indicator on the first invocation after midnight.
8. **Consider weekly/monthly summary skill** — A `/stats` skill that reads `daily.jsonl` and shows trends.

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ✅ **Done** (needs dedup fix) | P0 |
| 2 | Token burn rate + trend | ❌ Not started | P1 |
| 3 | Cost projection + budget | ❌ Not started | P1 |
| 4 | Autocompact countdown | ❌ Not started | P1 |
| 5 | Git operation state | ✅ Done | P2 |
| 6 | MCP health monitor | ❌ Not started | P2 |
| 7 | Tool success/failure ratio | ❌ Not started | P2 |
| 8 | Project stack detection | ❌ Not started | P2 |
| 9 | Sparkline token history | ❌ Not started | P3 |
| 10 | Message counter + density | ❌ Not started | P3 |
| 11 | Process resource attribution | ❌ Not started | P3 |
| 12 | Config status summary | ❌ Not started | P3 |

**Next priorities for work agent:** Fix dedup bug (high), then Features 2–4 (P1 tier).

---

*Next review in ~15 minutes.*
