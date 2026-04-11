# Review 009 — CRITICAL: Daily Token Tracking Is Fundamentally Broken

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** 792b1a8 (HEAD)  
**Previous Review:** review-008 (commit 26a7420)  
**LOC:** 655

---

## User Report

> "我觉得很有问题 我本地看我今天都几百个 M token 了 但是显示只有 2M. 我要查的不是当前 session,而是 claude code 当天所有"

Translation: Daily token count shows ~2M but user's actual usage is hundreds of millions. User wants **ALL Claude Code sessions today**, not just the current one.

## Root Cause: TWO Fundamental Design Flaws

### Flaw 1: Only Tracks Statusline-Visible Sessions

**daily.jsonl only records sessions where the statusline renders.** Today's evidence:

| Metric | Value |
|--------|-------|
| Main session transcripts today | **25** |
| Sessions recorded in daily.jsonl | **11** |
| **Sessions completely missing** | **14 (56%)** |

The statusline records a session in daily.jsonl during its render cycle (lines 484-501). If a session starts, does work, and ends before/between statusline renders, or if the session runs in a project where the statusline hasn't been invoked, it's never recorded.

### Flaw 2: SESSION_TOKENS Is Not Cumulative

Even for sessions that ARE tracked, `SESSION_TOKENS` is wildly wrong:

```bash
# Line 440:
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
```

- `TOTAL_INPUT` = `INPUT_TOK + CACHE_CREATE + CACHE_READ` → **per-turn snapshot** (current turn's input)
- `TOTAL_OUT` = `context_window.total_output_tokens` → **cumulative output** (all turns)

For a session with 50 turns, each sending 100k context:
- Actual input tokens consumed (billed): `50 × 100k = 5M`
- `TOTAL_INPUT` records only the LAST turn: `100k`
- `SESSION_TOKENS = 100k + output` — **misses 49 turns of input**

### Measured Impact

**Real daily usage** (scanned from ALL transcript files):

```
input_tokens:  1,534M  (cumulative across all turns, all sessions)
output_tokens:     3M
cache_read:      103M
cache_create:      0M
─────────────────────
TOTAL BILLED:  1,640M tokens
```

**daily.jsonl reports: 2.5M tokens** — off by **656x**.

---

## The Fix: Scan Transcript Files Directly

The statusline cannot rely on the API's `context_window.current_usage` for daily tracking — it's a per-turn snapshot. Instead, **scan ALL transcript JSONL files** in `~/.claude/projects/` to compute real daily totals.

### Approach: Transcript-Based Daily Aggregation

Every Claude Code session writes a transcript at:
```
~/.claude/projects/<project-dir-hash>/<session-uuid>.jsonl
```

Each `assistant` message contains `.message.usage`:
```json
{
  "type": "assistant",
  "message": {
    "usage": {
      "input_tokens": 45848,
      "output_tokens": 1024,
      "cache_read_input_tokens": 80000,
      "cache_creation_input_tokens": 0
    }
  }
}
```

### Algorithm

```bash
# Scan all transcripts modified today, sum usage from ALL assistant messages
TODAY=$(date +%Y-%m-%d)
DAILY_DIR="$HOME/.claude/statusline-data"
DAILY_CACHE="/tmp/.claude_sl_daily_$(id -u)"

# Only recompute if cache is stale (>30s)
if [ "$(file_age "$DAILY_CACHE")" -ge 30 ]; then
  # Find all transcript files modified today
  _TOTAL_IN=0 _TOTAL_OUT=0 _TOTAL_CACHE=0 _SESSIONS=0

  find "$HOME/.claude/projects" -name "*.jsonl" \
    -not -path "*/subagents/*" \
    -newermt "$TODAY 00:00" 2>/dev/null | while read _f; do
    # Sum usage from all assistant messages in this transcript
    _usage=$(grep "input_tokens" "$_f" 2>/dev/null | jq -s '
      reduce .[].message.usage as $u ({i:0,o:0,c:0};
        {i: (.i + ($u.input_tokens // 0)),
         o: (.o + ($u.output_tokens // 0)),
         c: (.c + ($u.cache_read_input_tokens // 0))}
      )' 2>/dev/null)
    # ... accumulate
  done

  # Write cache
  printf "DAY_TOK='%s'\nDAY_COST_EST='%s'\n" "$total" "$cost_est" > "$DAILY_CACHE"
fi
```

### Performance Concern

Scanning all transcripts on every statusline render (every ~1s) would be too expensive.
Solution: **Use the 30-second cache** that already exists. The scan only runs once every 30 seconds.

With 25 sessions and ~150 lines average, that's `grep | jq` on ~3,750 lines total. On a modern SSD this takes <1 second. Acceptable for a 30-second cache interval.

### What About Subagents?

Today's data shows subagent transcripts contain **13M tokens** — significant but smaller than main sessions. The user likely wants to see all usage including subagents.

Decision needed: Include subagent transcripts? They're at `*/subagents/*.jsonl`. Including them gives a complete picture but increases scan time.

**Recommendation:** Include subagents. The user said "claude code 当天所有" — ALL usage.

### Cost Estimation

The transcript files don't contain cost data directly. But we can estimate:

```
cost ≈ (input_tokens × $3/MTok + cache_read × $0.30/MTok + 
        cache_create × $3.75/MTok + output × $15/MTok) 
```

(Rates for Claude Sonnet. Could make configurable for Opus: $15/$1.50/$18.75/$75.)

Or: use the `COST_RAW` from the statusline API for the CURRENT session (which is accurate), and estimate others.

**Simplest approach:** Just show token count. Cost estimation is a separate feature.

---

## Implementation Spec for Dev Agent

### Changes Required

1. **Replace daily.jsonl-based tracking with transcript scanning**

   Remove lines 480-525 (the entire daily.jsonl write/read/prune block).
   
   Replace with a transcript scanner that:
   - Finds all `~/.claude/projects/**/*.jsonl` modified today
   - Sums `input_tokens + output_tokens + cache_read_input_tokens` from all assistant messages
   - Caches result for 30 seconds at `$DAILY_CACHE`
   - Outputs `DAY_TOK` and optionally `DAY_SESSIONS`

2. **Keep daily.jsonl for historical data** (optional)
   
   daily.jsonl can still exist for multi-day trends (Feature #9), but daily.jsonl should NOT be the source for "today's tokens". Today's data should come from live transcript scanning.

3. **Update DAY_TOK display**

   Current: `day-tok 2M` (wrong)  
   After fix: `day-tok 1640M` (correct, from transcript scan)

4. **Performance budget:** The scan must complete in <2 seconds. Use `grep` pre-filter + `jq -s` for efficient parsing. Cache 30 seconds.

### Pseudocode

```bash
# --- Daily token tracking (transcript-based) ---
DAY_TOK="" DAY_SESSIONS=""
DAILY_CACHE="/tmp/.claude_sl_daily_$(id -u)"

if [ "$(file_age "$DAILY_CACHE")" -lt 30 ] && [ -f "$DAILY_CACHE" ]; then
  . "$DAILY_CACHE"
else
  TODAY=$(date +%Y-%m-%d)
  _DAY_STATS=$(find "$HOME/.claude/projects" -name "*.jsonl" \
    -newermt "$TODAY 00:00" 2>/dev/null | \
    xargs grep -h "input_tokens" 2>/dev/null | \
    jq -s '[.[].message.usage // {} |
      {i: (.input_tokens // 0), o: (.output_tokens // 0),
       cr: (.cache_read_input_tokens // 0)}
    ] | {
      tokens: (map(.i + .o + .cr) | add // 0),
      sessions: (map(.i) | length)
    }' 2>/dev/null)
  DAY_TOK=$(printf '%s' "$_DAY_STATS" | jq -r '.tokens // 0')
  DAY_SESSIONS=$(printf '%s' "$_DAY_STATS" | jq -r '.sessions // 0')
  printf "DAY_TOK='%s'\nDAY_SESSIONS='%s'\n" "$DAY_TOK" "$DAY_SESSIONS" > "$DAILY_CACHE"
fi
```

**Note:** `xargs grep -h` is much faster than looping `while read`. It processes all files in a single grep invocation.

---

## Scores (Revised)

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.0/10 | ↓ -0.5 | Burn rate good, but daily tracking fundamentally wrong |
| Code Quality | 8.5/10 | — | Clean code, but wrong data source |
| Performance | 9/10 | — | Unchanged |
| Data Accuracy | **2/10** | ↓ -6.5 | **656x undercount. Worst score ever.** |
| UI/UX | 8.5/10 | — | Layout good |
| Stability | 8.5/10 | — | No regressions |
| **Overall** | **6.5/10** | **↓ -2.0** | **Data accuracy crisis overrides all other gains** |

---

## Action Items

### CRITICAL (Block Everything Else)

1. **Replace daily tracking with transcript-based scanning** — See implementation spec above. This is the #1 priority. The daily token display is 656x wrong.

### HIGH

2. **Include subagent transcripts in scan** — User said "所有" (all). Subagents are 13M tokens today.
3. **Handle date boundary** — Use file modification time (`-newermt "$TODAY 00:00"`) to find today's files. This may miss sessions started yesterday that continued into today.

### MEDIUM

4. **Cost estimation from transcripts** — Optional but useful. Apply model-specific rates to scanned tokens.
5. **Keep daily.jsonl for historical trends** — Don't delete it, but don't use it as the primary source for today's data.
6. **Performance test** — Verify scan completes in <2s with 142 transcript files.

### LOW (from review-008, still pending)

7. Differentiate `speed` (Row 3) vs `🔥` burn rate (Row 4) labels
8. Sanitize awk inputs with `-v` flag  
9. Update README

---

## Feature Tracking

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | Daily token/cost tracking | **BROKEN — needs transcript scanning** | P0 |
| 2 | Token burn rate + trend | ✅ Done | P1 |
| 3 | Cost projection + budget | ⚠️ Partial ($/hr done, no budget) | P1 |
| 4 | Autocompact countdown | ❌ Not started | P1 |
| 5 | Git operation state | ✅ Done | P2 |
| 6-12 | Various | ❌ Not started | P2-P3 |
| 13 | Session health score | ❌ Not started | P2 |
| 14 | Autocompact countdown timer | ❌ Not started | P1 |
| 15 | Cost budget alert | ❌ Not started | P1 |

---

*Dev agent: This is the highest priority item ever filed. The daily token display is off by 656x. Fix before any other work.*
