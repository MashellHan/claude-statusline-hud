#!/usr/bin/env bash
# ================================================================
#  Claude Statusline HUD — cross-platform (macOS + Linux)
# ================================================================
#  Presets (set via CLAUDE_STATUSLINE_PRESET or ~/.claude/statusline-preset):
#
#    minimal   — 1 row:  [Model | Max] Dir Git │ context bar
#    essential — 2 rows: + Turn info (tokens, speed, tools)
#    full      — 4 rows: + Session stats + Daily summary
#    vitals    — 5 rows: + System vitals (CPU, Mem, GPU, Disk, Battery)  (default)
# ================================================================

set -f  # disable globbing for safety

# --- Dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "[statusline-hud] ERROR: jq is required but not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

input=$(cat)

# --- Temp file cleanup trap ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null
EVENTS_FILE="${CACHE_DIR}/events_$$"
trap 'rm -f "$EVENTS_FILE"' EXIT

# --- Clean up stale statusline cache files (>1 day old) ---
find "$CACHE_DIR" -maxdepth 1 -name '*.cache' -mtime +1 -delete 2>/dev/null

# --- Platform detection ---
OS="$(uname -s)"
is_mac() { [ "$OS" = "Darwin" ]; }
is_linux() { [ "$OS" = "Linux" ]; }

# --- Terminal width detection ---
# Try multiple sources: $COLUMNS often unset in statusline subprocess,
# tput needs TERM, stty needs a tty on stdin/err. Pick the largest sane value.
_w_env="${COLUMNS:-0}"
_w_tput=$(tput cols 2>/dev/null || echo 0)
_w_stty=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
_w_stty="${_w_stty:-0}"
COLS=0
for _c in "$_w_env" "$_w_tput" "$_w_stty"; do
  case "$_c" in ''|*[!0-9]*) continue ;; esac
  [ "$_c" -gt "$COLS" ] 2>/dev/null && COLS="$_c"
done
[ "$COLS" -eq 0 ] 2>/dev/null && COLS=100
if [ "$COLS" -lt 70 ] 2>/dev/null; then TIER="compact"
elif [ "$COLS" -lt 95 ] 2>/dev/null; then TIER="normal"
else TIER="wide"; fi
# Allow forcing table-style alignment regardless of terminal width
if [ "${CLAUDE_SL_FORCE_TABLE:-0}" = "1" ]; then TIER="wide"; fi

# --- Shared column widths for table-aligned rows (R2/R3/R4/R5 in wide tier) ---
COL_PREFIX=18
COL_TOKEN=50  # fits "token 391M (in 319M create 5M cache 63M out 1M)"
COL_MSG=18
COL_TIME=28
COL_COST=14

# --- Determine preset ---
PRESET="${CLAUDE_STATUSLINE_PRESET:-}"
if [ -z "$PRESET" ] && [ -f "$HOME/.claude/statusline-preset" ]; then
  PRESET=$(tr -d '[:space:]' < "$HOME/.claude/statusline-preset")
fi
PRESET="${PRESET:-vitals}"

# --- Parse JSON (single jq call for all fields) ---
eval "$(printf '%s' "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "Unknown")",
  @sh "DIR=\(.workspace.current_dir // "")",
  @sh "PCT=\(.context_window.used_percentage // 0 | floor)",
  @sh "COST_RAW=\(.cost.total_cost_usd // 0)",
  @sh "DURATION_MS=\(.cost.total_duration_ms // 0 | floor)",
  @sh "API_MS=\(.cost.total_api_duration_ms // 0 | floor)",
  @sh "LINES_ADD=\(.cost.total_lines_added // 0)",
  @sh "LINES_DEL=\(.cost.total_lines_removed // 0)",
  @sh "VIM_MODE=\(.vim.mode // "")",
  @sh "AGENT_NAME=\(.agent.name // "")",
  @sh "WT_NAME=\(.worktree.name // "")",
  @sh "WT_BRANCH=\(.worktree.branch // "")",
  @sh "EXCEEDS_200K=\(.exceeds_200k_tokens // false)",
  @sh "INPUT_TOK=\(.context_window.current_usage.input_tokens // 0)",
  @sh "CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "TOTAL_OUT=\(.context_window.total_output_tokens // 0)",
  @sh "TOTAL_INPUT_CUM=\(.context_window.total_input_tokens // 0)",
  @sh "TRANSCRIPT=\(.transcript_path // "")",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "RL_5H_PCT=\(.rate_limits.five_hour.used_percentage // 0 | floor)",
  @sh "RL_5H_RESET=\(.rate_limits.five_hour.resets_at // 0 | floor)",
  @sh "SESSION_ID=\(.session_id // "")"
' 2>/dev/null)" || {
  # Fallback: if jq fails, set safe defaults
  MODEL="Unknown" DIR="" PCT=0 COST_RAW=0 DURATION_MS=0 API_MS=0
  LINES_ADD=0 LINES_DEL=0 VIM_MODE="" AGENT_NAME="" WT_NAME="" WT_BRANCH=""
  EXCEEDS_200K=false INPUT_TOK=0 CACHE_CREATE=0 CACHE_READ=0 TOTAL_OUT=0 TOTAL_INPUT_CUM=0
  TRANSCRIPT="" CTX_SIZE=200000 RL_5H_PCT=0 RL_5H_RESET=0 SESSION_ID=""
}

# --- Smart directory name ---
if [ "$DIR" = "$HOME" ]; then DIR_NAME="~"
elif [ -n "$DIR" ]; then DIR_NAME="${DIR##*/}"
else DIR_NAME=""; fi

# --- Adaptive model label ---
case "$TIER" in
  compact) MODEL_LABEL="${MODEL%% *}" ;;
  normal)  MODEL_LABEL="${MODEL%% (*}" ;;
  wide)    MODEL_LABEL="$MODEL" ;;
esac

# --- Adaptive bar widths ---
case "$TIER" in
  compact) BAR_W=6;  RL_BAR_W=6  ;;
  normal)  BAR_W=8;  RL_BAR_W=8  ;;
  wide)    BAR_W=10; RL_BAR_W=10 ;;
esac

# --- Colors ---
CYAN=$'\033[36m'    GREEN=$'\033[32m'   YELLOW=$'\033[33m'  RED=$'\033[31m'
BLUE=$'\033[34m'    MAGENTA=$'\033[35m' WHITE=$'\033[97m'
RST=$'\033[0m'      BOLD=$'\033[1m'     DIM=$'\033[2m'     ITAL=$'\033[3m'
BG_YELLOW=$'\033[43m'

# --- Theme detection: dark vs light terminal ---
# VAL = color for metric values. Bright white on dark bg, bold on light bg.
# Override: CLAUDE_SL_THEME=dark|light
_THEME="${CLAUDE_SL_THEME:-}"
if [ -z "$_THEME" ]; then
  # COLORFGBG="fg;bg" — bg ≥ 8 usually means light background
  if [ -n "${COLORFGBG:-}" ]; then
    _BG="${COLORFGBG##*;}"
    if [ "${_BG:-0}" -ge 8 ] 2>/dev/null; then _THEME="light"; else _THEME="dark"; fi
  else
    _THEME="dark"  # most terminals default dark
  fi
fi
if [ "$_THEME" = "light" ]; then
  VAL="${BOLD}"
else
  VAL="${WHITE}"
fi

# --- UTF-8 detection ---
# Override: set CLAUDE_SL_ASCII=1 to force ASCII bars, or CLAUDE_SL_UNICODE=1 to force Unicode.
# Default: check locale vars. Hook subprocesses often lack locale, so also check parent shell.
if [ "${CLAUDE_SL_ASCII:-}" = "1" ]; then
  USE_UNICODE=0
elif [ "${CLAUDE_SL_UNICODE:-}" = "1" ]; then
  USE_UNICODE=1
else
  USE_UNICODE=0
  # Check all locale sources — hooks may inherit from parent or have none
  _LOCALE="${LANG:-}${LC_ALL:-}${LC_CTYPE:-}${LANGUAGE:-}"
  case "$_LOCALE" in
    *UTF-8*|*utf-8*|*utf8*|*UTF8*) USE_UNICODE=1 ;;
  esac
  # macOS almost always supports Unicode even without locale vars
  is_mac && USE_UNICODE=1
fi

if [ "$USE_UNICODE" = "1" ]; then
  BAR_FILL="█" BAR_EMPTY="░" SEP_CHAR="│" DOT_SEP="·"
else
  BAR_FILL="#" BAR_EMPTY="-" SEP_CHAR="|" DOT_SEP="."
fi

SEP=" ${DIM}${SEP_CHAR}${RST} "

# --- Helpers ---
make_bar() {
  local pct=$1 width=${2:-10}
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  local filled=$((pct * width / 100)) empty=$((width - pct * width / 100))
  local bar="" i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}${BAR_FILL}"; i=$((i+1)); done
  i=0
  while [ "$i" -lt "$empty" ]; do bar="${bar}${BAR_EMPTY}"; i=$((i+1)); done
  printf '%s' "$bar"
}

mini_bar() {
  local pct=$1
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  if [ "$USE_UNICODE" = "1" ]; then
    local width=4 total=$((pct * width))
    local full=$((total / 100)) remainder=$(( (total % 100) * 8 / 100 ))
    local bar="" i=0
    while [ "$i" -lt "$full" ] && [ "$i" -lt "$width" ]; do bar="${bar}█"; i=$((i+1)); done
    if [ "$i" -lt "$width" ] && [ "$remainder" -gt 0 ]; then
      case "$remainder" in
        1) bar="${bar}▏" ;; 2) bar="${bar}▎" ;; 3) bar="${bar}▍" ;; 4) bar="${bar}▌" ;;
        5) bar="${bar}▋" ;; 6) bar="${bar}▊" ;; 7) bar="${bar}▉" ;;
      esac
      i=$((i+1))
    fi
    while [ "$i" -lt "$width" ]; do bar="${bar} "; i=$((i+1)); done
    printf '%s' "$bar"
  else
    # ASCII fallback: [##--] style
    local width=4 filled=$((pct * width / 100)) empty=$((width - pct * width / 100))
    local bar=""
    [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '#')
    [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '-')"
    printf '%s' "$bar"
  fi
}

bar_color() {
  if [ "$1" -ge 90 ] 2>/dev/null; then printf '%s' "$RED"
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

bar_color_inv() {
  if [ "$1" -le 10 ] 2>/dev/null; then printf '%s' "$RED"
  elif [ "$1" -le 30 ] 2>/dev/null; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

fmt_dur() {
  local s=$(($1 / 1000))
  local h=$((s/3600)) m=$(((s%3600)/60)) sec=$((s%60))
  if [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm %ds' "$m" "$sec"
  else printf '%ds' "$sec"; fi
}

fmt_tok() {
  if [ "$1" -ge 1000000 ] 2>/dev/null; then printf '%dM' "$(($1/1000000))"
  elif [ "$1" -ge 1000 ] 2>/dev/null; then printf '%dk' "$(($1/1000))"
  else printf '%d' "$1"; fi
}

fmt_cost() { printf '$%s' "$(printf '%s' "$1" | awk '{printf "%.2f", $1}')"; }

# --- Visible-width helpers (ANSI-aware) for table-style alignment ---
_vlen() {
  # Visible character length of $1, ignoring ANSI CSI escapes.
  # Uses awk so we don't fork sed; multi-byte chars (emoji, ↑↓) count as 1 grapheme
  # only when LANG supports it — but for our labels this is good enough.
  LC_ALL=C.UTF-8 awk -v s="$1" 'BEGIN{
    gsub(/\033\[[0-9;]*m/, "", s);
    # crude: count multi-byte UTF-8 sequences as single chars
    n=0; i=1; L=length(s);
    while (i<=L) {
      c=substr(s,i,1); b=0;
      if (c<"\200") b=1;
      else if (c<"\300") b=1;          # stray continuation
      else if (c<"\340") b=2;
      else if (c<"\360") b=3;
      else b=4;
      n++; i+=b;
    }
    print n;
  }' 2>/dev/null
}
_vpad() {
  # Right-pad string $1 (may contain ANSI) to visible width $2.
  local s="$1" w="$2" len pad
  len=$(_vlen "$s")
  pad=$((w - len))
  if [ "$pad" -gt 0 ]; then
    printf '%s%*s' "$s" "$pad" ""
  else
    printf '%s' "$s"
  fi
}

NOW=$(date +%s)

file_age() {
  local f="$1"
  [ -f "$f" ] || { echo 9999; return; }
  if is_mac; then echo $(( NOW - $(stat -f%m "$f" 2>/dev/null || echo 0) ))
  else echo $(( NOW - $(stat -c%Y "$f" 2>/dev/null || echo 0) )); fi
}

# --- Session ID for cache isolation ---
if [ -n "$SESSION_ID" ]; then
  _SID="$SESSION_ID"
elif [ -n "$TRANSCRIPT" ]; then
  _SID=$(printf '%s' "$TRANSCRIPT" | cksum | awk '{print $1}')
else
  _SID="$$"
fi

# =============================================
# GIT INFO (cached 10s)
# =============================================
GIT_DISPLAY=""
if [ -n "$DIR" ]; then
  _DIR_HASH=$(printf '%s' "$DIR" | cksum | awk '{print $1}')
  GIT_CACHE="${CACHE_DIR}/git_${_DIR_HASH}.cache"
  if [ "$(file_age "$GIT_CACHE")" -lt 10 ]; then
    GIT_INFO=$(cat "$GIT_CACHE")
  else
    if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
      GB=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
      GD=""
      # Single git status --porcelain call instead of 3 separate commands
      _GS_OUT=$(git -C "$DIR" status --porcelain 2>/dev/null)
      if [ -n "$_GS_OUT" ]; then
        gs=$(printf '%s\n' "$_GS_OUT" | grep -c '^[MADRC]')
        gu=$(printf '%s\n' "$_GS_OUT" | grep -c '^.[MDRC]')
        gq=$(printf '%s\n' "$_GS_OUT" | grep -c '^??')
      else
        gs=0 gu=0 gq=0
      fi
      [ "$gs" -gt 0 ] && GD="${GD}+${gs}"
      [ "$gu" -gt 0 ] && GD="${GD} ~${gu}"
      [ "$gq" -gt 0 ] && GD="${GD} ?${gq}"
      # Detect git operation state
      _GIT_DIR=$(git -C "$DIR" rev-parse --git-dir 2>/dev/null)
      GIT_STATE=""
      if [ -d "${_GIT_DIR}/rebase-merge" ]; then
        _RB_CUR=$(cat "${_GIT_DIR}/rebase-merge/msgnum" 2>/dev/null)
        _RB_END=$(cat "${_GIT_DIR}/rebase-merge/end" 2>/dev/null)
        GIT_STATE="REBASING${_RB_CUR:+ ${_RB_CUR}/${_RB_END}}"
      elif [ -d "${_GIT_DIR}/rebase-apply" ]; then
        GIT_STATE="REBASING"
      elif [ -f "${_GIT_DIR}/MERGE_HEAD" ]; then
        GIT_STATE="MERGING"
      elif [ -f "${_GIT_DIR}/CHERRY_PICK_HEAD" ]; then
        GIT_STATE="CHERRY-PICK"
      elif [ -f "${_GIT_DIR}/BISECT_LOG" ]; then
        GIT_STATE="BISECTING"
      elif [ -f "${_GIT_DIR}/REVERT_HEAD" ]; then
        GIT_STATE="REVERTING"
      fi
      UPSTREAM=$(git -C "$DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
      GAB=""
      if [ -n "$UPSTREAM" ]; then
        AB=$(git -C "$DIR" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
        AHEAD=$(printf '%s' "$AB" | awk '{print $1}')
        BEHIND=$(printf '%s' "$AB" | awk '{print $2}')
        [ "${AHEAD:-0}" -gt 0 ] && GAB="↑${AHEAD}"
        [ "${BEHIND:-0}" -gt 0 ] && GAB="${GAB}↓${BEHIND}"
      fi
      GIT_INFO="${GB}|${GD}|${GAB}|${GIT_STATE}"
    else
      GIT_INFO="|||"
    fi
    printf '%s' "$GIT_INFO" > "$GIT_CACHE"
  fi
  GB=$(printf '%s' "$GIT_INFO" | cut -d'|' -f1)
  GD=$(printf '%s' "$GIT_INFO" | cut -d'|' -f2)
  GAB=$(printf '%s' "$GIT_INFO" | cut -d'|' -f3)
  GIT_STATE=$(printf '%s' "$GIT_INFO" | cut -d'|' -f4)
  if [ -n "$GB" ]; then
    GIT_DISPLAY="${MAGENTA} ${GB}${RST}"
    [ -n "$GIT_STATE" ] && GIT_DISPLAY="${GIT_DISPLAY} ${RED}${BOLD}${GIT_STATE}${RST}"
    if [ -n "$GD" ]; then GIT_DISPLAY="${GIT_DISPLAY} ${YELLOW}[${GD}]${RST}"
    else GIT_DISPLAY="${GIT_DISPLAY} ${GREEN}✓${RST}"; fi
    [ -n "$GAB" ] && GIT_DISPLAY="${GIT_DISPLAY} ${CYAN}${GAB}${RST}"
  fi
fi

# --- Badges (truncate long names to prevent overflow) ---
BADGES=""
[ -n "$VIM_MODE" ] && BADGES="${BADGES}${SEP}${BOLD}${BLUE}${VIM_MODE}${RST}"
if [ -n "$AGENT_NAME" ]; then
  AGENT_TRUNC="${AGENT_NAME:0:8}"
  BADGES="${BADGES}${SEP}${BOLD}${CYAN}⚡ ${AGENT_TRUNC}${RST}"
fi
if [ -n "$WT_NAME" ]; then
  WT_TRUNC="${WT_NAME:0:15}"
  BADGES="${BADGES}${SEP}${DIM}🌿 ${WT_TRUNC}${WT_BRANCH:+→${WT_BRANCH}}${RST}"
fi
# MCP server count badge
_MCP_FILE="$HOME/.claude/mcp-configs/mcp-servers.json"
if [ -f "$_MCP_FILE" ]; then
  _MCP_COUNT=$(jq '.mcpServers | length' "$_MCP_FILE" 2>/dev/null)
  [ "${_MCP_COUNT:-0}" -gt 0 ] 2>/dev/null && \
    BADGES="${BADGES}${SEP}${DIM}mcp${RST} ${VAL}${_MCP_COUNT}${RST}"
fi
# Skills count badge
_SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$_SKILLS_DIR" ]; then
  _SKILLS_COUNT=$(find "$_SKILLS_DIR" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
  [ "${_SKILLS_COUNT:-0}" -gt 0 ] 2>/dev/null && \
    BADGES="${BADGES}${SEP}${DIM}skills${RST} ${VAL}${_SKILLS_COUNT}${RST}"
fi

# --- Update notice ---
UPDATE_BADGE=""
if [ -f "${CACHE_DIR}/update_available" ]; then
  NEW_VER=$(cat "${CACHE_DIR}/update_available" 2>/dev/null)
  [ -n "$NEW_VER" ] && UPDATE_BADGE="${SEP}${YELLOW}${BOLD}↑ v${NEW_VER}${RST}"
fi

# --- Precompute context bar (needed for Row 1) ---
# Autocompact buffer estimation: inflate by ~10% above 70% to reflect true context pressure
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))
ADJ_PCT=$PCT
if [ "$PCT" -ge 70 ] 2>/dev/null; then
  ADJ_PCT=$(( PCT + (PCT - 70) * 10 / 30 ))
  [ "$ADJ_PCT" -gt 100 ] && ADJ_PCT=100
fi
CTX_CLR=$(bar_color "$ADJ_PCT")
CTX_BAR=$(make_bar "$ADJ_PCT" "$BAR_W")
CTX_WARN=""
if [ "$EXCEEDS_200K" = "true" ] || [ "$ADJ_PCT" -ge 90 ] 2>/dev/null; then
  CTX_WARN=" ${BOLD}${BG_YELLOW} ⚠ ${RST}"
fi
CTX_LABEL="${VAL}${PCT}%${RST}"

# =============================================================
# ROW 1: [Model | Max] │ Dir │ Git │ Badges │ context bar  [ALL]
# =============================================================
if [ "$_THEME" = "light" ]; then
  R1="${CYAN}[${MODEL_LABEL} | Max]${RST}"
else
  R1="${BOLD}${CYAN}[${MODEL_LABEL} | Max]${RST}"
fi
R1="${R1}${SEP}${BOLD}${GREEN}${DIR_NAME}${RST}"
[ -n "$GIT_DISPLAY" ] && R1="${R1}${SEP}${GIT_DISPLAY}"
[ -n "$BADGES" ] && R1="${R1}${BADGES}"
[ -n "$UPDATE_BADGE" ] && R1="${R1}${UPDATE_BADGE}"
# Append context bar
if [ "$TIER" = "compact" ]; then
  R1="${R1}${SEP}${CYAN}ctx${RST} ${CTX_CLR}${CTX_LABEL}${RST}${CTX_WARN}"
else
  R1="${R1}${SEP}${CYAN}context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
fi
# (R1 print is deferred until after R2 precompute, so tools/cache/speed/rl
#  can be appended to it.)

# =============================================================
# ROW 2: Turn-level — per-turn tokens │ cache │ speed │ tools  [ESSENTIAL+]
# =============================================================

# --- Precompute turn-level metrics ---
TURN_DISPLAY=""
TURN_TOK_INNER=""  # content without "turn " prefix, for table mode
if [ "$INPUT_TOK" -gt 0 ] 2>/dev/null || [ "$CACHE_READ" -gt 0 ] 2>/dev/null; then
  _TURN_TOTAL=$((INPUT_TOK + CACHE_READ + CACHE_CREATE + TOTAL_OUT))
  _TURN_BD="${DIM}(${RST}${DIM}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST}"
  [ "$CACHE_READ" -gt 0 ] 2>/dev/null && _TURN_BD="${_TURN_BD} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHE_READ)${RST}"
  [ "$TIER" = "wide" ] && [ "$CACHE_CREATE" -gt 0 ] 2>/dev/null && \
    _TURN_BD="${_TURN_BD} ${DIM}create${RST} ${YELLOW}${VAL}$(fmt_tok $CACHE_CREATE)${RST}"
  [ "$TOTAL_OUT" -gt 0 ] 2>/dev/null && _TURN_BD="${_TURN_BD} ${DIM}out${RST} ${VAL}$(fmt_tok $TOTAL_OUT)${RST}"
  _TURN_BD="${_TURN_BD}${DIM})${RST}"
  TURN_TOK_INNER="${CYAN}token${RST} ${VAL}$(fmt_tok $_TURN_TOTAL)${RST} ${_TURN_BD}"
  TURN_DISPLAY="${CYAN}turn${RST} ${TURN_TOK_INNER}"
fi

# Cache hit rate (per-turn)
CACHE_HIT=""
if [ "$TOTAL_INPUT" -gt 0 ]; then
  CP=$((CACHE_READ * 100 / TOTAL_INPUT))
  if [ "$CP" -ge 80 ]; then CC="$GREEN"; elif [ "$CP" -ge 40 ]; then CC="$YELLOW"; else CC="$RED"; fi
  CACHE_HIT="${CYAN}cache${RST} ${CC}${VAL}${CP}%${RST}"
fi

# Throughput (session-level average) — based on streaming time, not wall-clock
THROUGHPUT=""
if [ "$API_MS" -gt 0 ] && [ "$TOTAL_OUT" -gt 0 ]; then
  TPM=$((TOTAL_OUT * 60000 / API_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
fi

# Rate limit indicator
RL_DISPLAY=""
if [ "$RL_5H_PCT" -gt 0 ] 2>/dev/null; then
  RL_CLR=$(bar_color "$RL_5H_PCT")
  RL_DISPLAY="${CYAN}rl${RST} ${RL_CLR}${VAL}${RL_5H_PCT}%${RST}"
  if [ "$RL_5H_RESET" -gt 0 ] 2>/dev/null; then
    _RL_LEFT=$(( RL_5H_RESET - NOW ))
    if [ "$_RL_LEFT" -gt 0 ]; then
      _RL_H=$(( _RL_LEFT / 3600 ))
      _RL_M=$(( (_RL_LEFT % 3600) / 60 ))
      if [ "$_RL_H" -gt 0 ]; then
        RL_DISPLAY="${RL_DISPLAY} ${DIM}reset${RST} ${VAL}${_RL_H}h${_RL_M}m${RST}"
      else
        RL_DISPLAY="${RL_DISPLAY} ${DIM}reset${RST} ${VAL}${_RL_M}m${RST}"
      fi
    fi
  fi
fi

# Tool activity (last 3 tools, cached 2s)
ACTIVITY_CACHE="${CACHE_DIR}/activity_${_SID}.cache"
ACTIVITY_LINE=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if [ "$(file_age "$ACTIVITY_CACHE")" -lt 2 ]; then
    ACTIVITY_LINE=$(cat "$ACTIVITY_CACHE")
  else
    tail -80 "$TRANSCRIPT" 2>/dev/null | jq -c '
      [(.message.content // [])[] | select(.type == "tool_use" or .type == "tool_result") |
        if .type == "tool_use" then
          {t: "u", id: .id, n: .name, tgt: (
            if (.name == "Edit" or .name == "Write" or .name == "Read") then
              (.input.file_path // "" | split("/") | last)
            elif (.name == "Grep" or .name == "Glob") then
              (.input.pattern // "")[0:20]
            elif .name == "Bash" then
              (.input.command // "")[0:25]
            elif .name == "Agent" then
              (.input.description // "agent")
            elif .name == "TodoWrite" then
              (.input.todos // [] |
                ([.[] | select(.status == "completed")] | length | tostring) + "/" +
                (length | tostring) + " " +
                ([.[] | select(.status == "in_progress")] | first // {content:""} | .content // "")[0:25])
            else "" end)}
        else {t: "r", id: .tool_use_id} end
      ][]
    ' 2>/dev/null > "$EVENTS_FILE"
    ACTIVITY_LINE=""
    if [ -s "$EVENTS_FILE" ]; then
      ACTIVITY_LINE=$(jq -rs '
        (reduce .[] as $e ({};
          if $e.t == "u" then .[$e.id] = {name: $e.n, target: $e.tgt, done: false}
          elif $e.t == "r" then .[$e.id].done = true
          else . end
        )) as $tools |
        ([$tools | to_entries | .[-3:] | reverse[] |
          if .value.done then "✓ " + .value.name
          else "◐ " + .value.name + (if .value.target != "" then " " + .value.target else "" end) end
        ] | join(" · ")) as $tool_str |
        ([$tools | to_entries[] | select(.value.name == "Agent" and .value.done == false)] |
          if length > 0 then (first | "⚡ " + .value.target) else "" end
        ) as $agent_str |
        [[$tool_str, $agent_str] | .[] | select(length > 0)] | join("  │  ")
      ' "$EVENTS_FILE" 2>/dev/null)
    fi
    rm -f "$EVENTS_FILE"
    printf '%s' "$ACTIVITY_LINE" > "$ACTIVITY_CACHE"
  fi
fi

# --- Append turn-status extras to Row 1 (tools, cache hit, speed, rl) ---
if [ "$PRESET" != "minimal" ] && [ "$TIER" != "compact" ]; then
  [ -n "$CACHE_HIT" ]   && R1="${R1}${SEP}${CACHE_HIT}"
  [ -n "$RL_DISPLAY" ]  && R1="${R1}${SEP}${RL_DISPLAY}"
  [ -n "$ACTIVITY_LINE" ] && R1="${R1}${SEP}${CYAN}tools${RST} ${ACTIVITY_LINE}"
fi
printf '%b\n' "$R1"

[ "$PRESET" = "minimal" ] && exit 0

# --- Assemble Row 2 ---
R2=""
if [ "$TIER" = "wide" ]; then
  # Table-aligned with R3/R4: identical column labels (token|msg|time|cost).
  # All extras (cache%, speed, rl, tools) moved to Row 1 — turn row stays clean.
  _R2_PREFIX="${CYAN}turn${RST}"
  _R2_TOKEN="$TURN_TOK_INNER"
  _DASH="${DIM}—${RST}"
  _R2_MSG="${CYAN}msg${RST} ${_DASH}"
  _R2_TIME="${CYAN}time${RST} ${_DASH}"
  _R2_COST="${CYAN}cost${RST} ${_DASH}"

  if [ -n "$_R2_TOKEN" ]; then
    R2="$(_vpad "$_R2_PREFIX" "$COL_PREFIX")${SEP}"
    R2="${R2}$(_vpad "$_R2_TOKEN" "$COL_TOKEN")${SEP}"
    R2="${R2}$(_vpad "$_R2_MSG"   "$COL_MSG")${SEP}"
    R2="${R2}$(_vpad "$_R2_TIME"  "$COL_TIME")${SEP}"
    R2="${R2}$(_vpad "$_R2_COST"  "$COL_COST")"
    [ -n "$THROUGHPUT" ] && R2="${R2}${SEP}${THROUGHPUT}"
  fi
else
  [ -n "$TURN_DISPLAY" ] && R2="$TURN_DISPLAY"
  [ -n "$THROUGHPUT" ] && [ -n "$R2" ] && R2="${R2}${SEP}${THROUGHPUT}"
fi
if [ -n "$R2" ]; then
  printf '%b\n' "$R2"
elif [ "$PRESET" != "minimal" ]; then
  printf '%b\n' "${CYAN}turn${RST} ${DIM}waiting...${RST}"
fi

# --- Token breakdown row (conditional): shown at 85%+ context ---
CTX_TOKENS=$((CTX_SIZE * PCT / 100))
if [ "$PCT" -ge 85 ] 2>/dev/null && [ "$TOTAL_INPUT" -gt 0 ] && [ "$TIER" != "compact" ]; then
  printf '%b\n' "  ${DIM}tokens${RST} $(fmt_tok $CTX_TOKENS)/$(fmt_tok $CTX_SIZE) ${DIM}—${RST} ${DIM}in${RST} ${BOLD}$(fmt_tok $INPUT_TOK)${RST} ${DIM}cached${RST} ${GREEN}${BOLD}$(fmt_tok $CACHE_READ)${RST} ${DIM}created${RST} ${YELLOW}$(fmt_tok $CACHE_CREATE)${RST} ${DIM}total-out${RST} ${BOLD}$(fmt_tok $TOTAL_OUT)${RST}"
fi

[ "$PRESET" = "essential" ] && exit 0

# =============================================================
# ROW 3: Session-level — token │ msg │ time │ cost │ code  [FULL+]
# =============================================================

# --- Session message & compact counts (from transcript, cached 10s) ---
SESS_USER_MSGS=0 SESS_LLM_MSGS=0 SESS_COMPACTS=0
SESS_INPUT=0 SESS_OUTPUT=0 SESS_CACHE_CREATE=0 SESS_CACHE_READ=0
SESS_MSG_CACHE="${CACHE_DIR}/sessmsg_${_SID}.cache"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if [ "$(file_age "$SESS_MSG_CACHE")" -lt 10 ] && [ -f "$SESS_MSG_CACHE" ]; then
    . "$SESS_MSG_CACHE"
  else
    _SESS_COUNTS=$(jq -r '.type + ":" + (.subtype // "")' "$TRANSCRIPT" 2>/dev/null | \
      awk -F: '
        $1=="user"      {u++}
        $1=="assistant"  {a++}
        $1=="system" && $2=="compact_boundary" {c++}
        END {printf "%d %d %d", u+0, a+0, c+0}
      ')
    SESS_USER_MSGS=$(printf '%s' "$_SESS_COUNTS" | awk '{print $1}')
    SESS_LLM_MSGS=$(printf '%s' "$_SESS_COUNTS" | awk '{print $2}')
    SESS_COMPACTS=$(printf '%s' "$_SESS_COUNTS" | awk '{print $3}')
    # Session token breakdown (cumulative across all turns in this transcript)
    _SESS_TOK_BD=$(jq -s '
      [.[] | .message.usage // empty] |
      {i: (map(.input_tokens // 0) | add // 0),
       o: (map(.output_tokens // 0) | add // 0),
       cc: (map(.cache_creation_input_tokens // 0) | add // 0),
       cr: (map(.cache_read_input_tokens // 0) | add // 0)}
    ' "$TRANSCRIPT" 2>/dev/null)
    eval "$(printf '%s' "$_SESS_TOK_BD" | jq -r '
      @sh "SESS_INPUT=\(.i // 0)",
      @sh "SESS_OUTPUT=\(.o // 0)",
      @sh "SESS_CACHE_CREATE=\(.cc // 0)",
      @sh "SESS_CACHE_READ=\(.cr // 0)"
    ' 2>/dev/null)" 2>/dev/null || {
      SESS_INPUT=0 SESS_OUTPUT=0 SESS_CACHE_CREATE=0 SESS_CACHE_READ=0
    }
    printf "SESS_USER_MSGS='%s'\nSESS_LLM_MSGS='%s'\nSESS_COMPACTS='%s'\nSESS_INPUT='%s'\nSESS_OUTPUT='%s'\nSESS_CACHE_CREATE='%s'\nSESS_CACHE_READ='%s'\n" \
      "$SESS_USER_MSGS" "$SESS_LLM_MSGS" "$SESS_COMPACTS" \
      "$SESS_INPUT" "$SESS_OUTPUT" "$SESS_CACHE_CREATE" "$SESS_CACHE_READ" > "$SESS_MSG_CACHE"
  fi
fi

# --- Precompute session-level metrics ---
SESSION_TOKENS=$((TOTAL_INPUT_CUM + TOTAL_OUT))
# Fallback: use context occupancy estimate if cumulative fields missing
_TOK_HEADLINE=$SESSION_TOKENS
[ "$CTX_TOKENS" -gt "$_TOK_HEADLINE" ] 2>/dev/null && _TOK_HEADLINE=$CTX_TOKENS

COST_FMT=$(fmt_cost "$COST_RAW")
DUR=$(fmt_dur "$API_MS")  # streaming/API time only, not session wall-clock
EFF=""

LINES=""
if [ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]; then
  NET=$((LINES_ADD - LINES_DEL))
  if [ "$NET" -gt 0 ]; then NI="${GREEN}▲${RST}"
  elif [ "$NET" -lt 0 ]; then NI="${RED}▼${RST}"
  else NI="${YELLOW}═${RST}"; fi
  LINES="${GREEN}+${LINES_ADD}${RST} ${RED}-${LINES_DEL}${RST} ${NI}"
fi

BURN_RATE=""
if [ "$API_MS" -gt 60000 ] && [ "$SESSION_TOKENS" -gt 0 ]; then
  BURN_COST_HR=$(awk -v d="$API_MS" -v c="$COST_RAW" 'BEGIN{dh=d/3600000; if(dh>0) printf "%.2f", c/dh; else print 0}')
  BURN_RATE="${YELLOW}🔥${RST} ${DIM}≈${RST}${VAL}\$${BURN_COST_HR}/hr${RST}"
fi

# --- Assemble Row 3 (table-aligned with R2/R4/R5 on wide terminals) ---
# (Column widths COL_PREFIX/COL_TOKEN/COL_MSG/COL_TIME/COL_COST defined above.)

_R3_PREFIX="${CYAN}session${RST}"
if [ -n "$SESSION_ID" ]; then
  _SID_SHORT="${SESSION_ID:0:8}"
  _R3_PREFIX="${CYAN}session${RST}${DIM}(${RST}${VAL}${_SID_SHORT}${RST}${DIM})${RST}"
fi
_R3_TOKEN=""
[ "$_TOK_HEADLINE" -gt 0 ] && _R3_TOKEN="${CYAN}token${RST} ${VAL}$(fmt_tok $_TOK_HEADLINE)${RST}"
_R3_MSG=""
if [ "$SESS_USER_MSGS" -gt 0 ] 2>/dev/null || [ "$SESS_LLM_MSGS" -gt 0 ] 2>/dev/null; then
  _R3_MSG="${CYAN}msg${RST} ${VAL}${SESS_USER_MSGS}↑${SESS_LLM_MSGS}↓${RST}"
  [ "$SESS_COMPACTS" -gt 0 ] 2>/dev/null && _R3_MSG="${_R3_MSG} ${YELLOW}⟳${SESS_COMPACTS}${RST}"
fi
_R3_TIME="${CYAN}time${RST} ${VAL}${DUR}${RST}${EFF}"
_R3_COST="${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"
# Session token breakdown (in/create/cache/out) — appended INSIDE the token
# column so it stays grouped with the total. Matches R4 day-total layout.
if [ "${SESS_INPUT:-0}" -gt 0 ] 2>/dev/null || [ "${SESS_OUTPUT:-0}" -gt 0 ] 2>/dev/null \
   || [ "${SESS_CACHE_READ:-0}" -gt 0 ] 2>/dev/null; then
  _R3_BD="${DIM}(${RST}${DIM}in${RST} ${VAL}$(fmt_tok "${SESS_INPUT:-0}")${RST}"
  [ "${SESS_CACHE_CREATE:-0}" -gt 0 ] 2>/dev/null && \
    _R3_BD="${_R3_BD} ${DIM}create${RST} ${YELLOW}${VAL}$(fmt_tok "${SESS_CACHE_CREATE:-0}")${RST}"
  _R3_BD="${_R3_BD} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok "${SESS_CACHE_READ:-0}")${RST}"
  _R3_BD="${_R3_BD} ${DIM}out${RST} ${VAL}$(fmt_tok "${SESS_OUTPUT:-0}")${RST}${DIM})${RST}"
  [ -n "$_R3_TOKEN" ] && _R3_TOKEN="${_R3_TOKEN} ${_R3_BD}" || _R3_TOKEN="$_R3_BD"
fi

if [ "$TIER" = "wide" ]; then
  R3="$(_vpad "$_R3_PREFIX" "$COL_PREFIX")${SEP}"
  R3="${R3}$(_vpad "$_R3_TOKEN" "$COL_TOKEN")${SEP}"
  R3="${R3}$(_vpad "$_R3_MSG" "$COL_MSG")${SEP}"
  R3="${R3}$(_vpad "$_R3_TIME" "$COL_TIME")${SEP}"
  R3="${R3}$(_vpad "$_R3_COST" "$COL_COST")"
else
  R3="$_R3_PREFIX"
  [ -n "$_R3_TOKEN" ] && R3="${R3} ${_R3_TOKEN}"
  [ -n "$_R3_MSG" ] && R3="${R3}${SEP}${_R3_MSG}"
  R3="${R3}${SEP}${_R3_TIME}${SEP}${_R3_COST}"
fi
[ -n "$LINES" ] && R3="${R3}${SEP}${CYAN}code${RST} ${LINES}"
[ -n "$THROUGHPUT" ] && R3="${R3}${SEP}${THROUGHPUT}"
[ -n "$BURN_RATE" ] && R3="${R3}${SEP}${BURN_RATE}"
printf '%b\n' "$R3"

# =============================================================
# ROW 4: Daily Token Summary                            [FULL+]
# =============================================================

# --- Daily token tracking (transcript-based — scans ALL sessions today) ---
DAILY_CACHE="${CACHE_DIR}/daily_$(id -u).cache"
DAY_COST="" DAY_TOK="" DAY_SESSIONS="" DAY_USER_MSGS=0 DAY_LLM_MSGS=0

if [ "$(file_age "$DAILY_CACHE")" -lt 30 ] && [ -f "$DAILY_CACHE" ]; then
  . "$DAILY_CACHE"
else
  TODAY=$(date +%Y-%m-%d)
  _PROJECTS_DIR="$HOME/.claude/projects"
  # Calculate local midnight as UTC range for correct timezone handling
  # Use epoch as intermediate to avoid macOS `date -u -j -f` parsing input as UTC
  if is_mac; then
    _TODAY_START_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TODAY 00:00:00" "+%s" 2>/dev/null)
  else
    _TODAY_START_EPOCH=$(date -d "$TODAY 00:00:00" +%s 2>/dev/null)
  fi
  if [ -n "$_TODAY_START_EPOCH" ]; then
    _TOMORROW_START_EPOCH=$((_TODAY_START_EPOCH + 86400))
    if is_mac; then
      _TODAY_START_UTC=$(date -u -r "$_TODAY_START_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
      _TOMORROW_START_UTC=$(date -u -r "$_TOMORROW_START_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    else
      _TODAY_START_UTC=$(date -u -d "@$_TODAY_START_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
      _TOMORROW_START_UTC=$(date -u -d "@$_TOMORROW_START_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    fi
  fi
  _TODAY_START_UTC="${_TODAY_START_UTC:-${TODAY}T00:00:00Z}"
  _TOMORROW_START_UTC="${_TOMORROW_START_UTC:-9999-12-31T23:59:59Z}"
  if [ -d "$_PROJECTS_DIR" ]; then
    _DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
      -type f -print0 2>/dev/null | \
      xargs -0 grep -h "input_tokens" 2>/dev/null | \
      jq -R -c --arg start "$_TODAY_START_UTC" --arg end "$_TOMORROW_START_UTC" '
        fromjson? |
        select(.timestamp != null and .timestamp >= $start and .timestamp < $end) |
        .message.usage // empty |
        {i: (.input_tokens // 0), o: (.output_tokens // 0),
         cc: (.cache_creation_input_tokens // 0),
         cr: (.cache_read_input_tokens // 0)}' 2>/dev/null | \
      jq -s '{
        input: (map(.i) | add // 0),
        output: (map(.o) | add // 0),
        cache_create: (map(.cc) | add // 0),
        cache_read: (map(.cr) | add // 0),
        tokens: (map(.i + .o + .cc + .cr) | add // 0),
        messages: length
      }' 2>/dev/null)
    # Approximate today's API/streaming duration: sum of (assistant_ts - prior_msg_ts)
    # across each transcript file. Per-file pass to keep timestamps ordered correctly.
    _DAY_API_SEC=0
    while IFS= read -r -d '' _F; do
      _F_SEC=$(jq -rs --arg start "$_TODAY_START_UTC" --arg end "$_TOMORROW_START_UTC" '
        def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        [.[] | select(.timestamp != null and .timestamp >= $start and .timestamp < $end)
              | {ts: .timestamp, t: .type}]
        | . as $msgs
        | [range(0; length) as $i |
            select($msgs[$i].t == "assistant" and $i > 0) |
            (($msgs[$i].ts | epoch) - ($msgs[$i-1].ts | epoch))
          ] | map(select(. >= 0 and . < 600)) | add // 0' \
        "$_F" 2>/dev/null)
      _DAY_API_SEC=$(awk -v a="$_DAY_API_SEC" -v b="${_F_SEC:-0}" 'BEGIN{printf "%.0f", a+b}')
    done < <(find "$_PROJECTS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null)
    DAY_API_MS=$((_DAY_API_SEC * 1000))
    # Count user↑ / assistant↓ messages across all today's transcripts
    _DAY_MSG_COUNTS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
      -type f -print0 2>/dev/null | \
      xargs -0 grep -h '"type"' 2>/dev/null | \
      jq -R -c --arg start "$_TODAY_START_UTC" --arg end "$_TOMORROW_START_UTC" '
        fromjson? |
        select(.timestamp != null and .timestamp >= $start and .timestamp < $end) |
        .type' 2>/dev/null | \
      awk '/"user"/{u++} /"assistant"/{a++} END{printf "%d %d", u+0, a+0}')
    DAY_USER_MSGS=$(printf '%s' "$_DAY_MSG_COUNTS" | awk '{print $1}')
    DAY_LLM_MSGS=$(printf '%s' "$_DAY_MSG_COUNTS" | awk '{print $2}')
    eval "$(printf '%s' "$_DAY_STATS" | jq -r '
      @sh "DAY_TOK=\(.tokens // 0)",
      @sh "DAY_SESSIONS=\(.messages // 0)",
      @sh "DAY_INPUT=\(.input // 0)",
      @sh "DAY_OUTPUT=\(.output // 0)",
      @sh "DAY_CACHE_CREATE=\(.cache_create // 0)",
      @sh "DAY_CACHE_TOK=\(.cache_read // 0)"
    ' 2>/dev/null)" 2>/dev/null || {
      DAY_TOK=0 DAY_SESSIONS=0 DAY_INPUT=0 DAY_OUTPUT=0 DAY_CACHE_CREATE=0 DAY_CACHE_TOK=0
    }
    _SHOW_COST=false
    if [ "${CLAUDE_SL_SHOW_API_EQUIV_COST:-0}" = "1" ]; then
      _SHOW_COST=true
    elif [ -n "$COST_RAW" ] && [ "$COST_RAW" != "0" ]; then
      _IS_API=$(awk -v c="$COST_RAW" 'BEGIN{print (c+0 > 0) ? "yes" : "no"}')
      [ "$_IS_API" = "yes" ] && _SHOW_COST=true
    fi
    if [ "$_SHOW_COST" = true ]; then
      DAY_COST=$(awk -v i="${DAY_INPUT:-0}" -v o="${DAY_OUTPUT:-0}" -v cc="${DAY_CACHE_CREATE:-0}" -v cr="${DAY_CACHE_TOK:-0}" \
        'BEGIN{printf "%.4f", (i*3 + o*15 + cc*3.75 + cr*0.3)/1000000}')
    else
      DAY_COST=""
    fi
    printf "DAY_TOK='%s'\nDAY_SESSIONS='%s'\nDAY_COST='%s'\nDAY_INPUT='%s'\nDAY_OUTPUT='%s'\nDAY_CACHE_CREATE='%s'\nDAY_CACHE_TOK='%s'\nDAY_USER_MSGS='%s'\nDAY_LLM_MSGS='%s'\nDAY_API_MS='%s'\n" \
      "$DAY_TOK" "$DAY_SESSIONS" "$DAY_COST" "$DAY_INPUT" "$DAY_OUTPUT" "$DAY_CACHE_CREATE" "$DAY_CACHE_TOK" "$DAY_USER_MSGS" "$DAY_LLM_MSGS" "$DAY_API_MS" > "$DAILY_CACHE"
  fi
fi

if [ -n "$DAY_TOK" ] && [ "$DAY_TOK" != "0" ] && [ "$TIER" != "compact" ]; then
  _TODAY_LABEL=$(date +%m-%d)
  _R4_PREFIX="${CYAN}day-total${RST}${DIM}(${RST}${VAL}${_TODAY_LABEL}${RST}${DIM})${RST}"
  _R4_TOKEN="${CYAN}token${RST} ${VAL}$(fmt_tok "$DAY_TOK")${RST}"
  _R4_MSG=""
  if [ "${DAY_USER_MSGS:-0}" -gt 0 ] 2>/dev/null || [ "${DAY_LLM_MSGS:-0}" -gt 0 ] 2>/dev/null; then
    _R4_MSG="${CYAN}msg${RST} ${VAL}$(fmt_tok "${DAY_USER_MSGS:-0}")↑$(fmt_tok "${DAY_LLM_MSGS:-0}")↓${RST}"
  elif [ -n "$DAY_SESSIONS" ] && [ "$DAY_SESSIONS" != "0" ]; then
    _R4_MSG="${CYAN}msg${RST} ${VAL}$(fmt_tok "$DAY_SESSIONS")${RST}"
  fi
  # Token breakdown (in/create/cache/out) — merged INTO the token column
  # (right after the total) so it stays grouped, matching R3 session row.
  _R4_BD="${DIM}(${RST}${DIM}in${RST} ${VAL}$(fmt_tok "${DAY_INPUT:-0}")${RST}"
  [ "${DAY_CACHE_CREATE:-0}" -gt 0 ] 2>/dev/null && \
    _R4_BD="${_R4_BD} ${DIM}create${RST} ${YELLOW}${VAL}$(fmt_tok "${DAY_CACHE_CREATE:-0}")${RST}"
  _R4_BD="${_R4_BD} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok "${DAY_CACHE_TOK:-0}")${RST}"
  _R4_BD="${_R4_BD} ${DIM}out${RST} ${VAL}$(fmt_tok "${DAY_OUTPUT:-0}")${RST}${DIM})${RST}"
  [ -n "$_R4_TOKEN" ] && _R4_TOKEN="${_R4_TOKEN} ${_R4_BD}" || _R4_TOKEN="$_R4_BD"
  _R4_COST=""
  if [ -n "$DAY_COST" ] && [ "$DAY_COST" != "0" ]; then
    _R4_COST="${CYAN}cost${RST} ${VAL}$(fmt_cost "$DAY_COST")${RST}"
  fi
  # Day time = total streaming time today (approx, from inter-message gaps)
  _R4_TIME=""
  if [ "${DAY_API_MS:-0}" -gt 0 ] 2>/dev/null; then
    _R4_TIME="${CYAN}time${RST} ${VAL}$(fmt_dur "${DAY_API_MS:-0}")${RST}"
  fi
  # Day burn rate ($/hr) — same formula as session: cost / streaming hours
  _R4_BURN=""
  if [ "${DAY_API_MS:-0}" -gt 60000 ] 2>/dev/null && [ -n "$DAY_COST" ] && [ "$DAY_COST" != "0" ]; then
    _DAY_BURN_HR=$(awk -v d="${DAY_API_MS:-0}" -v c="${DAY_COST:-0}" \
      'BEGIN{dh=d/3600000; if(dh>0) printf "%.2f", c/dh; else print 0}')
    _R4_BURN="${YELLOW}🔥${RST} ${DIM}≈${RST}${VAL}\$${_DAY_BURN_HR}/hr${RST}"
  fi

  if [ "$TIER" = "wide" ]; then
    R4="$(_vpad "$_R4_PREFIX" "$COL_PREFIX")${SEP}"
    R4="${R4}$(_vpad "$_R4_TOKEN" "$COL_TOKEN")${SEP}"
    R4="${R4}$(_vpad "$_R4_MSG" "$COL_MSG")${SEP}"
    R4="${R4}$(_vpad "$_R4_TIME" "$COL_TIME")${SEP}"
    R4="${R4}$(_vpad "$_R4_COST" "$COL_COST")"
    [ -n "$_R4_BURN" ] && R4="${R4}${SEP}${_R4_BURN}"
  else
    R4="$_R4_PREFIX ${_R4_TOKEN}"
    [ -n "$_R4_MSG" ] && R4="${R4}${SEP}${_R4_MSG}"
    [ -n "$_R4_TIME" ] && R4="${R4}${SEP}${_R4_TIME}"
    [ -n "$_R4_COST" ] && R4="${R4}${SEP}${_R4_COST}"
    [ -n "$_R4_BURN" ] && R4="${R4}${SEP}${_R4_BURN}"
  fi

  # Budget alert (appended after the cost column, like burn-rate on R3)
  if [ -n "$CLAUDE_SL_DAILY_BUDGET" ] && [ "$CLAUDE_SL_DAILY_BUDGET" != "0" ]; then
    _DAY_COST_RAW="${DAY_COST:-0}"
    if [ -n "$_DAY_COST_RAW" ] && [ "$_DAY_COST_RAW" != "0" ]; then
      _BUDGET_PCT=$(awk -v c="$_DAY_COST_RAW" -v b="$CLAUDE_SL_DAILY_BUDGET" \
        'BEGIN{if(b>0) printf "%d", (c/b)*100; else print 0}')
      _BUDGET_CLR=$(bar_color "$_BUDGET_PCT")
      _BUDGET_WARN=""
      [ "$_BUDGET_PCT" -ge 90 ] 2>/dev/null && _BUDGET_WARN=" ⚠️"
      R4="${R4}${SEP}${CYAN}budget${RST} ${_BUDGET_CLR}${VAL}≈$(fmt_cost "$_DAY_COST_RAW")${RST}${DIM}/${RST}${VAL}\$${CLAUDE_SL_DAILY_BUDGET}${RST}${_BUDGET_WARN}"
    fi
  fi
  printf '%b\n' "$R4"
fi

[ "$PRESET" = "full" ] && exit 0

# =============================================================
# ROW 5: System Vitals — btop-style mini bars          [VITALS]
# =============================================================

SYS_CACHE="${CACHE_DIR}/sys_$(id -u).cache"
if [ "$(file_age "$SYS_CACHE")" -lt 5 ]; then
  . "$SYS_CACHE"
else
  if is_mac; then
    TOP_OUT=$(/usr/bin/top -l1 -s0 -n0 2>/dev/null)
    CPU_USER=$(printf '%s' "$TOP_OUT" | grep "CPU usage" | awk '{print $3}' | tr -d '%')
    CPU_SYS=$(printf '%s' "$TOP_OUT" | grep "CPU usage" | awk '{print $5}' | tr -d '%')
    CPU_USED=$(awk "BEGIN{printf \"%d\", ${CPU_USER:-0} + ${CPU_SYS:-0}}")
    MEM_USED=$(printf '%s' "$TOP_OUT" | grep "PhysMem" | awk '{print $2}')
    MEM_TOTAL_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    MEM_TOTAL_GB=$(awk "BEGIN{printf \"%.0f\", ${MEM_TOTAL_BYTES:-0} / 1073741824}")
    MEM_USED_NUM=$(printf '%s' "$MEM_USED" | tr -d 'GM')
    if printf '%s' "$MEM_USED" | grep -q 'G'; then
      MEM_USED_BYTES=$(awk "BEGIN{printf \"%.0f\", ${MEM_USED_NUM} * 1073741824}")
    else
      MEM_USED_BYTES=$(awk "BEGIN{printf \"%.0f\", ${MEM_USED_NUM} * 1048576}")
    fi
    [ "$MEM_TOTAL_BYTES" -gt 0 ] 2>/dev/null && \
      MEM_PCT=$(awk "BEGIN{printf \"%.0f\", ${MEM_USED_BYTES} / ${MEM_TOTAL_BYTES} * 100}") || MEM_PCT=0
    GPU_PCT=$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -o '"Device Utilization %"=[0-9]*' | head -1 | awk -F'=' '{print $2}')
    GPU_PCT="${GPU_PCT:-0}"
    BV=$(pmset -g batt 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d '%')
  elif is_linux; then
    read -r _ cu cn cs ci _ < /proc/stat 2>/dev/null
    PREV_STAT="${CACHE_DIR}/cpu_prev"
    if [ -f "$PREV_STAT" ]; then
      read -r pu pn ps pi < "$PREV_STAT"
      TOTAL_D=$(( (cu+cn+cs+ci) - (pu+pn+ps+pi) )); IDLE_D=$(( ci - pi ))
      [ "$TOTAL_D" -gt 0 ] && CPU_USED=$(( (TOTAL_D - IDLE_D) * 100 / TOTAL_D )) || CPU_USED=0
    else CPU_USED=0; fi
    printf '%s' "$cu $cn $cs $ci" > "$PREV_STAT"
    MEM_TOTAL_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    MEM_AVAIL_KB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
    MEM_USED_KB=$((${MEM_TOTAL_KB:-0} - ${MEM_AVAIL_KB:-0}))
    MEM_TOTAL_GB=$(( ${MEM_TOTAL_KB:-0} / 1048576 ))
    MEM_USED="$(awk "BEGIN{printf \"%.1f\", ${MEM_USED_KB:-0} / 1048576}")G"
    [ "${MEM_TOTAL_KB:-0}" -gt 0 ] && MEM_PCT=$(( MEM_USED_KB * 100 / MEM_TOTAL_KB )) || MEM_PCT=0
    if command -v nvidia-smi >/dev/null 2>&1; then
      GPU_PCT=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    else GPU_PCT=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo 0); fi
    GPU_PCT="${GPU_PCT:-0}"
    if [ -f /sys/class/power_supply/BAT0/capacity ]; then BV=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    elif [ -f /sys/class/power_supply/BAT1/capacity ]; then BV=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
    else BV=""; fi
  fi
  DISK_LINE=$(df -h / 2>/dev/null | tail -1)
  DISK_USED=$(printf '%s' "$DISK_LINE" | awk '{print $3}')
  DISK_TOTAL=$(printf '%s' "$DISK_LINE" | awk '{print $2}')
  DISK_PCT=$(printf '%s' "$DISK_LINE" | awk '{gsub(/%/,""); print $5}')
  if is_mac; then LOAD_AVG=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  else LOAD_AVG=$(awk '{print $1}' /proc/loadavg 2>/dev/null); fi
  printf "CPU_USED=%q\nMEM_USED=%q\nMEM_TOTAL_GB=%q\nMEM_PCT=%q\nGPU_PCT=%q\nDISK_USED=%q\nDISK_TOTAL=%q\nDISK_PCT=%q\nBV=%q\nLOAD_AVG=%q\n" \
    "${CPU_USED:-0}" "${MEM_USED:-0M}" "${MEM_TOTAL_GB:-0}" "${MEM_PCT:-0}" \
    "${GPU_PCT:-0}" "${DISK_USED:-0G}" "${DISK_TOTAL:-0G}" "${DISK_PCT:-0}" \
    "${BV:-}" "${LOAD_AVG:-0}" > "$SYS_CACHE"
fi

_R5_CPU="${CYAN}cpu${RST} $(bar_color "${CPU_USED:-0}")$(mini_bar "${CPU_USED:-0}")${RST} ${VAL}${CPU_USED:-0}%${RST}"
_R5_MEM="${CYAN}mem${RST} $(bar_color "${MEM_PCT:-0}")$(mini_bar "${MEM_PCT:-0}")${RST} ${VAL}${MEM_USED:-0M}${RST}/${MEM_TOTAL_GB:-0}G"
_R5_GPU="${CYAN}gpu${RST} $(bar_color "${GPU_PCT:-0}")$(mini_bar "${GPU_PCT:-0}")${RST} ${VAL}${GPU_PCT:-0}%${RST}"
_R5_DISK=""
_R5_BAT=""
_R5_LOAD=""
if [ "$TIER" != "compact" ]; then
  _R5_DISK="${CYAN}disk${RST} $(bar_color "${DISK_PCT:-0}")$(mini_bar "${DISK_PCT:-0}")${RST} ${VAL}${DISK_USED:-0G}${RST}/${DISK_TOTAL:-0G}"
  if [ -n "$BV" ]; then
    if [ "$BV" -le 20 ] 2>/dev/null; then
      _R5_BAT="${CYAN}bat${RST} ${RED}${VAL}$(mini_bar "$BV")${RST} ${RED}${VAL}${BV}%${RST}"
    else
      _R5_BAT="${CYAN}bat${RST} ${GREEN}$(mini_bar "$BV")${RST} ${VAL}${BV}%${RST}"
    fi
  fi
  [ -n "$LOAD_AVG" ] && _R5_LOAD="${CYAN}load${RST} ${VAL}${LOAD_AVG}${RST}"
fi

if [ "$TIER" = "wide" ]; then
  # Table-aligned: prefix=vitals, token=cpu, msg=mem, time=gpu+disk(+bat), cost=load
  _R5_PREFIX="${CYAN}htop${RST}"
  _R5_TIME="$_R5_GPU"
  [ -n "$_R5_DISK" ] && _R5_TIME="${_R5_TIME} ${_R5_DISK}"
  [ -n "$_R5_BAT" ]  && _R5_TIME="${_R5_TIME} ${_R5_BAT}"
  R5="$(_vpad "$_R5_PREFIX" "$COL_PREFIX")${SEP}"
  R5="${R5}$(_vpad "$_R5_CPU"  "$COL_TOKEN")${SEP}"
  R5="${R5}$(_vpad "$_R5_MEM"  "$COL_MSG")${SEP}"
  R5="${R5}$(_vpad "$_R5_TIME" "$COL_TIME")${SEP}"
  R5="${R5}${_R5_LOAD}"
else
  R5="$_R5_CPU${SEP}${_R5_MEM}${SEP}${_R5_GPU}"
  [ -n "$_R5_DISK" ] && R5="${R5}${SEP}${_R5_DISK}"
  [ -n "$_R5_BAT" ]  && R5="${R5}${SEP}${_R5_BAT}"
  [ -n "$_R5_LOAD" ] && R5="${R5}${SEP}${_R5_LOAD}"
fi
printf '%b\n' "$R5"
