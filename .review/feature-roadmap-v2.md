# Feature Roadmap v2 — claude-statusline-hud

**Date:** 2026-04-11  
**Author:** Lead & Reviewer  
**Status:** Active  
**Previous:** feature-roadmap.md, feature-backlog-002.md

---

## Executive Summary

This roadmap incorporates three major inputs:

1. **Official Claude Code statusline JSON schema** — discovered `rate_limits`, `session_id`, `total_input_tokens`, `remaining_percentage` fields
2. **Competitive landscape research** — 6+ Claude Code statusline projects, largest at 18.3k stars
3. **Cross-platform extensibility assessment** — VS Code is feasible (P2), Cursor is not

### Competitive Context

| Competitor | Stars | Key Advantage |
|-----------|-------|---------------|
| jarrodwatts/claude-hud | 18.3k | Native Claude Code API, tool activity tracking |
| sirmalloc/ccstatusline | 7.1k | Powerline support, theme system, multi-line |
| Haleclipse/CCometixLine | 2.6k | Rust binary (fast), theme system |
| rz1989s/claude-code-statusline | 422 | 28 atomic components, MCP monitoring |
| chongdashu/cc-statusline | 563 | Cost burn rates, progress bars |
| **Ours (claude-statusline-hud)** | — | 4-level presets, adaptive width, burn rate |

**Our competitive advantages:** Preset system, adaptive terminal width, burn rate projection.  
**Our gaps:** No rate limit tracking, no MCP monitoring, no session_id usage, no budget alerts.

---

## NEW: Official Statusline JSON Schema Fields

The official docs at `https://code.claude.com/docs/en/statusline` reveal fields we're not using:

### Immediately Usable (Already in JSON Input)

| Field | Type | What It Provides |
|-------|------|------------------|
| `rate_limits.five_hour.used_percentage` | 0-100 | **5-hour rate limit usage** |
| `rate_limits.five_hour.resets_at` | Unix epoch | When 5hr limit resets |
| `rate_limits.seven_day.used_percentage` | 0-100 | **7-day rate limit usage** |
| `rate_limits.seven_day.resets_at` | Unix epoch | When 7day limit resets |
| `context_window.remaining_percentage` | 0-100 | Pre-calculated remaining % |
| `context_window.total_input_tokens` | int | **Cumulative session input tokens** |
| `context_window.total_output_tokens` | int | **Cumulative session output tokens** |
| `session_id` | string | Native session ID (replaces cksum hack) |
| `session_name` | string | Custom name from `--name` flag |
| `version` | string | Claude Code version |
| `workspace.project_dir` | string | Original launch directory |
| `workspace.added_dirs` | array | Dirs added via `/add-dir` |
| `workspace.git_worktree` | string | Git worktree name |
| `output_style.name` | string | Current output style |

**Key insight:** `rate_limits` data is already being passed to us in the JSON. We just need to parse and display it. This is a **zero-cost feature** — no transcript scanning needed.

---

## Priority Queue v2

```
P0 ████ CRITICAL — Fix & Deploy Daily Token Tracking
         Status: OOM fix implemented (two-stage jq), NOT committed/deployed
         Action: Dev agent must commit, push, deploy, clear cache
         Blocks: ALL P1 features

P1.1 ████ Rate Limit Display [NEW — uses existing JSON data]
         Source: rate_limits.five_hour.used_percentage + resets_at
         Effort: ~20 lines of bash, zero new data sources
         Impact: HIGH — every user wants to know their rate limit
         See: Feature Spec below

P1.2 ████ Use Native session_id [NEW — replaces cksum hack]
         Source: session_id field in JSON
         Effort: ~5 lines
         Impact: Correctness — eliminates hash collision risk

P1.3 ████ Cost Budget Alerts
         Depends on: P0 (accurate daily token data)
         Effort: ~15 lines
         See: Feature Spec below

P1.4 ████ Autocompact Countdown Timer
         Source: context_window.remaining_percentage
         Effort: ~25 lines
         Impact: MEDIUM — helps users anticipate compaction

P2.1 ████ MCP Health Monitor
         Source: Need to investigate available MCP data
         Effort: ~40 lines
         Impact: Competitive differentiator (only rz1989s has this)

P2.2 ████ Session Name Display
         Source: session_name field in JSON
         Effort: ~5 lines

P2.3 ████ VS Code Extension (Cross-Platform Phase 1)
         Approach: StatusBarItem API + file watching
         Reference: jack21/ClaudeCodeUsage extension
         Effort: 1-2 weeks
         See: Cross-Platform section below

P3.1 ████ Sparkline Token History (mini chart)
P3.2 ████ Multi-Day Trend Comparison
P3.3 ████ Session Health Score (0-100 composite)
P3.4 ████ Tool Success/Failure Ratio
P3.5 ████ Project Stack Detection
P3.6 ████ Message Counter + Density
```

---

## Feature Specs

### P1.1: Rate Limit Display

**Source data (already in JSON input):**
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

**Display spec:**

Normal state (< 80%):
```
rl 43% │ reset 2h14m
```

Warning state (80-95%):
```
⚠️  rl 87% │ reset 45m
```

Critical state (> 95%):
```
🔴 rl 98% │ reset 12m
```

**Implementation guidance:**

1. Parse `rate_limits.five_hour.used_percentage` from JSON (it's already there!)
2. Calculate reset countdown: `resets_at - $(date +%s)`
3. Format countdown as hours+minutes
4. Color code: green < 60%, yellow 60-80%, red > 80%
5. Show 5hr by default; show 7-day if 5hr is < 20% but 7-day is > 50%

**Integration point:** Add to Row 2 (context row) or as new Row between 2-3:
```
ctx 45% │ remain 55% │ rl 43% (reset 2h14m)
```

Or as a separate row when rate limit > 50%:
```
⚠️  rate limit 87% │ resets in 45m │ 7-day 15%
```

**Dev agent notes:**
- `resets_at` is Unix epoch seconds. Use `$(date +%s)` to get current time.
- Reset countdown formula: `RESET_SECS=$((RESETS_AT - $(date +%s)))`
- Format: `RESET_H=$((RESET_SECS / 3600))` and `RESET_M=$(((RESET_SECS % 3600) / 60))`
- The 5-hour window is the primary limit users hit. Show it prominently.

### P1.2: Use Native session_id

**Current (hacky):**
```bash
_SID=$(printf '%s' "$TRANSCRIPT" | cksum | cut -d' ' -f1)
```

**New (correct):**
```bash
_SID=$(printf '%s' "$JSON" | jq -r '.session_id // empty')
```

Dev agent: Replace all `_SID` references. The native session_id is guaranteed unique by Claude Code.

### P1.3: Cost Budget Alerts

**User configuration:**
```bash
export CLAUDE_SL_DAILY_BUDGET=50  # $50/day
```

**Display:**
```
cost $12.45 (day $48.72/50 ⚠️)    # > 90% of budget
cost $12.45 (day $32.10/50)         # < 90%
cost $12.45 (day $12.00)            # no budget set
```

**Implementation:**
1. Check `$CLAUDE_SL_DAILY_BUDGET` env var
2. If set, calculate `DAY_COST / BUDGET * 100`
3. Show `/BUDGET` suffix when budget is set
4. Add ⚠️ when > 90%, 🔴 when > 100%

### P1.4: Autocompact Countdown Timer

**Concept:** When context usage > 70%, show estimated remaining messages before autocompact triggers.

**Source data:**
```json
{
  "context_window": {
    "remaining_percentage": 25,
    "current_usage": { ... }
  }
}
```

**Display:**
```
ctx 75% ⏳ ~8 turns          # when > 70%
ctx 90% ⏳ ~2 turns ⚠️       # when > 85%
ctx 95% ⏳ ~1 turn 🔴        # imminent
```

**Estimation logic:**
1. Track context growth per message (delta between invocations)
2. `remaining_tokens / avg_tokens_per_turn ≈ turns_remaining`
3. Cache the estimate, recalculate every 30s

### P2.1: MCP Health Monitor

**Research finding:** Only `rz1989s/claude-code-statusline` currently shows MCP status among competitors. This is a differentiator.

**Data source options:**
1. Check `~/.claude/.mcp.json` or `~/.claude/plugins/*/mcp.json` for configured MCP servers
2. Parse plugin status from `workspace.added_dirs` or similar

**Display:**
```
mcp 3/3 ✓           # all servers healthy
mcp 2/3 ⚠️ (1 down)  # one server disconnected
```

**Dev agent:** First task is to investigate what MCP data is available to the statusline script. Check:
- `~/.claude/.mcp.json` file structure
- Any MCP-related fields in the statusline JSON
- Whether MCP server process status is queryable

---

## Cross-Platform Extensibility (P2)

### VS Code Extension — FEASIBLE ✅

**Architecture:**
```
┌─────────────────────────────────┐
│  VS Code Extension (TypeScript) │
│                                  │
│  StatusBarItem API               │
│  ├─ window.createStatusBarItem() │
│  ├─ text: "$(pulse) Tokens: X"  │
│  └─ tooltip: detailed stats     │
│                                  │
│  Data Source:                     │
│  ├─ Watch ~/.claude/projects/    │
│  └─ 1-min cache (like existing) │
└─────────────────────────────────┘
```

**Reference:** `jack21/ClaudeCodeUsage` (GitHub) already does this:
- Monitors `.claude/projects/` logs
- 1-minute caching
- Status bar display + webview dashboard

**Effort:** 1-2 weeks. Low risk — mature VS Code API.

### Cursor IDE — NOT FEASIBLE ❌

No public extension API. Closed source. Skip entirely.

### OpenCode / Terminal CLIs — MEDIUM

Python-based CLIs (like Aider) could use Rich library for TUI status display. Medium effort, lower priority.

### Recommended Cross-Platform Architecture (Future)

```
Core daemon (Rust/Go)          ← shared logic
├── JSON-RPC over Unix socket  ← protocol
├── VS Code adapter            ← thin TypeScript bridge
├── CLI adapter                ← bash/python consumer
└── Neovim adapter             ← Lua bridge
```

This is Phase 3+. Current priority is Claude Code native features.

---

## Competitive Feature Matrix

Features our competitors have that we DON'T:

| Feature | Who Has It | Our Priority |
|---------|-----------|-------------|
| Rate limit display | None yet! | **P1.1 — first mover** |
| MCP server monitoring | rz1989s | P2.1 |
| Powerline/Nerd Font support | sirmalloc | P3 |
| Theme system (gruvbox, nord) | sirmalloc, CCometixLine | P3 |
| Tool activity tracking | claude-hud | P3 |
| Todo progress display | claude-hud | P3 |
| Session name display | None yet | P2.2 |
| 28 atomic components | rz1989s | P3 (modular architecture) |

Features WE have that competitors DON'T:

| Feature | Details |
|---------|---------|
| 4-level preset system | minimal/essential/full/vitals |
| Adaptive terminal width | compact/normal/wide |
| Burn rate projection | $/hr cost projection |
| System vitals (btop-style) | CPU, RAM, disk bars |
| Cache efficiency display | cache_read tracking |

---

## Metrics & Scoring

Current overall score: **6.0/10** (down from 8.5 due to daily token crisis).

**Target scores after P0+P1 completion:**

| Category | Current | Target | Path |
|----------|---------|--------|------|
| Features | 7.5 | 9.0 | +rate limits, +budget alerts, +autocompact |
| Code Quality | 7.0 | 8.5 | +commit hygiene, +native session_id |
| Performance | 7.0 | 9.0 | Two-stage jq pipeline deployed |
| Data Accuracy | 3.0 | 9.0 | Transcript scanning + rate limits |
| UI/UX | 8.5 | 9.0 | Rate limit display, budget warnings |
| Stability | 6.0 | 8.5 | OOM fix, timeout guards |
| **Overall** | **6.0** | **8.8** | **P0 + P1.1-P1.4** |

---

## Timeline

```
Week 1 (NOW):
  ├── P0:   Fix daily token OOM + commit + deploy
  ├── P1.1: Rate limit display (20 lines, zero new data)
  └── P1.2: Native session_id (5 lines)

Week 2:
  ├── P1.3: Cost budget alerts
  └── P1.4: Autocompact countdown

Week 3-4:
  ├── P2.1: MCP health monitor
  ├── P2.2: Session name display
  └── Begin P2.3: VS Code extension

Month 2+:
  └── P3 features, cross-platform
```

---

*This roadmap supersedes feature-roadmap.md and feature-backlog-002.md.*  
*Next update: After P0 deployment is confirmed.*
