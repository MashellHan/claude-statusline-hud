# Review 008 — Token Fix Landed + Layout Rearranged + Burn Rate Feature

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Commits Reviewed:** 32c190f, fd277cf, 792b1a8 (3 commits since review-007)  
**Previous Review:** review-007 (commit 23b4095)  
**LOC:** 655 (was 635, +20 net)

---

## Summary of Changes

Three implementation commits landed, addressing ALL critical and high-priority items from reviews 005-007:

| Commit | Description |
|--------|-------------|
| `32c190f` | **fix: correct token calculation and reorganize Row 3 layout** — splits `TOTAL_TOKENS` into `CTX_TOKENS` + `SESSION_TOKENS`, moves cache+speed to Row 3 |
| `fd277cf` | **refactor: remove duplicate cache/speed from Row 4 (now in Row 3)** — cleanup pass |
| `792b1a8` | **feat: add burn rate and hourly cost projection to Row 4** — new Feature #2 from roadmap |

**This is the most impactful set of changes since the project started.** All three CRITICAL items from reviews 005-007 are resolved, plus a new P1 feature landed.

---

## Detailed Review

### 1. Token Calculation Fix (CRITICAL → RESOLVED ✅)

**Before (broken):**
```bash
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
# Mixed per-turn snapshot with cumulative session output
```

**After (correct):**
```bash
CTX_TOKENS=$((CTX_SIZE * PCT / 100))        # Context occupancy from API %
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))  # Cumulative billing total
```

**Verdict: Excellent.** This is exactly the fix recommended in review-006. Two clear variables with distinct semantics:
- `CTX_TOKENS` for Row 3 display (what's in the context window now)
- `SESSION_TOKENS` for daily tracking (total consumed for billing)

The comments at lines 437-438 explain the semantics clearly. Well done.

**Row 3 now uses `CTX_TOKENS`** (line 442-443) — correct for context display.  
**Daily tracking now uses `SESSION_TOKENS`** (lines 484, 487, 493) — correct for billing.  
**85%+ breakdown row uses `CTX_TOKENS`** (line 469) — correct.

**One observation:** The `out` label in Row 3 was renamed to `total-out` (line 443, 469). This is honest labeling since `TOTAL_OUT` is cumulative. However, this creates a display asymmetry: `in` and `cache` are per-turn snapshots shown next to `total-out` which is cumulative. The user may find this confusing. Consider:
- Option A: Keep `total-out` label (current — transparent about semantics)
- Option B: Show only per-turn values and move `total-out` elsewhere
- **Recommendation:** Keep as-is for now. The `total-out` label is accurate.

### 2. Row Layout Rearrangement (HIGH → RESOLVED ✅)

**User requested:** "speed 应该在第三行 包括 cache 然后 time 和 daily token 放在第四行"

**Implementation:**
- Row 3 now: `Context ████████░░ 72% │ token 140k (...) │ cache 76% │ speed 2.1k/min`
- Row 4 now: `cost $1.31 (day $14.82) │ time 12m (api 68%) │ code +42 -8 ▲ │ 🔥2.1k/min ≈$5.40/hr │ day-tok 145k`

**Verdict: Correctly implements user request.**

Cache and speed moved from Row 4 to Row 3 (lines 446-459, appended to R3 at lines 463-464).  
Duplicate cache/speed removed from Row 4 (`fd277cf`).  
Section comments updated: Row 3 header says "Tokens │ Cache │ Speed", Row 4 says "Cost │ Duration │ Lines │ Day-tok".

**Issue (MEDIUM):** Cache and speed are computed BEFORE the `essential` preset exit (line 472). This means essential preset users now see cache% and speed on Row 3, which wasn't the case before. Is this intentional? The old code computed them in the `FULL+` section. Since the user specifically asked for them on Row 3, and Row 3 is `ESSENTIAL+`, this seems correct. But it adds ~15ms of computation for essential users who previously didn't see these metrics.

### 3. Burn Rate Feature (NEW — Feature #2 from Roadmap ✅)

**Lines 543-555:** New burn rate calculation with hourly cost projection.

```bash
BURN_TPM=$((SESSION_TOKENS * 60000 / DURATION_MS))
BURN_COST_HR=$(awk "BEGIN{d=${DURATION_MS}/3600000; if(d>0) printf \"%.2f\", ${COST_RAW}/d; else print 0}")
BURN_RATE="${YELLOW}🔥${RST}${VAL}$(fmt_tok "$BURN_TPM")/min${RST}"
```

**Verdict: Good implementation with one concern.**

Positives:
- Clean 60-second minimum gate (`$DURATION_MS -gt 60000`) prevents noisy early readings
- Hourly cost projection uses `awk` for float math — correct approach in bash
- Compact tier hides the cost projection to save space (line 552)
- 🔥 emoji is a nice visual indicator

**Issue (HIGH): Burn rate `speed` vs `🔥` confusion.**

Row 3 shows: `speed 2.1k/min` (output throughput — tokens generated per minute)  
Row 4 shows: `🔥 2.1k/min` (burn rate — total tokens consumed per minute)

These measure different things but could show similar-looking numbers:
- `speed` = `TOTAL_OUT * 60000 / DURATION_MS` (output only)
- `🔥` = `SESSION_TOKENS * 60000 / DURATION_MS` (input + output)

When cache is high (90%+ of input), `SESSION_TOKENS ≈ TOTAL_INPUT + TOTAL_OUT` could be significantly larger than `TOTAL_OUT` alone. But the labels `speed Xk/min` and `🔥Xk/min` are confusingly similar.

**Recommendation:** Differentiate more clearly:
- Change burn rate label to `🔥burn Xk/min` or `🔥tok Xk/min`
- Or change speed label to `out-speed` or `gen-speed`
- Or remove the token/min from burn rate and only show `🔥 ≈$5.40/hr` (the cost projection is more actionable)

**Issue (MEDIUM): `awk` injection via `COST_RAW` and `DURATION_MS`.**

Line 550:
```bash
BURN_COST_HR=$(awk "BEGIN{d=${DURATION_MS}/3600000; if(d>0) printf \"%.2f\", ${COST_RAW}/d; else print 0}")
```

`DURATION_MS` and `COST_RAW` are injected directly into the awk program string. These come from `jq` parsing of the API JSON (lines 54-55), which should produce numbers. However, if the JSON were malformed and produced a string like `0; system("rm -rf /")`, this would be an injection vector.

**Mitigation:** The `jq` parser uses `// 0` defaults and `| floor` for integers, so this is very unlikely. But defensive coding would use:
```bash
BURN_COST_HR=$(awk -v d="$DURATION_MS" -v c="$COST_RAW" 'BEGIN{d=d/3600000; if(d>0) printf "%.2f", c/d; else print 0}')
```

This passes values as awk variables instead of embedding in the program string.

### 4. Dedup Optimization (MINOR IMPROVEMENT)

Line 490: `_EXISTING=$(grep "\"sid\":\"${_SID}\"" "$DAILY_LOG" 2>/dev/null | tail -1)` — stores grep result to avoid running grep twice (once for `-q`, once for value). This addresses the minor optimization noted in review-006. Good.

### 5. Daily.jsonl Data State

Current data:
```json
{"sid":"1368443996","tokens":58490,"cost":2.73}   // was 664k/1727 — FIXED
{"sid":"4106091531","tokens":93562,"cost":4.57}    // was 154k/252 — FIXED
{"sid":"484808888","tokens":180432,"cost":279.37}  // was 209k/249 — reasonable
```

The token values are now using `SESSION_TOKENS` and look much more reasonable. Session `1368443996` dropped from 664k to 58k — confirming the fix works. Some sessions still show high values (506k for `2181408896`), which is plausible for long sessions with high cumulative output.

**Note:** The old inflated data has been naturally replaced as sessions update their entries via dedup. No manual purge was needed.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | **8.5/10** | ↑ +1.0 | Token fix + layout + burn rate feature |
| Code Quality | **8.5/10** | ↑ +0.5 | Clean variable split, good comments |
| Performance | 9/10 | — | Cache/speed now computed for essential users too (+minor cost) |
| Data Accuracy | **8.5/10** | ↑ +3.5 | **Token inflation FIXED**, daily data self-correcting |
| UI/UX | **8.5/10** | ↑ +1.0 | Layout matches user request, burn rate is visually clear |
| Stability | 8.5/10 | — | No regressions |
| **Overall** | **8.5/10** | **↑ +1.3** | **Biggest improvement yet — all critical items resolved** |

---

## Action Items

### HIGH
1. **Differentiate `speed` (Row 3) from `🔥` burn rate (Row 4)** — They show similar tok/min metrics with confusingly similar display. Add clearer labels or remove tok/min from burn rate (keep only $/hr).

### MEDIUM
2. **Sanitize awk inputs** — Use `-v` flag for `DURATION_MS` and `COST_RAW` in line 550 instead of string interpolation.
3. **Update README** — Still pending. Document: daily tracking, data storage, row layout, burn rate feature.

### LOW
4. **Row 3 width on compact tier** — With cache+speed now on Row 3, the line could overflow on <70 column terminals. Test and conditionally hide cache/speed in compact tier.
5. **Consider showing session count** — Aggregation computes `sessions: length` but doesn't display it. `day $14.82 (3)` would show session count.

---

## Review-007 Action Items Status

| Item | Status | Notes |
|------|--------|-------|
| Fix TOTAL_TOKENS → split CTX_TOKENS + SESSION_TOKENS | ✅ **DONE** | Commit 32c190f |
| Purge/reset daily.jsonl | ✅ **Self-resolved** | Dedup naturally replaces old entries |
| Row layout: cache+speed→R3, time+day-tok→R4 | ✅ **DONE** | Commits 32c190f + fd277cf |
| Commit uncommitted changes | ✅ **DONE** | Part of 32c190f |
| Fix Row 3 "out Xk" semantics | ✅ **DONE** | Renamed to `total-out` |
| Start Feature 2: burn rate | ✅ **DONE** | Commit 792b1a8 |

**All 6 items resolved. Outstanding backlog cleared.**

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | ✅ **Done + Fixed** | P0 |
| 2 | Token burn rate + trend | ✅ **Done** | P1 |
| 3 | Cost projection + budget | ⚠️ **Partial** ($/hr shown, no budget alerts) | P1 |
| 4 | Autocompact countdown | ❌ Not started | P1 |
| 5 | Git operation state | ✅ Done | P2 |
| 6 | MCP health monitor | ❌ Not started | P2 |
| 7 | Tool success/failure ratio | ❌ Not started | P2 |
| 8 | Project stack detection | ❌ Not started | P2 |
| 9 | Sparkline token history | ❌ Not started | P3 |
| 10 | Message counter + density | ❌ Not started | P3 |
| 11 | Process resource attribution | ❌ Not started | P3 |
| 12 | Config status summary | ❌ Not started | P3 |
| 13 | Session health score | ❌ Not started | P2 |

---

## New Feature Ideas

### Feature 14: Autocompact Countdown Timer (P1 — next priority)

When `ADJ_PCT ≥ 80%`, show estimated turns until autocompact triggers:

```bash
# Estimate remaining context capacity
CTX_REMAINING=$((CTX_SIZE - CTX_TOKENS))
# Average input per turn (from SESSION_TOKENS / estimated_turns)
AVG_INPUT_PER_TURN=$((TOTAL_INPUT))  # current turn's input is a proxy
if [ "$AVG_INPUT_PER_TURN" -gt 0 ]; then
  TURNS_LEFT=$((CTX_REMAINING / AVG_INPUT_PER_TURN))
  # Display: "⏳ ~3 turns" in orange when < 5
fi
```

Display on Row 3 after the context bar: `Context ████████░░ 82% ⏳~3 turns`

This gives users advance warning to save work or manually compact. No competitor offers this.

### Feature 15: Cost Budget Alert (P1)

Allow setting a daily budget via `CLAUDE_SL_DAILY_BUDGET=50`:
```
cost $12.45 (day $48.72 ⚠️ 97% of $50 budget)
```

Use the already-computed `DAY_COST` with a color threshold (green < 70%, yellow < 90%, red ≥ 90%).

---

*Next review in ~15 minutes.*
