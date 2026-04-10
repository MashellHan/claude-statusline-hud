# Feature Roadmap — claude-statusline-hud

**Date:** 2026-04-11  
**Author:** Reviewer Agent  
**Status:** Proposed  
**Based on:** Analysis of btop++, starship, oh-my-posh, powerlevel10k, tmux plugins, neovim statusline (lualine/airline), and 6 competing Claude HUD projects (claude-hud 18.2k stars, ccstatusline 7.1k, CCometixLine 2.6k, claude-powerline 996, claude-statusline 1k, rz1989s 420)

---

## Feature List (12 Features, Priority Ordered)

### Feature 1: Daily Token & Cost Tracking (P0)
**What:** Aggregate token usage and cost across all sessions for the current day. Display in Row 4.  
**Why:** Users need to track daily budget consumption. Most competitors don't have this — strong differentiator.  
**Display:** `cost $1.31 (day $14.82) │ day-tok 145k`  
**Implementation:**
- Create `~/.claude/statusline-data/daily.jsonl` (append-only log)
- Each invocation: hash transcript path as session ID, append `{"ts":..., "sid":"...", "tokens":..., "cost":...}` if changed
- Dedup by checking last entry's session ID
- Aggregate with `jq` filtering by today's date
- Cache aggregation result for 30s in `/tmp/.claude_sl_daily`
- Midnight rollover: filter entries by `$(date +%Y-%m-%d)`

**Acceptance Criteria:**
- [ ] Accurate token count across multiple sessions in one day
- [ ] No double-counting within same session
- [ ] Survives session restart
- [ ] Minimal performance impact (<20ms)

---

### Feature 2: Token Burn Rate with Trend Arrow
**What:** Track token consumption velocity and show acceleration/deceleration trend.  
**Why:** Tells developers if a conversation is getting more expensive. Helps decide when to reset session.  
**Display:** `burn 2.1k/min ↑` (arrow: ↑ accelerating, → stable, ↓ decelerating)  
**Implementation:**
- Write `$NOW $TOTAL_TOKENS` to `/tmp/.claude_sl_burn` each invocation
- Keep last 3 data points, compute delta per minute
- Compare current rate vs previous rate for trend arrow
- Cache 5s

---

### Feature 3: Cost Projection & Budget Guard
**What:** Project total session cost based on burn rate. Warn when approaching user-defined budget.  
**Why:** Budget protection. Competitors like claude-powerline have budget alerts — table stakes.  
**Display:** `est $4.20 by 200k` or `cost $3.12 ⚠ budget $10`  
**Implementation:**
- Formula: `current_cost * (ctx_size / current_tokens)` for projection
- Budget via `CLAUDE_SL_BUDGET=10.00` env var or `~/.claude/statusline-budget`
- Yellow warning at 70% of budget, red at 90%

---

### Feature 4: Autocompact Countdown
**What:** Show estimated messages remaining before context autocompacts.  
**Why:** Concrete planning horizon vs abstract percentage. No competitor has this.  
**Display:** `~12 msgs left` or `compact in ~8 turns`  
**Implementation:**
- Count assistant message lines in transcript for message count
- Avg tokens per message = total_tokens / message_count
- Remaining = (ctx_size - current_tokens) / avg_per_msg
- Show in context row when > 70% full

---

### Feature 5: Git Operation State Detection
**What:** Detect rebase, merge, cherry-pick, bisect in progress.  
**Why:** Critical context when Claude edits files during git operations. Starship has this, we don't.  
**Display:** ` main REBASING 3/7` or ` main MERGING`  
**Implementation:**
- Check `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, `.git/rebase-merge/`, `.git/CHERRY_PICK_HEAD`, `.git/BISECT_LOG`
- Parse rebase progress from `.git/rebase-merge/msgnum` and `.git/rebase-merge/end`
- Add to existing git cache block (10s TTL)

---

### Feature 6: MCP Server Health Monitor
**What:** Show connected MCP server count and status.  
**Why:** Developers need to know if tool integrations are available before using them.  
**Display:** `mcp 3/3 ✓` or `mcp 2/3 ⚠ (github ✗)`  
**Implementation:**
- Parse `~/.claude/settings.json` for MCP config
- Check process/socket availability for each server
- Cache 30s (MCP state rarely changes mid-session)
- Show in Row 1 badges or as new segment

---

### Feature 7: Tool Success/Failure Ratio
**What:** Track tool invocation outcomes from transcript.  
**Why:** Declining success rate = Claude is struggling. Time to rethink approach.  
**Display:** `tools 42/45 ✓ (93%)` or `tools 12/20 ⚠ 60%`  
**Implementation:**
- Parse transcript for `tool_result` entries
- Count success vs error outcomes (check for `is_error` field)
- Warning threshold at <80%
- Extend existing activity parsing (2s cache)

---

### Feature 8: Project Stack Detection
**What:** Auto-detect tech stack from project config files.  
**Why:** Contextualizes what Claude is working with. Starship and oh-my-posh both do this.  
**Display:** `[ts] [react]` or `[py] [django]` in Row 1  
**Implementation:**
- Check for: `package.json` (Node), `tsconfig.json` (TS), `Cargo.toml` (Rust), `go.mod` (Go), `pyproject.toml` (Python), `Gemfile` (Ruby), etc.
- Parse framework from dependencies (react, django, rails, etc.)
- Cache 60s (project stack doesn't change mid-session)

---

### Feature 9: Sparkline Token History
**What:** 8-point sparkline showing context window growth trajectory.  
**Why:** Visual trend — is context growing linearly, exponentially, or in bursts?  
**Display:** `ctx ▁▂▃▄▅▆▇█ 87%` (replaces or augments current bar)  
**Implementation:**
- Append `$PCT` to rolling file `/tmp/.claude_sl_spark` (keep last 8)
- Map each value to braille/block character: `▁▂▃▄▅▆▇█`
- Pure bash array indexing, no external deps

---

### Feature 10: Message Counter with Density
**What:** Conversation turn count and messages-per-minute rate.  
**Why:** High density = rapid debugging. Low density = complex operations. Reflection metric.  
**Display:** `msgs 24 (1.6/min)`  
**Implementation:**
- Count `role: "user"` entries in transcript
- Divide by session duration for rate
- Add to stats row

---

### Feature 11: Process Resource Attribution
**What:** Show Claude Code's own CPU and memory consumption.  
**Why:** Distinguishes "system is loaded" from "Claude is resource-heavy." Important for laptops.  
**Display:** `claude: 12% cpu 340M`  
**Implementation:**
- `ps -o %cpu,rss -p $(pgrep -f "claude" | head -1)` (macOS/Linux)
- Show alongside or replacing system vitals on compact displays
- Cache 5s (same as system vitals)

---

### Feature 12: Config Status Summary
**What:** Count of loaded configurations at a glance.  
**Why:** Answers "is my environment fully configured?" Competitor ccstatusline tracks this.  
**Display:** `cfg: 2md 4rules 3mcp 1hook`  
**Implementation:**
- Count CLAUDE.md files in project and home dir
- Count rules files in `~/.claude/rules/`
- Count MCP entries in settings
- Count hooks in project/global hooks
- Cache 60s

---

## Priority Matrix

| Priority | Feature | Effort | Impact | Differentiation |
|----------|---------|--------|--------|-----------------|
| P0 | 1. Daily token/cost tracking | Medium | High | High — few competitors have this |
| P1 | 2. Burn rate + trend | Low | High | Medium — rz1989s has similar |
| P1 | 3. Cost projection + budget | Medium | High | Medium — claude-powerline has budget |
| P1 | 4. Autocompact countdown | Low | High | High — unique feature |
| P2 | 5. Git operation state | Low | Medium | Low — starship has this |
| P2 | 6. MCP health monitor | Medium | Medium | Medium — ccstatusline has similar |
| P2 | 7. Tool success ratio | Low | Medium | High — unique metric |
| P2 | 8. Project stack detection | Low | Medium | Low — starship standard |
| P3 | 9. Sparkline history | Low | Low | Medium — visual differentiator |
| P3 | 10. Message counter | Low | Low | Low — basic metric |
| P3 | 11. Process attribution | Medium | Low | Medium — unique |
| P3 | 12. Config summary | Low | Low | Low — nice to have |

---

## Competitive Analysis Summary

| Feature | This Project | claude-hud (18.2k★) | ccstatusline (7.1k★) | rz1989s (420★) |
|---------|-----|-----|-----|-----|
| Daily token tracking | ❌ → P0 | ❌ | ❌ | ❌ |
| Burn rate | ❌ → P1 | ❌ | ❌ | ✅ |
| Budget guard | ❌ → P1 | ❌ | ❌ | ✅ |
| Autocompact countdown | ❌ → P1 | ❌ | ❌ | ❌ |
| System vitals | ✅ | ❌ | ✅ | ❌ |
| Live activity | ✅ | ❌ | ✅ | ❌ |
| Adaptive width | ✅ | ✅ | ✅ | ✅ |
| Git status | ✅ | ✅ | ✅ | ✅ |
| Git operation state | ❌ → P2 | ❌ | ❌ | ❌ |
| MCP monitoring | ❌ → P2 | ❌ | ✅ | ✅ |
| Stack detection | ❌ → P2 | ❌ | ❌ | ❌ |
| Tool success rate | ❌ → P2 | ❌ | ❌ | ❌ |
| Pure bash (zero deps) | ✅ | ❌ (Node) | ❌ (TS) | ✅ |
| Presets system | ✅ | ✅ | ✅ | ❌ |

**Key Insight:** Daily token tracking, autocompact countdown, tool success rate, and git operation state are features NO competitor has. These are the strongest differentiators.

---

*This roadmap will be updated as features are implemented and reviewed.*
