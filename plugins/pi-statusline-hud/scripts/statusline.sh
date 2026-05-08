#!/usr/bin/env bash
# ================================================================
#  Pi (pi.dev) Statusline HUD — cross-platform (macOS + Linux)
# ================================================================
#  Standalone monitoring for Pi coding agent (https://pi.dev) sessions.
#  Reads from ~/.pi/agent/sessions/ JSONL session files (no stdin needed).
#
#  Integration:
#    tmux:  set -g status-right '#(path/to/statusline.sh 2>/dev/null)'
#    watch: watch -n 2 --color path/to/statusline.sh
#    live:  bash path/to/live.sh   (in a spare pane)
#
#  Presets (via PI_STATUSLINE_PRESET or ~/.pi/agent/statusline-preset):
#    minimal   — 1 row:  [Model | CTX] Dir Git | context bar
#    essential — 2 rows: + Turn info (tokens, speed)
#    full      — 4 rows: + Session stats + Daily summary
#    vitals    — 5 rows: + System vitals (CPU, Mem, GPU, Disk, Battery)  (default)
# ================================================================

set -f

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "[pi-hud] ERROR: jq is required. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

# --- Cache directory ---
_UID="$(id -u 2>/dev/null || echo 0)"
CACHE_DIR="${PI_STATUSLINE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-statusline}"
if ! mkdir -p "$CACHE_DIR" 2>/dev/null || [ ! -w "$CACHE_DIR" ]; then
  CACHE_DIR="${TMPDIR:-/tmp}/pi-statusline-${_UID}"
  mkdir -p "$CACHE_DIR" 2>/dev/null || CACHE_DIR="${TMPDIR:-/tmp}"
fi
chmod 700 "$CACHE_DIR" 2>/dev/null || true
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

# --- Preset ---
PRESET="${PI_STATUSLINE_PRESET:-}"
if [ -z "$PRESET" ] && [ -f "$HOME/.pi/agent/statusline-preset" ]; then
  PRESET=$(tr -d '[:space:]' < "$HOME/.pi/agent/statusline-preset")
fi
PRESET="${PRESET:-vitals}"

# --- Colors ---
CYAN=$'\033[36m'    GREEN=$'\033[32m'   YELLOW=$'\033[33m'  RED=$'\033[31m'
BLUE=$'\033[34m'    MAGENTA=$'\033[35m' WHITE=$'\033[97m'
RST=$'\033[0m'      BOLD=$'\033[1m'     DIM=$'\033[2m'     ITAL=$'\033[3m'
BG_YELLOW=$'\033[43m'

# --- Theme ---
_THEME="${PI_SL_THEME:-}"
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
if [ "${PI_SL_ASCII:-}" = "1" ]; then USE_UNICODE=0
elif [ "${PI_SL_UNICODE:-}" = "1" ]; then USE_UNICODE=1
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

# --- Helpers (same primitives as Claude/Codex HUDs) ---
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
    local width=4
    local total=$((pct * width))
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
    local width=4
    local filled=$((pct * width / 100)) empty=$((width - pct * width / 100))
    local bar=""
    [ "$filled" -gt 0 ] && bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    [ "$empty" -gt 0 ] && bar="${bar}$(printf '%*s' "$empty" '' | tr ' ' '-')"
    printf '%s' "$bar"
  fi
}

bar_color() {
  if [ "$1" -ge 90 ] 2>/dev/null; then printf '%s' "$RED"
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf '%s' "$YELLOW"
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

NOW=$(date +%s)
file_age() {
  local f="$1"
  [ -f "$f" ] || { echo 9999; return; }
  if is_mac; then echo $(( NOW - $(stat -f%m "$f" 2>/dev/null || echo 0) ))
  else echo $(( NOW - $(stat -c%Y "$f" 2>/dev/null || echo 0) )); fi
}

case "$TIER" in
  compact) BAR_W=6  ;;
  normal)  BAR_W=8  ;;
  wide)    BAR_W=10 ;;
esac

# ================================================================
# PI DATA EXTRACTION — Read from ~/.pi/agent/sessions/<--cwd-->/*.jsonl
# Session format: https://github.com/earendil-works/pi-mono
#   header line: {"type":"session","version":3,"id":...,"timestamp":...,"cwd":...}
#   message line: {"type":"message","id":...,"parentId":...,"message":{role,...,usage:{...,cost:{...}}}}
# Pi conveniently embeds both `usage.totalTokens` and per-call `cost` in
# every assistant message, so no pricing table is needed.
# ================================================================

PI_HOME="${PI_HOME:-$HOME/.pi}"
PI_SESSIONS_DIR="${PI_HOME}/agent/sessions"

# --- Locate active session ---
# Prefer explicit env, else newest jsonl under PI_SESSIONS_DIR.
SESSION_FILE=""
SESSION_ID=""
if [ -n "${PI_SESSION_FILE:-}" ] && [ -f "$PI_SESSION_FILE" ]; then
  SESSION_FILE="$PI_SESSION_FILE"
elif [ -d "$PI_SESSIONS_DIR" ]; then
  if is_mac; then
    SESSION_FILE=$(find "$PI_SESSIONS_DIR" -name "*.jsonl" -type f -exec stat -f '%m %N' {} \; 2>/dev/null \
      | sort -n | tail -1 | cut -d' ' -f2-)
  else
    SESSION_FILE=$(find "$PI_SESSIONS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null \
      | sort -n | tail -1 | cut -d' ' -f2-)
  fi
fi

SESSION_ACTIVE=false
if [ -n "$SESSION_FILE" ]; then
  _SESSION_AGE=$(file_age "$SESSION_FILE")
  [ "$_SESSION_AGE" -lt 120 ] 2>/dev/null && SESSION_ACTIVE=true
  _FNAME="${SESSION_FILE##*/}"
  SESSION_ID="${_FNAME%.jsonl}"
fi

# --- Extract session data (cached 3s) ---
MODEL="" PROVIDER="" DIR="" PI_VER="" CTX_SIZE=0
INPUT_TOK=0 CACHED_INPUT=0 OUTPUT_TOK=0 CACHE_WRITE=0 TOTAL_TOK=0
SESS_INPUT_TOK=0 SESS_CACHED_INPUT=0 SESS_OUTPUT_TOK=0 SESS_CACHE_WRITE=0 SESS_TOTAL_TOK=0
SESS_COST_RAW=0 LAST_TURN_COST=0
TURN_DURATION_MS=0 TOTAL_DURATION_MS=0
TURN_ACTIVE=false TOOLS_COUNT=0 BASH_COUNT=0 _TURN_COUNT=0
SESS_CACHE="${CACHE_DIR}/session_${SESSION_ID:-none}.cache"

if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
  if [ "$(file_age "$SESS_CACHE")" -lt 3 ] && [ -f "$SESS_CACHE" ]; then
    . "$SESS_CACHE"
  else
    # Header (first line) — version, cwd
    _HDR=$(head -1 "$SESSION_FILE" 2>/dev/null)
    DIR=$(printf '%s' "$_HDR" | jq -r '.cwd // ""' 2>/dev/null)

    # Aggregate via single jq pass: model, totals, last-turn deltas.
    _STATS=$(jq -s '
      def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      [.[] | select(.type == "message")] as $msgs
      | [$msgs[] | select(.message.role == "assistant")] as $asst
      | ($asst | last // {}) as $lastA
      | {
          model:      ($lastA.message.model // ""),
          provider:   ($lastA.message.provider // ""),
          last_in:    ($lastA.message.usage.input // 0),
          last_out:   ($lastA.message.usage.output // 0),
          last_cr:    ($lastA.message.usage.cacheRead // 0),
          last_cw:    ($lastA.message.usage.cacheWrite // 0),
          last_tot:   ($lastA.message.usage.totalTokens // 0),
          last_cost:  ($lastA.message.usage.cost.total // 0),
          sess_in:    ([$asst[].message.usage.input // 0] | add // 0),
          sess_out:   ([$asst[].message.usage.output // 0] | add // 0),
          sess_cr:    ([$asst[].message.usage.cacheRead // 0] | add // 0),
          sess_cw:    ([$asst[].message.usage.cacheWrite // 0] | add // 0),
          sess_tot:   ([$asst[].message.usage.totalTokens // 0] | add // 0),
          sess_cost:  ([$asst[].message.usage.cost.total // 0] | add // 0),
          turns:      ([$msgs[] | select(.message.role == "user")] | length),
          tools:      ([$msgs[] | select(.message.role == "toolResult")] | length),
          bash:       ([$msgs[] | select(.message.role == "bashExecution")] | length),
          first_ts:   ($msgs | first | (.timestamp // "")),
          last_ts:    ($msgs | last  | (.timestamp // "")),
          last_user_ts: ([$msgs[] | select(.message.role == "user") | .timestamp] | last // ""),
          last_asst_ts: ($lastA.timestamp // "")
        }
    ' "$SESSION_FILE" 2>/dev/null)

    if [ -n "$_STATS" ]; then
      eval "$(printf '%s' "$_STATS" | jq -r '
        @sh "MODEL=\(.model // "unknown")",
        @sh "PROVIDER=\(.provider // "")",
        @sh "INPUT_TOK=\(.last_in // 0)",
        @sh "CACHED_INPUT=\(.last_cr // 0)",
        @sh "OUTPUT_TOK=\(.last_out // 0)",
        @sh "CACHE_WRITE=\(.last_cw // 0)",
        @sh "TOTAL_TOK=\(.last_tot // 0)",
        @sh "LAST_TURN_COST=\(.last_cost // 0)",
        @sh "SESS_INPUT_TOK=\(.sess_in // 0)",
        @sh "SESS_CACHED_INPUT=\(.sess_cr // 0)",
        @sh "SESS_OUTPUT_TOK=\(.sess_out // 0)",
        @sh "SESS_CACHE_WRITE=\(.sess_cw // 0)",
        @sh "SESS_TOTAL_TOK=\(.sess_tot // 0)",
        @sh "SESS_COST_RAW=\(.sess_cost // 0)",
        @sh "_TURN_COUNT=\(.turns // 0)",
        @sh "TOOLS_COUNT=\(.tools // 0)",
        @sh "BASH_COUNT=\(.bash // 0)",
        @sh "_FIRST_TS=\(.first_ts // "")",
        @sh "_LAST_TS=\(.last_ts // "")",
        @sh "_LAST_USER_TS=\(.last_user_ts // "")",
        @sh "_LAST_ASST_TS=\(.last_asst_ts // "")"
      ' 2>/dev/null)" 2>/dev/null
    fi

    # Per-model context window estimates (tokens). Pi doesn't store this in
    # the session, so we approximate based on common provider defaults.
    case "${MODEL:-}" in
      *opus-4*|*sonnet-4*|*haiku-4*|*claude-sonnet*|*claude-opus*|*claude-haiku*) CTX_SIZE=200000 ;;
      *gpt-5*|*gpt-4.1*|*o3*|*o4*) CTX_SIZE=400000 ;;
      *gpt-4o*) CTX_SIZE=128000 ;;
      *gemini-2*) CTX_SIZE=1000000 ;;
      *) CTX_SIZE=200000 ;;
    esac

    # Convert ISO timestamps -> epoch seconds (strip fractional seconds).
    _ts_to_epoch() {
      local ts="$1"
      [ -z "$ts" ] && { echo 0; return; }
      local clean="${ts%%.*}"; clean="${clean%Z}"
      if is_mac; then
        date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null || echo 0
      else
        date -d "$ts" +%s 2>/dev/null || echo 0
      fi
    }
    _FIRST_EPOCH=$(_ts_to_epoch "${_FIRST_TS:-}")
    _LAST_EPOCH=$(_ts_to_epoch "${_LAST_TS:-}")
    _LAST_USER_EPOCH=$(_ts_to_epoch "${_LAST_USER_TS:-}")
    _LAST_ASST_EPOCH=$(_ts_to_epoch "${_LAST_ASST_TS:-}")

    [ "${_FIRST_EPOCH:-0}" -gt 0 ] 2>/dev/null && [ "${_LAST_EPOCH:-0}" -gt 0 ] 2>/dev/null && \
      TOTAL_DURATION_MS=$(( (_LAST_EPOCH - _FIRST_EPOCH) * 1000 ))

    # Turn active = last user msg is newer than last assistant msg.
    if [ "${_LAST_USER_EPOCH:-0}" -gt "${_LAST_ASST_EPOCH:-0}" ] 2>/dev/null; then
      TURN_ACTIVE=true
      [ "${_LAST_USER_EPOCH:-0}" -gt 0 ] && \
        TURN_DURATION_MS=$(( (NOW - _LAST_USER_EPOCH) * 1000 ))
    else
      TURN_ACTIVE=false
      [ "${_LAST_USER_EPOCH:-0}" -gt 0 ] 2>/dev/null && [ "${_LAST_ASST_EPOCH:-0}" -gt 0 ] 2>/dev/null && \
        TURN_DURATION_MS=$(( (_LAST_ASST_EPOCH - _LAST_USER_EPOCH) * 1000 ))
    fi

    # Persist
    printf "MODEL=%q\nPROVIDER=%q\nDIR=%q\nINPUT_TOK=%q\nCACHED_INPUT=%q\nOUTPUT_TOK=%q\nCACHE_WRITE=%q\nTOTAL_TOK=%q\nLAST_TURN_COST=%q\nSESS_INPUT_TOK=%q\nSESS_CACHED_INPUT=%q\nSESS_OUTPUT_TOK=%q\nSESS_CACHE_WRITE=%q\nSESS_TOTAL_TOK=%q\nSESS_COST_RAW=%q\nCTX_SIZE=%q\nTURN_ACTIVE=%q\nTURN_DURATION_MS=%q\nTOTAL_DURATION_MS=%q\nTURN_COUNT=%q\nTOOLS_COUNT=%q\nBASH_COUNT=%q\n" \
      "${MODEL:-unknown}" "${PROVIDER:-}" "${DIR:-}" \
      "${INPUT_TOK:-0}" "${CACHED_INPUT:-0}" "${OUTPUT_TOK:-0}" "${CACHE_WRITE:-0}" "${TOTAL_TOK:-0}" \
      "${LAST_TURN_COST:-0}" \
      "${SESS_INPUT_TOK:-0}" "${SESS_CACHED_INPUT:-0}" "${SESS_OUTPUT_TOK:-0}" "${SESS_CACHE_WRITE:-0}" "${SESS_TOTAL_TOK:-0}" \
      "${SESS_COST_RAW:-0}" "${CTX_SIZE:-0}" \
      "${TURN_ACTIVE:-false}" "${TURN_DURATION_MS:-0}" "${TOTAL_DURATION_MS:-0}" \
      "${_TURN_COUNT:-0}" "${TOOLS_COUNT:-0}" "${BASH_COUNT:-0}" > "$SESS_CACHE"
  fi
fi

INPUT_TOK="${INPUT_TOK:-0}"
CACHED_INPUT="${CACHED_INPUT:-0}"
OUTPUT_TOK="${OUTPUT_TOK:-0}"
CACHE_WRITE="${CACHE_WRITE:-0}"
TOTAL_TOK="${TOTAL_TOK:-0}"
SESS_INPUT_TOK="${SESS_INPUT_TOK:-$INPUT_TOK}"
SESS_CACHED_INPUT="${SESS_CACHED_INPUT:-$CACHED_INPUT}"
SESS_OUTPUT_TOK="${SESS_OUTPUT_TOK:-$OUTPUT_TOK}"
SESS_CACHE_WRITE="${SESS_CACHE_WRITE:-$CACHE_WRITE}"
SESS_TOTAL_TOK="${SESS_TOTAL_TOK:-$TOTAL_TOK}"
SESS_COST_RAW="${SESS_COST_RAW:-0}"
LAST_TURN_COST="${LAST_TURN_COST:-0}"
TOTAL_DURATION_MS="${TOTAL_DURATION_MS:-0}"
TURN_DURATION_MS="${TURN_DURATION_MS:-0}"
_TURN_COUNT="${_TURN_COUNT:-${TURN_COUNT:-0}}"

# --- No session fallback ---
if [ -z "$SESSION_FILE" ]; then
  printf '%b\n' "${DIM}[pi-hud] no active session in ${PI_SESSIONS_DIR}${RST}"
  exit 0
fi

# --- Smart directory ---
if [ "$DIR" = "$HOME" ]; then DIR_NAME="~"
elif [ -n "$DIR" ]; then DIR_NAME="${DIR##*/}"
else DIR_NAME=""; fi

# --- Model label ---
case "$TIER" in
  compact) MODEL_LABEL="${MODEL%%-*}" ;;
  normal)  MODEL_LABEL="$MODEL" ;;
  wide)    MODEL_LABEL="${PROVIDER:+${PROVIDER}/}${MODEL}" ;;
esac
[ -z "$MODEL_LABEL" ] && MODEL_LABEL="unknown"

# --- Context % ---
PCT=0
if [ "$CTX_SIZE" -gt 0 ] 2>/dev/null && [ "$TOTAL_TOK" -gt 0 ] 2>/dev/null; then
  PCT=$((TOTAL_TOK * 100 / CTX_SIZE))
  [ "$PCT" -gt 100 ] && PCT=100
fi
CTX_CLR=$(bar_color "$PCT")
CTX_BAR=$(make_bar "$PCT" "$BAR_W")
CTX_WARN=""
[ "$PCT" -ge 90 ] 2>/dev/null && CTX_WARN=" ${BOLD}${BG_YELLOW} ! ${RST}"
CTX_LABEL="${VAL}${PCT}%${RST}"

# ================================================================
# GIT INFO (cached 10s)
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
      UPSTREAM=$(git -C "$DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
      GAB=""
      if [ -n "$UPSTREAM" ]; then
        AB=$(git -C "$DIR" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
        AHEAD=$(printf '%s' "$AB" | awk '{print $1}')
        BEHIND=$(printf '%s' "$AB" | awk '{print $2}')
        [ "${AHEAD:-0}" -gt 0 ] && GAB="↑${AHEAD}"
        [ "${BEHIND:-0}" -gt 0 ] && GAB="${GAB}↓${BEHIND}"
      fi
      GIT_INFO="${GB}|${GD}|${GAB}"
    else
      GIT_INFO="||"
    fi
    printf '%s' "$GIT_INFO" > "$GIT_CACHE"
  fi
  GB=$(printf '%s' "$GIT_INFO" | cut -d'|' -f1)
  GD=$(printf '%s' "$GIT_INFO" | cut -d'|' -f2)
  GAB=$(printf '%s' "$GIT_INFO" | cut -d'|' -f3)
  if [ -n "$GB" ]; then
    GIT_DISPLAY="${MAGENTA} ${GB}${RST}"
    if [ -n "$GD" ]; then GIT_DISPLAY="${GIT_DISPLAY} ${YELLOW}[${GD}]${RST}"
    else GIT_DISPLAY="${GIT_DISPLAY} ${GREEN}✓${RST}"; fi
    [ -n "$GAB" ] && GIT_DISPLAY="${GIT_DISPLAY} ${CYAN}${GAB}${RST}"
  fi
fi

# --- Status badge ---
STATUS_BADGE=""
if [ "$SESSION_ACTIVE" = true ]; then
  if [ "$TURN_ACTIVE" = true ]; then STATUS_BADGE="${GREEN}${BOLD}RUNNING${RST}"
  else STATUS_BADGE="${YELLOW}IDLE${RST}"; fi
else
  STATUS_BADGE="${DIM}ENDED${RST}"
fi

# --- Context-size label ---
if [ "$CTX_SIZE" -ge 1000 ] 2>/dev/null; then
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
if [ "$TIER" = "compact" ]; then
  R1="${R1}${SEP}${CYAN}ctx${RST} ${CTX_CLR}${CTX_LABEL}${RST}${CTX_WARN}"
else
  R1="${R1}${SEP}${CYAN}context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
fi
printf '%b\n' "$R1"

[ "$PRESET" = "minimal" ] && exit 0

# =============================================================
# ROW 2: Turn-level — tokens breakdown | speed | cost  [ESSENTIAL+]
# =============================================================
TURN_DISPLAY=""
if [ "$INPUT_TOK" -gt 0 ] 2>/dev/null || [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null; then
  TURN_DISPLAY="${CYAN}turn${RST} ${DIM}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST}"
  [ "$CACHED_INPUT" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHED_INPUT)${RST}"
  [ "$CACHE_WRITE" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}write${RST} ${YELLOW}${VAL}$(fmt_tok $CACHE_WRITE)${RST}"
  [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null && TURN_DISPLAY="${TURN_DISPLAY} ${DIM}out${RST} ${VAL}$(fmt_tok $OUTPUT_TOK)${RST}"
fi

CACHE_HIT=""
_TOTAL_INPUT=$(( INPUT_TOK + CACHED_INPUT + CACHE_WRITE ))
if [ "$_TOTAL_INPUT" -gt 0 ] 2>/dev/null; then
  CP=$((CACHED_INPUT * 100 / _TOTAL_INPUT))
  if [ "$CP" -ge 80 ]; then CC="$GREEN"; elif [ "$CP" -ge 40 ]; then CC="$YELLOW"; else CC="$RED"; fi
  CACHE_HIT="${CYAN}cache${RST} ${CC}${VAL}${CP}%${RST}"
fi

THROUGHPUT=""
if [ "$TURN_DURATION_MS" -gt 0 ] 2>/dev/null && [ "$OUTPUT_TOK" -gt 0 ] 2>/dev/null; then
  TPM=$((OUTPUT_TOK * 60000 / TURN_DURATION_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
elif [ "$TOTAL_DURATION_MS" -gt 0 ] 2>/dev/null && [ "$SESS_OUTPUT_TOK" -gt 0 ] 2>/dev/null; then
  TPM=$((SESS_OUTPUT_TOK * 60000 / TOTAL_DURATION_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
fi

TURN_COST_DISPLAY=""
if awk -v c="$LAST_TURN_COST" 'BEGIN{exit !(c+0 > 0)}'; then
  TURN_COST_DISPLAY="${CYAN}cost${RST} ${VAL}$(fmt_cost "$LAST_TURN_COST")${RST}"
fi

TURN_DUR_DISPLAY=""
if [ "$TURN_DURATION_MS" -gt 0 ] 2>/dev/null; then
  TURN_DUR_DISPLAY="${DIM}(${RST}${VAL}$(fmt_dur $TURN_DURATION_MS)${RST}${DIM})${RST}"
fi

R2=""
[ -n "$TURN_DISPLAY" ] && R2="$TURN_DISPLAY"
[ -n "$TURN_DUR_DISPLAY" ] && R2="${R2:+${R2} }${TURN_DUR_DISPLAY}"
if [ "$TIER" != "compact" ]; then
  [ -n "$CACHE_HIT" ] && R2="${R2:+${R2}${SEP}}${CACHE_HIT}"
  [ -n "$THROUGHPUT" ] && R2="${R2:+${R2}${SEP}}${THROUGHPUT}"
  [ -n "$TURN_COST_DISPLAY" ] && R2="${R2:+${R2}${SEP}}${TURN_COST_DISPLAY}"
fi
if [ -n "$R2" ]; then
  printf '%b\n' "$R2"
elif [ "$PRESET" != "minimal" ]; then
  printf '%b\n' "${CYAN}turn${RST} ${DIM}waiting...${RST}"
fi

[ "$PRESET" = "essential" ] && exit 0

# =============================================================
# ROW 3: Session-level — token | turns | tools | time | cost  [FULL+]
# =============================================================
COST_FMT=$(fmt_cost "$SESS_COST_RAW")

DUR=""
[ "$TOTAL_DURATION_MS" -gt 0 ] 2>/dev/null && DUR=$(fmt_dur "$TOTAL_DURATION_MS")

BURN_RATE=""
if [ "$TOTAL_DURATION_MS" -gt 60000 ] 2>/dev/null && \
   awk -v c="$SESS_COST_RAW" 'BEGIN{exit !(c+0 > 0)}'; then
  BURN_COST_HR=$(awk -v d="$TOTAL_DURATION_MS" -v c="$SESS_COST_RAW" \
    'BEGIN{dh=d/3600000; if(dh>0) printf "%.2f", c/dh; else print 0}')
  BURN_RATE="${YELLOW}!${RST} ${DIM}~${RST}${VAL}\$${BURN_COST_HR}/hr${RST}"
fi

R3="${CYAN}session${RST}"
[ "$SESS_TOTAL_TOK" -gt 0 ] 2>/dev/null && \
  R3="${R3} ${CYAN}token${RST} ${VAL}$(fmt_tok $SESS_TOTAL_TOK)${RST}"
[ "${_TURN_COUNT:-0}" -gt 0 ] 2>/dev/null && \
  R3="${R3}${SEP}${CYAN}turns${RST} ${VAL}${_TURN_COUNT}${RST}"
_TOTAL_TOOLS=$(( ${TOOLS_COUNT:-0} + ${BASH_COUNT:-0} ))
[ "$_TOTAL_TOOLS" -gt 0 ] 2>/dev/null && \
  R3="${R3}${SEP}${CYAN}tools${RST} ${VAL}${_TOTAL_TOOLS}${RST}"
[ -n "$DUR" ] && R3="${R3}${SEP}${CYAN}time${RST} ${VAL}${DUR}${RST}"
R3="${R3}${SEP}${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"
[ -n "$BURN_RATE" ] && R3="${R3}${SEP}${BURN_RATE}"
printf '%b\n' "$R3"

# =============================================================
# ROW 4: Daily Summary — aggregate across all sessions today  [FULL+]
# =============================================================
DAILY_CACHE="${CACHE_DIR}/daily_${_UID}.cache"
DAY_TOK=0 DAY_INPUT=0 DAY_CACHED=0 DAY_OUTPUT=0 DAY_WRITE=0 DAY_SESSIONS=0 DAY_COST=0

if [ "$(file_age "$DAILY_CACHE")" -lt 30 ] && [ -f "$DAILY_CACHE" ]; then
  . "$DAILY_CACHE"
elif [ -d "$PI_SESSIONS_DIR" ]; then
  # Find every jsonl file modified today and sum assistant usage across them.
  if is_mac; then
    _TODAY_START_EPOCH=$(date -j -f "%Y-%m-%d" "$(date +%Y-%m-%d)" "+%s" 2>/dev/null || echo 0)
  else
    _TODAY_START_EPOCH=$(date -d "$(date +%Y-%m-%d)" +%s 2>/dev/null || echo 0)
  fi
  _AGG_FILE="${CACHE_DIR}/daily_agg_$$"
  : > "$_AGG_FILE"
  _SESS_COUNTED=0
  while IFS= read -r -d '' _sf; do
    if is_mac; then _MT=$(stat -f%m "$_sf" 2>/dev/null || echo 0)
    else _MT=$(stat -c%Y "$_sf" 2>/dev/null || echo 0); fi
    [ "${_MT:-0}" -ge "${_TODAY_START_EPOCH:-0}" ] || continue
    jq -c '
      select(.type == "message" and .message.role == "assistant") |
      {i: (.message.usage.input // 0),
       cr: (.message.usage.cacheRead // 0),
       cw: (.message.usage.cacheWrite // 0),
       o: (.message.usage.output // 0),
       t: (.message.usage.totalTokens // 0),
       c: (.message.usage.cost.total // 0)}
    ' "$_sf" 2>/dev/null >> "$_AGG_FILE"
    _SESS_COUNTED=$((_SESS_COUNTED + 1))
  done < <(find "$PI_SESSIONS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null)

  _DAY_STATS=$(jq -s '{
      input:   (map(.i) | add // 0),
      cached:  (map(.cr) | add // 0),
      write:   (map(.cw) | add // 0),
      output:  (map(.o) | add // 0),
      tokens:  (map(.t) | add // 0),
      cost:    (map(.c) | add // 0)
    }' "$_AGG_FILE" 2>/dev/null)
  rm -f "$_AGG_FILE"

  if [ -n "$_DAY_STATS" ]; then
    eval "$(printf '%s' "$_DAY_STATS" | jq -r '
      @sh "DAY_TOK=\(.tokens // 0)",
      @sh "DAY_INPUT=\(.input // 0)",
      @sh "DAY_CACHED=\(.cached // 0)",
      @sh "DAY_WRITE=\(.write // 0)",
      @sh "DAY_OUTPUT=\(.output // 0)",
      @sh "DAY_COST=\(.cost // 0)"
    ' 2>/dev/null)" 2>/dev/null
  fi
  DAY_SESSIONS="$_SESS_COUNTED"
  printf "DAY_TOK=%q\nDAY_INPUT=%q\nDAY_CACHED=%q\nDAY_WRITE=%q\nDAY_OUTPUT=%q\nDAY_SESSIONS=%q\nDAY_COST=%q\n" \
    "${DAY_TOK:-0}" "${DAY_INPUT:-0}" "${DAY_CACHED:-0}" "${DAY_WRITE:-0}" \
    "${DAY_OUTPUT:-0}" "${DAY_SESSIONS:-0}" "${DAY_COST:-0}" > "$DAILY_CACHE"
fi

if [ "${DAY_TOK:-0}" -gt 0 ] 2>/dev/null && [ "$TIER" != "compact" ]; then
  _TODAY_LABEL=$(date +%m-%d)
  R4="${CYAN}day-total${RST}${DIM}(${RST}${VAL}${_TODAY_LABEL}${RST}${DIM})${RST}"
  R4="${R4} ${CYAN}token${RST} ${VAL}$(fmt_tok "$DAY_TOK")${RST}"
  R4="${R4} ${DIM}(${RST}${CYAN}in${RST} ${VAL}$(fmt_tok "${DAY_INPUT:-0}")${RST}"
  [ "${DAY_CACHED:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4} ${CYAN}cache${RST} ${GREEN}${VAL}$(fmt_tok "${DAY_CACHED:-0}")${RST}"
  [ "${DAY_WRITE:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4} ${CYAN}write${RST} ${YELLOW}${VAL}$(fmt_tok "${DAY_WRITE:-0}")${RST}"
  R4="${R4} ${CYAN}out${RST} ${VAL}$(fmt_tok "${DAY_OUTPUT:-0}")${RST}${DIM})${RST}"
  [ "${DAY_SESSIONS:-0}" -gt 0 ] 2>/dev/null && \
    R4="${R4}${SEP}${CYAN}sessions${RST} ${VAL}${DAY_SESSIONS}${RST}"
  if awk -v c="${DAY_COST:-0}" 'BEGIN{exit !(c+0 > 0)}'; then
    R4="${R4}${SEP}${CYAN}cost${RST} ${VAL}$(fmt_cost "$DAY_COST")${RST}"
  fi
  if [ -n "${PI_SL_DAILY_BUDGET:-}" ] && [ "${PI_SL_DAILY_BUDGET:-0}" != "0" ]; then
    if awk -v c="${DAY_COST:-0}" 'BEGIN{exit !(c+0 > 0)}'; then
      _BUDGET_PCT=$(awk -v c="$DAY_COST" -v b="$PI_SL_DAILY_BUDGET" \
        'BEGIN{if(b>0) printf "%d", (c/b)*100; else print 0}')
      _BUDGET_CLR=$(bar_color "$_BUDGET_PCT")
      _BUDGET_WARN=""
      [ "$_BUDGET_PCT" -ge 90 ] 2>/dev/null && _BUDGET_WARN=" !"
      R4="${R4}${SEP}${CYAN}budget${RST} ${_BUDGET_CLR}${VAL}~$(fmt_cost "$DAY_COST")${RST}${DIM}/${RST}${VAL}\$${PI_SL_DAILY_BUDGET}${RST}${_BUDGET_WARN}"
    fi
  fi
  printf '%b\n' "$R4"
fi

[ "$PRESET" = "full" ] && exit 0

# =============================================================
# ROW 5: System Vitals — CPU, Mem, GPU, Disk, Battery  [VITALS]
# =============================================================
SYS_CACHE="${CACHE_DIR}/sys_${_UID}.cache"
if [ "$(file_age "$SYS_CACHE")" -lt 5 ]; then
  . "$SYS_CACHE"
else
  if is_mac; then
    TOP_OUT=$(/usr/bin/top -l1 -s0 -n0 2>/dev/null)
    CPU_USER=$(printf '%s' "$TOP_OUT" | grep "CPU usage" | awk '{print $3}' | tr -d '%')
    CPU_SYS=$(printf '%s' "$TOP_OUT" | grep "CPU usage" | awk '{print $5}' | tr -d '%')
    CPU_USED=$(awk "BEGIN{printf \"%d\", ${CPU_USER:-0} + ${CPU_SYS:-0}}")
    MEM_USED=$(printf '%s' "$TOP_OUT" | grep "PhysMem" | awk '{print $2}')
    MEM_USED="${MEM_USED:-0M}"
    MEM_TOTAL_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    MEM_TOTAL_GB=$(awk "BEGIN{printf \"%.0f\", ${MEM_TOTAL_BYTES:-0} / 1073741824}")
    MEM_USED_NUM=$(printf '%s' "$MEM_USED" | tr -cd '0-9.')
    MEM_USED_NUM="${MEM_USED_NUM:-0}"
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
