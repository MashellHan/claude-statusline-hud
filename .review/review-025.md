# Review 025 — CRITICAL: `find -newermt` Pre-Filter Drops 78% of Files

**Date:** 2026-04-16  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Severity:** CRITICAL  
**Type:** Correctness — Data Integrity (Undercounting)  
**Triggered by:** User report: "你怎么觉得你算的是对的 pew应该更准确吧 仔细审查一下"

---

## Summary

The daily token scanning pipeline undercounts by **7-12x** due to the `find -newermt "$TODAY 00:00"` pre-filter discarding 78% of files that contain today's messages. This is the **single largest bug** in the statusline HUD.

The third-party tool `pew` (`@nocoo/pew`) was used as ground truth. Per-file counting matches exactly between our jq pipeline and pew's Node.js parser — the entire discrepancy is from **which files get scanned**.

---

## The Bug

**Lines:** 599-600

```bash
_DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" -type f -print0 2>/dev/null | \
  xargs -0 grep -h "input_tokens" 2>/dev/null | \
  jq -c --arg today "$TODAY" '
    select(.timestamp != null and (.timestamp | startswith($today))) | ...
```

### Why `-newermt` Fails

`find -newermt "$TODAY 00:00"` matches files whose **mtime** (last modification time) is after local midnight. This was intended as a "harmless performance optimization" to avoid scanning old files.

**The assumption was:** files modified today will contain today's messages.  
**The reality:** Claude Code's architecture breaks this assumption.

### How Claude Code Creates Files

Claude Code spawns **subagent processes** that create separate `.jsonl` transcript files. These files:

1. May be created and **closed** during a previous day (e.g., a 30-second subagent at 23:58)
2. But the **parent session** continues into the next day, generating messages that reference the subagent's work
3. The subagent's file retains its original mtime (yesterday), so `find -newermt` skips it
4. More importantly: many files contain messages spanning **multiple days** — `find -newermt` only checks the file's mtime, not the timestamps inside

### Quantified Impact

| Metric | `-newermt` filtered | All files | % missed |
|--------|-------------------|-----------|----------|
| Files scanned | 120 | 542 | **78%** |
| `"input_tokens"` lines | 31,788 | 78,033 | **59%** |
| Messages (local 4/15) | ~993 | ~6,763 | **85%** |
| Tokens (local 4/15) | ~60M | ~704M | **91%** |

### Cross-Validation With Pew

Pew (`@nocoo/pew` v2.20.3) scans **all** `.jsonl` files under `~/.claude/projects/` — no mtime pre-filter. Its `normalizeClaudeUsage` function extracts the same fields:

```javascript
inputTokens = usage.input_tokens + (usage.cache_creation_input_tokens || 0)
cachedInputTokens = usage.cache_read_input_tokens || 0
outputTokens = usage.output_tokens || 0
```

Per-file verification on a single large file:

| Method | Tokens | Messages |
|--------|--------|----------|
| Our jq pipeline | 10,401,497 | 91 |
| Pew `parseClaudeFile` | 10,401,497 | 91 |

**Identical.** The counting logic is correct; the file selection is wrong.

---

## Root Cause Analysis

The bug has **two layers**:

### Layer 1: `find -newermt` (CRITICAL — 78% file loss)

Only 120 of 542 files have mtime after local midnight. The other 422 files contain usage data with timestamps that fall within "today" but the file itself wasn't modified today.

**Why this happens:**
- Claude Code's project directory (`~/.claude/projects/`) accumulates files across all sessions
- A single project directory may have 20-50 `.jsonl` files from different sessions and subagents
- Most files are from previous days and were not modified today — BUT they may still contain messages that fall within today's time window when using proper timezone-aware filtering

### Layer 2: `startswith($today)` (MEDIUM — 40% message loss in UTC+8)

Even among the 120 files that pass the `-newermt` filter, the `startswith($today)` comparison uses local date against UTC timestamps:

- Local 4/15 00:00 = UTC 4/14 16:00
- Messages from local 00:00-08:00 have UTC dates of the **previous day**
- `startswith("2026-04-15")` misses them

### Combined Effect

```
Total files:                    542  (100%)
After find -newermt:            120  (22%)   ← Layer 1: -78%
After startswith($today):       ~60M tokens  ← Layer 2: -40% of remaining
True local-day total:           ~704M tokens
Effective accuracy:             8.5%
```

---

## Fix

### Recommended Approach: Remove `-newermt`, Use Timestamp-Only Filtering

```bash
TODAY=$(date +%Y-%m-%d)
_PROJECTS_DIR="$HOME/.claude/projects"

# Calculate local midnight as UTC timestamp for correct timezone handling
if is_mac; then
  _TODAY_START_UTC=$(date -u -j -f "%Y-%m-%d %H:%M:%S" \
    "$TODAY 00:00:00" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  _TOMORROW_START_UTC=$(date -u -j -v+1d -f "%Y-%m-%d %H:%M:%S" \
    "$TODAY 00:00:00" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
else
  _TODAY_START_UTC=$(date -u -d "$TODAY 00:00:00" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  _TOMORROW_START_UTC=$(date -u -d "$TODAY 00:00:00 + 1 day" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
fi

# Fallback for failed date conversion
_TODAY_START_UTC="${_TODAY_START_UTC:-${TODAY}T00:00:00Z}"
_TOMORROW_START_UTC="${_TOMORROW_START_UTC:-$(date -d tomorrow +%Y-%m-%d 2>/dev/null || echo '9999-12-31')T00:00:00Z}"

if [ -d "$_PROJECTS_DIR" ]; then
  _DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null | \
    xargs -0 grep -h "input_tokens" 2>/dev/null | \
    jq -c --arg start "$_TODAY_START_UTC" --arg end "$_TOMORROW_START_UTC" '
      select(.timestamp != null and .timestamp >= $start and .timestamp < $end) |
      .message.usage // empty |
      {i: (.input_tokens // 0), o: (.output_tokens // 0),
       cr: (.cache_read_input_tokens // 0)}' 2>/dev/null | \
    jq -s '{
      input: (map(.i) | add // 0),
      output: (map(.o) | add // 0),
      cache_read: (map(.cr) | add // 0),
      tokens: (map(.i + .o + .cr) | add // 0),
      messages: length
    }' 2>/dev/null)
fi
```

### Performance Concern: Scanning All 542 Files

Scanning all files is slower than scanning 120. Mitigated by:

1. **Cache TTL is 30 seconds** — the full scan only runs every 30s, not every render
2. **`grep -h "input_tokens"` is fast** — it's a simple string match, not JSON parsing
3. **jq streaming pipeline** — only parses matching lines, not full files

If performance is still a concern, use a **broader** `-newermt` window instead of removing it entirely:

```bash
# Alternative: Use 2-day window instead of today-only
# This catches files modified yesterday that contain today's messages
_YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || \
  date -v-1d +%Y-%m-%d 2>/dev/null || echo "$TODAY")

find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$_YESTERDAY 00:00" -type f -print0 2>/dev/null | \
```

**Warning:** Even a 2-day window will miss files from 3+ days ago that were modified before yesterday. The only truly correct approach is to scan all files and let jq filter by timestamp.

### Performance Benchmark (Recommended)

Before choosing between "no pre-filter" and "2-day window", benchmark on the user's actual data:

```bash
# Time: scan all files
time find ~/.claude/projects -name "*.jsonl" -type f -print0 | \
  xargs -0 grep -ch "input_tokens" | awk '{s+=$1}END{print s}'

# Time: scan -newermt yesterday
time find ~/.claude/projects -name "*.jsonl" \
  -newermt "$(date -v-1d +%Y-%m-%d) 00:00" -type f -print0 | \
  xargs -0 grep -ch "input_tokens" | awk '{s+=$1}END{print s}'
```

If full scan takes <2s, remove the pre-filter entirely (30s cache makes this negligible).

---

## Interaction With Previous Reviews

| Review | Finding | Status After This Fix |
|--------|---------|----------------------|
| review-023 | `find -newermt` matches file mtime, not message timestamp | **SUPERSEDED** — removing `-newermt` eliminates this issue |
| review-024 (original) | Pew overcounting 4.2x due to cursor resets | **RETRACTED** — pew is correct, we are undercounting |
| review-024 (corrected) | Timezone bug in `startswith($today)` | **STILL VALID** — fixed by UTC range comparison in this review's fix |
| review-022 #3 | `find \| xargs` without `-print0 / -0` | **STILL VALID** — `-print0` already applied, keep it |

---

## Test Plan

1. **Correctness**: Compare daily total against pew after fix — should match within 1%
2. **Timezone**: Test at UTC+8 00:01 — should include messages from previous UTC day
3. **Performance**: Benchmark full scan vs `-newermt` scan — accept if <3s on 30s cache cycle
4. **Edge cases**:
   - Empty projects directory → should show 0
   - Files with no timestamp field → should be skipped (existing `select(.timestamp != null)`)
   - Files with malformed timestamps → should be skipped

---

## Action Items

| Priority | Item | Effort |
|----------|------|--------|
| **P0** | Remove `find -newermt` or use 2-day window; add UTC range comparison | Medium |
| **P1** | Benchmark full scan performance on user's 542-file dataset | Trivial |
| **P1** | Add test case: daily scanning with mock multi-day transcript files | Low |
