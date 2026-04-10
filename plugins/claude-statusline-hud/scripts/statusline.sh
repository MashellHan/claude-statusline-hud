#!/usr/bin/env bash
# ================================================================
#  Claude Statusline HUD — cross-platform (macOS + Linux)
# ================================================================
#  Presets (set via CLAUDE_STATUSLINE_PRESET or ~/.claude/statusline-preset):
#
#    minimal   — 1 row:  [Model | Max]  Dir  Git
#    essential — 2 rows: + Activity (when active), Context/Usage bars
#    full      — 3–4 rows: + Stats (cost, time, code, etc.)
#    vitals    — 4–5 rows: + System vitals (CPU, Mem, GPU, Disk, Battery)  (default)
# ================================================================

set -f  # disable globbing for safety

input=$(cat)

# --- Temp file cleanup trap ---
EVENTS_FILE="/tmp/.claude_sl_events_$$"
trap 'rm -f "$EVENTS_FILE"' EXIT

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
  @sh "TRANSCRIPT=\(.transcript_path // "")",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)"
' 2>/dev/null)" || {
  # Fallback: if jq fails, set safe defaults
  MODEL="Unknown" DIR="" PCT=0 COST_RAW=0 DURATION_MS=0 API_MS=0
  LINES_ADD=0 LINES_DEL=0 VIM_MODE="" AGENT_NAME="" WT_NAME="" WT_BRANCH=""
  EXCEEDS_200K=false INPUT_TOK=0 CACHE_CREATE=0 CACHE_READ=0 TOTAL_OUT=0
  TRANSCRIPT="" CTX_SIZE=200000
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

file_age() {
  local f="$1"
  [ -f "$f" ] || { echo 9999; return; }
  if is_mac; then echo $(( $(date +%s) - $(stat -f%m "$f" 2>/dev/null || echo 0) ))
  else echo $(( $(date +%s) - $(stat -c%Y "$f" 2>/dev/null || echo 0) )); fi
}

NOW=$(date +%s)

# --- Session ID for cache isolation ---
if [ -n "$TRANSCRIPT" ]; then
  _SID=$(printf '%s' "$TRANSCRIPT" | cksum | awk '{print $1}')
else
  _SID="$$"
fi

# =============================================
# GIT INFO (cached 10s)
# =============================================
GIT_DISPLAY=""
if [ -n "$DIR" ]; then
  GIT_CACHE="/tmp/.claude_sl_git"
  if [ "$(file_age "$GIT_CACHE")" -lt 10 ]; then
    GIT_INFO=$(cat "$GIT_CACHE")
  else
    if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
      GB=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
      GD=""
      gs=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
      gu=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
      gq=$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
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

# --- Badges (truncate long names to prevent overflow) ---
BADGES=""
[ -n "$VIM_MODE" ] && BADGES="${BADGES}${SEP}${BOLD}${BLUE}${VIM_MODE}${RST}"
if [ -n "$AGENT_NAME" ]; then
  AGENT_TRUNC="${AGENT_NAME:0:15}"
  BADGES="${BADGES}${SEP}${BOLD}${CYAN}⚡ ${AGENT_TRUNC}${RST}"
fi
if [ -n "$WT_NAME" ]; then
  WT_TRUNC="${WT_NAME:0:15}"
  BADGES="${BADGES}${SEP}${DIM}🌿 ${WT_TRUNC}${WT_BRANCH:+→${WT_BRANCH}}${RST}"
fi

# --- Update notice ---
UPDATE_BADGE=""
if [ -f "/tmp/.claude_sl_update_available" ]; then
  NEW_VER=$(cat "/tmp/.claude_sl_update_available" 2>/dev/null)
  [ -n "$NEW_VER" ] && UPDATE_BADGE="${SEP}${YELLOW}${BOLD}↑ v${NEW_VER}${RST}"
fi

# =============================================================
# ROW 1: [Model | Max] │ Dir │ Git │ Badges │ Update  [ALL]
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
printf '%b\n' "$R1"

[ "$PRESET" = "minimal" ] && exit 0

# =============================================================
# ROW 2 (conditional): Live Activity — Tools │ Todos │ Agents
#   Shown when there's active work. Parsed from transcript.
#   Cached 2s. Appears in ESSENTIAL+ presets.
# =============================================================

ACTIVITY_CACHE="/tmp/.claude_sl_activity_${_SID}"
ACTIVITY_LINE=""

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if [ "$(file_age "$ACTIVITY_CACHE")" -lt 2 ]; then
    ACTIVITY_LINE=$(cat "$ACTIVITY_CACHE")
  else
    # Transcript JSONL: tools are nested in .message.content[]
    # Step 1: Extract lightweight events line-by-line via jq -c pipe (no slurp)
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

    # Step 2: Build display from extracted events (single slurp of small data)
    ACTIVITY_LINE=""
    if [ -s "$EVENTS_FILE" ]; then
      ACTIVITY_LINE=$(jq -rs '
        (reduce .[] as $e ({};
          if $e.t == "u" then .[$e.id] = {name: $e.n, target: $e.tgt, done: false}
          elif $e.t == "r" then .[$e.id].done = true
          else . end
        )) as $tools |
        ([$tools | to_entries | .[-5:] | reverse[] |
          if .value.done then "✓ " + .value.name
          else "◐ " + .value.name + (if .value.target != "" then " " + .value.target else "" end) end
        ] | join(" · ")) as $tool_str |
        ([$tools | to_entries[] | select(.value.name == "TodoWrite")] |
          if length > 0 then
            (last.value.target | split(" ") | .[0]) as $counts |
            (last.value.target | split(" ") | .[1:] | join(" ")) as $task_name |
            if ($task_name | length) > 0 then "▸ " + $task_name + " (" + $counts + ")"
            elif ($counts | length) > 0 then "✓ todos " + $counts
            else "" end
          else "" end
        ) as $todo_str |
        ([$tools | to_entries[] | select(.value.name == "Agent" and .value.done == false)] |
          if length > 0 then (first | "⚡ " + .value.target) else "" end
        ) as $agent_str |
        [[$tool_str, $todo_str, $agent_str] | .[] | select(length > 0)] | join("  │  ")
      ' "$EVENTS_FILE" 2>/dev/null)
    fi
    rm -f "$EVENTS_FILE"
    printf '%s' "$ACTIVITY_LINE" > "$ACTIVITY_CACHE"
  fi
fi

if [ -n "$ACTIVITY_LINE" ]; then
  printf '%b\n' "${DIM}›${RST} ${ACTIVITY_LINE}"
fi

# =============================================================
# ROW 3: Context bar │ Usage bars                   [ESSENTIAL+]
# =============================================================

# --- Autocompact buffer estimation ---
# Inflate by ~10% above 70% to reflect true context pressure.
TOTAL_INPUT=$((INPUT_TOK + CACHE_CREATE + CACHE_READ))
ADJ_PCT=$PCT
if [ "$PCT" -ge 70 ] 2>/dev/null; then
  ADJ_PCT=$(( PCT + (PCT - 70) * 10 / 30 ))
  [ "$ADJ_PCT" -gt 100 ] && ADJ_PCT=100
fi

CTX_CLR=$(bar_color "$ADJ_PCT")
CTX_BAR=$(make_bar "$ADJ_PCT" "$BAR_W")

# --- Context warning: ⚠ when exceeds 200k OR adjusted PCT ≥ 90% ---
CTX_WARN=""
if [ "$EXCEEDS_200K" = "true" ] || [ "$ADJ_PCT" -ge 90 ] 2>/dev/null; then
  CTX_WARN=" ${BOLD}${BG_YELLOW} ⚠ ${RST}"
fi

CTX_LABEL="${VAL}${PCT}%${RST}"

# ---- Build token display for context row ----
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUT))
TOK_DISPLAY=""
if [ "$TOTAL_TOKENS" -gt 0 ]; then
  TOK_DISPLAY="${CYAN}token${RST} ${VAL}$(fmt_tok $TOTAL_TOKENS)${RST} (${CYAN}in${RST} ${VAL}$(fmt_tok $INPUT_TOK)${RST} ${CYAN}cache${RST} ${GREEN}${VAL}$(fmt_tok $CACHE_READ)${RST} ${CYAN}out${RST} ${VAL}$(fmt_tok $TOTAL_OUT)${RST})"
fi

R3="${CYAN}Context${RST} ${CTX_CLR}${CTX_BAR}${RST} ${CTX_LABEL}${CTX_WARN}"
[ -n "$TOK_DISPLAY" ] && R3="${R3}${SEP}${TOK_DISPLAY}"
printf '%b\n' "$R3"

# --- Token breakdown row (conditional): shown at 85%+ context ---
if [ "$PCT" -ge 85 ] 2>/dev/null && [ "$TOTAL_INPUT" -gt 0 ] && [ "$TIER" != "compact" ]; then
  CTX_TOTAL=$((TOTAL_INPUT + TOTAL_OUT))
  printf '%b\n' "  ${DIM}tokens${RST} $(fmt_tok $CTX_TOTAL)/$(fmt_tok $CTX_SIZE) ${DIM}—${RST} ${DIM}in${RST} ${BOLD}$(fmt_tok $INPUT_TOK)${RST} ${DIM}cached${RST} ${GREEN}${BOLD}$(fmt_tok $CACHE_READ)${RST} ${DIM}created${RST} ${YELLOW}$(fmt_tok $CACHE_CREATE)${RST} ${DIM}out${RST} ${BOLD}$(fmt_tok $TOTAL_OUT)${RST}"
fi

[ "$PRESET" = "essential" ] && exit 0

# =============================================================
# ROW 4: Stats — Cost │ Duration │ Lines │ Cache │ Speed  [FULL+]
# =============================================================

COST_FMT=$(fmt_cost "$COST_RAW")
DUR=$(fmt_dur "$DURATION_MS")
EFF=""
if [ "$DURATION_MS" -gt 0 ] && [ "$API_MS" -gt 0 ]; then
  EFF=" (${CYAN}api${RST} ${VAL}$((API_MS * 100 / DURATION_MS))%${RST})"
fi

LINES=""
if [ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]; then
  NET=$((LINES_ADD - LINES_DEL))
  if [ "$NET" -gt 0 ]; then NI="${GREEN}▲${RST}"
  elif [ "$NET" -lt 0 ]; then NI="${RED}▼${RST}"
  else NI="${YELLOW}═${RST}"; fi
  LINES="${GREEN}+${LINES_ADD}${RST} ${RED}-${LINES_DEL}${RST} ${NI}"
fi

CACHE_HIT=""
if [ "$TOTAL_INPUT" -gt 0 ]; then
  CP=$((CACHE_READ * 100 / TOTAL_INPUT))
  if [ "$CP" -ge 80 ]; then CC="$GREEN"; elif [ "$CP" -ge 40 ]; then CC="$YELLOW"; else CC="$RED"; fi
  CACHE_HIT="${CYAN}cache${RST} ${CC}${VAL}${CP}%${RST}"
fi

THROUGHPUT=""
if [ "$DURATION_MS" -gt 0 ] && [ "$TOTAL_OUT" -gt 0 ]; then
  TPM=$((TOTAL_OUT * 60000 / DURATION_MS))
  THROUGHPUT="${CYAN}speed${RST} ${VAL}$(fmt_tok "$TPM")/min${RST}"
fi

R4="${CYAN}cost${RST} ${VAL}${COST_FMT}${RST}"
R4="${R4}${SEP}${CYAN}time${RST} ${VAL}${DUR}${RST}${EFF}"
[ -n "$LINES" ] && R4="${R4}${SEP}${CYAN}code${RST} ${LINES}"
[ -n "$CACHE_HIT" ] && R4="${R4}${SEP}${CACHE_HIT}"
[ -n "$THROUGHPUT" ] && R4="${R4}${SEP}${THROUGHPUT}"
printf '%b\n' "$R4"

[ "$PRESET" = "full" ] && exit 0

# =============================================================
# ROW 5: System Vitals — btop-style mini bars          [VITALS]
# =============================================================

SYS_CACHE="${TMPDIR:-/tmp}/.claude_sl_sys_$(id -u)"
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
    PREV_STAT="/tmp/.claude_sl_cpu_prev"
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
  cat > "$SYS_CACHE" <<CACHE
CPU_USED='${CPU_USED:-0}'
MEM_USED='${MEM_USED:-0M}'
MEM_TOTAL_GB='${MEM_TOTAL_GB:-0}'
MEM_PCT='${MEM_PCT:-0}'
GPU_PCT='${GPU_PCT:-0}'
DISK_USED='${DISK_USED:-0G}'
DISK_TOTAL='${DISK_TOTAL:-0G}'
DISK_PCT='${DISK_PCT:-0}'
BV='${BV:-}'
LOAD_AVG='${LOAD_AVG:-0}'
CACHE
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
