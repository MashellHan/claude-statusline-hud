# Review 017 — CRITICAL: SESSION_TOKENS Is 99.4% Wrong (Confirmed)

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Session token calculation analysis  
**LOC:** 688

---

## 🔴 CRITICAL: SESSION_TOKENS Shows 0.6% of Actual Tokens

### The Bug

The script computes `SESSION_TOKENS` by mixing **per-turn snapshot** data with **cumulative** data:

```bash
# Line 63-66: These are per-TURN snapshots (current_usage.*)
INPUT_TOK=$(.context_window.current_usage.input_tokens)        # THIS turn only
CACHE_CREATE=$(.context_window.current_usage.cache_creation_input_tokens)  # THIS turn only
CACHE_READ=$(.context_window.current_usage.cache_read_input_tokens)        # THIS turn only

# Line 66: This IS cumulative
TOTAL_OUT=$(.context_window.total_output_tokens)               # ALL turns

# Line 446, 468: The broken calculation
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))         # = LAST TURN INPUT ONLY!
SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))                    # = last_turn_input + all_output
```

### Verified Measurement (This Session)

```
Turns in session:                        609
                                  
CUMULATIVE (sum of all turns):
  input_tokens:              27,913,924
  cache_creation:                     0
  cache_read:                20,978,104
  output_tokens:                135,027
  TOTAL:                     49,027,055

LAST TURN ONLY (what script uses for input):
  input_tokens:                     616
  cache_creation:                     0
  cache_read:                   149,620
  sum:                          150,236

SCRIPT's SESSION_TOKENS:
  = last_turn_in(150,236) + cum_output(135,027)
  = 285,263

ACTUAL SESSION TOTAL:           49,027,055
SCRIPT SHOWS:                      285,263
RATIO:                               0.6%
MISSING:                        48,741,792 tokens (99.4% undercount)
```

**The script shows 285K tokens when the real total is 49M. It's off by 172x.**

### Root Cause

The JSON from Claude Code has two sets of token fields:

| Field | Scope | What It Is |
|-------|-------|------------|
| `context_window.current_usage.input_tokens` | **Per-turn** | Input tokens for the LAST API call |
| `context_window.current_usage.cache_read_input_tokens` | **Per-turn** | Cache read for the LAST API call |
| `context_window.current_usage.cache_creation_input_tokens` | **Per-turn** | Cache creation for the LAST API call |
| `context_window.total_input_tokens` | **Cumulative** | Sum of all input tokens across session |
| `context_window.total_output_tokens` | **Cumulative** | Sum of all output tokens across session |

The script uses `current_usage.*` (per-turn) for input but `total_output_tokens` (cumulative) for output. This produces a nonsense number that's almost entirely output tokens from the cumulative counter plus a tiny sliver of the last turn's input.

### Why `CTX_TOKENS` Is More Accurate

```bash
CTX_TOKENS=$((CTX_SIZE * PCT / 100))
```

`CTX_TOKENS` is derived from `used_percentage` which Claude Code computes correctly. It represents the current context window occupancy (what's in memory now). This is accurate for its purpose (context fullness) but is NOT the same as cumulative billing tokens.

---

## The Fix

### What We Need

Two distinct metrics:
1. **Context occupancy** (`CTX_TOKENS`) — how full the context window is right now → already correct
2. **Session total tokens** (`SESSION_TOKENS`) — cumulative billing tokens → **BROKEN**

### Fix: Use `total_input_tokens` (cumulative field)

The JSON already provides `context_window.total_input_tokens` — we just aren't using it!

**Step 1:** Add to jq extraction (line 66-67):

```bash
  @sh "TOTAL_INPUT_CUM=\(.context_window.total_input_tokens // 0)",
```

Add fallback (line 77):
```bash
  ... TOTAL_INPUT_CUM=0
```

**Step 2:** Fix SESSION_TOKENS (line 468):

```bash
# OLD (broken — mixes per-turn and cumulative):
# SESSION_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))

# NEW (both cumulative):
SESSION_TOKENS=$((TOTAL_INPUT_CUM + TOTAL_OUT))
```

**Step 3:** Keep `TOTAL_INPUT` for cache hit calculation (line 476):

`TOTAL_INPUT` (per-turn input breakdown) is still needed for the cache hit rate display on Row 3. It correctly shows how much of the *current turn's* input was cache hits. Don't change this.

```bash
# This is CORRECT — shows cache hit for current turn:
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))
CP=$((CACHE_READ * 100 / TOTAL_INPUT))
```

**Step 4:** Update token display on Row 3 (line 471):

Currently shows `token 285K` (wrong). Should show cumulative session tokens:

```bash
# Keep showing per-turn breakdown but use cumulative for the headline number
if [ "$SESSION_TOKENS" -gt 0 ]; then
  TOK_DISPLAY="${CYAN}token${RST} ${VAL}$(fmt_tok $SESSION_TOKENS)${RST}"
  if [ "$TIER" = "wide" ]; then
    # Show per-turn breakdown in wide mode only
    TOK_DISPLAY="${TOK_DISPLAY} (${CYAN}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST} ${CYAN}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHE_READ)${RST} ${CYAN}out${RST} ${VAL}$(fmt_tok $TOTAL_OUT)${RST})"
  fi
fi
```

### Impact on Other Features

| Feature | Impact | Action |
|---------|--------|--------|
| Burn rate (line 599) | Uses `SESSION_TOKENS` → will be fixed automatically | ✅ No change needed |
| Cache hit % (line 476) | Uses `TOTAL_INPUT` (per-turn) → still correct | ✅ No change needed |
| Token display Row 3 | Uses `CTX_TOKENS` for headline → needs SESSION_TOKENS | Fix display |
| Daily token tracking | Uses transcript scanning (cumulative) → already correct | ✅ Confirmed accurate |

### Why Daily Token Is Accurate

The daily scanning pipeline sums `message.usage.input_tokens` etc. from EVERY line in ALL transcript files:

```bash
jq -c '.message.usage // empty |
  {i: (.input_tokens // 0), o: (.output_tokens // 0),
   cr: (.cache_read_input_tokens // 0)}' | jq -s aggregate
```

This correctly sums every API call's usage across all sessions. **Per-turn values summed across all turns = cumulative total.** That's why daily shows ~2.7B while session shows 285K.

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.5/10 | — | Features work, data is wrong |
| Code Quality | 7.0/10 | ↓ -1.0 | Mixing per-turn and cumulative is a design error |
| Performance | 8.5/10 | — | No change |
| Data Accuracy | **4.0/10** | ↓ -3.5 | **SESSION_TOKENS is 172x wrong** |
| UI/UX | 7.5/10 | ↓ -1.0 | User sees meaningless token number |
| Stability | 8.0/10 | — | No crashes, just wrong data |
| **Overall** | **7.0/10** | **↓ -1.2** | **Critical data accuracy regression** |

---

## Action Items

### CRITICAL

1. **Fix SESSION_TOKENS** — Parse `total_input_tokens` from JSON, use it for cumulative session total. See exact implementation above. ~5 lines changed.

### HIGH

2. **Verify the fix** — After deploying, SESSION_TOKENS should show ~49M for this session (not 285K)
3. **Clear caches** — `rm -f /tmp/.claude_sl_*` after deploying

### MEDIUM

4. **Review-016 features** — Session ID, skills, MCP badges (still pending)
5. **P1.4 Autocompact** — `remaining_percentage` is available in JSON

---

## Summary

| Metric | Current (WRONG) | Should Be | Fix |
|--------|-----------------|-----------|-----|
| SESSION_TOKENS | 285,263 | 49,027,055 | Use `total_input_tokens` |
| Burn rate | Based on 285K | Based on 49M | Auto-fixed by SESSION_TOKENS |
| Daily tokens | 2,719,602,937 | ~2.7B | ✅ Already correct |
| CTX_TOKENS | Correct | Correct | ✅ No change |

**The per-session token is 172x wrong. The daily token (transcript-based) is correct. Fix: use `total_input_tokens` (cumulative) instead of `current_usage.input_tokens` (per-turn).**

---

*Dev agent: This is a ~5 line fix. Add `TOTAL_INPUT_CUM` to jq extraction, use it for `SESSION_TOKENS`. Keep `TOTAL_INPUT` (per-turn) for cache hit %. Commit, push, deploy, clear caches. See implementation spec above.*
