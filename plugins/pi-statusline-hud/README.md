# Pi Statusline HUD

Comprehensive statusline HUD for [Pi](https://pi.dev/) (`@earendil-works/pi-coding-agent`),
adapted from the Claude / Codex Statusline HUD family. Reads directly from
`~/.pi/agent/sessions/**/*.jsonl` so no Pi-side hook is required.

## Quick start

```bash
# tmux
set -g status-right '#(/path/to/plugins/pi-statusline-hud/scripts/statusline.sh 2>/dev/null)'

# Live in a spare pane
bash plugins/pi-statusline-hud/scripts/live.sh

# One-shot
bash plugins/pi-statusline-hud/scripts/statusline.sh
```

## Presets

Set with `PI_STATUSLINE_PRESET=...` or by writing the preset name to
`~/.pi/agent/statusline-preset`. Default: `vitals`.

| Preset      | Rows | Contents                                               |
|-------------|------|--------------------------------------------------------|
| `minimal`   | 1    | model · cwd · git · status · context bar               |
| `essential` | 2    | + per-turn token breakdown, cache hit %, speed, cost   |
| `full`      | 4    | + session totals + today aggregate                     |
| `vitals`    | 5    | + CPU / Mem / GPU / Disk / Battery / Load              |

## Environment

| Variable                     | Purpose                                                 |
|------------------------------|---------------------------------------------------------|
| `PI_HOME`                    | Override `~/.pi`                                        |
| `PI_SESSION_FILE`            | Force a specific JSONL session file                     |
| `PI_STATUSLINE_PRESET`       | Preset name                                             |
| `PI_STATUSLINE_CACHE_DIR`    | Cache dir (default `$XDG_CACHE_HOME/pi-statusline`)     |
| `PI_SL_THEME`                | `dark` (default) or `light`                             |
| `PI_SL_ASCII=1`              | Force ASCII (no Unicode bars)                           |
| `PI_SL_UNICODE=1`            | Force Unicode bars                                      |
| `PI_SL_DAILY_BUDGET`         | USD budget; daily row shows `~$x/$N` and warns ≥90%     |
| `PI_STATUSLINE_INTERVAL`     | Refresh seconds for `live.sh` (default `2`)             |

## How it reads Pi sessions

Pi stores conversations as JSONL trees:
`~/.pi/agent/sessions/--<cwd-with-slashes-replaced>--/<ts>_<uuid>.jsonl`

The first line is a `session` header (`version`, `cwd`); the rest are
`{ "type": "message", "message": { "role": ..., "usage": { ..., "cost": {...} } } }`
entries. Pi already embeds **per-call cost** in `usage.cost.total`, so the HUD
reports real provider cost without needing a pricing table.

The HUD uses the most recently modified `.jsonl` under `PI_SESSIONS_DIR` as the
active session, with `<120s` mtime considered `RUNNING`.

## Dependencies

`jq`, `awk`, `git` (optional). macOS + Linux supported.
