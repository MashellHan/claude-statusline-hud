# Review 021 — BUG: Only Row 1 Shows During Agent Runs

**Date:** 2026-04-14  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Diagnose why HUD shows only 1 row when agent is running  
**LOC:** 742

---

## User Report

> "我发现在agent 运行过程中容易出现 hub 只有一行的问题"

Screenshot shows:
```
[claude-opus-4.6-1m | Max] │ claude-session-monitor │ main ✓ │ mcp 27 │ skills 124 │ context █░░░░░░░ 32...
►► bypass permissions on (shift+tab to cycle)
```

Only Row 1 visible. Row 2 (turn+tools), Row 3 (session), Row 4 (daily), Row 5 (vitals) all missing. The `32...` at the end of Row 1 is also suspicious — it looks like the output is being **truncated**.

---

## Root Cause Analysis

### Theory 1: Claude Code Truncates Statusline Output (MOST LIKELY)

Claude Code's statusline renderer likely has a **line count limit** or **character limit** for the statusline output. When the statusline script outputs too many rows, Claude Code may:
- Truncate to N lines (probably 2, since the `►► bypass permissions` line is Claude Code's own UI)
- Truncate each line to a max character width

**Evidence from screenshot:**
- Row 1 ends with `32...` — the `...` is a truncation indicator from Claude Code
- Only 1 row of our output is shown
- The `bypass permissions on` line is Claude Code's own prompt UI, not our Row 2

**Why it's worse during agent runs:**
- Row 1 now includes: Model + Dir + Git + **Agent badge** (`⚡ claude-session-monitor`) + MCP badge + Skills badge + Context bar
- That's **significantly longer** than a normal session's Row 1
- `claude-session-monitor` alone adds ~25 characters
- Combined with `mcp 27 │ skills 124 │ context ████████ 32%`, Row 1 can exceed 120+ chars

**When Row 1 is very long, Claude Code may:**
1. Truncate the line (confirmed: `32...` = truncation of `32%`)
2. Refuse to show additional rows (to avoid overflowing the terminal)

### Theory 2: Terminal Height Constraint

During agent runs with task lists visible (the screenshot shows a long task tree), the available vertical space for the statusline is reduced. Claude Code may dynamically limit statusline rows based on available terminal height.

### Theory 3: Script Timeout

The statusline script may be hitting a timeout when:
- `tail -80 "$TRANSCRIPT"` is slow on a very large transcript (agent sessions can be huge)
- `jq` parsing of the transcript takes too long
- Multiple file operations (MCP badge, skills badge) add latency

Claude Code has a timeout for the statusline command. If exceeded, it may truncate the output to whatever was printed before timeout.

### Theory 4: Preset/TRANSCRIPT Issue

If `TRANSCRIPT` is empty or the transcript file doesn't exist yet (agent just started), many conditionals would skip. But this wouldn't explain the truncation of Row 1 itself.

---

## Most Likely Root Cause: **Row 1 is too wide**

Looking at the screenshot carefully:

```
[claude-opus-4.6-1m | Max] │ claude-session-monitor │ main ✓ │ mcp 27 │ skills 124 │ context █░░░░░░░ 32...
```

Counting the visible characters:
- `[claude-opus-4.6-1m | Max]` = 27 chars
- `│ claude-session-monitor` = 25 chars
- `│ main ✓` = 8 chars
- `│ mcp 27` = 8 chars
- `│ skills 124` = 12 chars
- `│ context █░░░░░░░ 32%` = 22 chars

**Total: ~102+ characters** (without ANSI escape codes)

With ANSI escape sequences, the **byte length** is 3-5x larger (each `\033[xxm` adds 4-7 bytes). Claude Code may be measuring byte length, not display width, and truncating.

---

## Recommendations

### Fix 1: Row 1 Width Management (HIGH)

Row 1 has too many elements. When badges push it beyond ~100 visible chars, it breaks.

**Options:**
A) **Move MCP + Skills badges to Row 2** (reduce Row 1 width)
B) **Truncate agent name** to 8 chars instead of 15
C) **Hide badges in compact mode when agent is active**
D) **Dynamic width check**: count visible chars and drop segments if over limit

**Recommended approach (D):**
```bash
# After assembling R1, check approximate visible width
_R1_PLAIN=$(printf '%b' "$R1" | sed 's/\x1b\[[0-9;]*m//g')
_R1_LEN=${#_R1_PLAIN}
if [ "$_R1_LEN" -gt "$COLS" ]; then
  # Re-assemble without MCP/skills badges
  # Or use compact labels
fi
```

### Fix 2: Reduce Badge Verbosity (MEDIUM)

When agent badge is present (long name), other badges should compress:
```bash
# Normal:  mcp 27 │ skills 124 │ context ████████ 32%
# With agent: ⚡ claude-ses... │ ctx 32%
# (drop mcp + skills, use compact ctx)
```

### Fix 3: Limit Row Count Based on Terminal (MEDIUM)

Claude Code may have a fixed line limit (e.g., 2 lines). If so, we should prioritize which rows to show:

```bash
# Detect Claude Code's statusline max lines
# If only N lines allowed, show most important N rows
MAX_ROWS="${CLAUDE_SL_MAX_ROWS:-5}"
```

### Fix 4: Performance Guard for Agent Sessions (LOW)

Agent sessions have huge transcripts. Add a guard:

```bash
# Skip transcript parsing for huge files
_TRANSCRIPT_LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo 0)
if [ "$_TRANSCRIPT_LINES" -gt 10000 ]; then
  # Skip tool activity parsing, use cached data only
fi
```

---

## Verification Steps

Dev agent should:

1. **Check Claude Code's statusline line/char limits:**
   ```bash
   # Create a test script that outputs many lines
   echo -e "Line1\nLine2\nLine3\nLine4\nLine5" 
   # See how many lines Claude Code actually renders
   ```

2. **Measure actual Row 1 width in agent mode:**
   ```bash
   # Add debug output
   printf '%b' "$R1" | sed 's/\x1b\[[0-9;]*m//g' | wc -c
   ```

3. **Test with minimal Row 1:**
   ```bash
   # Temporarily remove MCP+Skills badges, see if more rows appear
   ```

---

## Action Items for Dev Agent

### HIGH
1. **Add dynamic width check for Row 1** — if `_R1_LEN > COLS`, drop lower-priority badges (MCP, skills)
2. **Truncate agent name more aggressively** when Row 1 is crowded — 8 chars instead of 15
3. **Investigate Claude Code's actual max statusline output** — how many lines/chars does it allow?

### MEDIUM
4. **Add `CLAUDE_SL_MAX_ROWS` env var** — let users control row count
5. **Compact mode for badges when agent active** — drop verbose labels

---

## Summary

**Problem:** Row 1 with agent badge + MCP + skills + context bar exceeds terminal/Claude Code width limits, causing either truncation or suppression of subsequent rows.

**Most likely fix:** Dynamic Row 1 width management — drop MCP/skills badges when agent name is present, or move them to Row 2.

---

*Dev agent: The core issue is Row 1 being too wide when agent badge + MCP + skills + context are all present. Add a visible-width check after R1 assembly. If over COLS, drop badges progressively (skills first, then MCP, then shorten agent name). See Fix 1 option D above.*
