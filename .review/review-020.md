# Review 020 — Full Project Scoring + Competitive Analysis + Optimization Roadmap

**Date:** 2026-04-11 23:30 (CST)  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Comprehensive project assessment + competitive landscape update  
**LOC:** 746  
**Tests:** 155/155 passing (8 suites, 925 lines of test code)

---

## 1. Competitive Landscape (Updated April 2026)

The landscape has changed dramatically since our last analysis. **Our previous data was wrong** — the projects listed in `feature-roadmap-v2.md` (jarrodwatts/claude-hud, sirmalloc/ccstatusline, etc.) do not appear in current GitHub search results. The real competitive field:

### Top 10 Claude Code Statusline Projects (by stars)

| # | Project | Stars | Lang | Key Features | Unique |
|---|---------|-------|------|--------------|--------|
| 1 | **kamranahmedse/claude-statusline** | 1,037 | Bash+JS | Rate limits via API curl, git, dir | npx installer, API-based rate limits |
| 2 | **martinemde/starship-claude** | 80 | Shell | Starship integration, compaction zones | Declarative TOML config, "dumb zone" concept |
| 3 | **ersinkoc/claude-statusline** | 76 | Shell | Basic statusline | — |
| 4 | **AndyShaman/claude-statusline** | 32 | Bash | H/W rate limits, MCP count, OAuth token | Queries `api.anthropic.com/api/oauth/usage` directly, cross-platform credential access |
| 5 | **spences10/claude-statusline-powerline** | 30 | — | Powerline style, SQLite DB, cache rate | 31x faster than file parsing, IntelliSense config |
| 6 | **tzengyuxio/claude-statusline** | 28 | — | Two-line, Nerd Font, context bar | — |
| 7 | **JungHoonGhae/claude-statusline** | 27 | Bash | Pure bash, no Node | — |
| 8 | **bartleby/claude-statusline** | 23 | — | **21 themes**, 5hr+7day rate limits, ASCII avatar | `/skin <name>` command, dual rate-limit bars |
| 9 | **hell0github/claude-statusline** | 20 | — | Context, cost, session reset time | — |
| 10 | **simplpear/claude-statusline-lite** | 13 | Python | Rate limits, zero deps | Single file |

### Key Competitive Insights

**🔴 Critical Gap: We have NO rate limit display**
- #1 (1,037★) fetches rate limits via `curl` from API
- #4 (32★) queries OAuth usage endpoint directly
- #8 (23★) shows dual 5hr+7day limits with progress bars
- **Our code has parsing for `rate_limits` JSON field (dormant since v2.1.90 doesn't include it), but we don't do API-based fetching like competitors**

**🟡 Gap: No theme system**
- #8 (bartleby) has 21 themes with `/skin` command
- #5 (spences10) has powerline styling
- #2 (martinemde) uses Starship for theming
- We have dark/light detection only

**🟡 Gap: No MCP server count**
- #4 (AndyShaman) shows `3 MCPs` badge
- We have the data (`~/.claude/mcp-configs/mcp-servers.json`) but don't display it

**🟢 Our Advantages (still strong)**
- 4-level preset system (no competitor has this)
- Adaptive terminal width tiers (compact/normal/wide)
- System vitals (CPU, RAM, GPU, disk, battery) — btop-style
- Daily token aggregation from transcript scanning
- Burn rate projection ($/hr)
- Tool activity tracking with status icons
- Session message counting with compaction counter
- 155-test suite (most competitors have 0 tests)

---

## 2. Project Scoring

### Scoring Rubric (10 dimensions)

| # | Dimension | Score | Weight | Weighted | Notes |
|---|-----------|-------|--------|----------|-------|
| 1 | **Feature Completeness** | 7.5/10 | 15% | 1.125 | Good breadth, missing rate limits & themes |
| 2 | **Data Accuracy** | 8.0/10 | 15% | 1.200 | SESSION_TOKENS fixed (was 4.0), daily accurate |
| 3 | **Code Quality** | 7.0/10 | 10% | 0.700 | Single 746-line file, 9 lines >120 chars, no shellcheck |
| 4 | **Performance** | 8.5/10 | 10% | 0.850 | Two-stage jq pipeline, 4-level cache (2/5/10/30s) |
| 5 | **UI/UX** | 7.0/10 | 15% | 1.050 | Good info density, layout needs restructure (review-019) |
| 6 | **Test Coverage** | 8.0/10 | 10% | 0.800 | 155 tests, 8 suites, but no integration/E2E tests |
| 7 | **Stability** | 8.5/10 | 5% | 0.425 | No crashes, OOM fix done, graceful fallbacks |
| 8 | **Cross-Platform** | 7.0/10 | 5% | 0.350 | macOS + Linux, no Windows |
| 9 | **Competitive Position** | 5.5/10 | 10% | 0.550 | No rate limits = missing #1 user request |
| 10 | **Developer Experience** | 6.5/10 | 5% | 0.325 | No npx installer, manual marketplace sync |
| | **OVERALL** | | 100% | **7.375/10** | |

### Score Breakdown

**Strengths (≥8.0):**
- Performance (8.5): Streaming jq pipeline, intelligent caching
- Stability (8.5): Robust error handling, 65 `2>/dev/null` guards
- Data Accuracy (8.0): SESSION_TOKENS fixed, daily scanning correct
- Test Coverage (8.0): 155 unit tests across 8 suites

**Weaknesses (<7.0):**
- Competitive Position (5.5): Missing rate limits, themes, MCP display
- Developer Experience (6.5): No one-command installer, manual deploy
- Code Quality (7.0): 746-line single file approaching limit

---

## 3. Optimization Suggestions (Priority Queue)

### P0 — Layout Restructure (review-019, already spec'd)
**Impact:** UI/UX +1.0  
Move context to Row 1, turn info to Row 2, session to Row 3.  
Status: Spec written, awaiting dev agent.

### P1 — Rate Limit Display via API (NEW — CRITICAL for competitive parity)
**Impact:** Competitive +2.5, Feature +1.0

**What competitors do:**
- kamranahmedse (1,037★): `curl` to API endpoint
- AndyShaman (32★): Reads OAuth token, queries `api.anthropic.com/api/oauth/usage`
- bartleby (23★): Dual 5hr+7day bars with reset countdown

**Our approach should be:**

Option A — **OAuth-based API query** (like AndyShaman):
```bash
# Read OAuth token from macOS Keychain or ~/.claude/.credentials.json
# Query usage endpoint, cache for 2 minutes
# Display: rl 5h 43% (reset 2h14m) │ rl 7d 15%
```

Option B — **Wait for JSON field** (current approach):
- Code already parses `rate_limits.five_hour.used_percentage`
- Claude Code v2.1.90 doesn't send it
- Could activate instantly when/if a future version adds it

**Recommendation:** Implement BOTH. API query as primary, JSON field as secondary. Cache aggressively (2-5 min). This is the #1 feature gap vs competitors.

### P2 — MCP Server Badge
**Impact:** Feature +0.5, Competitive +0.5

```bash
# Already have the data source:
# ~/.claude/mcp-configs/mcp-servers.json → jq '.mcpServers | length'
# Display: mcp 27 on Row 1 badges
```

### P3 — Skills Count Badge
**Impact:** Feature +0.3

```bash
# ~/.claude/skills/ → ls | wc -l
# Display: skills 124 on Row 1 badges
```

### P4 — Theme System (Medium-term)
**Impact:** UI/UX +1.0, Competitive +1.0

Competitors with themes:
- bartleby: 21 themes via `/skin <name>`
- martinemde: Starship TOML palettes
- spences10: Powerline color schemes

**Our approach:** Environment variable override:
```bash
export CLAUDE_SL_THEME=cyberpunk  # or ocean, matrix, etc.
# Override color variables per theme
```

Start with 5 themes: default, ocean, matrix, nord, solarized.

### P5 — One-Command Installer
**Impact:** DX +2.0, Competitive +1.0

kamranahmedse has `npx claude-statusline` (1,037★ — installer UX matters).

```bash
# Goal: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
# Auto-detect OS, install jq if missing, configure settings.json
```

### P6 — Autocompact Countdown (P1.4 from roadmap)
**Impact:** Feature +0.5

```bash
# remaining_percentage IS in the JSON
# When > 70%: show estimated turns remaining
# ⏳ ~8 turns
```

### P7 — Session Name Display
**Impact:** Feature +0.3

```bash
# session_name field from JSON (--name flag)
# Display alongside session(id) if present
```

### P8 — Sparkline Token History
**Impact:** UI/UX +0.5, Competitive +1.0

No competitor has this. Show context usage trend as sparkline:

```
context ▁▂▃▅▆▇ 78%
```

Track last 10 readings in a small cache file.

---

## 4. Revised Feature Priority Matrix

```
P0  ████ Layout Restructure          (review-019)  — UI/UX improvement
P1  ████ Rate Limit via API          (NEW)         — #1 competitive gap
P2  ████ MCP Server Badge            (review-016)  — data ready, ~10 lines
P3  ████ Skills Count Badge          (review-016)  — data ready, ~5 lines
P4  ████ Theme System                (NEW)         — 5 themes, ~50 lines
P5  ████ One-Command Installer       (NEW)         — npx or curl|bash
P6  ████ Autocompact Countdown       (P1.4)        — remaining_percentage
P7  ████ Session Name Display        (P2.2)        — ~5 lines
P8  ████ Sparkline Token History     (NEW)         — differentiator
```

### Estimated Impact on Score

| After | Score | Change | Key Driver |
|-------|-------|--------|------------|
| P0 done | 7.6 | +0.2 | UI/UX |
| P1 done | 8.2 | +0.6 | Competitive + Feature |
| P2+P3 done | 8.5 | +0.3 | Feature |
| P4 done | 8.8 | +0.3 | UI/UX + Competitive |
| P5 done | 9.1 | +0.3 | DX |
| All done | 9.3 | +1.9 | Full suite |

---

## 5. Technical Debt

| Issue | Severity | Fix |
|-------|----------|-----|
| Single 746-line file | MEDIUM | Split into modules: `parse.sh`, `display.sh`, `cache.sh` |
| No shellcheck | LOW | Add shellcheck to CI |
| 9 lines > 120 chars | LOW | Wrap long printf statements |
| `[-5:]` should be `[-3:]` | LOW | Part of review-019 |
| `›` prefix instead of `tools` label | LOW | Part of review-019 |
| No integration tests | MEDIUM | Test with real JSON payloads |
| Manual marketplace sync | MEDIUM | Add post-commit hook |

---

## 6. Competitive Scorecard

| Dimension | Us | kamranahmedse | bartleby | AndyShaman |
|-----------|-----|---------------|----------|------------|
| Stars | — | 1,037 | 23 | 32 |
| Rate limits | ❌ | ✅ API | ✅ dual | ✅ OAuth |
| Themes | ❌ (dark/light) | ❌ | ✅ 21 | ❌ |
| Context bar | ✅ | ✅ | ✅ | ✅ |
| Git integration | ✅ | ✅ | ✅ | ✅ |
| Cost tracking | ✅ | ❌ | ✅ | ❌ |
| System vitals | ✅ | ❌ | ❌ | ❌ |
| Preset system | ✅ 4-level | ❌ | ❌ | ❌ |
| Adaptive width | ✅ 3-tier | ❌ | ❌ | ❌ |
| Tool activity | ✅ | ❌ | ❌ | ❌ |
| Daily aggregation | ✅ | ❌ | ❌ | ❌ |
| Burn rate | ✅ | ❌ | ❌ | ❌ |
| MCP display | ❌ | ❌ | ❌ | ✅ |
| Tests | ✅ 155 | ❌ | ❌ | ❌ |
| Installer | ❌ | ✅ npx | ❌ | ✅ curl|bash |

**Summary:** We have the deepest feature set but lack the #1 user-facing feature (rate limits) and the #1 DX feature (one-command install). Fix these two and we're best-in-class.

---

## Action Items for Dev Agent

### CRITICAL
1. **Implement P0 layout restructure** (review-019 spec)

### HIGH
2. **Research rate limit API access** — How does kamranahmedse fetch it? Can we read OAuth token from `~/.claude/.credentials.json` or macOS Keychain?
3. **Add MCP badge** to Row 1 — `jq '.mcpServers | length' ~/.claude/mcp-configs/mcp-servers.json`
4. **Add Skills badge** to Row 1 — `ls ~/.claude/skills/ | wc -l`

### MEDIUM
5. **Add `[-3:]` limit** for tools display
6. **Replace `›` with `tools` label**

---

*This review will be regenerated every 30 minutes with fresh competitive data. Expires: 2026-04-12 23:30 CST (24 hours).*
