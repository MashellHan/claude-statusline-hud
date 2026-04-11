# Review 013 — Rate Limit Display Landed (P1.1) + Daily Token Verified

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** ee6f1c5 `feat: add rate limit display (P1.1 — first-to-market)`  
**Previous Review:** review-012 (OOM fix verified, roadmap published)  
**LOC:** ~637 (up from 612, +25 lines for rate limit)

---

## Status: Dev Agent Delivered P1.1 ✅

### What Was Done

The dev agent implemented rate limit display in **one commit** after review-012 was published:

1. **Parsed `rate_limits.five_hour.used_percentage` and `resets_at`** from JSON input (lines 68-69)
2. **Added rate limit display to Row 3** with color-coded percentage and reset countdown (lines 463-482)
3. **Added fallback defaults** (`RL_5H_PCT=0 RL_5H_RESET=0`) in the jq error path (line 73)
4. **Committed, pushed, and deployed** — all three deployment steps followed correctly

### Deployment Checklist

| Checkpoint | Status |
|-----------|--------|
| Code implemented | ✅ 25 lines added |
| Git committed | ✅ `ee6f1c5` |
| Git pushed | ✅ Up to date with origin |
| Deployed to marketplace | ✅ `diff` returns 0 |
| Tests passing | ✅ 8/8 (100%) per test report |

### Daily Token Cache Verified

```
DAY_TOK='1993882395'     ← ~2.0B tokens (≈1994M)
DAY_SESSIONS='24244'     ← message count (not session count, see Issue below)
DAY_COST=''              ← cost not computed from transcripts (expected)
```

Cache file age: created 16:18 today. **Daily token tracking is now working.** The value increased from the 1,736M measured earlier in review-010 to ~1,994M, which makes sense — more sessions ran throughout the day.

---

## Code Review: Rate Limit Feature

### ✅ What's Good

1. **Correct data extraction** — `jq -r` with `// 0 | floor` handles missing/null values safely
2. **Color coding uses existing `bar_color` function** — consistent with context bar coloring (green < 70%, yellow 70-90%, red ≥ 90%)
3. **Reset countdown logic is correct** — `RL_5H_RESET - NOW` with proper hours/minutes formatting
4. **Edge cases handled** — `[ "$RL_5H_PCT" -gt 0 ]` prevents showing "rl 0%" when no rate limit data
5. **Placement is smart** — appended to Row 3 (context row), keeps related metrics together
6. **Clean integration** — follows existing pattern: build display string, append with `SEP` if non-empty

### ⚠️ Issues Found

#### Issue 1: Color Thresholds Don't Match Roadmap Spec (MEDIUM)

**Roadmap spec (feature-roadmap-v2.md):**
```
green < 60%, yellow 60-80%, red > 80%
```

**Actual `bar_color` function (line 190-194):**
```
green < 70%, yellow 70-89%, red ≥ 90%
```

The dev agent reused `bar_color`, which was designed for context window occupancy. For rate limits, the thresholds should arguably be **more aggressive** — hitting 80% rate limit is more urgent than 80% context window. But using the same function is pragmatic and keeps code DRY.

**Verdict:** Acceptable. The existing thresholds (70/90) are close enough. If we want custom thresholds, a separate `rl_color` function would add 5 lines. LOW priority.

#### Issue 2: `2>/dev/null` on Arithmetic Comparisons (LOW)

```bash
if [ "$RL_5H_PCT" -gt 0 ] 2>/dev/null; then
```

The `2>/dev/null` on `[ ]` is a defensive pattern — it silences errors if the variable is empty or non-numeric. This is fine for bash robustness, but it also silently swallows legitimate bugs. Acceptable for a statusline script where crashing is worse than showing nothing.

#### Issue 3: No 7-Day Rate Limit (LOW)

The spec in feature-roadmap-v2.md suggested:
> Show 5hr by default; show 7-day if 5hr is < 20% but 7-day is > 50%

The implementation only parses `five_hour`. The `seven_day` limit is not extracted. This is fine for v1 — the 5-hour limit is what users actually hit. Adding 7-day is a future enhancement.

#### Issue 4: `DAY_SESSIONS` Is Still Message Count (Carried)

The cache shows `DAY_SESSIONS='24244'` — this is the number of API messages, not session files. Not displayed in UI currently, so LOW priority. When we show it, use `find | wc -l`.

---

## Remaining P1 Items

| Item | Status | Notes |
|------|--------|-------|
| P0: Daily token OOM fix | ✅ DONE | Committed e731161, verified working (~1994M) |
| P1.1: Rate limit display | ✅ DONE | Committed ee6f1c5, deployed |
| P1.2: Native session_id | ❌ Not started | Replace cksum hack with `session_id` from JSON |
| P1.3: Cost budget alerts | ❌ Not started | Depends on `CLAUDE_SL_DAILY_BUDGET` env var |
| P1.4: Autocompact countdown | ❌ Not started | Use `remaining_percentage` for turn estimation |

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.5/10 | ↑ +1.0 | Rate limit display (first-to-market!), daily token working |
| Code Quality | 8.0/10 | — | Clean implementation, DRY with bar_color, proper fallbacks |
| Performance | 8.5/10 | — | Two-stage jq pipeline, rate limit from existing JSON parse |
| Data Accuracy | 8.0/10 | ↑ +1.0 | Daily token verified at ~1994M, rate limit % from API |
| UI/UX | 8.5/10 | — | Good placement on Row 3, color coding |
| Stability | 8.0/10 | ↑ +0.5 | Defensive arithmetic, proper fallbacks |
| **Overall** | **8.3/10** | **↑ +0.5** | **Solid progress. Two P1 items done in one day.** |

---

## Next Action Items for Dev Agent

### HIGH

1. **P1.2: Use native `session_id`** (~5 lines)
   - Add to jq extraction: `@sh "SESSION_ID=\(.session_id // "")"`
   - Replace `_SID` cksum hack with `SESSION_ID`
   - Commit immediately after implementation

2. **P1.3: Cost budget alerts** (~15 lines)
   - Check `$CLAUDE_SL_DAILY_BUDGET` env var
   - Display `(day $48.72/50 ⚠️)` format
   - See feature-roadmap-v2.md for spec

### MEDIUM

3. **P1.4: Autocompact countdown** (~25 lines)
   - Parse `remaining_percentage` from JSON
   - Estimate remaining turns
   - Display `⏳ ~8 turns` on Row 2

4. **Add 7-day rate limit** as secondary display
   - Parse `rate_limits.seven_day.used_percentage` and `resets_at`
   - Show when 5hr < 20% but 7day > 50%

### LOW

5. **Custom rate limit color thresholds** — `rl_color` function with 50/80 breakpoints instead of 70/90
6. **Fix `DAY_SESSIONS`** — use `find | wc -l` for actual session file count

---

*Dev agent: Great work on P1.1 — first-to-market! Next: P1.2 (native session_id, 5 lines) and P1.3 (budget alerts, 15 lines). Both are small and self-contained. Commit each separately.*
