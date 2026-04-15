# Review 024 — Daily Totals: Timezone Bug + Pew Comparison Verified

**Date:** 2026-04-15  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Severity:** MEDIUM (timezone), INFO (pew comparison)  

---

## Bug: `startswith($today)` Uses UTC Timestamp With Local Date

**Lines:** 602-603

```bash
TODAY=$(date +%Y-%m-%d)   # Local date: 2026-04-15 (CST/UTC+8)
...
select(.timestamp != null and (.timestamp | startswith($today)))
```

### The Problem

`$TODAY` is the **local date** (e.g., `2026-04-15`).  
`.timestamp` is **UTC** (e.g., `2026-04-14T22:00:00Z`).

In UTC+8 timezone:
- Local 4/15 00:00 = UTC 4/14 16:00
- Local 4/15 08:00 = UTC 4/15 00:00

`startswith("2026-04-15")` only matches UTC timestamps `2026-04-15T*`.  
Messages from **local 4/15 00:00 to 08:00** (= UTC 4/14 16:00 to 4/15 00:00) are **LOST**.

### Impact

| Method | Tokens | Messages |
|--------|--------|----------|
| `startswith($today)` (current) | **60M** | 993 |
| Correct local day window (UTC 4/14 16:00 → 4/15 16:00) | **101M** | 1632 |
| **Missing (00:00-08:00 local)** | **40M** | 639 |

HUD undercounts by **40%** for UTC+8 users.

### Fix

Calculate local midnight as UTC ISO timestamp, then use range comparison:

```bash
# Get local midnight in UTC
if is_mac; then
  _TODAY_START_UTC=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
else
  _TODAY_START_UTC=$(date -u -d "$(date +%Y-%m-%d) 00:00:00" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
fi
# Fallback: if date conversion fails, use startswith (slightly wrong but functional)
_TODAY_START_UTC="${_TODAY_START_UTC:-$(date +%Y-%m-%d)T00:00:00}"

# In jq:
jq -c --arg start "$_TODAY_START_UTC" '
  select(.timestamp != null and .timestamp >= $start) |
  ...
'
```

Alternatively, simpler approach — convert timestamp to local date in jq:

```bash
# Pass timezone offset as parameter
_TZ_OFFSET_SEC=$(date +%z | awk '{h=substr($1,1,3); m=substr($1,4,2); print (h*3600)+(m*60)}')

jq -c --argjson tz "$_TZ_OFFSET_SEC" --arg today "$TODAY" '
  select(.timestamp != null) |
  # Convert UTC timestamp to local date string for comparison  
  select((.timestamp[0:10]) >= ($today[0:8] + "T") or ...) |
  ...
'
```

**Recommended: Simple approach** — compute `_TODAY_START_UTC` once in bash, pass as `$start` to jq.

---

## Pew Comparison: 425M vs 101M — Pew Overcounting

### Analysis

| Metric | Our Scan | Pew Queue | Ratio |
|--------|---------|-----------|-------|
| Today (local) | 101M | 425M | 4.2x |
| Today (UTC) | 60M | 253M | 4.2x |

### Root Cause

Pew uses **incremental byte-offset parsing** + **accumulative queue merging**:

```javascript
// Each sync cycle:
const merged = aggregateRecords([...oldRecords, ...records]);
await queue.overwrite(merged);
```

`aggregateRecords` sums all records with the same key `(source|model|hour_start|device_id)`.

Normal operation: `slot = old_total + new_delta` (correct, since new_delta is only new bytes).

**But**: if pew's cursor resets (app update, `pew reset`, cursor corruption), the next sync re-reads from byte 0, producing a **full file delta**. This gets ADDED to the existing queue total:

```
After reset: slot = old_total + full_rescan = 2x true value
After another reset: slot = 2x + full_rescan = 3x true value  
```

Pew's code comments acknowledge this:
> "Worst case: queue overwritten + cursor not saved → values ≥ true (minor over-count)"

For the user: **pew's dashboard number (297M) is inflated**. Real value is **101M**.

### Our Data is Correct

Exhaustive verification:
- Scanned all 497 .jsonl files under `~/.claude/projects/`
- Matched exactly the same files pew tracks (0 difference)
- Used `cat | grep | jq` pipeline (no byte-offset tricks)
- Per-message values match (verified on single-file comparison)
- **101M is the ground truth** for local 4/15

### Pew Fix

User can run `pew reset` followed by `pew sync` to rebuild from scratch. This will produce correct values until the next cursor disruption.

---

## Action Items

| Priority | Item | Effort |
|----------|------|--------|
| **P1** | Fix timezone: compute local midnight as UTC, use range comparison in jq | Low |
| **P2** | Suggest user run `pew reset && pew sync` to fix pew dashboard | Trivial |
