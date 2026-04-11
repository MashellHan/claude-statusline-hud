# Review 007 — Status Check: No New Implementation Changes

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** 50dc185 (`refactor: improve daily tracking dedup logic and add log pruning`)  
**Previous Review:** review-006 (commit be97d1b)  
**LOC:** 635 (unchanged)

---

## Changes Since Last Review

**One new commit:** `50dc185` — This is the work agent committing the changes that were already reviewed as uncommitted diffs in review-006. No new implementation work.

The committed changes are:
- Concurrent session dedup via `grep`/`sed` (already reviewed: good)
- 30-day JSONL pruning at 500+ lines (already reviewed: good)
- `grep "$TODAY"` pre-filter for aggregation (already reviewed: good)
- Compact tier `day-tok` hiding (already reviewed: good)

**All review-006 assessments remain valid.**

---

## Outstanding Items Tracker

### CRITICAL — Blocking All Progress

| # | Item | Status | Reviews Pending |
|---|------|--------|-----------------|
| 1 | **Split TOTAL_TOKENS into CTX_TOKENS + SESSION_TOKENS** | **NOT STARTED** | Reviews 5, 6, 7 |
| 2 | **Purge/reset daily.jsonl token values** | **NOT STARTED** | Reviews 5, 6, 7 |

**Current daily.jsonl still shows inflated tokens:**
```json
{"sid":"484808888","tokens":209236,"cost":249.42}
{"sid":"4261098065","tokens":193978,"cost":300.63}
```

These token values mix per-turn context snapshot with cumulative output. The costs are correct.

**Concrete fix (copy-paste ready):**

```bash
# Line 437: Replace TOTAL_TOKENS with two separate variables
# Context occupancy (for Row 3 display — what's in the window right now)
CTX_TOKENS=$((CTX_SIZE * PCT / 100))

# Session billing total (for daily.jsonl tracking)
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
```

Then update references:
- Line 439-440: Use `CTX_TOKENS` in `TOK_DISPLAY` for Row 3
- Line 449: Use `CTX_TOKENS` in the 85%+ breakdown row
- Line 465: Guard condition — use `SESSION_TOKENS` instead of `TOTAL_TOKENS`
- Line 468: `_ENTRY` — use `SESSION_TOKENS` for daily tracking

### HIGH — User Request

| # | Item | Status | Reviews Pending |
|---|------|--------|-----------------|
| 3 | **Row layout: cache+speed→R3, time+day-tok→R4** | **NOT STARTED** | Reviews 5, 6, 7 |

**Concrete fix:**

Step 1 — Move `CACHE_HIT` and `THROUGHPUT` computation before the Row 3 `printf` (before line 445). Currently they're computed at lines 523-533, after `[ "$PRESET" = "essential" ] && exit 0`. This means they won't be available in essential preset, which is correct since Row 3 is essential+ but cache/speed are full+ features.

Revised approach: Keep computation where it is (after essential exit), but restructure Row 4 output:

```bash
# Row 3 already printed. Row 4 section:
# Move cache+speed to a new R3b line? No — user wants them ON Row 3.
# This means cache+speed must be computed BEFORE the essential exit.
```

Actually, the user specifically said "speed 应该在第三行 包括 cache" — this means cache% and speed should be visible in `essential+` preset. Move the CACHE_HIT and THROUGHPUT computations to before line 445, and append them to R3.

### MEDIUM

| # | Item | Status |
|---|------|--------|
| 4 | Fix Row 3 `out Xk` semantics (cumulative vs snapshot mismatch) | NOT STARTED |
| 5 | Update README with daily tracking docs | NOT STARTED |
| 6 | Optimize duplicate grep in dedup (minor) | NOT STARTED |

---

## Code Quality Observation: Comment Drift

The section header at line 456 still says:
```bash
# ROW 4: Stats — Cost │ Duration │ Lines │ Cache │ Speed  [FULL+]
```

But the user wants `Cache` and `Speed` moved to Row 3. When the layout change is implemented, this comment must be updated to match. Same for the Row 3 header at line 413.

---

## Scores

No implementation changes = no score changes. Carrying forward from review-006:

| Category | Score | Notes |
|----------|-------|-------|
| Features | 7.5/10 | Daily tracking present, tokens still wrong |
| Code Quality | 8/10 | Dedup/pruning well-implemented |
| Performance | 9/10 | grep pre-filter good |
| Data Accuracy | **5/10** | Token inflation unfixed, cost correct |
| UI/UX | 7.5/10 | Layout change still pending |
| Stability | 8.5/10 | Solid error handling |
| **Overall** | **7.2/10** | **No change — waiting on CRITICAL fixes** |

---

## Velocity Concern

**The CRITICAL token fix has been outstanding for 3 consecutive reviews (005→006→007).** The fix is straightforward — 4 line changes + daily.jsonl purge. At the current rate, the inflated data continues to accumulate in daily.jsonl, making the daily tracking feature effectively useless.

**Recommendation:** If the work agent is blocked or unresponsive, escalate. The user explicitly reported "day token 数量不对" and is waiting for the fix.

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ⚠️ **Token data inflated** | P0 (bug fix) |
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

---

## New Feature Idea: Session Health Score

**Feature 13: Composite Session Health Indicator (P2)**

Inspired by btop's system health overview. Combine multiple signals into a single 0-100 health score:

- **Context pressure** (weight 30%): 100 - PCT (more context left = healthier)
- **Cache efficiency** (weight 25%): cache hit % (higher = healthier, less billing)
- **Cost velocity** (weight 25%): inverse of burn rate (slower burn = healthier)
- **Tool success rate** (weight 20%): % of tool calls succeeding

Display: `health 78 ████████░░` with color gradient (green > yellow > red).

This gives users a single at-a-glance indicator for "should I reset this session?" without reading 4 rows of metrics. No competitor has this — strong differentiator.

---

*Next review in ~15 minutes.*
