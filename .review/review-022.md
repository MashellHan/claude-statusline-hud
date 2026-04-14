# Review 022 — 10 Real Issues: Security, Performance, Correctness

**Date:** 2026-04-14  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Scope:** Full codebase audit — `statusline.sh` (746 LOC), test suite (168 tests)  
**Method:** 3-axis parallel analysis (security, performance/correctness, test coverage)

---

## Scoring Summary

| Dimension | Issues Found | Severity |
|-----------|-------------|----------|
| Security | 3 | 2 CRITICAL, 1 HIGH |
| Performance | 4 | 1 HIGH, 3 MEDIUM |
| Correctness | 2 | 2 MEDIUM |
| Test Coverage | 1 | 1 HIGH |

---

## Issue 1 — CRITICAL: Source from /tmp Without Ownership Check

**Lines:** 513, 592, 668  
**Severity:** CRITICAL  
**Type:** Security — Privilege Escalation

Three locations source shell files from `/tmp` without verifying file ownership or permissions:

```bash
# Line 513
. "$SESS_MSG_CACHE"        # /tmp/.claude_sl_sessmsg_${_SID}

# Line 592
. "$DAILY_CACHE"           # /tmp/.claude_sl_daily_$(id -u)

# Line 668
. "$SYS_CACHE"             # /tmp/.claude_sl_sys_$(id -u)
```

**Attack:** On multi-user systems, attacker writes arbitrary shell commands to predictable `/tmp/.claude_sl_daily_1000`. Next render sources the file → code execution under victim's user.

**Fix:**
```bash
# Option A: Move caches to ~/.cache/claude-statusline/ (user-only, no /tmp)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR"

# Option B: Verify ownership before sourcing
_owner=$(stat -c '%u' "$file" 2>/dev/null || stat -f '%u' "$file" 2>/dev/null)
[ "$_owner" = "$(id -u)" ] && . "$file"
```

**Recommendation:** Option A is cleaner. Move ALL cache files from `/tmp` to `~/.cache/claude-statusline/`.

---

## Issue 2 — CRITICAL: Heredoc Cache Write Enables Injection

**Lines:** 718-729  
**Severity:** CRITICAL  
**Type:** Security — Code Injection via Cache Poisoning

```bash
cat > "$SYS_CACHE" <<CACHE
CPU_USED='${CPU_USED:-0}'
MEM_USED='${MEM_USED:-0M}'
...
CACHE
```

The heredoc delimiter `CACHE` is **unquoted**, so Bash expands `${...}` before writing. If any system command returns a value containing `'`, the single-quote escaping breaks:

```bash
# If MEM_USED somehow becomes: 4G'; rm -rf ~/important; echo '
# Written to cache:
MEM_USED='4G'; rm -rf ~/important; echo ''
# Next source → EXECUTES
```

Realistic? On Linux, `MEM_USED` comes from awk on `/proc/meminfo` — low risk. On macOS, it comes from `top` output parsing — also low risk. But the pattern is fundamentally unsafe.

**Fix:** Use `printf '%q'` for safe shell quoting:
```bash
printf "CPU_USED=%q\nMEM_USED=%q\n..." \
  "${CPU_USED:-0}" "${MEM_USED:-0M}" ... > "$SYS_CACHE"
```

**Similarly affects:** Line 525-526 (`SESS_MSG_CACHE`) and line 628-629 (`DAILY_CACHE`), though these use `printf` with `%s` and single quotes — slightly safer but same class of vulnerability if values contain `'`.

---

## Issue 3 — HIGH: `find | xargs grep` Without `-print0 / -0`

**Lines:** 597-599  
**Severity:** HIGH  
**Type:** Security + Correctness — Filename Injection

```bash
find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" 2>/dev/null | \
  xargs grep -h "input_tokens" 2>/dev/null | \
```

Claude projects directory paths often contain spaces (e.g., `-Users-mengxionghan-Workspace-my project-`). Without `-print0` / `xargs -0`, filenames with spaces are split into separate arguments.

**Fix:**
```bash
find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" -type f -print0 2>/dev/null | \
  xargs -0 grep -h "input_tokens" 2>/dev/null | \
```

---

## Issue 4 — HIGH: `file_age()` Calls `date +%s` Repeatedly Instead of Reusing `$NOW`

**Lines:** 220-225, 227  
**Severity:** HIGH  
**Type:** Performance — Redundant Subprocess Spawning

```bash
file_age() {
  ...
  echo $(( $(date +%s) - $(stat -f%m "$f" ...) ))  # NEW date process each call
}

NOW=$(date +%s)  # Already computed globally at line 227
```

`file_age()` is called 5 times per render (lines 245, 432, 512, 591, 667). Each call spawns `date +%s` + `stat` = 2 subprocesses. That's **10 unnecessary subprocesses** when `$NOW` already exists.

**Fix:**
```bash
file_age() {
  local f="$1"
  [ -f "$f" ] || { echo 9999; return; }
  if is_mac; then echo $(( NOW - $(stat -f%m "$f" 2>/dev/null || echo 0) ))
  else echo $(( NOW - $(stat -c%Y "$f" 2>/dev/null || echo 0) )); fi
}
```

Saves 5 `date` subprocess spawns per render. On macOS, `date` fork+exec takes ~3ms each = **~15ms saved**.

---

## Issue 5 — MEDIUM: 6 Separate jq Calls to Extract Fields From Same JSON Object

**Lines:** 610-614, 623  
**Severity:** MEDIUM  
**Type:** Performance — Subprocess Multiplication

```bash
DAY_TOK=$(printf '%s' "$_DAY_STATS" | jq -r '.tokens // 0')
DAY_SESSIONS=$(printf '%s' "$_DAY_STATS" | jq -r '.messages // 0')
DAY_INPUT=$(printf '%s' "$_DAY_STATS" | jq -r '.input // 0')
DAY_OUTPUT=$(printf '%s' "$_DAY_STATS" | jq -r '.output // 0')
DAY_CACHE_TOK=$(printf '%s' "$_DAY_STATS" | jq -r '.cache_read // 0')
# ... and line 623: another jq call
```

6 jq processes to read 6 fields from the same ~100-byte JSON string. Each jq fork+exec ≈ 5ms on macOS.

**Fix:** Single `eval` with `@sh`, same pattern as the main JSON parse (line 49):
```bash
eval "$(printf '%s' "$_DAY_STATS" | jq -r '
  @sh "DAY_TOK=\(.tokens // 0)",
  @sh "DAY_SESSIONS=\(.messages // 0)",
  @sh "DAY_INPUT=\(.input // 0)",
  @sh "DAY_OUTPUT=\(.output // 0)",
  @sh "DAY_CACHE_TOK=\(.cache_read // 0)"
' 2>/dev/null)"
```

Saves 5 jq subprocesses × 5ms = **~25ms on cache miss**.

---

## Issue 6 — MEDIUM: `ls | wc -l` Miscounts Skills

**Line:** 330  
**Severity:** MEDIUM  
**Type:** Correctness — Wrong Count

```bash
_SKILLS_COUNT=$(ls "$_SKILLS_DIR" 2>/dev/null | wc -l | tr -d ' ')
```

`ls` without `-A` **excludes** hidden files/dirs (like `.git`), but **includes** subdirectories. If `~/.claude/skills/` contains subdirectories, they're counted as skills.

Additionally, `ls` output format can vary across systems — some implementations add trailing blank lines.

**Fix:**
```bash
_SKILLS_COUNT=$(find "$_SKILLS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
```

Or if skills are directories (one dir per skill):
```bash
_SKILLS_COUNT=$(find "$_SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
```

Check actual structure of `~/.claude/skills/` to determine which is correct.

---

## Issue 7 — MEDIUM: `tail -80 | jq` Can Break on Multiline JSON

**Line:** 435  
**Severity:** MEDIUM  
**Type:** Correctness — Silent Data Loss

```bash
tail -80 "$TRANSCRIPT" 2>/dev/null | jq -c '[...]'
```

`tail -80` splits at **line boundaries**, not JSON object boundaries. If a transcript entry contains a multiline string (e.g., code with newlines in tool output), `tail` cuts mid-JSON-object. `jq` silently fails (`2>/dev/null`), and the tools display shows nothing.

**Impact:** Tool activity display occasionally goes blank for no apparent reason.

**Fix:** Use jq's own slicing to read only the last N objects:
```bash
jq -c '[.message.content // []][-80:][] | ...' "$TRANSCRIPT"
```

Or if performance is a concern (full file read), keep `tail` but increase to `-200` and add a recovery filter:
```bash
tail -200 "$TRANSCRIPT" 2>/dev/null | jq -c '...' 2>/dev/null
```

---

## Issue 8 — MEDIUM: Git Branch Name With `|` Breaks Cache Parsing

**Lines:** 290, 296-299  
**Severity:** MEDIUM  
**Type:** Correctness — Field Misalignment

```bash
# Line 290: Store with | delimiter
GIT_INFO="${GB}|${GD}|${GAB}|${GIT_STATE}"

# Lines 296-299: Parse with cut
GB=$(printf '%s' "$GIT_INFO" | cut -d'|' -f1)
GD=$(printf '%s' "$GIT_INFO" | cut -d'|' -f2)
```

If git branch name contains `|` (legal in git: `git checkout -b "feat|WIP"`), fields shift right.

**Likelihood:** Low (unusual naming convention), but git allows it.

**Fix:** Use a delimiter that's illegal in git ref names. Git branch names cannot contain `~`, `^`, `:`, `\`, or ASCII control characters:
```bash
GIT_INFO="${GB}~${GD}~${GAB}~${GIT_STATE}"
# Parse:
GB=$(printf '%s' "$GIT_INFO" | cut -d'~' -f1)
```

Actually `~` is valid at end of refspec. Safest: use tab `$'\t'` as delimiter — never appears in branch names.

---

## Issue 9 — MEDIUM: 30 awk + 17 jq = 47 Subprocesses Per Full Render

**Lines:** Various (see table)  
**Severity:** MEDIUM  
**Type:** Performance — Total Subprocess Budget

Full `vitals` preset render on cache miss spawns approximately:

| Category | Count | Source |
|----------|-------|--------|
| jq | 10-11 | Main parse + MCP + activity (×2) + daily (×7) |
| awk | 20-24 | fmt_cost, checksums, git, session, vitals parsing |
| date | 6-10 | NOW + file_age (×5) |
| stat | 5 | file_age (×5) |
| git | 5-7 | rev-parse, symbolic-ref, status, rev-list |
| Other | 5-8 | cut, tail, find, xargs, grep, top/sysctl |
| **Total** | **~55-65** | |

For a statusline that renders every 2-5 seconds, 55+ subprocesses is heavy. Caching mitigates this (cache hit path ≈ 15-20 subprocesses), but a cold start is expensive.

**Top Savings Opportunities:**
1. `file_age()`: Reuse `$NOW` → saves 5 date processes
2. Daily stats: Single jq eval → saves 5 jq processes
3. Replace simple awk with shell arithmetic (e.g., `${AB%% *}` instead of `awk '{print $1}'`) → saves 5-8 awk processes
4. Estimated total saving: **15-18 subprocesses** (~25-30% reduction)

---

## Issue 10 — HIGH: Test Coverage Has Major Blind Spots

**Scope:** `.test/` (168 tests, 8 suites)  
**Severity:** HIGH  
**Type:** Test Gap — Critical Paths Untested

The test suite covers formatting, calculations, colors, and presets well, but has **zero tests** for:

| Untested Path | Lines | Risk |
|---------------|-------|------|
| Rate limit display | 410-426 | Feature invisible if broken |
| Daily token scanning | 587-631 | OOM/crash on production data |
| Transcript activity parsing | 428-476 | Silent failure on multiline JSON |
| MCP/Skills badge counting | 320-333 | Wrong counts displayed |
| Cache file sourcing (`. "$CACHE"`) | 513, 592, 668 | Security regression undetected |
| `eval` fallback on jq failure | 73-79 | Crash on malformed JSON |
| `~/.claude/statusline-preset` reading | 43-44 | Config file parsing |
| Cache TTL expiry behavior | Various | Stale data served |

**Current coverage estimate:** ~65-70% of code paths.  
**Security test coverage:** ~10%.

**Recommendation:** Add test suites:
- `test-security.sh` — Malicious JSON input, cache poisoning, eval safety
- `test-daily.sh` — Daily scanning with mock transcript files
- `test-activity.sh` — Tool activity parsing with real transcript excerpts
- `test-ratelimit.sh` — Rate limit display at various thresholds

---

## Priority Matrix

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | #1 Cache files → `~/.cache/` | Medium | Eliminates entire attack class |
| **P0** | #3 `find -print0 \| xargs -0` | Trivial | Prevents filename injection |
| **P1** | #4 `file_age()` reuse `$NOW` | Trivial | -15ms per render |
| **P1** | #5 Daily stats single jq | Low | -25ms on cache miss |
| **P1** | #10 Add security + daily tests | Medium | Prevents regressions |
| **P2** | #2 Heredoc → `printf %q` | Low | Defense in depth |
| **P2** | #6 `ls` → `find -type f` | Trivial | Correct skills count |
| **P2** | #7 `tail` → jq slice | Low | Fix intermittent blank tools |
| **P3** | #8 Git delimiter `|` → `\t` | Trivial | Edge case hardening |
| **P3** | #9 Reduce subprocess count | Medium | Latency improvement |

---

## Summary

The codebase is functionally solid (168/168 tests passing) with good caching strategy, but has **systemic security weakness** in its `/tmp` cache sourcing pattern (Issues #1, #2, #3) and **performance drag** from subprocess proliferation (Issues #4, #5, #9). The test suite has good breadth but critical depth gaps (Issue #10).

**Single highest-impact change:** Move all cache files from `/tmp` to `~/.cache/claude-statusline/` with `chmod 700`. This simultaneously fixes Issues #1, #2, and #3 — eliminating the entire `/tmp` attack surface.
