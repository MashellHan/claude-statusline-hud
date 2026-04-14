# Review 021 — BUG: Only Row 1 Shows Before First Turn Completes

**Date:** 2026-04-14  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Diagnose why HUD shows only 1 row when agent is running  
**LOC:** 742

---

## User Report

> "我发现在agent 运行过程中容易出现 hub 只有一行的问题"
> "是不是因为第一次 turn 还没结束的原因 有了一个 turn 就好了"

Screenshot shows only Row 1 during agent's first turn:
```
[claude-opus-4.6-1m | Max] │ claude-session-monitor │ main ✓ │ mcp 27 │ skills 124 │ context █░░░░░░░ 32...
```

---

## Root Cause: Row 2 is Conditional, First Turn Has All Zeros

User identified correctly: **before the first turn finishes**, all turn-level data is zero.

### Row-by-Row Analysis at First Turn

| Row | Guard Condition | First-Turn State | Result |
|-----|----------------|------------------|--------|
| **Row 1** | None (always prints) | ✅ Model, dir, git, badges all available | **SHOWS** |
| **Row 2** | `[ -n "$R2" ]` (line 490) | See breakdown below → **R2=""** | **SKIPPED** |
| **Row 3** | None — `printf` always (line 577) | `session(id) token 0 │ time 0s │ cost $0.00` | **SHOULD SHOW** |
| **Row 4** | `[ -n "$DAY_TOK" ] && [ "$DAY_TOK" != "0" ]` | May have data from other sessions | **MAYBE** |
| **Row 5** | None (vitals preset) | CPU/mem/gpu always available | **SHOULD SHOW** |

### Why Row 2 is Empty (line 479-490)

```bash
R2=""
# TURN_DISPLAY: needs INPUT_TOK>0 or CACHE_READ>0 → both 0 on first turn → empty
[ -n "$TURN_DISPLAY" ] && R2="$TURN_DISPLAY"          # SKIP

# CACHE_HIT: needs TOTAL_INPUT>0 → 0 on first turn → empty
[ -n "$CACHE_HIT" ] && R2="${R2:+...}${CACHE_HIT}"     # SKIP

# THROUGHPUT: needs DURATION_MS>0 AND TOTAL_OUT>0 → both 0 → empty
[ -n "$THROUGHPUT" ] && R2="${R2:+...}${THROUGHPUT}"    # SKIP

# RL_DISPLAY: needs RL_5H_PCT>0 → no rate_limits in JSON → empty
[ -n "$RL_DISPLAY" ] && R2="${R2:+...}${RL_DISPLAY}"   # SKIP

# ACTIVITY_LINE: needs transcript with tool_use entries → empty on first turn
[ -n "$ACTIVITY_LINE" ] && R2="${R2:+...}tools ..."    # SKIP

# R2 is "" → row is NOT printed
[ -n "$R2" ] && printf '%b\n' "$R2"                    # SKIP ← this is correct behavior
```

**Row 2 is correctly skipped** — there's no turn data to show yet. This is by design.

### But Why Are Rows 3-5 ALSO Missing?

Row 3 (line 577) does `printf '%b\n' "$R3"` unconditionally. Row 5 (vitals) also always prints. So the question is: **why do they not appear in the screenshot?**

**Two possible explanations:**

#### A. Claude Code's statusline renderer has a fixed display area

Claude Code may allocate space for the statusline based on the **first render**. If the first render produces only 1 line, subsequent re-renders may be constrained to 1 line until a resize/refresh event.

#### B. The screenshot was taken at a very specific moment

The `32...` truncation suggests Claude Code was mid-render or the output was being consumed. Rows 3-5 may have been printed but not displayed due to a rendering race condition.

#### C. Preset is `essential` for this session

If `CLAUDE_STATUSLINE_PRESET=essential` or `~/.claude/statusline-preset` contains `essential`, the script exits at line 498:
```bash
[ "$PRESET" = "essential" ] && exit 0
```
This would skip Rows 3-5 entirely. But we verified the file contains `full`.

**Most likely: Explanation A** — Claude Code locks the statusline height to the initial render's line count.

---

## The Real Fix: Row 2 Should Never Be Completely Empty

The fix is simple: **always show something on Row 2**, even when there's no turn data. This ensures the first render has the right number of lines, so Claude Code allocates enough space.

### Option 1: Show a "waiting" indicator (RECOMMENDED)

```bash
# Line 490: Always print Row 2
if [ -n "$R2" ]; then
  printf '%b\n' "$R2"
else
  printf '%b\n' "${CYAN}turn${RST} ${DIM}waiting...${RST}"
fi
```

### Option 2: Show at least context tokens on Row 2

```bash
if [ -z "$R2" ] && [ "$CTX_TOKENS" -gt 0 ]; then
  R2="${CYAN}turn${RST} ${DIM}—${RST}"
fi
[ -n "$R2" ] && printf '%b\n' "$R2"
```

### Option 3: Show empty separator line

```bash
if [ -n "$R2" ]; then
  printf '%b\n' "$R2"
else
  printf '%b\n' "${DIM}···${RST}"
fi
```

---

## Secondary Issue: Row 1 Truncation (`32...`)

Even though it's not the primary cause, Row 1 IS too wide in this screenshot. The `32...` shows truncation of `32%`. This needs fixing independently:

1. **Agent name `claude-session-monitor`** should truncate to 8 chars → `claude-s...`
2. When agent badge present, consider skipping `mcp` and `skills` badges
3. Dynamic width check (see review-021 original spec)

---

## Action Items for Dev Agent

### HIGH
1. **Always print Row 2** — show `turn waiting...` or `turn —` when all turn data is zero. This prevents Claude Code from locking to a 1-line statusline on first render.

### MEDIUM
2. **Truncate agent name to 8 chars** (currently 15) — `${AGENT_NAME:0:8}`
3. **Test the fix** by starting a new session and verifying all rows appear immediately

---

## Summary

**Root cause:** User correctly identified — before the first turn completes, `INPUT_TOK`, `CACHE_READ`, `TOTAL_OUT`, `DURATION_MS`, `ACTIVITY_LINE` are all zero/empty, causing Row 2's `[ -n "$R2" ]` guard to skip the row entirely. If Claude Code locks statusline height to the first render, subsequent renders with more data don't get additional lines.

**Fix:** Always output something for Row 2 (e.g., `turn waiting...`), so the first render establishes the correct line count.

---

*Dev agent: Change line 490 from `[ -n "$R2" ] && printf '%b\n' "$R2"` to always print Row 2 with a fallback like `turn waiting...` or `turn —`. This ensures Claude Code allocates enough vertical space on first render. Also truncate `AGENT_NAME` from `:0:15` to `:0:8`.*
