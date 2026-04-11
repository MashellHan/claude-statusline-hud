# Review 015 — CRITICAL: DAY_COST Shows $5,053 Using Hardcoded API Prices

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** b9eb9f1 `fix: compute DAY_COST from transcript token breakdown (P1.3)`  
**Previous Review:** review-014  
**LOC:** ~660

---

## 🔴 CRITICAL: DAY_COST = $5,053 — Misleading for Max Plan Users

### The Problem

The `b9eb9f1` fix computes daily cost by multiplying raw token counts by hardcoded Sonnet 4.6 API list prices:

```bash
# Line 537-538:
DAY_COST=$(printf '%s' "$_DAY_STATS" | jq -r '[.input, .output, .cache_read] | @tsv' | \
  awk -F'\t' '{printf "%.4f", ($1*3 + $2*15 + $3*0.3)/1000000}')
```

Today's breakdown:
```
input:      1.58B × $3/1M   = $4,742
output:     5.2M  × $15/1M  = $77
cache_read: 643M  × $0.30/1M = $192
TOTAL:      $5,053
```

**This is the API list price, not the user's actual cost.** For Max plan subscribers (flat monthly fee), the real incremental cost is **$0**.

### Why This Matters

1. **User alarm** — Seeing `budget $5053/50 🔴` would cause panic
2. **Inaccurate data** — The #1 principle of this HUD is data accuracy (see review-009 crisis)
3. **No way to get real cost from transcripts** — Transcript JSONL files do NOT contain cost data (verified: `grep` for "cost" and "total_cost_usd" in transcripts returns nothing)
4. **`COST_RAW` from Claude Code** — `cost.total_cost_usd` is the only source of real cost, but it's per-session and likely $0 for Max users

### Investigation Results

| Data Source | Has Cost? | Accurate? |
|------------|-----------|-----------|
| Statusline JSON `cost.total_cost_usd` | ✅ | ✅ For API users, $0 for Max |
| Transcript JSONL files | ❌ No cost field | N/A |
| Hardcoded token × price | ✅ | ❌ Wrong for Max, wrong for other models |

---

## Recommended Fix

### Strategy: Show Token-Equivalent Cost with Clear "≈" Label

Since we can't get real cost from transcripts, reframe the display:

**Option A: Rename to "token equivalent" (RECOMMENDED)**

Show the computed value but label it clearly as an estimate:
```
day-tok 2.3B │ ≈$5.0k (api-eq)
```

Or in budget mode:
```
budget ≈$5.0k/$10k (api-eq)
```

The `≈` and `(api-eq)` make it clear this is an API-equivalent estimate, not actual billing.

**Option B: Don't show DAY_COST at all**

Remove the hardcoded cost calculation entirely. Only show `DAY_COST` if the user has API billing (when per-session `COST_RAW > 0`):

```bash
# Only compute DAY_COST if current session reports non-zero cost
# (indicates API billing, not Max plan)
if [ "$COST_RAW" != "0" ] && [ -n "$COST_RAW" ]; then
  # ... compute from hardcoded prices (approximate for API users)
else
  DAY_COST=""  # Don't show cost for Max plan users
fi
```

**Option C: Accumulate per-session COST_RAW**

Add current session's `COST_RAW` to a running daily total in the cache. But this only captures sessions where statusline renders — same undercounting problem as the old daily.jsonl. **Not recommended.**

### My Recommendation: Option B (with fallback to A)

1. **Default behavior:** If `COST_RAW == 0` → don't show `DAY_COST`, don't show budget alerts
2. **API billing users:** If `COST_RAW > 0` → compute approximate `DAY_COST` from tokens
3. **Env var override:** `CLAUDE_SL_SHOW_API_EQUIV_COST=1` → force show token-equivalent cost even for Max users

This way Max users see clean `day-tok 2.3B` without a scary dollar amount, and API users get approximate cost tracking.

---

## Implementation Spec for Dev Agent

```bash
# Replace lines 536-538 with:

# Only estimate daily cost if user appears to be on API billing
# (COST_RAW > 0 indicates per-token billing, not Max subscription)
_SHOW_COST=false
if [ "${CLAUDE_SL_SHOW_API_EQUIV_COST:-0}" = "1" ]; then
  _SHOW_COST=true
elif [ -n "$COST_RAW" ] && [ "$COST_RAW" != "0" ]; then
  _IS_API=$(awk -v c="$COST_RAW" 'BEGIN{print (c+0 > 0) ? "yes" : "no"}')
  [ "$_IS_API" = "yes" ] && _SHOW_COST=true
fi

if [ "$_SHOW_COST" = true ]; then
  # Approximate cost using Sonnet pricing: $3/$15/$0.30 per 1M tokens
  DAY_COST=$(printf '%s' "$_DAY_STATS" | jq -r '[.input, .output, .cache_read] | @tsv' 2>/dev/null | \
    awk -F'\t' '{printf "%.4f", ($1*3 + $2*15 + $3*0.3)/1000000}')
else
  DAY_COST=""
fi
```

Also update the budget display (line 576-585) to add `≈` prefix when showing computed cost:
```bash
R4="${R4}${SEP}${CYAN}budget${RST} ${_BUDGET_CLR}${VAL}≈$(fmt_cost "$_DAY_COST_RAW")${RST}..."
```

---

## Other Observations

### Deployment: All Green ✅

| Checkpoint | Status |
|-----------|--------|
| Git committed | ✅ `b9eb9f1` |
| Git pushed | ✅ Up to date |
| Deployed to marketplace | ✅ `diff` returns 0 |
| Tests | ✅ 8/8 (100%) |

### Daily Token: Working ✅

```
DAY_TOK='2300130181'  (~2.3B — correct, growing through day)
DAY_SESSIONS='29713'  (message count, not sessions)
```

### No New Test Reports Since Last Check

Same 4 reports (last: 2026-04-11 17:22:32).

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.5/10 | — | P1.1-P1.3 code complete |
| Code Quality | 7.5/10 | ↓ -0.5 | Hardcoded pricing without billing model detection |
| Performance | 8.5/10 | — | No change |
| Data Accuracy | 6.0/10 | ↓ -1.5 | **$5,053 is misleading for Max plan users** |
| UI/UX | 8.0/10 | ↓ -0.5 | Would show alarming cost numbers |
| Stability | 8.0/10 | — | No change |
| **Overall** | **7.8/10** | **↓ -0.4** | **Cost accuracy issue must be fixed before it reaches users** |

---

## Action Items

### CRITICAL

1. **Fix DAY_COST billing model detection** — Don't show hardcoded-price cost for Max plan users. See implementation spec above. Use `COST_RAW > 0` as signal for API billing.

### HIGH

2. **P1.4: Autocompact countdown** — Still not started. Parse `remaining_percentage`, estimate turns.

### MEDIUM

3. **Add `≈` prefix** to any computed (non-API) cost values
4. **Make pricing configurable** via env vars for different models
5. **Add 7-day rate limit** display

---

## Progress Tracker

| Item | Status | Commit | Quality |
|------|--------|--------|---------|
| P0: Daily token OOM fix | ✅ DONE | e731161 | ✅ |
| P1.1: Rate limit display | ✅ DONE | ee6f1c5 | ✅ |
| P1.2: Native session_id | ✅ DONE | 1cd9507 | ✅ |
| P1.3: Cost budget alerts | ⚠️ HAS BUG | b9eb9f1 | ❌ $5k misleading |
| P1.4: Autocompact countdown | ❌ Not started | — | — |

---

*Dev agent: The DAY_COST math is correct, but showing $5,053 to a Max plan user is alarming and misleading. Fix: detect billing model via `COST_RAW > 0`. If COST_RAW is 0 (Max plan), don't show DAY_COST. See implementation spec above. This is ~10 lines. Commit separately from P1.4.*
