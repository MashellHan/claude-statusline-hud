# claude-statusline-hud

A comprehensive, btop-inspired statusline HUD plugin for Claude Code. Cross-platform (macOS + Linux) with adaptive terminal width, daily token tracking, burn rate projection, rate limit display, and system vitals.

> Forked from [Thewhey-Brian/claude-statusline-hud](https://github.com/Thewhey-Brian/claude-statusline-hud)

![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

## Preview

### Dark Terminal
![Dark Terminal](assets/screenshot-dark.png)

### Light Terminal
![Light Terminal](assets/screenshot-light.png)

## Features

- **5–7 row HUD** with configurable presets (minimal → vitals)
- **Context window** progress bar with autocompact buffer estimation and warning
- **Live activity** tracking — running tools, todos, agents parsed from transcript
- **Rate limit** display with reset countdown (5-hour window)
- **Burn rate** — hourly cost projection based on current session velocity
- **Daily token summary** — aggregates all sessions today from transcript files
- **Daily cost budget alerts** with configurable threshold
- **Session message counts** — user/LLM messages + compaction count
- **Git integration** — branch, staged/unstaged/untracked, ahead/behind, operation state (REBASING, MERGING, CHERRY-PICK, BISECTING, REVERTING)
- **System vitals** — CPU, memory, GPU, disk, battery, load (btop-style mini bars)
- **Adaptive width** — compact/normal/wide layout based on terminal columns
- **Dark/light theme** auto-detection via `COLORFGBG`
- **Unicode/ASCII** auto-detection with manual override
- **Session ID** cache isolation for multi-instance safety
- **Stale cache cleanup** — auto-removes cache files older than 1 day

## Presets

| Preset | Rows | What you see |
|---|---|---|
| `minimal` | 1 | Model, directory, git branch & status |
| `essential` | 2–3 | + Activity (when active), context bar, rate limit, cache, speed |
| `full` | 3–6 | + Session stats, daily token summary, token breakdown at 85%+ |
| **`vitals`** | **4–7** | **+ System vitals (CPU, memory, GPU, disk, battery, load) (default)** |

### Switch preset

```bash
# Option 1: Write to file
echo "vitals" > ~/.claude/statusline-preset

# Option 2: Environment variable
export CLAUDE_STATUSLINE_PRESET=essential

# Option 3: Use the built-in skill
/statusline
```

## Presets x Terminal Width

<details>
<summary><b>minimal</b> — 1 row</summary>

**Wide (>=100 cols):**
```
[Opus 4.6 (1M context) | Max] | my-project |  main [+2 ~1] ^2 | NORMAL | lightning agent
```

**Compact (<70 cols):**
```
[Opus | Max] | my-project |  main checkmark
```
</details>

<details>
<summary><b>essential</b> — 2–3 rows</summary>

**Wide (>=100 cols):**
```
[Opus 4.6 (1M context) | Max] | my-project |  main [+2 ~1] ^2
> circle Edit auth.ts . checkmark Read x3 | > Fix auth bug (2/5)
context ######.... 42% | token 84k (in 50k cache 80k total-out 15k) | rl 65% reset 2h0m | cache 57% | speed 1k/min
```

Activity row only shows when tools/todos/agents are active.

**Compact (<70 cols):**
```
[Opus | Max] | my-project |  main checkmark
context ###### 42% | token 84k (in 50k cache 80k total-out 15k)
```
</details>

<details open>
<summary><b>full</b> — 3–6 rows</summary>

**Wide (>=100 cols):**
```
[Sonnet 4 | Max] | my-project |  main [+2 ~1] ^2 | lightning agent
> circle Edit auth.ts . checkmark Read x3 | > Fix auth (2/5) | lightning explore
context ########.. 42% | token 84k (in 50k cache 80k total-out 15k) | rl 65% reset 2h0m | cache 57% | speed 1k/min
session (a1b2c3d4) cost $18.75 | time 30m 0s (api 66%) | code +250 -80 up | fire ~$37.50/hr | msg-user 12 msg-llm 45
day 411k (in 180k cache 120k out 111k) | llm-msgs 892 | ~cost $2.87
```

**At high context (85%+), a token breakdown row appears:**
```
context #########. 87% warning | token 179k (in 30k cache 140k total-out 4k) | rl 72% reset 1h23m
  tokens 179k/200k — in 30k cached 140k created 5k total-out 4k
```

**Compact (<70 cols):**
```
[Sonnet | Max] | my-project |  main checkmark
context ###### 42% | token 84k (in 50k cache 80k total-out 15k)
session cost $18.75 | time 30m 0s | code +250 -80 up
```
</details>

<details>
<summary><b>vitals</b> — 4–7 rows</summary>

**Wide (>=100 cols):**
```
[Opus 4.6 (1M context) | Max] | my-project |  main checkmark ^2 | lightning agent
> circle Edit auth.ts . checkmark Read x3 | > Fix auth bug (2/5)
context ########.. 42% | token 84k (in 50k cache 80k total-out 15k) | rl 65% reset 2h0m | cache 57% | speed 1k/min
session (a1b2c3d4) cost $18.75 | time 30m 0s (api 66%) | code +250 -80 up | fire ~$37.50/hr | msg-user 12 msg-llm 45
day 411k (in 180k cache 120k out 111k) | llm-msgs 892 | ~cost $2.87
cpu ##.. 35% | mem #### 15G/16G | gpu #... 11% | disk .... 15G/926G | bat #### 80% | load 2.41
```

**Compact (<70 cols):**
```
[Opus | Max] | my-project |  main checkmark
context ###### 42% | token 84k
session cost $18.75 | time 30m 0s | code +250 -80 up
cpu ##.. 35% | mem #### 15G/16G | gpu #... 11%
```
</details>

## Install

### Quick Install

```bash
# Step 1: Add the marketplace
/plugin marketplace add MashellHan/claude-statusline-hud

# Step 2: Install the plugin
/plugin install claude-statusline-hud
```

The plugin auto-configures on the next session start via a `SessionStart` hook. If the statusline doesn't appear, run the setup script manually:

```bash
bash ~/.claude/plugins/cache/claude-statusline-hud/claude-statusline-hud/*/scripts/setup.sh
```

### Uninstall

```bash
# Step 1: Remove statusLine config
bash ~/.claude/plugins/cache/claude-statusline-hud/claude-statusline-hud/*/scripts/teardown.sh

# Step 2: Remove the plugin
/plugin uninstall claude-statusline-hud
```

### Alternative: Test Locally

```bash
claude --plugin-dir /path/to/claude-statusline-hud/plugins/claude-statusline-hud
```

## What Each Metric Means

### Row 1 — Identity & Location

| Element | Description |
|---|---|
| `[Model \| Max]` | Active model name and subscription plan |
| `Dir` | Current working directory (`~` for home) |
| `branch` | Git branch with dirty status (`+staged ~unstaged ?untracked`) |
| `REBASING` / `MERGING` / etc. | Git operation state (rebase, merge, cherry-pick, bisect, revert) |
| `up/down` | Commits ahead of / behind remote |
| `lightning agent` | Active agent name (when using `--agent`) |
| `leaf worktree` | Active worktree name and branch |
| `NORMAL`/`INSERT` | Vim keybinding mode |
| `up vX.Y` | Update available notification |

### Row 2 — Live Activity (conditional)

Shows the last 5 tools (most recent first), parsed from the session transcript. Only appears when there's activity.

| Symbol | Meaning |
|---|---|
| `>` | Activity row prefix |
| `circle` | Tool currently running — shows target (file, pattern, command) |
| `checkmark` | Tool completed |
| `>` | Active todo/task in progress with completion count |
| `lightning` | Running subagent |

### Row 3 — Context & Rate Limit

| Element | Description |
|---|---|
| `context 42%` | Context window fill % with autocompact buffer estimation (+10% above 70%) |
| `warning` | Warning when adjusted context >= 90% or tokens exceed 200k |
| `token 84k` | Context window token occupancy (derived from API percentage) |
| `in 50k` | Input tokens (excludes cache) |
| `cache 80k` | Cache read tokens — higher means cheaper |
| `total-out 15k` | Cumulative output tokens |
| `rl 65% reset 2h0m` | 5-hour rate limit usage with reset countdown |
| `cache 57%` | Prompt cache hit rate (green >= 80%, yellow >= 40%, red < 40%) |
| `speed 1k/min` | Output token throughput |
| `tokens 179k/200k — ...` | Detailed breakdown row (only at 85%+ context) |

### Row 4 — Session Stats

| Element | Description |
|---|---|
| `session (a1b2c3d4)` | Session label with truncated session ID |
| `cost $18.75` | Total API cost this session (USD) |
| `time 30m 0s` | Wall-clock session time |
| `(api 66%)` | % of time spent waiting for API responses |
| `code +250 -80 up` | Lines added/removed with net direction (up growing, down shrinking, = neutral) |
| `fire ~$37.50/hr` | Burn rate — hourly cost projection (shown after 60s) |
| `msg-user 12 msg-llm 45` | User and LLM message counts this session |
| `loop 3` | Compaction count (number of context auto-compactions) |

### Row 5 — Daily Token Summary

Aggregates token usage from ALL Claude Code sessions today by scanning `~/.claude/projects/*.jsonl` transcript files.

| Element | Description |
|---|---|
| `day 411k` | Total tokens consumed today across all sessions |
| `in 180k` | Total input tokens today |
| `cache 120k` | Total cache read tokens today |
| `out 111k` | Total output tokens today |
| `llm-msgs 892` | Total LLM messages today |
| `~cost $2.87` | Estimated daily cost (Sonnet pricing: $3/$15/$0.30 per 1M tokens) |
| `budget ~$2.87/$10.00 warning` | Budget alert when `CLAUDE_SL_DAILY_BUDGET` is set |

### Row 6 — System Vitals (btop-style)

| Element | Description |
|---|---|
| `cpu` | User + system CPU usage with sub-character precision bar |
| `mem` | Memory used / total |
| `gpu` | GPU utilization (Apple Silicon, NVIDIA, or AMD/Intel) |
| `disk` | Root volume used / total |
| `bat` | Battery level (red alert <= 20%) |
| `load` | 1-minute load average |

## Adaptive Width

The statusline automatically adapts to your terminal width:

| Width | Model label | Bar width | Vitals | Extra |
|---|---|---|---|---|
| **Wide** (>=100) | `Opus 4.6 (1M context)` | 10 chars | All (cpu/mem/gpu/disk/bat/load) | cache, speed, day-tok |
| **Normal** (70–99) | `Opus 4.6` | 8 chars | All | cache, speed |
| **Compact** (<70) | `Opus` | 6 chars | cpu/mem/gpu only | Minimal metrics |

## Platform Support

| Feature | macOS | Linux |
|---|---|---|
| CPU usage | `/usr/bin/top` | `/proc/stat` delta |
| Memory | `/usr/bin/top` + `sysctl hw.memsize` | `/proc/meminfo` |
| GPU | `ioreg` (Apple Silicon) | `nvidia-smi` or `/sys/class/drm` |
| Disk | `df` | `df` |
| Battery | `pmset` | `/sys/class/power_supply/BAT0` |
| Load average | `sysctl vm.loadavg` | `/proc/loadavg` |

## Performance

All expensive operations are cached to keep the statusline snappy:

| Data source | Cache TTL | Notes |
|---|---|---|
| Live activity (tools/todos/agents) | 2 seconds | Parses last 80 lines of transcript JSONL |
| System vitals (CPU/mem/GPU/disk) | 5 seconds | Single cache file, sourced as shell vars |
| Git info (branch, dirty, ahead/behind) | 10 seconds | Per-directory cache isolation via cksum |
| Session message counts | 10 seconds | User/LLM/compaction counts |
| Daily token aggregation | 30 seconds | Scans today's transcript files |

### Optimizations

- **Single jq call** for JSON parsing (20+ fields in one invocation)
- **Two-stage jq pipeline** for daily tracking (streaming extract then small aggregate)
- **Per-session cache isolation** using session ID or transcript path cksum
- **Stale cache auto-cleanup** — files older than 1 day removed on startup
- **Temp file trap** — cleanup on EXIT signal

## Environment Variables

| Variable | Description |
|---|---|
| `CLAUDE_STATUSLINE_PRESET` | Override preset (`minimal`/`essential`/`full`/`vitals`) |
| `CLAUDE_SL_ASCII=1` | Force ASCII bars (`#` `-` instead of Unicode blocks) |
| `CLAUDE_SL_UNICODE=1` | Force Unicode bars |
| `CLAUDE_SL_THEME=dark\|light` | Override terminal theme detection |
| `CLAUDE_SL_SHOW_API_EQUIV_COST=1` | Show estimated daily cost even on Max subscription |
| `CLAUDE_SL_DAILY_BUDGET=10` | Set daily cost budget (USD) — shows budget bar + warning at 90%+ |

## Requirements

- **Required:** `bash`, `jq`
- **Optional:** `git` (git status), `awk` (cost calculations)

## File Structure

```
claude-statusline-hud/
├── .claude-plugin/
│   └── marketplace.json       # Marketplace catalog
├── plugins/
│   └── claude-statusline-hud/
│       ├── .claude-plugin/
│       │   └── plugin.json    # Plugin manifest
│       ├── hooks/
│       │   └── hooks.json     # SessionStart hook for auto-setup
│       ├── scripts/
│       │   ├── statusline.sh  # Main statusline script (~740 lines)
│       │   ├── setup.sh       # Post-install: injects statusLine config
│       │   └── teardown.sh    # Post-uninstall: removes statusLine config
│       └── skills/
│           └── statusline/
│               └── SKILL.md   # /statusline skill for preset switching
├── LICENSE
└── README.md
```

## License

MIT
