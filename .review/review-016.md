# Review 016 — Rate Limits Not Available + New Feature Specs: Session ID, Skills Count, MCP Health

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Commit Reviewed:** b3485d8 `fix: detect billing model before showing DAY_COST`  
**Previous Review:** review-015  
**LOC:** 688

---

## Finding 1: rate_limits Field Does NOT Exist in JSON Input

### Investigation

Captured the actual JSON that Claude Code sends to the statusline hook via `tee` debug:

```json
{
  "context_window": { "total_input_tokens", "total_output_tokens", "context_window_size", "current_usage", "used_percentage", "remaining_percentage" },
  "cost": { "total_cost_usd", "total_duration_ms", "total_api_duration_ms", "total_lines_added", "total_lines_removed" },
  "cwd": "...",
  "exceeds_200k_tokens": false,
  "model": { "id", "display_name" },
  "output_style": { "name" },
  "session_id": "7b464892-...",
  "transcript_path": "...",
  "version": "2.1.90",
  "workspace": { "current_dir", "project_dir", "added_dirs" }
}
```

**`rate_limits` is NOT present.** The official docs list it, but Claude Code v2.1.90 does not send it. Possibly:
- Feature not yet shipped
- Only available on certain plans
- The local proxy at `localhost:7024` strips it

### Impact on P1.1

The rate limit display code (ee6f1c5) is correct but **will never fire** until Claude Code adds this field. The `// 0` fallback silently hides it. No action needed — it will auto-activate when the field appears.

### Fields We CAN Use But Don't Yet

| Field | Currently Used? | Opportunity |
|-------|----------------|-------------|
| `session_id` | ✅ P1.2 (cache key) | **Also display it** |
| `version` | ❌ | Show Claude Code version |
| `output_style.name` | ❌ | Show current output style |
| `remaining_percentage` | ❌ | **Autocompact countdown (P1.4)** |
| `workspace.project_dir` | ❌ | Original project directory |
| `workspace.added_dirs` | ❌ | Additional dirs count |
| `model.id` | ❌ | Full model identifier |

---

## Finding 2: MCP & Skills Data Available from Filesystem

### MCP Servers: 27 configured

**Source:** `~/.claude/mcp-configs/mcp-servers.json`

```bash
jq '.mcpServers | length' ~/.claude/mcp-configs/mcp-servers.json
# → 27
```

Servers include: github, context7, playwright, supabase, firecrawl, memory, browser-use, vercel, cloudflare-*, sequential-thinking, etc.

**Types:**
- 15 NPM/command-based servers
- 2 Python packages
- 10 HTTP endpoints

**Health cache:** `~/.claude/mcp-health-cache.json` — does NOT currently exist on this system. Created by `mcp-health-check.js` hook when tool failures occur.

### Skills: 124 installed

```bash
ls -1d ~/.claude/skills/* | wc -l
# → 124
```

Categories: code-review, security-scan, tdd, deployment, language-specific reviewers, etc.

### Commands: ~71

```bash
ls -1 ~/.claude/commands/ | wc -l
```

---

## New Feature Specs for Dev Agent

### Feature A: Session ID Display on Row 1

**What:** Show truncated session ID as a badge on Row 1.

**Why:** Helps users identify which session they're in, especially with multiple Claude Code instances.

**Display:**
```
[Opus 4.6 | Max] │ my-project │  main ✓ │ 📋 7b46..75bc
```

**Implementation (insert after line 318, before update badge):**

```bash
# --- Session ID badge ---
SID_BADGE=""
if [ -n "$SESSION_ID" ]; then
  _SID_SHORT="${SESSION_ID:0:4}..${SESSION_ID: -4}"
  SID_BADGE="${SEP}${DIM}📋 ${_SID_SHORT}${RST}"
fi
```

Then add to R1 assembly (around line 337):
```bash
[ -n "$SID_BADGE" ] && R1="${R1}${SID_BADGE}"
```

**Notes:**
- Use first 4 + last 4 chars of UUID: `7b46..75bc` (10 chars total)
- Dim color — informational, not attention-grabbing
- Only show when `SESSION_ID` is non-empty (always should be)

### Feature B: Skills Count on Row 1

**What:** Show total skills count as a badge.

**Display:**
```
[Opus 4.6 | Max] │ my-project │  main ✓ │ 🧩 124
```

**Implementation:**

Add to the caching section (use git cache pattern, 60s refresh):
```bash
SKILLS_CACHE="/tmp/.claude_sl_skills_$(id -u)"
SKILLS_COUNT=""
if [ "$(file_age "$SKILLS_CACHE")" -lt 60 ] && [ -f "$SKILLS_CACHE" ]; then
  . "$SKILLS_CACHE"
else
  _SC=$(ls -1d "$HOME/.claude/skills"/* 2>/dev/null | wc -l | tr -d ' ')
  SKILLS_COUNT="$_SC"
  printf "SKILLS_COUNT='%s'\n" "$SKILLS_COUNT" > "$SKILLS_CACHE"
fi
```

Add badge (near line 318):
```bash
[ -n "$SKILLS_COUNT" ] && [ "$SKILLS_COUNT" != "0" ] && \
  BADGES="${BADGES}${SEP}${DIM}🧩 ${SKILLS_COUNT}${RST}"
```

**Notes:**
- Cache 60 seconds — skills directory rarely changes
- Simple `ls | wc -l` is <2ms
- Show on Row 1 as dim badge (non-intrusive)

### Feature C: MCP Server Health on Row 1

**What:** Show MCP server count and health status.

**Display:**
```
# All healthy (or no health data):
🔗 27

# Some servers have failures (when health cache exists):
🔗 25/27 ⚠️
```

**Implementation:**

Add to caching section (30s refresh, same as daily cache):
```bash
MCP_CACHE="/tmp/.claude_sl_mcp_$(id -u)"
MCP_DISPLAY=""
if [ "$(file_age "$MCP_CACHE")" -lt 30 ] && [ -f "$MCP_CACHE" ]; then
  . "$MCP_CACHE"
else
  _MCP_CONF="$HOME/.claude/mcp-configs/mcp-servers.json"
  _MCP_TOTAL=0
  if [ -f "$_MCP_CONF" ]; then
    _MCP_TOTAL=$(jq '.mcpServers | length' "$_MCP_CONF" 2>/dev/null)
  fi
  
  # Check health cache if it exists
  _MCP_HEALTH="$HOME/.claude/mcp-health-cache.json"
  _MCP_FAILED=0
  if [ -f "$_MCP_HEALTH" ]; then
    _MCP_FAILED=$(jq '[.[] | select(.healthy == false)] | length' "$_MCP_HEALTH" 2>/dev/null)
  fi
  
  if [ "$_MCP_TOTAL" -gt 0 ]; then
    if [ "$_MCP_FAILED" -gt 0 ]; then
      _MCP_OK=$(( _MCP_TOTAL - _MCP_FAILED ))
      MCP_DISPLAY="${YELLOW}🔗 ${_MCP_OK}/${_MCP_TOTAL} ⚠️${RST}"
    else
      MCP_DISPLAY="${DIM}🔗 ${_MCP_TOTAL}${RST}"
    fi
  fi
  printf "MCP_DISPLAY='%s'\n" "$MCP_DISPLAY" > "$MCP_CACHE"
fi
```

Add badge (near line 318):
```bash
[ -n "$MCP_DISPLAY" ] && BADGES="${BADGES}${SEP}${MCP_DISPLAY}"
```

**Notes:**
- `mcp-servers.json` is the definitive MCP config (27 servers currently)
- Health cache (`mcp-health-cache.json`) may not exist — that's OK, show total count
- When health cache exists and reports failures, show `OK/Total ⚠️`
- Cache 30s to avoid re-reading JSON too often
- `jq` call is <2ms on 6.5KB file

### Feature Priority & Row Placement

| Feature | Row | Position | Effort | Priority |
|---------|-----|----------|--------|----------|
| Session ID badge | R1 | After worktree badge | ~8 lines | HIGH |
| Skills count | R1 | After session ID | ~10 lines | HIGH |
| MCP health | R1 | After skills | ~20 lines | HIGH |

All three go on **Row 1 as badges**, following the existing pattern (vim mode → agent → worktree → session ID → skills → MCP).

**Row 1 with all features:**
```
[Opus 4.6 | Max] │ my-project │  main ✓ │ ⚡ agent │ 📋 7b46..75bc │ 🧩 124 │ 🔗 27
```

In compact mode (< 70 cols), badges are already trimmed by terminal width. No extra logic needed.

---

## Compact Mode Consideration

Row 1 could get crowded with 6+ badges. Dev agent should:
1. Show all badges in wide mode (≥ 100 cols)
2. Show session ID + MCP only in normal mode (70-99)
3. Hide session ID, skills, MCP in compact mode (< 70)

Use existing `TIER` variable:
```bash
if [ "$TIER" != "compact" ]; then
  [ -n "$SID_BADGE" ] && R1="${R1}${SID_BADGE}"
  [ -n "$SKILLS_COUNT" ] && ...
  [ -n "$MCP_DISPLAY" ] && ...
fi
```

---

## DAY_COST Fix Verification

Commit `b3485d8` correctly detects billing model:
- `COST_RAW > 0` → API billing → compute DAY_COST
- `COST_RAW = 0` → Max plan → `DAY_COST = ""`
- `CLAUDE_SL_SHOW_API_EQUIV_COST=1` → force show

Cache currently still shows `DAY_COST='5052.9910'` because the stale cache hasn't expired with the new code path yet. The fix is deployed and will self-correct on next cache refresh when `COST_RAW = 0`.

**Action:** Dev agent should clear cache after deploying: `rm -f /tmp/.claude_sl_daily_*`

---

## Scores

| Category | Score | Change | Notes |
|----------|-------|--------|-------|
| Features | 8.5/10 | — | Rate limit code ready (waiting on API), 3 new features specced |
| Code Quality | 8.0/10 | ↑ +0.5 | Billing detection clean, good fallback design |
| Performance | 8.5/10 | — | New features all use caching |
| Data Accuracy | 7.5/10 | ↑ +1.5 | DAY_COST fix deployed, rate_limits correctly silent |
| UI/UX | 8.5/10 | — | Session ID + skills + MCP will improve information density |
| Stability | 8.0/10 | — | No regressions |
| **Overall** | **8.2/10** | **↑ +0.4** | **DAY_COST fix confirmed. 3 new features ready to implement.** |

---

## Action Items for Dev Agent

### HIGH — Implement These 3 Features

1. **Session ID badge** on Row 1 — `📋 7b46..75bc` (~8 lines)
2. **Skills count badge** on Row 1 — `🧩 124` (~10 lines, cached 60s)
3. **MCP server count/health** on Row 1 — `🔗 27` (~20 lines, cached 30s)

All three follow the existing badge pattern. Add after the worktree badge section (after line 318). Hide in compact mode.

**Commit each feature separately. Push and deploy after each.**

### MEDIUM

4. **Clear stale DAY_COST cache** — `rm -f /tmp/.claude_sl_daily_*`
5. **P1.4: Autocompact countdown** — `remaining_percentage` IS in the JSON. Parse it and estimate turns.
6. **Show Claude Code version** — Parse `version` field, show on Row 1 or as tooltip data

---

*Dev agent: Three small features, all follow the badge pattern on Row 1. Session ID (~8 lines), skills count (~10 lines, cached 60s), MCP health (~20 lines, cached 30s). See implementation specs above. Commit each separately.*
