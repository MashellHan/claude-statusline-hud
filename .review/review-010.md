# Review 010 — Daily Token: Implementation Exists But NOT Deployed + OOM Bug

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** ba26780 (HEAD) + uncommitted changes in working tree  
**Previous Review:** review-009 (commit cebf664)  
**LOC:** 635 (working tree, down from 655 committed)

---

## Status: THREE Problems Found

### Problem 1: Repo Has Fix, But NOT Committed

Dev agent implemented the transcript-based scanning in the **repo working tree**, but **never committed it**. Current state:

| Location | Version | Daily Token Works? |
|----------|---------|-------------------|
| Repo (committed HEAD) | Old daily.jsonl-based | No (656x undercount) |
| Repo (working tree, uncommitted) | New transcript-based | **Has OOM bug** (see Problem 2) |
| Marketplace install (what actually runs) | Old daily.jsonl-based | **No — this is what user sees** |

**The user's Claude Code is running the marketplace version** at:
```
~/.claude/plugins/marketplaces/claude-statusline-hud/plugins/claude-statusline-hud/scripts/statusline.sh
```

This is the OLD code with daily.jsonl. The new transcript scanning code exists only in the repo working tree and has never been deployed.

### Problem 2: New Code Has an OOM/Timeout Bug

The new transcript scanning code (repo working tree, lines 492-501) does:

```bash
_DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" 2>/dev/null | \
  xargs grep -h "input_tokens" 2>/dev/null | \
  jq -s '[.[].message.usage // {} | ...]' 2>/dev/null)
```

**The `jq -s` (slurp) loads ALL matching lines into memory at once.** Today this is:

- 163 transcript files
- 20,084 matching lines
- **33 MB of raw JSON data**

`jq -s` tries to parse 33MB into a single JSON array. This either OOMs or times out silently, returning empty output. **I tested this directly and confirmed it produces no output.**

### Problem 3: `sessions` Count Is Wrong

The new code computes `sessions: length` — but `length` counts the number of **usage entries** (individual API messages), not session files. Today this returns 19,831 "sessions" when there are actually 28 main sessions + 135 subagent sessions = 163 total.

---

## Verified Fix: Two-Stage jq Pipeline

I tested and confirmed a working approach. The key insight: **extract small usage objects first with streaming jq, THEN aggregate.**

### Tested & Verified Results

```
Approach: jq streaming extract → jq -s aggregate
Result:   1,735M tokens, 19,797 messages, 1.2 seconds

Approach: jq streaming extract → awk sum (fastest)  
Result:   1,736M tokens, 19,831 messages, 1.4 seconds

Breakdown: input=1,547M  output=3M  cache_read=186M
```

Both approaches complete in ~1.4 seconds, well within the 30-second cache window.

### Recommended Implementation

Replace lines 490-505 in the repo working tree with:

```bash
  _PROJECTS_DIR="$HOME/.claude/projects"
  if [ -d "$_PROJECTS_DIR" ]; then
    # Two-stage pipeline: streaming extract → aggregate
    # Stage 1: jq -c extracts tiny {i,o,cr} objects (streaming, constant memory)
    # Stage 2: jq -s aggregates the small objects (a few KB)
    _DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
      -newermt "$TODAY 00:00" 2>/dev/null | \
      xargs grep -h "input_tokens" 2>/dev/null | \
      jq -c '.message.usage // empty |
        {i: (.input_tokens // 0), o: (.output_tokens // 0),
         cr: (.cache_read_input_tokens // 0)}' 2>/dev/null | \
      jq -s '{
        tokens: (map(.i + .o + .cr) | add // 0),
        messages: length
      }' 2>/dev/null)
    DAY_TOK=$(printf '%s' "$_DAY_STATS" | jq -r '.tokens // 0' 2>/dev/null)
    DAY_SESSIONS=$(printf '%s' "$_DAY_STATS" | jq -r '.messages // 0' 2>/dev/null)
    printf "DAY_TOK='%s'\nDAY_SESSIONS='%s'\nDAY_COST=''\n" \
      "$DAY_TOK" "$DAY_SESSIONS" > "$DAILY_CACHE"
  fi
```

### Why This Works

| Step | Data Size | Memory |
|------|-----------|--------|
| `grep -h "input_tokens"` | 33 MB (full JSONL lines) | streaming |
| `jq -c '.message.usage ...'` | **~400 KB** (tiny JSON per line) | streaming |
| `jq -s '{tokens: ...}'` | ~400 KB (small objects) | fits easily |

Stage 1 (`jq -c`) runs in constant memory — it processes one line at a time. Only Stage 2 needs to slurp, but by then the data is only ~400 KB.

---

## Deployment Checklist for Dev Agent

1. **Fix the OOM bug** — Replace single `jq -s` with two-stage pipeline (see above)
2. **Commit the changes** — The transcript scanning code has never been committed
3. **Copy to marketplace install** — After committing, sync to:
   ```
   cp plugins/claude-statusline-hud/scripts/statusline.sh \
      ~/.claude/plugins/marketplaces/claude-statusline-hud/plugins/claude-statusline-hud/scripts/statusline.sh
   ```
4. **Clear stale cache** — `rm -f /tmp/.claude_sl_daily_*` to force fresh scan
5. **Verify output** — The `day-tok` display should show ~1.7B (1736M) not 2M

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 7.5/10 | ↓ -0.5 | Transcript scanning written but broken + undeployed |
| Code Quality | 7/10 | ↓ -1.5 | OOM bug in pipeline, uncommitted code |
| Performance | 7/10 | ↓ -2.0 | 33MB jq -s will hang on large installations |
| Data Accuracy | **3/10** | ↑ +1.0 | Right approach, wrong execution. User still sees old data |
| UI/UX | 8.5/10 | — | Layout is good |
| Stability | 6/10 | ↓ -2.5 | Silent failure (empty output) when data is large |
| **Overall** | **6.0/10** | **↓ -0.5** | **Good direction but needs OOM fix + deploy** |

---

## Action Items

### CRITICAL

1. **Fix OOM: two-stage jq pipeline** — See exact code above. Tested and verified.
2. **Commit the transcript scanning code** — It's been sitting uncommitted.
3. **Deploy to marketplace install path** — User is running old code.
4. **Clear daily cache** after deploying — `rm /tmp/.claude_sl_daily_*`

### HIGH

5. **Fix session count** — Show file count (actual sessions) not message count. Use `find | wc -l` separately.
6. **Handle `xargs` argument list too long** — With many files, `xargs` may split into multiple invocations. This is OK for grep but verify behavior.

### MEDIUM

7. **Add timeout/size guard** — If scan takes >5s, abort and show "scanning..." placeholder.
8. **Consider caching per-file results** — Only re-scan files that changed since last cache.

---

*Dev agent: Fix the OOM bug, commit, deploy. This is a 4-step process. The user is waiting.*
