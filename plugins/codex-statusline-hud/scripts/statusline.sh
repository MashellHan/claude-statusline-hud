#!/usr/bin/env bash
# ================================================================
#  Codex CLI Statusline HUD — cross-platform (macOS + Linux)
# ================================================================
#  Standalone monitoring for OpenAI Codex CLI sessions.
#  Reads data from ~/.codex/sessions/ JSONL logs (no stdin needed).
#
#  Integration:
#    tmux:  set -g status-right '#(path/to/statusline.sh 2>/dev/null)'
#    watch: watch -n 2 --color path/to/statusline.sh
#
#  Presets (set via CODEX_STATUSLINE_PRESET or ~/.codex/statusline-preset):
#    minimal   — 1 row:  [Model | CTX] Dir Git | context bar
#    essential — 2 rows: + Turn info (tokens, speed)
#    full      — 4 rows: + Session stats + Daily summary
#    vitals    — 5 rows: + System vitals (CPU, Mem, GPU, Disk, Battery)  (default)
# ================================================================

set -f  # disable globbing for safety

# --- Dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "[codex-hud] ERROR: jq is required but not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

# --- Cache directory setup ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-statusline"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null

# --- Clean up stale cache files (>1 day old) ---
find "$CACHE_DIR" -maxdepth 1 -name '*.cache' -mtime +1 -delete 2>/dev/null

# --- Platform detection ---
OS="$(uname -s)"
is_mac() { [ "$OS" = "Darwin" ]; }
is_linux() { [ "$OS" = "Linux" ]; }

# --- Terminal width detection ---
COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}"
if [ "$COLS" -lt 70 ] 2>/dev/null; then TIER="compact"
elif [ "$COLS" -lt 100 ] 2>/dev/null; then TIER="normal"
else TIER="wide"; fi

# --- Determine preset ---
PRESET="${CODEX_STATUSLINE_PRESET:-}"
if [ -z "$PRESET" ] && [ -f "$HOME/.codex/statusline-preset" ]; then
  PRESET=$(tr -d '[:space:]' < "$HOME/.codex/statusline-preset")
fi
PRESET="${PRESET:-vitals}"

# --- Colors ---
CYAN=$'\033[36m'    GREEN=$'\033[32m'   YELLOW=$'\033[33m'  RED=$'\033[31m'
BLUE=$'\033[34m'    MAGENTA=$'\033[35m' WHITE=$'\033[97m'
RST=$'\033[0m'      BOLD=$'\033[1m'     DIM=$'\033[2m'     ITAL=$'\033[3m'
BG_YELLOW=$'\033[43m'

# --- Theme detection ---
_THEME="${CODEX_SL_THEME:-}"
if [ -z "$_THEME" ]; then
  if [ -n "${COLORFGBG:-}" ]; then
    _BG="${COLORFGBG##*;}"
    if [ "${_BG:-0}" -ge 8 ] 2>/dev/null; then _THEME="light"; else _THEME="dark"; fi
  else
    _THEME="dark"
  fi
fi
if [ "$_THEME" = "light" ]; then VAL="${BOLD}"; else VAL="${WHITE}"; fi

# --- UTF-8 detection ---
if [ "${CODEX_SL_ASCII:-}" = "1" ]; then USE_UNICODE=0
elif [ "${CODEX_SL_UNICODE:-}" = "1" ]; then USE_UNICODE=1
else
  USE_UNICODE=0
  _LOCALE="${LANG:-}${LC_ALL:-}${LC_CTYPE:-}${LANGUAGE:-}"
  case "$_LOCALE" in *UTF-8*|*utf-8*|*utf8*|*UTF8*) USE_UNICODE=1 ;; esac
  is_mac && USE_UNICODE=1
fi
if [ "$USE_UNICODE" = "1" ]; then
  BAR_FILL="█" BAR_EMPTY="░" SEP_CHAR="│" DOT_SEP="·"
else
  BAR_FILL="#" BAR_EMPTY="-" SEP_CHAR="|" DOT_SEP="."
fi
SEP=" ${DIM}${SEP_CHAR}${RST} "

# --- Helpers (reused from Claude HUD) ---
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

# --- Reverse file (tac on Linux, tail -r on macOS) ---
_tac() {
  if is_mac; then tail -r "$1" 2>/dev/null
  else tac "$1" 2>/dev/null; fi
}

NOW=$(date +%s)

file_age() {
  local f="$1"
  [ -f "$f" ] || { echo 9999; return; }
  if is_mac; then echo $(( NOW - $(stat -f%m "$f" 2>/dev/null || echo 0) ))
  else echo $(( NOW - $(stat -c%Y "$f" 2>/dev/null || echo 0) )); fi
}

# --- Adaptive bar widths ---
case "$TIER" in
  compact) BAR_W=6  ;;
  normal)  BAR_W=8  ;;
  wide)    BAR_W=10 ;;
esac

# ================================================================
# CODEX DATA EXTRACTION — Read from ~/.codex/sessions/ JSONL
# ================================================================

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_SESSIONS_DIR="${CODEX_HOME}/sessions"
TODAY_DIR="${CODEX_SESSIONS_DIR}/$(date +%Y/%m/%d)"

# --- Find active session (newest rollout-*.jsonl with mtime < 120s) ---
SESSION_FILE=""
SESSION_ID=""
if [ -d "$TODAY_DIR" ]; then
  SESSION_FILE=$(find "$TODAY_DIR" -name "rollout-*.jsonl" -type f 2>/dev/null | sort | tail -1)
fi
# Fallback: check yesterday if today is empty (session started before midnight)
if [ -z "$SESSION_FILE" ]; then
  if is_mac; then
    _YESTERDAY_DIR="${CODEX_SESSIONS_DIR}/$(date -v-1d +%Y/%m/%d 2>/dev/null)"
  else
    _YESTERDAY_DIR="${CODEX_SESSIONS_DIR}/$(date -d yesterday +%Y/%m/%d 2>/dev/null)"
  fi
  if [ -d "$_YESTERDAY_DIR" ]; then
    SESSION_FILE=$(find "$_YESTERDAY_DIR" -name "rollout-*.jsonl" -type f 2>/dev/null | sort | tail -1)
  fi
fi

# Check if session is active (mtime < 120s)
SESSION_ACTIVE=false
if [ -n "$SESSION_FILE" ]; then
  _SESSION_AGE=$(file_age "$SESSION_FILE")
  [ "$_SESSION_AGE" -lt 120 ] 2>/dev/null && SESSION_ACTIVE=true
  # Extract session ID from filename: rollout-YYYY-MM-DDTHH-MM-SS-UUID.jsonl
  _FNAME="${SESSION_FILE##*/}"
  SESSION_ID="${_FNAME%.jsonl}"
  SESSION_ID="${SESSION_ID#rollout-}"
fi

# --- Extract session data (cached 3s) ---
MODEL="" DIR="" CTX_SIZE=0
INPUT_TOK=0 CACHED_INPUT=0 OUTPUT_TOK=0 REASON_TOK=0 TOTAL_TOK=0
TURN_DURATION_MS=0 TURN_ACTIVE=false
SESS_CACHE="${CACHE_DIR}/session_${SESSION_ID:-none}.cache"

if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
  if [ "$(file_age "$SESS_CACHE")" -lt 3 ] && [ -f "$SESS_CACHE" ]; then
    . "$SESS_CACHE"
  else
    # Extract session_meta (usually first line, but grep to be safe)
    _META=$(grep -m1 '"session_meta"' "$SESSION_FILE" 2>/dev/null | jq -r '
      select(.type == "session_meta") |
      @sh "MODEL=\(.payload.model // "unknown")",
      @sh "DIR=\(.payload.cwd // "")",
      @sh "CLI_VER=\(.payload.cli_version // "")"
    ' 2>/dev/null)
    [ -n "$_META" ] && eval "$_META"

    # Extract last token_count with non-null info (using tac for efficiency)
    _TOK=$(_tac "$SESSION_FILE" 2>/dev/null | jq -c '
      select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)
    ' 2>/dev/null | head -1)
    if [ -n "$_TOK" ]; then
      eval "$(printf '%s' "$_TOK" | jq -r '
        @sh "INPUT_TOK=\(.payload.info.total_token_usage.input_tokens // 0)",
        @sh "CACHED_INPUT=\(.payload.info.total_token_usage.cached_input_tokens // 0)",
        @sh "OUTPUT_TOK=\(.payload.info.total_token_usage.output_tokens // 0)",
        @sh "REASON_TOK=\(.payload.info.total_token_usage.reasoning_output_tokens // 0)",
        @sh "TOTAL_TOK=\(.payload.info.total_token_usage.total_tokens // 0)",
        @sh "CTX_SIZE=\(.payload.info.model_context_window // 0)"
      ' 2>/dev/null)" 2>/dev/null
    fi

    # Extract turn timing: find last task_started without matching task_complete
    _LAST_START=$(_tac "$SESSION_FILE" 2>/dev/null | jq -c '
      select(.type == "event_msg" and .payload.type == "task_started")
    ' 2>/dev/null | head -1)
    _LAST_START_TURN=""
    _LAST_START_AT=0
    if [ -n "$_LAST_START" ]; then
      _LAST_START_TURN=$(printf '%s' "$_LAST_START" | jq -r '.payload.turn_id // ""' 2>/dev/null)
      _LAST_START_AT=$(printf '%s' "$_LAST_START" | jq -r '.payload.started_at // 0' 2>/dev/null)
    fi

    # Check if this turn has completed
    TURN_ACTIVE=false
    TURN_DURATION_MS=0
    if [ -n "$_LAST_START_TURN" ]; then
      _LAST_COMPLETE=$(_tac "$SESSION_FILE" 2>/dev/null | jq -c --arg tid "$_LAST_START_TURN" '
        select(.type == "event_msg" and .payload.type == "task_complete" and .payload.turn_id == $tid)
      ' 2>/dev/null | head -1)
      if [ -z "$_LAST_COMPLETE" ]; then
        TURN_ACTIVE=true
        [ "$_LAST_START_AT" -gt 0 ] 2>/dev/null && \
          TURN_DURATION_MS=$(( (NOW - _LAST_START_AT) * 1000 ))
      else
        TURN_DURATION_MS=$(printf '%s' "$_LAST_COMPLETE" | jq -r '.payload.duration_ms // 0' 2>/dev/null)
      fi
    fi

    # Count total turns and compute total session duration
    _TURN_COUNT=$(grep -c '"task_complete"' "$SESSION_FILE" 2>/dev/null || echo 0)
    _SESSION_START_TS=$(grep -m1 '"session_meta"' "$SESSION_FILE" 2>/dev/null | jq -r '.payload.timestamp // empty' 2>/dev/null)
    TOTAL_DURATION_MS=0
    if [ -n "$_SESSION_START_TS" ]; then
      # Handle ISO 8601 timestamps: 2026-04-02T12:04:09.414Z
      _CLEAN_TS="${_SESSION_START_TS%%.*}"  # strip fractional seconds
      if is_mac; then
        _START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$_CLEAN_TS" "+%s" 2>/dev/null || echo 0)
      else
        _START_EPOCH=$(date -d "${_SESSION_START_TS}" +%s 2>/dev/null || echo 0)
      fi
      [ "$_START_EPOCH" -gt 0 ] 2>/dev/null && \
        TOTAL_DURATION_MS=$(( (NOW - _START_EPOCH) * 1000 ))
    fi

    # Count tools executed
    TOOLS_COUNT=$(grep -c '"exec_command_end"' "$SESSION_FILE" 2>/dev/null || echo 0)
    PATCHES_COUNT=$(grep -c '"patch_apply_end"' "$SESSION_FILE" 2>/dev/null || echo 0)

    # Persist to cache
    printf "MODEL=%q\nDIR=%q\nCLI_VER=%q\nINPUT_TOK=%q\nCACHED_INPUT=%q\nOUTPUT_TOK=%q\nREASON_TOK=%q\nTOTAL_TOK=%q\nCTX_SIZE=%q\nTURN_ACTIVE=%q\nTURN_DURATION_MS=%q\nTOTAL_DURATION_MS=%q\nTURN_COUNT=%q\nTOOLS_COUNT=%q\nPATCHES_COUNT=%q\n" \
      "${MODEL:-unknown}" "${DIR:-}" "${CLI_VER:-}" \
      "${INPUT_TOK:-0}" "${CACHED_INPUT:-0}" "${OUTPUT_TOK:-0}" \
      "${REASON_TOK:-0}" "${TOTAL_TOK:-0}" "${CTX_SIZE:-0}" \
      "${TURN_ACTIVE:-false}" "${TURN_DURATION_MS:-0}" "${TOTAL_DURATION_MS:-0}" \
      "${_TURN_COUNT:-0}" "${TOOLS_COUNT:-0}" "${PATCHES_COUNT:-0}" > "$SESS_CACHE"
    _TURN_COUNT="${_TURN_COUNT:-0}"
  fi
fi

# --- No session fallback ---
if [ -z "$SESSION_FILE" ] || [ "$TOTAL_TOK" -eq 0 ] 2>/dev/null; then
  if [ -z "$SESSION_FILE" ]; then
    printf '%b\n' "${DIM}[codex-hud] no active session${RST}"
    exit 0
  fi
fi

# --- Fallback model from config.toml if session didn't provide it ---
if [ "$MODEL" = "" ] || [ "$MODEL" = "unknown" ]; then
  _CONF="${CODEX_HOME}/config.toml"
  if [ -f "$_CONF" ]; then
    MODEL=$(grep '^model ' "$_CONF" 2>/dev/null | head -1 | sed 's/^[^=]*= *"\{0,1\}//' | sed 's/"\{0,1\} *$//')
  fi
  MODEL="${MODEL:-unknown}"
fi

# --- Smart directory name ---
if [ "$DIR" = "$HOME" ]; then DIR_NAME="~"
elif [ -n "$DIR" ]; then DIR_NAME="${DIR##*/}"
else DIR_NAME=""; fi

# --- Model label ---
case "$TIER" in
  compact) MODEL_LABEL="${MODEL%%-*}" ;;
  normal)  MODEL_LABEL="$MODEL" ;;
  wide)    MODEL_LABEL="$MODEL${CLI_VER:+ (v${CLI_VER})}" ;;
esac

# --- Context percentage ---
PCT=0
if [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
  PCT=$((TOTAL_TOK * 100 / CTX_SIZE))
  [ "$PCT" -gt 100 ] && PCT=100
fi
CTX_CLR=$(bar_color "$PCT")
CTX_BAR=$(make_bar "$PCT" "$BAR_W")
CTX_WARN=""
[ "$PCT" -ge 90 ] 2>/dev/null && CTX_WARN=" ${BOLD}${BG_YELLOW} ! ${RST}"
CTX_LABEL="${VAL}${PCT}%${RST}"

# ================================================================
# GIT INFO (cached 10s) — reused from Claude HUD
# ================================================================
GIT_DISPLAY=""
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
  _DIR_HASH=$(printf '%s' "$DIR" | cksum | awk '{print $1}')
  GIT_CACHE="${CACHE_DIR}/git_${_DIR_HASH}.cache"
  if [ "$(file_age "$GIT_CACHE")" -lt 10 ]; then
    GIT_INFO=$(cat "$GIT_CACHE")
  else
    if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
      GB=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
      GD=""
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
      _GIT_DIR=$(git -C "$DIR" rev-parse --git-dir 2>/dev/null)
      GIT_STATE=""
      if [ -d "${_GIT_DIR}/rebase-merge" ]; then
        _RB_CUR=$(cat "${_GIT_DIR}/rebase-merge/msgnum" 2>/dev/null)
        _RB_END=$(cat "${_GIT_DIR}/rebase-merge/end" 2>/dev/null)
        GIT_STATE="REBASING${_RB_CUR:+ ${_RB_CUR}/${_RB_END}}"
      elif [ -d "${_GIT_DIR}/rebase-apply" ]; then GIT_STATE="REBASING"
      elif [ -f "${_GIT_DIR}/MERGE_HEAD" ]; then GIT_STATE="MERGING"
      elif [ -f "${_GIT_DIR}/CHERRY_PICK_HEAD" ]; then GIT_STATE="CHERRY-PICK"
      elif [ -f "${_GIT_DIR}/BISECT_LOG" ]; then GIT_STATE="BISECTING"
      elif [ -f "${_GIT_DIR}/REVERT_HEAD" ]; then GIT_STATE="REVERTING"
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

# --- Session status badge ---
STATUS_BADGE=""
if [ "$SESSION_ACTIVE" = true ]; then
  if [ "$TURN_ACTIVE" = true ]; then
    STATUS_BADGE="${GREEN}${BOLD}RUNNING${RST}"
  else
    STATUS_BADGE="${YELLOW}IDLE${RST}"
  fi
else
  STATUS_BADGE="${DIM}ENDED${RST}"
fi

# --- Context size label ---
if [ "$CTX_SIZE" -ge 1000000 ] 2>/dev/null; then
  CTX_SIZE_LABEL="$(( CTX_SIZE / 1000 ))k"
elif [ "$CTX_SIZE" -ge 1000 ] 2>/dev/null; then
  CTX_SIZE_LABEL="$(( CTX_SIZE / 1000 ))k"
else
  CTX_SIZE_LABEL="$CTX_SIZE"
fi

# =============================================================
# ROW 1: [Model | CTX] Dir Git | Status | context bar  [ALL]
# =============================================================
if [ "$_THEME" = "light" ]; then
  R1="${CYAN}[${MODEL_LABEL} | ${CTX_SIZE_LABEL}]${RST}"
else
  R1="${BOLD}${CYAN}[${MODEL_LABEL} | ${CTX_SIZE_LABEL}]${RST}"
fi
[ -n "$DIR_NAME" ] && R1="${R1}${SEP}${BOLD}${GREEN}${DIR_NAME}${RST}"
[ -n "$GIT_DISPLAY" ] && R1="${R1}${SEP}${GIT_DISPLAY}"
R1="${R1}${SEP}${STATUS_BADGE}"
# Append context bar
if [ "$TIER" = "compact" ]; then
  R1="${R1}${SEP}${CYAN}ctx${RST} ${CTX_CLR}${CTX_LABEL}${RST}${CTX_WARN}"
else
  R1="${R1}${SEP}${CYAN}context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
fi
printf '%b\n' "$R1"

[ "$PRESET" = "minimal" ] && exit 0

# =============================================================
# ROW 2: Turn-level — tokens breakdown | speed  [ESSENTIAL+]
# =============================================================

# Token breakdown
TURN_DISPLAY=""
if [ "$INPUT_TOK" -gt 0 ] 2>/dev/null || [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null; then
  TURN_DISPLAY="${CYAN}turn${RST} ${DIM}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST}"
  [ "$CACHED_INPUT" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHED_INPUT)${RST}"
  [ "$REASON_TOK" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}reason${RST} ${YELLOW}${VAL}$(fmt_tok $REASON_TOK)${RST}"
  [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}out${RST} ${VAL}$(fmt_tok $OUTPUT_TOK)${RST}"
fi

# Cache hit rate
CACHE_HIT=""
if [ "$INPUT_TOK" -gt 0 ] 2>/dev/null && [ "$CACHED_INPUT" -gt 0 ] 2>/dev/null; then
  CP=$((CACHED_INPUT * 100 / INPUT_TOK))
  if [ "$CP" -ge 80 ]; then CC="$GREEN"; elif [ "$CP" -ge 40 ]; then CC="$YELLOW"; else CC="$RED"; fi
  CACHE_HIT="${CYAN}cache${RST} ${CC}${VAL}${CP}%${RST}"
fi

# Throughput
THROUGHPUT=""
if [ "$TOTAL_DURATION_MS" -gt 0 ] 2>/dev/null && [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null; then
  TPM=$((OUTPUT_TOK * 60000 / TOTAL_DURATION_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
fi

# Turn duration
TURN_DUR_DISPLAY=""
if [ "$TURN_DURATION_MS" -gt 0 ] 2>/dev/null; then
  TURN_DUR_DISPLAY="${DIM}(${RST}${VAL}$(fmt_dur $TURN_DURATION_MS)${RST}${DIM})${RST}"
fi

# Tool activity (last 3 tools from session)
TOOL_ACTIVITY=""
if [ -n "$SESSION_FILE" ] && [ "${TOOLS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
  ACTIVITY_CACHE="${CACHE_DIR}/activity_${SESSION_ID:-none}.cache"
  if [ "$(file_age "$ACTIVITY_CACHE")" -lt 3 ] && [ -f "$ACTIVITY_CACHE" ]; then
    TOOL_ACTIVITY=$(cat "$ACTIVITY_CACHE")
  else
    TOOL_ACTIVITY=$(_tac "$SESSION_FILE" 2>/dev/null | jq -r '
      select(.type == "event_msg" and .payload.type == "exec_command_end") |
      .payload.parsed_cmd[0].type // "cmd"
    ' 2>/dev/null | head -5 | sort | uniq -c | sort -rn | awk '{printf "%s(%d) ", $2, $1}' | sed 's/ $//')
    printf '%s' "$TOOL_ACTIVITY" > "$ACTIVITY_CACHE"
  fi
fi

# --- Assemble Row 2 ---
R2=""
[ -n "$TURN_DISPLAY" ] && R2="$TURN_DISPLAY"
[ -n "$TURN_DUR_DISPLAY" ] && R2="${R2:+${R2} }${TURN_DUR_DISPLAY}"
if [ "$TIER" != "compact" ]; then
  [ -n "$CACHE_HIT" ] && R2="${R2:+${R2}${SEP}}${CACHE_HIT}"
  [ -n "$THROUGHPUT" ] && R2="${R2:+${R2}${SEP}}${THROUGHPUT}"
fi
if [ -n "$TOOL_ACTIVITY" ]; then
  R2="${R2:+${R2}${SEP}}${CYAN}tools${RST} ${TOOL_ACTIVITY}"
fi
if [ -n "$R2" ]; then
  printf '%b\n' "$R2"
elif [ "$PRESET" != "minimal" ]; then
  printf '%b\n' "${CYAN}turn${RST} ${DIM}waiting...${RST}"
fi

[ "$PRESET" = "essential" ] && exit 0

# =============================================================
# ROW 3: Session-level — tokens | cost | time | turns  [FULL+]
# =============================================================

# --- OpenAI pricing (per 1M tokens) ---
_PRICE_IN=2.50 _PRICE_CACHED=1.25 _PRICE_OUT=10.00
case "${MODEL:-}" in
  *gpt-5.4*|*gpt-5.3*|*gpt-5*)   _PRICE_IN=2.50; _PRICE_CACHED=1.25; _PRICE_OUT=10.00 ;;
  *gpt-4.1-mini*)                 _PRICE_IN=0.40; _PRICE_CACHED=0.10; _PRICE_OUT=1.60 ;;
  *gpt-4.1*|*gpt-4.1-nano*)      _PRICE_IN=2.00; _PRICE_CACHED=0.50; _PRICE_OUT=8.00 ;;
  *o3*|*o4-mini*)                 _PRICE_IN=2.00; _PRICE_CACHED=0.50; _PRICE_OUT=8.00 ;;
esac

# Calculate session cost
_NET_INPUT=$(( INPUT_TOK - CACHED_INPUT ))
[ "$_NET_INPUT" -lt 0 ] && _NET_INPUT=0
COST_RAW=$(awk -v ni="$_NET_INPUT" -v ci="$CACHED_INPUT" -v o="$OUTPUT_TOK" \
  -v pi="$_PRICE_IN" -v pc="$_PRICE_CACHED" -v po="$_PRICE_OUT" \
  'BEGIN{printf "%.4f", (ni*pi + ci*pc + o*po)/1000000}')
COST_FMT=$(fmt_cost "$COST_RAW")

# Duration
DUR=""
[ "$TOTAL_DURATION_MS" -gt 0 ] 2>/dev/null && DUR=$(fmt_dur "$TOTAL_DURATION_MS")

# Burn rate
BURN_RATE=""
if [ "$TOTAL_DURATION_MS" -gt 60000 ] 2>/dev/null && [ "$TOTAL_TOK" -gt 0 ] 2>/dev/null; then
  BURN_COST_HR=$(awk -v d="$TOTAL_DURATION_MS" -v c="$COST_RAW" \
    'BEGIN{dh=d/3600000; if(dh>0) printf "%.2f", c/dh; else print 0}')
  BURN_RATE="${YELLOW}!${RST} ${DIM}~${RST}${VAL}\$${BURN_COST_HR}/hr${RST}"
fi

# --- Assemble Row 3 ---
R3="${CYAN}session${RST}"
# Tokens
if [ "$TOTAL_TOK" -gt 0 ] 2>/dev/null; then
  R3="${R3} ${CYAN}token${RST} ${VAL}$(fmt_tok $TOTAL_TOK)${RST}"
fi
# Turns
[ "${_TURN_COUNT:-0}" -gt 0 ] 2>/dev/null && \
  R3="${R3}${SEP}${CYAN}turns${RST} ${VAL}${_TURN_COUNT}${RST}"
# Tools
_TOTAL_TOOLS=$(( ${TOOLS_COUNT:-0} + ${PATCHES_COUNT:-0} ))
[ "$_TOTAL_TOOLS" -gt 0 ] 2>/dev/null && \
  R3="${R3}${SEP}${CYAN}tools${RST} ${VAL}${_TOTAL_TOOLS}${RST}"
# Time
[ -n "$DUR" ] && R3="${R3}${SEP}${CYAN}time${RST} ${VAL}${DUR}${RST}"
# Cost
R3="${R3}${SEP}${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"
# Burn rate
[ -n "$BURN_RATE" ] && R3="${R3}${SEP}${BURN_RATE}"
printf '%b\n' "$R3"

# =============================================================
# ROW 4: Daily Summary — aggregate across all sessions  [FULL+]
# =============================================================

DAILY_CACHE="${CACHE_DIR}/daily_$(id -u).cache"
DAY_TOK=0 DAY_INPUT=0 DAY_CACHED=0 DAY_OUTPUT=0 DAY_REASON=0 DAY_SESSIONS=0 DAY_COST=""

if [ "$(file_age "$DAILY_CACHE")" -lt 30 ] && [ -f "$DAILY_CACHE" ]; then
  . "$DAILY_CACHE"
else
  if [ -d "$TODAY_DIR" ]; then
    # Aggregate last token_count from each session file today
    # Process each file individually to get last token_count per session
    _AGG_FILE="${CACHE_DIR}/daily_agg_$$"
    : > "$_AGG_FILE"
    set +f  # re-enable globbing for file matching
    for _sf in "$TODAY_DIR"/rollout-*.jsonl; do
      [ -f "$_sf" ] || continue
      _tac "$_sf" | jq -c '
        select(.type=="event_msg" and .payload.type=="token_count" and .payload.info!=null) |
        .payload.info.total_token_usage
      ' 2>/dev/null | head -1 >> "$_AGG_FILE"
    done
    set -f  # re-disable globbing
    _DAY_STATS=$(jq -s '{
        input: (map(.input_tokens // 0) | add // 0),
        cached: (map(.cached_input_tokens // 0) | add // 0),
        output: (map(.output_tokens // 0) | add // 0),
        reason: (map(.reasoning_output_tokens // 0) | add // 0),
        tokens: (map(.total_tokens // 0) | add // 0),
        sessions: length
      }' "$_AGG_FILE" 2>/dev/null)
    rm -f "$_AGG_FILE"
    if [ -n "$_DAY_STATS" ]; then
      eval "$(printf '%s' "$_DAY_STATS" | jq -r '
        @sh "DAY_TOK=\(.tokens // 0)",
        @sh "DAY_INPUT=\(.input // 0)",
        @sh "DAY_CACHED=\(.cached // 0)",
        @sh "DAY_OUTPUT=\(.output // 0)",
        @sh "DAY_REASON=\(.reason // 0)",
        @sh "DAY_SESSIONS=\(.sessions // 0)"
      ' 2>/dev/null)" 2>/dev/null
    fi
    # Calculate daily cost
    _DAY_NET_INPUT=$(( DAY_INPUT - DAY_CACHED ))
    [ "$_DAY_NET_INPUT" -lt 0 ] && _DAY_NET_INPUT=0
    DAY_COST=$(awk -v ni="$_DAY_NET_INPUT" -v ci="$DAY_CACHED" -v o="$DAY_OUTPUT" \
      -v pi="$_PRICE_IN" -v pc="$_PRICE_CACHED" -v po="$_PRICE_OUT" \
      'BEGIN{printf "%.4f", (ni*pi + ci*pc + o*po)/1000000}')
    printf "DAY_TOK=%q\nDAY_INPUT=%q\nDAY_CACHED=%q\nDAY_OUTPUT=%q\nDAY_REASON=%q\nDAY_SESSIONS=%q\nDAY_COST=%q\n" \
      "${DAY_TOK:-0}" "${DAY_INPUT:-0}" "${DAY_CACHED:-0}" "${DAY_OUTPUT:-0}" \
      "${DAY_REASON:-0}" "${DAY_SESSIONS:-0}" "${DAY_COST:-}" > "$DAILY_CACHE"
  fi
fi

if [ "${DAY_TOK:-0}" -gt 0 ] 2>/dev/null && [ "$TIER" != "compact" ]; then
  _TODAY_LABEL=$(date +%m-%d)
  R4="${CYAN}day-total${RST}${DIM}(${RST}${VAL}${_TODAY_LABEL}${RST}${DIM})${RST}"
  R4="${R4} ${CYAN}token${RST} ${VAL}$(fmt_tok "$DAY_TOK")${RST}"
  R4="${R4} ${DIM}(${RST}${CYAN}in${RST} ${VAL}$(fmt_tok "${DAY_INPUT:-0}")${RST}"
  [ "${DAY_CACHED:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4} ${CYAN}cache${RST} ${GREEN}${VAL}$(fmt_tok "${DAY_CACHED:-0}")${RST}"
  [ "${DAY_REASON:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4} ${CYAN}reason${RST} ${YELLOW}${VAL}$(fmt_tok "${DAY_REASON:-0}")${RST}"
  R4="${R4} ${CYAN}out${RST} ${VAL}$(fmt_tok "${DAY_OUTPUT:-0}")${RST}${DIM})${RST}"
  [ "${DAY_SESSIONS:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4}${SEP}${CYAN}sessions${RST} ${VAL}${DAY_SESSIONS}${RST}"
  if [ -n "$DAY_COST" ] && [ "$DAY_COST" != "0" ] && [ "$DAY_COST" != "0.0000" ]; then
    R4="${R4}${SEP}${CYAN}cost${RST} ${VAL}$(fmt_cost "$DAY_COST")${RST}"
  fi
  # Budget alert
  if [ -n "${CODEX_SL_DAILY_BUDGET:-}" ] && [ "${CODEX_SL_DAILY_BUDGET:-0}" != "0" ]; then
    _DAY_COST_RAW="${DAY_COST:-0}"
    if [ -n "$_DAY_COST_RAW" ] && [ "$_DAY_COST_RAW" != "0" ]; then
      _BUDGET_PCT=$(awk -v c="$_DAY_COST_RAW" -v b="$CODEX_SL_DAILY_BUDGET" \
        'BEGIN{if(b>0) printf "%d", (c/b)*100; else print 0}')
      _BUDGET_CLR=$(bar_color "$_BUDGET_PCT")
      _BUDGET_WARN=""
      [ "$_BUDGET_PCT" -ge 90 ] 2>/dev/null && _BUDGET_WARN=" !"
      R4="${R4}${SEP}${CYAN}budget${RST} ${_BUDGET_CLR}${VAL}~$(fmt_cost "$_DAY_COST_RAW")${RST}${DIM}/${RST}${VAL}\$${CODEX_SL_DAILY_BUDGET}${RST}${_BUDGET_WARN}"
    fi
  fi
  printf '%b\n' "$R4"
fi

[ "$PRESET" = "full" ] && exit 0

# =============================================================
# ROW 5: System Vitals — CPU, Mem, GPU, Disk, Battery  [VITALS]
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

R5="${CYAN}cpu${RST} $(bar_color "${CPU_USED:-0}")$(mini_bar "${CPU_USED:-0}")${RST} ${VAL}${CPU_USED:-0}%${RST}"
R5="${R5}${SEP}${CYAN}mem${RST} $(bar_color "${MEM_PCT:-0}")$(mini_bar "${MEM_PCT:-0}")${RST} ${VAL}${MEM_USED:-0M}${RST}/${MEM_TOTAL_GB:-0}G"
R5="${R5}${SEP}${CYAN}gpu${RST} $(bar_color "${GPU_PCT:-0}")$(mini_bar "${GPU_PCT:-0}")${RST} ${VAL}${GPU_PCT:-0}%${RST}"
if [ "$TIER" != "compact" ]; then
  R5="${R5}${SEP}${CYAN}disk${RST} $(bar_color "${DISK_PCT:-0}")$(mini_bar "${DISK_PCT:-0}")${RST} ${VAL}${DISK_USED:-0G}${RST}/${DISK_TOTAL:-0G}"
  if [ -n "$BV" ]; then
    if [ "$BV" -le 20 ] 2>/dev/null; then
      R5="${R5}${SEP}${CYAN}bat${RST} ${RED}${VAL}$(mini_bar "$BV")${RST} ${RED}${VAL}${BV}%${RST}"
    else
      R5="${R5}${SEP}${CYAN}bat${RST} ${GREEN}$(mini_bar "$BV")${RST} ${VAL}${BV}%${RST}"
    fi
  fi
  [ -n "$LOAD_AVG" ] && R5="${R5}${SEP}${CYAN}load${RST} ${VAL}${LOAD_AVG}${RST}"
fi
printf '%b\n' "$R5"
