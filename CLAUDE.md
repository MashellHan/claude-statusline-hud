# Claude Code Project Memory

## Project Overview

Claude Statusline HUD — a Bash-based tmux/terminal statusline plugin for Claude Code. Displays context window usage, token stats, cost, git info, rate limits, and system vitals.

**Main file:** `plugins/claude-statusline-hud/scripts/statusline.sh` (~670 LOC)
**Test suite:** `.test/run-tests.sh` (155 tests across 8 suites)
**Reviews:** `.review/` directory (reviewer agent drops numbered review docs)
**Marketplace install:** `~/.claude/plugins/marketplaces/claude-statusline-hud/plugins/claude-statusline-hud/scripts/statusline.sh`

## Auto-Commit and Push Rule

**MANDATORY:** After ANY code change:

1. Verify syntax: `bash -n plugins/claude-statusline-hud/scripts/statusline.sh`
2. Run tests: `bash .test/run-tests.sh`
3. If tests pass: `git add <changed files> && git commit -m "<conventional commit message>" && git push origin main`
4. Deploy to marketplace: `cp plugins/claude-statusline-hud/scripts/statusline.sh ~/.claude/plugins/marketplaces/claude-statusline-hud/plugins/claude-statusline-hud/scripts/statusline.sh`
5. Clear caches if daily token logic changed: `rm -f /tmp/.claude_sl_daily_*`
6. Verify marketplace sync: `diff <repo file> <marketplace file>`

**Never leave uncommitted code changes in the working tree.**

## Architecture

- Single Bash script, no external dependencies beyond `jq`, `awk`, `git`
- JSON input from Claude Code via stdin (session data, context window, rate limits)
- Two-stage jq pipeline for daily token scanning (streaming extract + aggregate) to avoid OOM
- 4-level cache strategy: 2s (activity), 5s (system), 10s (git), 30s (daily aggregation)
- Session isolation via native `session_id` from JSON (fallback: cksum of transcript path)
- Adaptive rendering: compact/normal/wide tiers based on terminal width
- 4 presets: minimal/essential/full/vitals

## Key Design Decisions

- `DAY_COST` only shown for API billing users (COST_RAW > 0). Max plan users see day-tok without dollar amounts.
- Override with `CLAUDE_SL_SHOW_API_EQUIV_COST=1` to force API-equivalent cost display.
- `CLAUDE_SL_DAILY_BUDGET` env var enables budget alerts (e.g., `budget ~$48/$50`).
- Rate limit display uses `bar_color` thresholds (green <70%, yellow 70-89%, red >=90%).
- All awk variables passed via `-v` flag (injection-safe).

## Commit Convention

Use conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`, `perf:`

## Current Status (as of review-015)

| Feature | Status | Commit |
|---------|--------|--------|
| P0: Daily token OOM fix | Done | e731161 |
| P1.1: Rate limit display | Done | ee6f1c5 |
| P1.2: Native session_id | Done | 1cd9507 |
| P1.3: Cost budget alerts | Done | b3485d8 |
| P1.4: Autocompact countdown | Not started | - |
