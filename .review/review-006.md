# Review 006 — Root Cause Analysis: Token Metric Mismatch + Uncommitted Changes

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commit Reviewed:** 6bc05f3 (HEAD) + uncommitted changes in working tree  
**Previous Review:** review-005 (commit 6bc05f3)  
**LOC:** 635 (was 636, -1 net from uncommitted changes)

---

## Changes Since Last Review

The work agent has **uncommitted changes** in `statusline.sh` that address 3 items from review-004:

| Diff Section | What Changed | Status |
|---|---|---|
| Lines 465-481 | **Concurrent session dedup rewritten** — replaced `tail -1` approach with `grep`/`sed` by session ID | Good fix |
| Lines 483-489 | **JSONL pruning added** — 30-day retention, triggers above 500 lines | Good fix |
| Lines 492-498 | **Aggregation pre-filtered by date** — `grep "$TODAY"` before `jq -rs` | Good fix |
| Line 544 | **`day-tok` hidden on compact tier** | Good fix |

**However, the two CRITICAL items from review-005 remain unaddressed:**
1. Token calculation bug — NOT FIXED
2. Row layout rearrangement — NOT DONE

---

## CRITICAL: Revised Root Cause Analysis — Token Inflation

**Review-005 identified the bug but hypothesized incorrectly about the cause.** After deeper research, here is the corrected analysis:

### Confirmed: Token Fields ARE Additive

The Claude API docs confirm that `input_tokens`, `cache_creation_input_tokens`, and `cache_read_input_tokens` are **separate, non-overlapping** values. Their sum equals total input tokens. So line 418 is **correct**:

```bash
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))  # ← CORRECT
```

### The Real Bug: Mixing Snapshot with Cumulative

The inflation comes from **mixing two incompatible metric types**:

| Field | Source Path | Type | Semantics |
|-------|------------|------|-----------|
| `INPUT_TOK` | `context_window.current_usage.input_tokens` | **Snapshot** | Current turn's non-cached input |
| `CACHE_CREATE` | `context_window.current_usage.cache_creation_input_tokens` | **Snapshot** | Current turn's cache writes |
| `CACHE_READ` | `context_window.current_usage.cache_read_input_tokens` | **Snapshot** | Current turn's cache reads |
| `TOTAL_OUT` | `context_window.total_output_tokens` | **Cumulative** | Sum of ALL output across ALL turns |

Line 437 adds them together:
```bash
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
#              ^^^^^^^^^^^^   ^^^^^^^^^
#              per-turn snap  cumulative across session
```

### Why This Causes 664k on a 200k Window

Consider a session with 15 API turns:
- Current context snapshot: `input_tokens + cache_create + cache_read` = ~180k (fits in window)
- Cumulative output across 15 turns: ~484k (each turn generates ~32k output)
- **TOTAL_TOKENS = 180k + 484k = 664k** — impossible for context, correct for billing

The `total` prefix in `total_output_tokens` is the giveaway — it's a session lifetime accumulator.

### Validation: Cost Is Also Cumulative

`cost.total_cost_usd` (line 53) uses the same `total_` naming convention. The daily.jsonl cost values ($236, $252, $1727, $1741) are **real session costs**, not inflated. At Opus rates ($15/MTok input, $75/MTok output), a session generating 484k cumulative output = ~$36 for output alone, plus input costs with caching. The costs are plausible for heavy Opus sessions.

**The cost data in daily.jsonl is CORRECT. Only the token data is wrong.**

### Impact Matrix (Revised from Review-005)

| Metric | Affected? | Details |
|--------|-----------|---------|
| Row 3: Context bar `%` | No | Uses `PCT` from API — already correct |
| Row 3: `token Xk` | **YES** | Shows `TOTAL_TOKENS` which mixes snapshot + cumulative |
| Row 3: `(in Xk cache Xk out Xk)` | **Partially** | `in` and `cache` are snapshot (correct for display), `out` is cumulative |
| Row 4: `cache X%` | **YES** | `CACHE_READ / TOTAL_INPUT` — `TOTAL_INPUT` is per-turn, so this is actually correct for current turn cache hit rate (not a bug!) |
| Row 4: `speed X/min` | No | Uses `TOTAL_OUT / DURATION_MS` — cumulative output / cumulative time = correct throughput |
| Row 4: `day-tok` | **YES** | Aggregates `TOTAL_TOKENS` from daily.jsonl — stores inflated values |
| Autocompact estimation | No | Uses `$PCT` from API, only uses `TOTAL_INPUT` for the 70%+ inflation factor |
| 85%+ breakdown row | **YES** | Line 449: `CTX_TOTAL = TOTAL_INPUT + TOTAL_OUT` — same bug |

### Recommended Fix (Revised)

**The fix depends on WHAT the user wants to see:**

#### For "total tokens used in current context window" (context occupancy):
```bash
# Option A: Derive from API percentage (most accurate)
TOTAL_TOKENS=$((CTX_SIZE * PCT / 100))

# Option B: Use only snapshot fields (excludes output, since output
# isn't "in" the context window the same way)
TOTAL_TOKENS=$((TOTAL_INPUT))
```

#### For "total tokens consumed in this session" (billing):
```bash
# The current formula is actually correct for this interpretation
# But rename it to make the semantics clear
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
```

#### For daily tracking:
```bash
# Use the session billing total (correct for daily cost/usage tracking)
# This is what TOTAL_TOKENS currently is — actually fine for daily.jsonl
# But then DISPLAY it differently in Row 3 (context) vs Row 4 (daily)
```

**RECOMMENDATION:** Use **two separate variables**:

```bash
# Context occupancy (for Row 3 display)
CTX_TOKENS=$((CTX_SIZE * PCT / 100))

# Session billing total (for daily tracking in daily.jsonl)
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
```

Row 3 shows `CTX_TOKENS` (what's in context now).  
Daily tracking stores `SESSION_TOKENS` (total consumed, for billing).  
Row 3 breakdown at 85%+ shows individual fields with correct labels.

---

## Uncommitted Changes: Detailed Review

### 1. Concurrent Session Dedup (Lines 470-477)

```bash
if [ -f "$DAILY_LOG" ] && grep -q "\"sid\":\"${_SID}\"" "$DAILY_LOG" 2>/dev/null; then
  _OLD_TOK=$(grep "\"sid\":\"${_SID}\"" "$DAILY_LOG" | tail -1 | jq -r '.tokens // 0' 2>/dev/null)
  if [ "$_OLD_TOK" != "$TOTAL_TOKENS" ]; then
    sed -i.bak "/\"sid\":\"${_SID}\"/d" "$DAILY_LOG" && rm -f "${DAILY_LOG}.bak"
    printf '%s\n' "$_ENTRY" >> "$DAILY_LOG"
    rm -f "$DAILY_CACHE"
  fi
```

**Verdict: Good.** This correctly handles concurrent sessions by:
1. Searching the entire file for the session ID (not just `tail -1`)
2. Only updating if tokens changed (avoids unnecessary writes)
3. Deleting all entries for the SID before re-appending (handles double-entries)

**Minor issue (LOW):** The `grep | tail -1 | jq` at line 472 runs grep twice (once for `-q`, once for value extraction). Could combine:

```bash
_EXISTING=$(grep "\"sid\":\"${_SID}\"" "$DAILY_LOG" 2>/dev/null | tail -1)
if [ -n "$_EXISTING" ]; then
  _OLD_TOK=$(printf '%s' "$_EXISTING" | jq -r '.tokens // 0' 2>/dev/null)
  ...
```

This saves one grep invocation (~5ms on large files). Not critical.

### 2. JSONL Pruning (Lines 483-489)

```bash
if [ -f "$DAILY_LOG" ] && [ "$(wc -l < "$DAILY_LOG")" -gt 500 ]; then
  _30D_AGO=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d 2>/dev/null)
  if [ -n "$_30D_AGO" ]; then
    jq -c --arg d "$_30D_AGO" 'select(.date >= $d)' "$DAILY_LOG" > "${DAILY_LOG}.tmp" && mv "${DAILY_LOG}.tmp" "$DAILY_LOG"
  fi
fi
```

**Verdict: Good implementation.** Cross-platform date handling (macOS `-v-30d` / Linux `-d '30 days ago'`). Only runs when file exceeds 500 lines.

**Issue (LOW):** The `wc -l` and `jq` both read the entire file. The 500-line threshold prevents this from running often, so acceptable.

### 3. Date Pre-Filter (Lines 496-498)

```bash
_AGG=$(grep "\"$TODAY\"" "$DAILY_LOG" 2>/dev/null | jq -rs '
  {cost: (map(.cost) | add // 0), tokens: (map(.tokens) | add // 0), sessions: length}
' 2>/dev/null)
```

**Verdict: Good.** `grep` pre-filters by today's date before passing to `jq -rs`, avoiding slurping the entire file. Clean improvement over the previous `jq -rs --arg d "$TODAY" '[.[] | select(...)]'` approach.

### 4. Compact Tier Day-Tok Hide (Line 544)

```bash
if [ -n "$DAY_TOK" ] && [ "$DAY_TOK" != "0" ] && [ "$TIER" != "compact" ]; then
```

**Verdict: Correct.** Added `$TIER != "compact"` guard. Row 4 was getting too long for compact terminals.

---

## Outstanding Action Items

### CRITICAL

1. **Split `TOTAL_TOKENS` into context vs session metrics** — Create `CTX_TOKENS` (from `PCT * CTX_SIZE / 100`) for Row 3 display, and `SESSION_TOKENS` (current formula) for daily tracking. This is the root cause of the "day token 数量不对" bug. See detailed fix recommendation above.

2. **Purge corrupted daily.jsonl token data** — The cost data is correct, but token values are inflated. After fixing the formula, either: (a) delete `daily.jsonl` and start fresh, or (b) leave it and accept that historical token values are wrong (costs are fine).

### HIGH (User Request — Unfulfilled)

3. **Rearrange Row 3/4 layout** — User requested: `cache` and `speed` on Row 3, `time` and `day-tok` on Row 4. **Not started.** See review-005 for implementation details. Steps:
   - Move `CACHE_HIT` and `THROUGHPUT` computation before Row 3 `printf`
   - Append to `R3` instead of `R4`
   - Remove from R4 construction (lines 542-543)
   - Update section comment headers

### MEDIUM

4. **Commit the uncommitted dedup/pruning changes** — These are good fixes sitting in the working tree. Commit them.

5. **Fix Row 3 `out Xk` display** — Currently shows cumulative `TOTAL_OUT`, but the `in` and `cache` values beside it are per-turn snapshots. Either: (a) show all per-turn values with a separate cumulative line, or (b) label `out` as `total-out` to make the semantics clear.

6. **Update README** — Still not done. Document daily tracking, data files, row layout.

### LOW

7. **Optimize duplicate grep** in dedup logic (line 471-472) — minor, ~5ms savings.
8. **Add session count display** — Aggregation already computes `sessions: length`; consider showing `(3 sessions)` in day-cost parenthetical.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 7.5/10 | — | Daily tracking present, but data accuracy blocks usefulness |
| Code Quality | 8/10 | ↑ +1.0 | Uncommitted fixes are well-implemented (dedup, pruning, pre-filter) |
| Performance | 9/10 | ↑ +0.5 | grep pre-filter, conditional pruning — good optimizations |
| Data Accuracy | **5/10** | ↑ +1.0 | Root cause identified; cost data is correct (revised up from 4), tokens still wrong |
| UI/UX | 7.5/10 | — | Layout change still pending |
| Stability | 8.5/10 | — | No change |
| **Overall** | **7.2/10** | **↑ +0.7** | **Good uncommitted fixes; token bug root cause now clear** |

Score improvement: dedup and pruning fixes are solid, and the cost data was found to be correct (previously scored the whole data pipeline as broken).

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ⚠️ **Cost correct, tokens inflated** | P0 (fix token calc) |
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

## Work Agent Priority Queue

```
1. [CRITICAL] Fix TOTAL_TOKENS → split into CTX_TOKENS + SESSION_TOKENS
2. [CRITICAL] Purge/reset daily.jsonl after token fix
3. [HIGH]     Row layout change: cache+speed→R3, time+day-tok→R4
4. [MEDIUM]   Commit current uncommitted changes (dedup, pruning, pre-filter)
5. [MEDIUM]   Fix Row 3 "out Xk" label/semantics
6. [P1]       Start Feature 2: burn rate + trend arrow
```

**Do NOT start P1 features until items 1-3 are complete and committed.**

---

*Next review in ~15 minutes.*
