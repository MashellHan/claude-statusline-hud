# Review 012 — OOM Fix in Working Tree, Competitive Research Complete, Rate Limit Discovery

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** 5878829 (HEAD) + uncommitted working tree changes  
**Previous Review:** review-011 (design clarification)  
**LOC:** ~612 (committed at e731161, down from 655)

---

## Status Summary

### ✅ GOOD NEWS: OOM Fix Is Correct

The dev agent implemented the **two-stage jq pipeline** exactly as specified in review-010:

```bash
# Working tree (UNCOMMITTED) — lines 493-502:
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
```

This replaces the old `jq -s` on 33MB with a two-stage pipeline (streaming extract → small aggregate). The cache-first check is also correct — `file_age` check before the expensive scan.

**Verified the diff:** 43 deletions, 23 insertions. The old `daily.jsonl` self-tracking system is fully replaced with transcript-based scanning. Net reduction of 20 lines. Clean.

### ✅ COMMITTED AND DEPLOYED

| Checkpoint | Status |
|-----------|--------|
| OOM fix implemented | ✅ Two-stage jq pipeline |
| Git committed | ✅ `e731161 refactor: rewrite daily token tracking to scan transcripts directly` |
| Git pushed | ✅ Pushed to origin/main |
| Deployed to marketplace | ✅ `diff` shows zero differences with marketplace install |
| Cache cleared | ⚠️ Needs verification — dev agent should run `rm -f /tmp/.claude_sl_daily_*` |

**The dev agent followed the auto-commit rule this time.** Commit `e731161` landed after review-011.

### 🆕 MAJOR DISCOVERY: Rate Limit Data Already in JSON

The official Claude Code statusline documentation reveals that `rate_limits` data is **already being passed** in the JSON input:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.5,
      "resets_at": 1744358400
    },
    "seven_day": {
      "used_percentage": 15.3,
      "resets_at": 1744876800
    }
  }
}
```

**No competitor displays rate limit data.** We would be first-to-market. This is a ~20-line feature with zero new data sources.

---

## Competitive Research Findings

### Landscape (6 Claude Code statusline projects found)

| Project | Stars | Our Advantage Over Them |
|---------|-------|------------------------|
| jarrodwatts/claude-hud | 18.3k | We have presets, adaptive width, burn rate |
| sirmalloc/ccstatusline | 7.1k | We have presets, they have theming |
| Haleclipse/CCometixLine | 2.6k | We have more data points, they're faster (Rust) |
| rz1989s/claude-code-statusline | 422 | They have 28 components + MCP monitoring |
| chongdashu/cc-statusline | 563 | We have presets, they have progress bars |

**Key gaps to close:**
1. Rate limit display — **nobody has this yet** (P1.1, first mover)
2. MCP monitoring — only rz1989s has it (P2.1)
3. Theme system — sirmalloc and CCometixLine have it (P3)

### Cross-Platform Assessment

| Platform | Feasibility | Priority |
|----------|-------------|----------|
| VS Code | ✅ HIGH (mature API, existing examples) | P2.3 |
| Cursor IDE | ❌ NOT FEASIBLE (no public API) | Skip |
| OpenCode/CLI | ⚠️ MEDIUM | P3+ |

See `.review/feature-roadmap-v2.md` for full competitive matrix and specs.

---

## Code Review: Working Tree Diff

### What Changed (43 deletions, 23 insertions)

**Removed:**
- Old `DAILY_DIR` / `DAILY_LOG` / `daily.jsonl` self-tracking system
- Session dedup logic (grep + sed + append)
- 30-day pruning logic
- Old `jq -rs` aggregation on daily.jsonl

**Added:**
- Cache-first pattern: check `file_age` before scanning
- Transcript-based scanning via `find | xargs grep | jq -c | jq -s`
- `DAY_SESSIONS` variable (message count, not session count — see Issue 1)

### Issue 1: DAY_SESSIONS Is Still Message Count, Not Session Count

```bash
DAY_SESSIONS=$(printf '%s' "$_DAY_STATS" | jq -r '.messages // 0' 2>/dev/null)
```

`.messages` is `length` of usage entries (API calls), not the number of session files. Today this would show ~20,000 "sessions" when there are ~163. But `DAY_SESSIONS` isn't currently displayed in the UI, so this is LOW priority. When we do show it, use `find | wc -l` for actual file count.

### Issue 2: `xargs` Argument Limit

With many transcript files, `xargs` may split into multiple `grep` invocations. This is OK — `grep -h` output is line-by-line, so splitting is safe for the streaming pipeline. No action needed.

### Issue 3: awk Injection (Carried from review-010)

Line 529 (burn rate) now correctly uses `-v` flags:
```bash
BURN_COST_HR=$(awk -v d="$DURATION_MS" -v c="$COST_RAW" 'BEGIN{...}')
```

✅ Fixed. Previously injected variables directly into program string.

---

## Action Items for Dev Agent

### P0 — VERIFY DEPLOYMENT

1. **Clear stale caches** (if not already done):
   ```bash
   rm -f /tmp/.claude_sl_daily_* /tmp/.claude_sl_*
   ```

2. **Verify output:** After clearing cache and waiting 30s, the `day-tok` field should show ~1.7B (≈1736M), not 2M.

### P1.1 — HIGH (Next After P0)

5. **Add rate limit display** — See feature-roadmap-v2.md P1.1 spec.
   - Parse `rate_limits.five_hour.used_percentage` and `resets_at` from JSON
   - Display: `rl 43% │ reset 2h14m`
   - ~20 lines. Zero new data sources. First-to-market feature.

### P1.2 — HIGH

6. **Use native `session_id`** instead of cksum hack:
   ```bash
   # Replace: _SID=$(printf '%s' "$TRANSCRIPT" | cksum | cut -d' ' -f1)
   # With:    _SID=$(printf '%s' "$JSON" | jq -r '.session_id // empty')
   ```

### MEDIUM

7. **Add timeout guard** to transcript scanning — if scan takes > 5s, abort and show placeholder
8. **When displaying DAY_SESSIONS in future**, use `find | wc -l` for actual session file count

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 7.5/10 | — | OOM fix deployed! Rate limits spec ready. |
| Code Quality | 8.0/10 | ↑ +1.0 | OOM fix committed, awk injection fixed, auto-commit followed |
| Performance | 8.5/10 | ↑ +1.5 | Two-stage pipeline deployed (~1.4s for 33MB) |
| Data Accuracy | 7.0/10 | ↑ +4.0 | Transcript scanning deployed! Needs cache clear + verify. |
| UI/UX | 8.5/10 | — | No change |
| Stability | 7.5/10 | ↑ +1.5 | OOM fix prevents silent failures |
| **Overall** | **7.8/10** | **↑ +1.8** | **OOM fix landed. Next: rate limits (P1.1) for 9.0+** |

**Score jumped from 6.0 to 7.8 with the OOM fix deployment. Adding rate limit display (P1.1) will push to 9.0+.**

---

## New Documents

- `.review/feature-roadmap-v2.md` — Comprehensive roadmap with competitive analysis, official JSON schema fields, cross-platform assessment, and feature specs for P1.1-P2.3.

---

*Dev agent: P0 is DONE (commit e731161). Clear cache (`rm -f /tmp/.claude_sl_daily_*`) and verify. Then immediately start P1.1 (rate limit display — 20 lines, uses existing JSON data, first-to-market). See feature-roadmap-v2.md for the spec.*
