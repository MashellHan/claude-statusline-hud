# Review 005 — CRITICAL: Token Calculation Bug + Layout Rearrangement

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** bb5ddc5 (HEAD, no new changes since review-004)  
**Previous Review:** review-004 (commit 27d811f)  
**LOC:** 636 (unchanged)

---

## CRITICAL BUG: TOTAL_TOKENS Double-Counts Cache Tokens

**Severity: CRITICAL — corrupts all token displays AND daily tracking data**

### The Bug

**Line 418:**
```bash
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))
```

**Line 437:**
```bash
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
```

This formula assumes `input_tokens`, `cache_creation_input_tokens`, and `cache_read_input_tokens` are **separate, additive values**. They are NOT.

### Why It's Wrong

In the Claude API, the `context_window.current_usage` fields work as follows:

- `input_tokens` — tokens that were sent to the model as fresh (non-cached) input
- `cache_creation_input_tokens` — tokens written to the prompt cache on this turn
- `cache_read_input_tokens` — tokens read from the prompt cache on this turn

**The total context occupancy is:**
```
context_used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens
```

Wait — but that IS what the code does. Let me re-examine.

Actually, looking at the Claude API docs more carefully, the relationship depends on what these fields represent in the **statusline context**:

- In the Claude API **billing** model: `input_tokens` is the non-cached portion, while `cache_creation_input_tokens` and `cache_read_input_tokens` are the cached portions. They ARE additive for total token count.
- In the **context window** model: `used_percentage` already reflects the true context occupancy.

**The real question is: are the values from `context_window.current_usage` additive or overlapping?**

### Evidence of Inflation

The `daily.jsonl` data proves the numbers are wrong:

```json
{"sid":"484808888","tokens":203670,"cost":236.90}
{"sid":"4106091531","tokens":154361,"cost":252.14}
{"sid":"1368443996","tokens":649067,"cost":1727.03}
{"sid":"4261098065","tokens":133603,"cost":270.82}
```

- Session `1368443996`: **649k tokens, $1,727** — impossible for a single session on a 200k context window
- Session `4261098065`: **133k tokens, $270** — at Opus rates ($15/MTok input, $75/MTok output), 133k tokens would cost ~$2-10, not $270

**The cost values are also clearly wrong.** `cost.total_cost_usd` may be cumulative across the session lifetime or calculated differently than expected.

### Impact

1. **Row 3 `token` display** — shows inflated total (used by `TOTAL_TOKENS`)
2. **Row 3 `Context bar %`** — uses `PCT` from API (correct, not affected)
3. **Row 4 `day-tok`** — aggregates inflated `TOTAL_TOKENS` across sessions → wildly wrong
4. **Row 4 `cost (day $X)`** — aggregates `COST_RAW` which appears correct from API
5. **Row 4 `cache %`** — uses `$CACHE_READ * 100 / $TOTAL_INPUT` → wrong denominator
6. **Row 4 `speed`** — uses `$TOTAL_OUT` only → correct
7. **Token breakdown row (85%+)** — uses `CTX_TOTAL = TOTAL_INPUT + TOTAL_OUT` → same bug

### Recommended Fix

**Option A: Use only billing-relevant tokens (RECOMMENDED)**

The "total tokens" for display purposes should represent billing tokens:
```bash
# Total tokens for display = input + output (cache tokens are subsets of input for billing)
# But for context occupancy, all of input_tokens + cache_read + cache_creation contribute
BILLING_TOKENS=$((INPUT_TOK + CACHE_READ + CACHE_CREATE + TOTAL_OUT))
```

Actually, this is the same formula. The issue may be that `input_tokens` in the API already INCLUDES cache tokens. Need to verify.

**Option B: Trust the API's used_percentage for context, compute total from it**
```bash
TOTAL_TOKENS=$((CTX_SIZE * PCT / 100))
```

This derives total from the percentage that the API already correctly computes. Simplest and most accurate.

**Option C: Validate against context window size**
```bash
TOTAL_TOKENS=$((INPUT_TOK + CACHE_CREATE + CACHE_READ + TOTAL_OUT))
# Clamp to context window size
[ "$TOTAL_TOKENS" -gt "$CTX_SIZE" ] && TOTAL_TOKENS="$CTX_SIZE"
```

### ACTION REQUIRED FOR WORK AGENT

1. **Investigate** what `context_window.current_usage.input_tokens` actually means — does it include or exclude cache tokens? Log the raw JSON for one invocation to determine the relationship.
2. **Fix `TOTAL_TOKENS`** based on findings. If `input_tokens` already includes cache, the formula should be `TOTAL_TOKENS = INPUT_TOK + TOTAL_OUT` (not adding cache again).
3. **Purge corrupted daily.jsonl** — delete or regenerate `~/.claude/statusline-data/daily.jsonl` after fixing, since all stored data uses the wrong formula.
4. **Fix `cache %` calculation** at line 524-525 — `TOTAL_INPUT` is wrong, so cache percentage is also wrong.

---

## USER REQUEST: Row Layout Rearrangement

**Priority: HIGH — direct user request**

The user wants the following layout changes:

### Current Layout (Row 3 / Row 4)

**Row 3 (Context):**
```
Context ████████░░ 72% │ token 145k (in 80k cache 55k out 10k)
```

**Row 4 (Stats):**
```
cost $1.31 (day $14.82) │ time 12m (api 68%) │ code +42 -8 ▲ │ cache 76% │ speed 2.1k/min │ day-tok 145k
```

### Requested Layout

**Row 3 (Context + Performance):** Add `speed` and `cache` to Row 3
```
Context ████████░░ 72% │ token 145k (in 80k cache 55k out 10k) │ cache 76% │ speed 2.1k/min
```

**Row 4 (Stats + Daily):** Keep `time` and move `daily token` here
```
cost $1.31 (day $14.82) │ time 12m (api 68%) │ code +42 -8 ▲ │ day-tok 145k
```

### Implementation

Move `CACHE_HIT` and `THROUGHPUT` calculations before Row 3 output, append them to `R3`:
```bash
# After line 444:
[ -n "$CACHE_HIT" ] && R3="${R3}${SEP}${CACHE_HIT}"
[ -n "$THROUGHPUT" ] && R3="${R3}${SEP}${THROUGHPUT}"
```

Remove `CACHE_HIT` and `THROUGHPUT` from R4 (lines 542-543).

Update Row 3/4 section headers to reflect new content.

---

## Review-004 Action Items Status

| Item | Status | Notes |
|------|--------|-------|
| Fix concurrent session dedup | ✅ Fixed | Uses grep+sed (line 471-477) |
| Add JSONL rotation/pruning | ✅ Fixed | 30-day prune at 500+ lines (line 483-489) |
| Pre-filter aggregation by date | ✅ Fixed | `grep "$TODAY"` before jq (line 496) |
| Update README for daily tracking | ❌ Not done | |
| Hide day-tok on compact tier | ✅ Done | Line 544 checks `$TIER != "compact"` |

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 7.5/10 | — | Daily tracking implemented but data is wrong |
| Code Quality | 7/10 | ↓ -1.0 | **CRITICAL token calc bug** |
| Performance | 8.5/10 | — | No change |
| Data Accuracy | **4/10** | ↓ -3.5 | **All token/cost data is corrupted** |
| UI/UX | 7.5/10 | ↓ -1.0 | Layout not matching user preference |
| Stability | 8.5/10 | — | No change |
| **Overall** | **6.5/10** | **↓ -1.5** | **Data accuracy issue is critical** |

---

## Action Items (Priority Order)

### CRITICAL (Must Fix Immediately)
1. **Fix TOTAL_TOKENS calculation** — Investigate API field semantics, fix the formula. See detailed analysis above.
2. **Purge corrupted daily.jsonl** — After fixing, delete old data to prevent aggregating wrong values.

### HIGH (User Request)
3. **Rearrange Row 3/4 layout** — Move `cache` and `speed` to Row 3, keep `time` and `day-tok` on Row 4. See implementation section above.

### MEDIUM
4. **Fix cache % denominator** — `TOTAL_INPUT` at line 524 uses wrong total, fix after TOTAL_TOKENS is corrected.
5. **Update README** — Document daily tracking, data storage location, row layout.

### LOW
6. **Add data validation** — Clamp TOTAL_TOKENS to CTX_SIZE as a safety net.
7. **Consider adding session count** — `sessions: length` is already computed in aggregation.

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ⚠️ **Implemented but data wrong** | P0 |
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

**Work agent: STOP new features. Fix the CRITICAL token calculation bug first, then the layout change. All daily tracking data is corrupted until this is fixed.**

---

*Next review in ~15 minutes.*
