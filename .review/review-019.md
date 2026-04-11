# Review 019 — Layout Restructure: Hierarchical Row Organization

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Full layout refine — reorder rows by information hierarchy  
**LOC:** 747 (current)

---

## User Request

> "根据层级整体 refine 一下布局, 第一行基本信息 + context; 第二行 turn 级别的信息 token, speed等 + 最近的 3 个 tools; 3: session 级别的 显示 token, 然后 msg, 时间和 cost ; daily total 保持现状"

Restructure rows by information hierarchy:

| Row | Level | Content |
|-----|-------|---------|
| 1 | **Basic + Context** | Model, Dir, Git, Badges + context bar/% |
| 2 | **Turn-level** | Per-turn tokens (in/cache), speed, cache hit + last 3 tools |
| 3 | **Session-level** | Session tokens, msgs, time, cost |
| 4 | **Daily** | Keep as-is (day-total with breakdown) |
| 5 | **System** | Keep as-is (vitals preset only) |

---

## Current Layout (BEFORE)

```
Row 1: [Model | Max] │ Dir │ Git │ Badges
Row 2: › ✓ Bash · ✓ Edit · ✓ Write                          (tools only)
Row 3: context ████░░░░ 42% │ token 49M (in 616 cache 149K out 135K) │ cache 99% │ speed 2k/min
Row 4: session(abc12345) cost $0.42 │ time 5h 23m │ code +245 -89 │ msg-user 87 msg-llm 605 ⟳10
Row 5: day-total(04-11) token 2B (in 1B cache 800M out 135M) │ msg 28K │ cost $5053.23
Row 6: cpu ██░░ 45% │ mem ███░ 12G/64G │ gpu ░░░░ 0% │ disk ██░░ 234G/926G │ bat ████ 87%
```

## Proposed Layout (AFTER)

```
Row 1: [Model | Max] Dir Git Badges │ context ████░░░░ 42%
Row 2: turn in 616 cache 149K │ cache 99% │ speed 2k/min │ tools ✓ Bash · ✓ Edit · ✓ Write
Row 3: session(abc12345) token 49M │ msg 87↑605↓ ⟳10 │ time 5h 23m (api 78%) │ cost $0.42 │ code +245 -89
Row 4: day-total(04-11) token 2B (in 1B cache 800M out 135M) │ msg 28K │ cost $5053.23
Row 5: cpu ██░░ 45% │ mem ███░ 12G/64G │ gpu ░░░░ 0% │ disk ██░░ 234G/926G
```

### Key Changes

1. **Context** moves from Row 3 → end of Row 1 (saves a row, always visible even in `minimal`)
2. **Tools** move from Row 2 → end of Row 2 (after turn-level metrics)
3. **Turn-level metrics** (per-turn tokens, speed, cache hit) group together on Row 2
4. **Session-level metrics** (cumulative tokens, msgs, time, cost, code) group on Row 3
5. **`›` prefix** replaced with `tools` label (from review-018)
6. **`[-5:]`** changed to `[-3:]` for tool list (from review-018)
7. **Message counts** use compact `87↑605↓` format instead of `msg-user 87 msg-llm 605`

---

## Detailed Specification

### Row 1: Basic Info + Context

**Preset:** ALL (including `minimal`)

Append context bar to the existing Row 1:

```
[Model | Max] │ Dir │ Git │ Badges │ context ████░░░░ 42%⚠
```

**Implementation:**

After building existing R1 (line 336-339), append context:

```bash
# Build context display (moved from old Row 3)
CTX_CLR=$(bar_color "$ADJ_PCT")
CTX_BAR=$(make_bar "$ADJ_PCT" "$BAR_W")
CTX_WARN=""
if [ "$EXCEEDS_200K" = "true" ] || [ "$ADJ_PCT" -ge 90 ] 2>/dev/null; then
  CTX_WARN=" ${BOLD}${BG_YELLOW} ⚠ ${RST}"
fi
CTX_LABEL="${VAL}${PCT}%${RST}"

# Append to R1
R1="${R1}${SEP}${CYAN}context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
```

**Compact mode (<70 cols):** Show only percentage, no bar:

```bash
if [ "$TIER" = "compact" ]; then
  R1="${R1}${SEP}${CYAN}ctx${RST} ${CTX_CLR}${CTX_LABEL}${RST}${CTX_WARN}"
else
  R1="${R1}${SEP}${CYAN}context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
fi
```

**Note:** Context bar computation (`ADJ_PCT`, `CTX_CLR`, etc.) must be moved BEFORE Row 1 output (currently it's at lines 446-463, after Row 2). Move to before line 330.

---

### Row 2: Turn-Level Info + Tools

**Preset:** ESSENTIAL+

This row shows what happened in the **last API turn** plus recent tool activity.

```
turn in 616 cache 149K │ cache 99% │ speed 2k/min │ tools ✓ Bash · ✓ Edit · ✓ Write
```

**Left side — per-turn token breakdown:**

```bash
TURN_DISPLAY=""
if [ "$INPUT_TOK" -gt 0 ] || [ "$CACHE_READ" -gt 0 ]; then
  TURN_DISPLAY="${CYAN}turn${RST} ${DIM}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST}"
  [ "$CACHE_READ" -gt 0 ] && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHE_READ)${RST}"
  [ "$TIER" = "wide" ] && [ "$CACHE_CREATE" -gt 0 ] && \
    TURN_DISPLAY="${TURN_DISPLAY} ${DIM}create${RST} ${YELLOW}${VAL}$(fmt_tok $CACHE_CREATE)${RST}"
fi
```

**Middle — cache hit % and speed (moved from old Row 3):**

```bash
# Cache hit rate (per-turn)
CACHE_HIT=""
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))
if [ "$TOTAL_INPUT" -gt 0 ]; then
  CP=$((CACHE_READ * 100 / TOTAL_INPUT))
  if [ "$CP" -ge 80 ]; then CC="$GREEN"; elif [ "$CP" -ge 40 ]; then CC="$YELLOW"; else CC="$RED"; fi
  CACHE_HIT="${CYAN}cache${RST} ${CC}${VAL}${CP}%${RST}"
fi

# Speed (per-turn throughput)
THROUGHPUT=""
if [ "$DURATION_MS" -gt 0 ] && [ "$TOTAL_OUT" -gt 0 ]; then
  TPM=$((TOTAL_OUT * 60000 / DURATION_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
fi
```

**Right side — tools (last 3, from review-018):**

Change `[-5:]` to `[-3:]` in tool extraction jq (line 390).

Replace `›` with `tools` label.

**Assembly:**

```bash
R2=""
[ -n "$TURN_DISPLAY" ] && R2="$TURN_DISPLAY"
if [ "$TIER" != "compact" ]; then
  [ -n "$CACHE_HIT" ] && R2="${R2:+${R2}${SEP}}${CACHE_HIT}"
  [ -n "$THROUGHPUT" ] && R2="${R2:+${R2}${SEP}}${THROUGHPUT}"
fi
if [ -n "$ACTIVITY_LINE" ]; then
  R2="${R2:+${R2}${SEP}}${CYAN}tools${RST} ${ACTIVITY_LINE}"
fi
[ -n "$R2" ] && printf '%b\n' "$R2"
```

**Rate limit (if present):** Append after speed, before tools:

```bash
[ -n "$RL_DISPLAY" ] && R2="${R2:+${R2}${SEP}}${RL_DISPLAY}"
```

---

### Row 3: Session-Level Info

**Preset:** FULL+

Combines old Row 3's session token with old Row 4's session stats.

```
session(abc12345) token 49M │ msg 87↑605↓ ⟳10 │ time 5h 23m (api 78%) │ cost $0.42 │ code +245 -89
```

**Implementation:**

```bash
R3="${CYAN}session${RST}"
if [ -n "$SESSION_ID" ]; then
  _SID_SHORT="${SESSION_ID:0:8}"
  R3="${CYAN}session${RST}${DIM}(${RST}${VAL}${_SID_SHORT}${RST}${DIM})${RST}"
fi

# Session tokens (cumulative)
if [ "$SESSION_TOKENS" -gt 0 ]; then
  R3="${R3} ${CYAN}token${RST} ${VAL}$(fmt_tok $SESSION_TOKENS)${RST}"
fi

# Message counts (compact: user↑llm↓)
if [ "$SESS_USER_MSGS" -gt 0 ] || [ "$SESS_LLM_MSGS" -gt 0 ]; then
  R3="${R3}${SEP}${CYAN}msg${RST} ${VAL}${SESS_USER_MSGS}↑${SESS_LLM_MSGS}↓${RST}"
  [ "$SESS_COMPACTS" -gt 0 ] && R3="${R3} ${YELLOW}⟳${SESS_COMPACTS}${RST}"
fi

# Time
R3="${R3}${SEP}${CYAN}time${RST} ${VAL}${DUR}${RST}${EFF}"

# Cost
R3="${R3}${SEP}${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"

# Code changes (if any)
[ -n "$LINES" ] && R3="${R3}${SEP}${CYAN}code${RST} ${LINES}"

# Burn rate (if available)
[ -n "$BURN_RATE" ] && R3="${R3}${SEP}${BURN_RATE}"
```

---

### Row 4: Daily Total (NO CHANGE)

Keep the existing `day-total(MM-DD)` row exactly as-is.

---

### Row 5: System Vitals (NO CHANGE)

Keep the existing vitals row exactly as-is.

---

## Preset Visibility Matrix

| Row | minimal | essential | full | vitals |
|-----|---------|-----------|------|--------|
| 1. Basic + Context | ✓ | ✓ | ✓ | ✓ |
| 2. Turn + Tools | — | ✓ | ✓ | ✓ |
| 3. Session | — | — | ✓ | ✓ |
| 4. Daily | — | — | ✓ | ✓ |
| 5. System Vitals | — | — | — | ✓ |

**Important change:** `essential` now shows Row 2 (turn + tools) but NOT Row 3 (session). Previously `essential` showed context bar + token display. The context is now on Row 1 (visible to all), and detailed token/cost goes to Row 3 (full+).

---

## Tier Variants

### Compact (<70 cols)

```
Row 1: [Opus] Dir Git │ ctx 42%
Row 2: turn in 616 cache 149K │ tools ✓ Bash · ✓ Edit
Row 3: session token 49M │ msg 87↑605↓ │ time 5h │ cost $0.42
```

- No context bar, just `ctx N%`
- No cache hit % or speed on Row 2
- No burn rate, no code changes on Row 3
- No daily breakdown (skip Row 4)

### Normal (70-99 cols)

```
Row 1: [Claude Opus 4.6] Dir Git Badges │ context ████░░░░ 42%
Row 2: turn in 616 cache 149K │ cache 99% │ speed 2k/min │ tools ✓ Bash · ✓ Edit · ✓ Write
Row 3: session(abc12345) token 49M │ msg 87↑605↓ ⟳10 │ time 5h 23m │ cost $0.42 │ code +245 -89
Row 4: day-total(04-11) token 2B (...) │ msg 28K │ cost $5053
```

### Wide (≥100 cols)

```
Row 1: [Claude Opus 4.6 (1M Context)] Dir Git Badges │ context ██████████ 42%
Row 2: turn in 616 cache 149K create 0 │ cache 99% │ speed 2k/min │ tools ✓ Bash · ✓ Edit · ✓ Write
Row 3: session(abc12345) token 49M │ msg 87↑605↓ ⟳10 │ time 5h 23m (api 78%) │ cost $0.42 │ code +245 -89 ▲ │ 🔥≈$0.08/hr
Row 4: day-total(04-11) token 2B (in 1B cache 800M out 135M) │ msg 28K │ cost $5053 │ budget ...
Row 5: cpu ██░░ 45% │ mem ███░ 12G/64G │ gpu ░░░░ 0% │ disk ██░░ 234G/926G │ bat ████ 87% │ load 2.1
```

---

## Implementation Roadmap

### Step 1: Move context computation before Row 1 output

Move lines 444-463 (autocompact buffer, CTX_CLR, CTX_BAR, CTX_WARN, CTX_LABEL) to before line 330 (before "ROW 1" section).

### Step 2: Append context to Row 1

After line 339 (`R1` assembly), add context append per tier.

### Step 3: Change Row 2 from pure tools → turn + tools

1. Change `[-5:]` to `[-3:]` (line 390)
2. Replace `${DIM}›${RST}` with `${CYAN}tools${RST}` (line 415)
3. Build combined R2 with turn info + cache hit + speed + tools
4. Move cache hit / speed computation before Row 2 output

### Step 4: Rebuild Row 3 as session-level

1. Move `SESSION_TOKENS` computation before Row 3
2. Replace old context-bar Row 3 with session row
3. Merge old Row 4 stats into new Row 3
4. Remove old separate Row 4

### Step 5: Adjust preset gates

- `minimal`: exit after Row 1 (unchanged)
- `essential`: exit after Row 2 (was: exit after old Row 3)
- `full`: exit after Row 4 daily (was: exit after old Row 4 stats)
- `vitals`: show Row 5 system vitals (unchanged)

### Step 6: Token breakdown at 85%+

The conditional token breakdown (line 526-528) currently triggers at 85% context. Move to Row 2 area — show inline as part of turn info in wide mode, or as a sub-row when context is critically full.

---

## Commit Order

```
1. refactor: restructure layout — move context to Row 1, turn to Row 2, session to Row 3
   (This is ONE commit — it's a layout reshuffle, not adding new features)
```

All the pieces already exist in the code. This is purely moving them to different rows. Net code change should be small (~20-30 lines changed, minimal net new lines).

---

## Pre-Implementation Notes

### Already Completed (from previous reviews)

- [x] SESSION_TOKENS fix (review-017) — commit `665589a`
- [x] Session ID display (review-016) — on current Row 4
- [x] Message counts (review-018) — on current Row 4
- [x] Daily token summary (review-018) — current Row 5
- [x] Billing model detection (review-015)

### Still NOT Done

- [ ] Row 2 `tools` label + `[-3:]` limit (review-018) — **included in this refactor**
- [ ] Row 2 turn info (review-018) — **included in this refactor**
- [ ] Skills count badge on Row 1 (review-016) — defer to next review
- [ ] MCP server health badges on Row 1 (review-016) — defer to next review
- [ ] P1.4 Autocompact countdown — defer

---

## Scores

No score change. This is a layout spec, not a review of new code. After implementation:
- UI/UX expected ↑ +1.0 (clearer hierarchy, less row count for essential info)
- Code Quality expected ↑ +0.5 (cleaner row assembly, DRY)

---

*Dev agent: This is a layout restructure, NOT new features. Move context bar to Row 1 (all presets), group turn-level metrics + last 3 tools on Row 2 (essential+), merge session stats into Row 3 (full+), keep daily and vitals as-is. Change `[-5:]` to `[-3:]`, replace `›` with `tools`. See detailed spec above. ONE commit.*
