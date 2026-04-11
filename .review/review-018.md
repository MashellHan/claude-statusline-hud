# Review 018 — Row 2 Improvements: Label Tool Use + Show Last Turn Info

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** UI clarity improvements for Row 2  
**LOC:** 688

---

## User Request

> "标注一下这是什么 tool use 之类的. 然后加一点最后一次 turns 的信息 也要标注清楚"

Two changes to Row 2:
1. Add a label so users know what the tool list means
2. Add last turn's token info with clear labels

---

## Current Row 2

```
› ✓ Bash · ✓ Edit · ✓ Write
```

No context — user doesn't know this is "recent tool calls". The `›` prefix is too subtle.

## Proposed Row 2

```
tools ✓ Bash · ✓ Edit · ✓ Write │ turn in 616 cache 149K out 3.2K
```

Or in wide mode with more detail:
```
tools ✓ Bash · ✓ Edit · ✓ Write │ last-turn in 616 cache-read 149K out 3.2K
```

---

## Feature A: Label the Tool Use Section

### Current (line 414-416):

```bash
if [ -n "$ACTIVITY_LINE" ]; then
  printf '%b\n' "${DIM}›${RST} ${ACTIVITY_LINE}"
fi
```

### Change:

Replace the `›` prefix with `tools` label:

```bash
if [ -n "$ACTIVITY_LINE" ]; then
  printf '%b\n' "${CYAN}tools${RST} ${ACTIVITY_LINE}"
fi
```

**Why `tools` not `tool-use`:** Consistent with other labels (`context`, `cost`, `time`, `code`). Short. Clear.

---

## Feature B: Show Last Turn Info

### What to Show

The `current_usage.*` fields are the **last turn's** token breakdown. Currently these are (incorrectly) used for SESSION_TOKENS, but they are actually useful as "what happened in the last API call":

- `INPUT_TOK` = last turn's input tokens (the new/uncached tokens sent)
- `CACHE_READ` = last turn's cache hit tokens
- `TOTAL_OUT` = cumulative output (we already have this, but for last turn we need per-turn output)

**Problem:** The JSON only provides `total_output_tokens` (cumulative), NOT per-turn output. The per-turn output is only in the transcript's `message.usage.output_tokens`.

**Solution:** We already parse `SESS_USER_MSGS` / `SESS_LLM_MSGS` from the transcript (lines 418-438). We can add last turn's output tokens to that parse. Or simpler: just show the input-side breakdown since that's what we have.

### Implementation

Add after the `ACTIVITY_LINE` display (after line 416), as part of Row 2:

```bash
# --- Last turn token info (append to Row 2) ---
TURN_INFO=""
if [ "$INPUT_TOK" -gt 0 ] || [ "$CACHE_READ" -gt 0 ]; then
  TURN_INFO="${CYAN}turn${RST} ${DIM}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST}"
  [ "$CACHE_READ" -gt 0 ] && TURN_INFO="${TURN_INFO} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHE_READ)${RST}"
  [ "$CACHE_CREATE" -gt 0 ] && TURN_INFO="${TURN_INFO} ${DIM}create${RST} ${YELLOW}${VAL}$(fmt_tok $CACHE_CREATE)${RST}"
fi
```

Then combine both pieces in the Row 2 output:

```bash
if [ -n "$ACTIVITY_LINE" ] || [ -n "$TURN_INFO" ]; then
  _R2=""
  [ -n "$ACTIVITY_LINE" ] && _R2="${CYAN}tools${RST} ${ACTIVITY_LINE}"
  if [ -n "$TURN_INFO" ]; then
    if [ -n "$_R2" ]; then
      _R2="${_R2}${SEP}${TURN_INFO}"
    else
      _R2="${TURN_INFO}"
    fi
  fi
  # Add message counts if available (compact mode: skip)
  if [ "$TIER" != "compact" ] && [ "$SESS_USER_MSGS" -gt 0 ]; then
    _R2="${_R2}${SEP}${DIM}msgs${RST} ${VAL}${SESS_USER_MSGS}↑${SESS_LLM_MSGS}↓${RST}"
    [ "$SESS_COMPACTS" -gt 0 ] && _R2="${_R2} ${YELLOW}${SESS_COMPACTS}⟳${RST}"
  fi
  printf '%b\n' "$_R2"
fi
```

### Display Examples

**Normal mode (70-99 cols):**
```
tools ✓ Bash · ✓ Edit · ✓ Write │ turn in 616 cache 149K │ msgs 87↑605↓
```

**Wide mode (≥100 cols):**
```
tools ✓ Bash · ✓ Edit · ✓ Write │ turn in 616 cache 149K create 0 │ msgs 87↑605↓ 10⟳
```

**Compact mode (<70 cols):**
```
tools ✓ Bash · ✓ Edit · ✓ Write │ turn in 616 cache 149K
```

**With active (in-progress) tool:**
```
tools ◐ Bash git status · ✓ Edit │ turn in 616 cache 149K
```

### Label Meanings

| Label | What It Shows |
|-------|---------------|
| `tools` | Recent tool calls: ✓=done, ◐=running |
| `turn` | Last API turn's token breakdown |
| `in` | New (non-cached) input tokens sent |
| `cache` | Cache-read tokens (saved cost) |
| `create` | Cache-creation tokens (only in wide mode) |
| `msgs` | Session message count: user↑ assistant↓ |
| `⟳` | Number of compactions in this session |

---

## Implementation Summary

### Files to Change

**`plugins/claude-statusline-hud/scripts/statusline.sh`**

1. **Line 390:** Change `[-5:]` to `[-3:]` — show last 3 tools instead of 5
2. **Line 415:** Change `${DIM}›${RST}` to `${CYAN}tools${RST}`
3. **Lines 414-416:** Replace simple output with combined Row 2 assembly (tools + turn + msgs)
4. Move the `SESS_USER_MSGS` display from unused to integrated in Row 2

### Lines of Code

- Remove: ~3 lines (old Row 2 output)
- Add: ~20 lines (combined Row 2 with labels + turn info + msg counts)
- Net: ~+17 lines

### Caching

No new caching needed — `INPUT_TOK`, `CACHE_READ`, `CACHE_CREATE` are already parsed from JSON. `SESS_USER_MSGS` etc. are already cached at 10s intervals.

---

## Scores

No score change from review-017. This is a UI improvement spec, not a review of new code.

---

## Action Items for Dev Agent

### HIGH

1. **Fix SESSION_TOKENS** from review-017 first (CRITICAL, ~5 lines)

2. **Then implement Row 2 improvements:**
   - Change `›` prefix to `tools` label
   - Add `turn in X cache Y` after tool list
   - Add `msgs N↑M↓` with compaction count
   - See implementation spec above (~17 lines)
   - Commit separately from SESSION_TOKENS fix

### Commit Order

```
1. fix: use total_input_tokens for SESSION_TOKENS (review-017)
2. feat: label Row 2 tool use + show last turn info (review-018)
3. feat: add session ID, skills count, MCP health badges (review-016)
```

---

*Dev agent: Two changes to Row 2. (1) Replace `›` with `tools` label. (2) Append `turn in X cache Y` and `msgs N↑M↓`. See implementation code above. Do this AFTER fixing SESSION_TOKENS from review-017.*
