# Review 014 — P1.2 + P1.3 Landed, But Budget Alert Is a Dead Feature

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** 1cd9507 `feat: use native session_id + add daily cost budget alerts (P1.2, P1.3)`  
**Previous Review:** review-013 (rate limit display)  
**LOC:** ~655 (up from 637, +18 lines)

---

## Status Summary

### P1.2: Native session_id ✅ WELL DONE

The dev agent correctly replaced the cksum hack with native `session_id`:

```bash
# NEW (lines 228-230):
if [ -n "$SESSION_ID" ]; then
  _SID="$SESSION_ID"
elif [ -n "$TRANSCRIPT" ]; then        # Fallback: cksum
  _SID=$(printf '%s' "$TRANSCRIPT" | cksum | awk '{print $1}')
else
  _SID="$$"
fi
```

**What's good:**
- Graceful fallback chain: `session_id` → cksum → PID
- Handles empty/missing `session_id` correctly
- `SESSION_ID` added to jq extraction and fallback defaults
- No behavioral change if API doesn't provide session_id

### P1.3: Budget Alert — ⚠️ DEAD FEATURE (Never Fires)

The budget display code (lines 569-579) is correct **in isolation**, but it depends on `DAY_COST`, which is **always empty**.

**Root cause chain:**

1. Transcript scanning (line 531) writes: `DAY_COST=''` (hardcoded empty)
2. Cache sources this: `DAY_COST=''`
3. Budget code checks: `_DAY_COST_RAW="${DAY_COST:-0}"` → gets `''` which is not `"0"` but is empty
4. Then checks: `[ -n "$_DAY_COST_RAW" ] && [ "$_DAY_COST_RAW" != "0" ]` → `''` fails `-n`, so **body never executes**

**Why `DAY_COST` is empty:** The old `daily.jsonl` system tracked per-session cost. The new transcript scanning only extracts tokens (input/output/cache_read) — it does NOT extract cost data from transcripts.

**Two paths to fix:**

#### Option A: Calculate DAY_COST from DAY_TOK (Approximate)

Use the known Sonnet 4.6 pricing to estimate daily cost from tokens:
- Input: $3/1M tokens, Output: $15/1M tokens, Cache read: $0.30/1M tokens
- This requires splitting `DAY_TOK` into input/output/cache components (which the pipeline already extracts but doesn't persist separately)

**Implementation:** Modify the two-stage jq pipeline to also output `input_sum`, `output_sum`, `cache_read_sum`, then calculate cost with awk.

#### Option B: Sum Per-Session COST_RAW (Accurate)

The per-session `COST_RAW` comes from the statusline JSON (Claude Code calculates it). Accumulate it in the daily cache file whenever we write to it. But this only captures sessions where the statusline renders — we'd be back to the old undercounting problem.

**Recommendation: Option A.** Extend the existing two-stage pipeline to split tokens by type and calculate approximate cost. The transcript data has the breakdown (input/output/cache_read are already in the jq extraction).

---

## Deployment Checklist

| Checkpoint | Status |
|-----------|--------|
| Code implemented | ✅ 18 lines added |
| Git committed | ✅ `1cd9507` |
| Git pushed | ✅ Up to date with origin |
| Deployed to marketplace | ✅ `diff` returns 0 |
| Tests passing | ✅ 8/8 (100%) |

### Daily Token Cache

```
DAY_TOK='2113070380'    ← ~2.1B tokens (growing through the day, correct)
DAY_SESSIONS='26369'    ← message count (not session count)
DAY_COST=''             ← EMPTY — budget alert never fires
```

---

## Code Review Details

### P1.2 Session ID: Clean ✅

- **Lines changed:** 5 (jq extraction + fallback logic)
- **Backward compatible:** Yes — falls back to cksum if session_id is missing
- **Security:** No issues — session_id is read-only from Claude Code

### P1.3 Budget Alert: Correct Logic, Wrong Data Source ⚠️

**The code itself is well-written:**
```bash
if [ -n "$CLAUDE_SL_DAILY_BUDGET" ] && [ "$CLAUDE_SL_DAILY_BUDGET" != "0" ]; then
  _DAY_COST_RAW="${DAY_COST:-0}"
  if [ -n "$_DAY_COST_RAW" ] && [ "$_DAY_COST_RAW" != "0" ]; then
    _BUDGET_PCT=$(awk -v c="$_DAY_COST_RAW" -v b="$CLAUDE_SL_DAILY_BUDGET" \
      'BEGIN{if(b>0) printf "%d", (c/b)*100; else print 0}')
    ...
  fi
fi
```

**Positive:**
- Uses `awk -v` for injection-safe variable passing ✅
- Proper guard against zero budget (division by zero) ✅
- Color coding reuses `bar_color` for consistency ✅
- ⚠️ emoji at ≥90% threshold ✅

**Problem:** `DAY_COST` is always empty, so none of this code ever executes.

---

## Action Items for Dev Agent

### CRITICAL

1. **Fix DAY_COST computation** — Extend the two-stage jq pipeline to compute approximate daily cost.

   Modify the second `jq -s` stage to output token breakdowns:
   ```bash
   jq -s '{
     input: (map(.i) | add // 0),
     output: (map(.o) | add // 0),
     cache_read: (map(.cr) | add // 0),
     tokens: (map(.i + .o + .cr) | add // 0),
     messages: length
   }' 2>/dev/null)
   ```

   Then calculate cost with awk using Sonnet pricing ($3/$15/$0.30 per 1M):
   ```bash
   DAY_COST=$(printf '%s' "$_DAY_STATS" | jq -r '[.input, .output, .cache_read] | @tsv' | \
     awk -F'\t' '{printf "%.4f", ($1*3 + $2*15 + $3*0.3)/1000000}')
   ```

   Update the cache line to persist `DAY_COST`:
   ```bash
   printf "DAY_TOK='%s'\nDAY_SESSIONS='%s'\nDAY_COST='%s'\n" \
     "$DAY_TOK" "$DAY_SESSIONS" "$DAY_COST" > "$DAILY_CACHE"
   ```

   **Note:** This is approximate — it assumes Sonnet 4.6 pricing and doesn't account for cache creation tokens or model variations. But it's much better than empty.

### HIGH

2. **P1.4: Autocompact countdown** — Parse `remaining_percentage`, estimate remaining turns, display `⏳ ~N turns`. See feature-roadmap-v2.md.

### MEDIUM

3. **Add 7-day rate limit** — Parse `seven_day` fields, show when relevant
4. **Make pricing configurable** — `CLAUDE_SL_TOKEN_PRICE_INPUT` etc. env vars for different models

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.5/10 | — | P1.2 done, P1.3 code exists but non-functional |
| Code Quality | 8.0/10 | — | Clean code, proper fallbacks, but dead feature |
| Performance | 8.5/10 | — | No change |
| Data Accuracy | 7.5/10 | ↓ -0.5 | DAY_COST empty = budget alert dead |
| UI/UX | 8.5/10 | — | Good budget display design (when it works) |
| Stability | 8.0/10 | — | session_id fallback is well designed |
| **Overall** | **8.2/10** | **↓ -0.1** | **P1.2 is solid. P1.3 needs DAY_COST fix to become functional.** |

Score slightly down because shipping a feature that never fires is a quality concern. The code is correct — it just needs data.

---

## Progress Tracker

| Item | Status | Commit |
|------|--------|--------|
| P0: Daily token OOM fix | ✅ DONE | e731161 |
| P1.1: Rate limit display | ✅ DONE | ee6f1c5 |
| P1.2: Native session_id | ✅ DONE | 1cd9507 |
| P1.3: Cost budget alerts | ⚠️ PARTIAL | 1cd9507 (display code done, DAY_COST empty) |
| P1.4: Autocompact countdown | ❌ Not started | — |

---

*Dev agent: P1.2 is solid, great fallback design. P1.3 needs one fix — DAY_COST is always empty because the transcript pipeline doesn't compute cost. See the CRITICAL action item above for exact code to add. This is ~8 lines. Then P1.3 will be fully functional.*
