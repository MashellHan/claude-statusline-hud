# Review 001 — Initial Comprehensive Review

**Date:** 2026-04-11  
**Reviewer:** Claude Opus 4.6 (Automated)  
**Version:** 1.3.0  
**Commit:** 712c213  
**Files Reviewed:** All project files (8 source files, 527 LOC core)

---

## Overall Assessment

**Score: 7.0 / 10**

A solid, well-structured statusline HUD with good cross-platform support and adaptive layout. The core idea is strong, but there are significant opportunities for improvement across feature completeness, data accuracy, performance, code quality, and project maturity.

---

## 1. Feature Analysis

### Current Features (What's Working Well)
- 4-level preset system (minimal/essential/full/vitals) — excellent UX
- Adaptive terminal width handling (compact/normal/wide) — smart
- Cross-platform support (macOS + Linux) — essential
- Live activity parsing from transcript — innovative
- Theme detection (dark/light) — nice touch
- Version update badge — useful lifecycle feature
- Git integration with dirty/ahead/behind status — comprehensive

### Missing Features (Priority Ordered)

#### P0 — Must Have
| Feature | Description | Rationale |
|---------|-------------|-----------|
| **Daily token tracking** | Aggregate token usage across sessions for the current day | Users need to track daily budget consumption. User specifically requested this. |
| **Daily cost tracking** | Cumulative daily cost (USD) across all sessions | Cost awareness is critical for power users |
| **Rate limit status** | Show remaining API calls/tokens before rate limit | Original upstream had this; removing it was a regression for power users |
| **Session history** | Log sessions to a persistent file (`~/.claude/statusline-history.jsonl`) | Enables daily/weekly/monthly reporting |

#### P1 — Should Have
| Feature | Description | Rationale |
|---------|-------------|-----------|
| **Conversation turn counter** | Show number of human/assistant turns | Helps gauge conversation depth |
| **Error/retry indicator** | Show API errors and retry count this session | Visibility into reliability |
| **File change summary** | Show top 3 modified files this session | Quick context on what's being worked on |
| **Network latency** | Show avg API response latency (ms) | Performance debugging |
| **Context compaction indicator** | Show when/how many times context was compacted | Users lose context without knowing |

#### P2 — Nice to Have
| Feature | Description | Rationale |
|---------|-------------|-----------|
| **Sparkline history** | Show 10-sample token throughput sparkline | Trend visualization like btop |
| **Session comparison** | Compare current session cost/tokens vs average | Anomaly detection |
| **Notification system** | Alert when cost exceeds threshold | Budget protection |
| **Export capability** | Export session stats to JSON/CSV | Reporting and analysis |
| **Custom row plugin system** | Let users add their own rows via scripts | Extensibility |

### Innovative Feature Ideas
1. **Adaptive cost prediction** — Estimate remaining cost based on context fill rate and current spending velocity
2. **Token efficiency score** — Ratio of useful output vs total input (measures how well cache is being used)
3. **Session health indicator** — Composite score: cache hit rate + context headroom + throughput = green/yellow/red
4. **Project-aware stats** — Track cumulative stats per git repo, not just per session
5. **Pomodoro-style timer** — Show focused coding streaks and suggest breaks

---

## 2. Code Quality

### Architecture (6/10)

**Issue: Monolithic script**  
`statusline.sh` is 527 lines in a single file. While this is under the 800-line limit, it mixes concerns:
- JSON parsing
- Platform detection
- Git operations
- Activity parsing
- System vitals collection
- UI rendering

**Recommendation:** Split into modules:
```
scripts/
├── statusline.sh        # Main entry, orchestration only (~50 lines)
├── lib/
│   ├── parse.sh         # JSON parsing helpers
│   ├── git.sh           # Git info collection
│   ├── activity.sh      # Transcript parsing
│   ├── vitals.sh        # System metrics
│   ├── render.sh        # Row formatting and output
│   └── daily.sh         # Daily aggregation (new)
```

### Specific Code Issues

#### Issue 1: `eval` usage (SECURITY — MEDIUM)
**File:** `statusline.sh:153`
```bash
eval "bar=\"\${bar}\${chars_${remainder}}\""
```
While `remainder` is computed from arithmetic and bounded 0-7, `eval` is inherently risky. An indirect expansion or case statement is safer.

**Fix:**
```bash
case "$remainder" in
  1) bar="${bar}▏" ;; 2) bar="${bar}▎" ;; 3) bar="${bar}▍" ;; 4) bar="${bar}▌" ;;
  5) bar="${bar}▋" ;; 6) bar="${bar}▊" ;; 7) bar="${bar}▉" ;; esac
```

#### Issue 2: Unquoted variable splits (LOW)
Several instances of unquoted variables in arithmetic contexts could cause issues with unexpected input:
- `statusline.sh:131`: `[ "$pct" -gt 100 ]` — safe due to `-gt`, but inconsistent quoting throughout

#### Issue 3: Temp file cleanup (MEDIUM)
**File:** `statusline.sh:298-349`  
`EVENTS_FILE="/tmp/.claude_sl_events_$$"` uses PID-based temp files. If the script is killed before `rm -f`, orphan files accumulate. Consider using `mktemp` and a trap:
```bash
trap 'rm -f "$EVENTS_FILE"' EXIT
```

#### Issue 4: Cache race condition (LOW)
Multiple concurrent Claude sessions write to the same cache files (`/tmp/.claude_sl_git`, etc.). While unlikely to cause visible issues, it can produce garbled reads. Consider using session-specific cache keys.

#### Issue 5: `source` of cache file (MEDIUM)
**File:** `statusline.sh:449`
```bash
. "$SYS_CACHE"
```
Sourcing `/tmp/.claude_sl_sys` as shell code is a potential injection vector if another process writes to this file. The cache file content is generated by this script, but the `/tmp` directory is world-writable.

**Fix:** Use a more restricted temp directory:
```bash
SYS_CACHE="${TMPDIR:-/tmp}/.claude_sl_sys_$(id -u)"
```
Or parse the file instead of sourcing it.

#### Issue 6: Excessive `jq` invocations (PERFORMANCE)
**File:** `statusline.sh:38-56`  
19 separate `jq` calls to parse the same JSON input. Each spawns a new process.

**Fix:** Single `jq` call with destructuring:
```bash
eval "$(printf '%s' "$input" | jq -r '
  "MODEL=\(.model.display_name // "Unknown")",
  "DIR=\(.workspace.current_dir // "")",
  "PCT=\(.context_window.used_percentage // 0 | floor)"
  # ... etc
')"
```
This reduces 19 process spawns to 1.

### Code Style (7/10)
- Variable naming is mostly clear (e.g., `CTX_CLR`, `BAR_W`)
- Comments exist for sections, but sparse within logic
- Functions are well-separated (`make_bar`, `mini_bar`, `fmt_dur`, `fmt_tok`)
- Missing `shellcheck` compliance — several potential warnings

---

## 3. Performance

### Current Performance (7/10)
- Good caching strategy (2s/5s/10s TTLs)
- Transcript parsing uses `tail -80` efficiently
- System vitals collection is reasonably optimized for macOS/Linux

### Performance Issues

| Issue | Impact | Fix |
|-------|--------|-----|
| 19x `jq` process spawns per invocation | ~50-80ms overhead | Consolidate to 1 `jq` call |
| `git diff --cached --numstat` + `git diff --numstat` + `git ls-files` = 3 separate git calls | ~30ms per call uncached | Combine into single `git status --porcelain` parse |
| `/usr/bin/top -l1` on macOS takes ~1s first call | Blocks rendering | Already mitigated by cache, but first-load is slow |
| Activity parsing spawns 2 `jq` processes on each non-cached call | ~20ms | Could be combined into one |
| `awk "BEGIN{printf...}"` for arithmetic | ~5ms each | Use bash arithmetic where possible |

### Recommended Performance Targets
- Cold start (no cache): < 200ms
- Warm invocation (all cached): < 50ms
- Current estimated warm: ~80-100ms (due to 19 `jq` calls even on cached data — JSON parsing always runs)

---

## 4. Data Accuracy

### Verified Correct
- Context window percentage calculation
- Token formatting (k/M suffixes)
- Cost formatting
- Duration formatting
- Git dirty/ahead/behind counts
- Battery level detection

### Potential Accuracy Issues

| Issue | Severity | Description |
|-------|----------|-------------|
| Autocompact estimation | MEDIUM | `ADJ_PCT` formula `(PCT - 70) * 10 / 30` is heuristic, not based on actual autocompact behavior. At 85%, it shows 90% — potentially misleading |
| Cache hit rate | LOW | `CACHE_READ * 100 / TOTAL_INPUT` counts cache_read as a fraction of total input, but cache_creation should arguably be excluded from the denominator |
| Throughput calculation | LOW | `TOTAL_OUT * 60000 / DURATION_MS` measures total output over total time, not actual generation speed. Long idle periods deflate the number |
| GPU on macOS | MEDIUM | `ioreg -r -d 1 -c IOAccelerator` may report 0% on newer Apple Silicon chips that use different IOService classes |
| Memory on macOS | LOW | `top -l1` PhysMem "used" includes wired + compressed + cached; "available" would be more meaningful |

---

## 5. UI/UX

### Strengths
- btop-inspired design is familiar to terminal users
- Color coding follows intuitive green/yellow/red scale
- Adaptive width prevents overflow/truncation
- Unicode bars with ASCII fallback — accessibility

### Improvement Opportunities

| Area | Current | Proposed | Reason |
|------|---------|----------|--------|
| Row labels | Left-aligned text | Consistent column alignment | Easier to scan vertically |
| Token display | `token 44k (in 41k cache 0 out 2k)` | `tok 44k │ in 41k │ cache 0 │ out 2k` | Cleaner separator-based layout |
| Cost display | `cost $1.31` | `cost $1.31 (day $14.82)` | Add daily context |
| Context bar | Shows raw % | Show `42% → ~48% adj` at high usage | Make adjustment transparent |
| Vitals row | All items same style | Highlight anomalies (red bg for CPU > 90%) | Draw attention to issues |
| Empty state | Nothing shown for 0 values | Dim zeros instead of hiding | Consistent layout reduces jank |

---

## 6. Stability

### Robustness (7/10)
- Error handling for missing commands (git, jq) — partial
- Cache file age detection handles missing files
- Platform detection is solid (uname)

### Stability Issues
| Issue | Impact | Fix |
|-------|--------|-----|
| No `jq` availability check | Script fails silently if jq missing | Add startup check with clear error message |
| Transcript file may not exist | Non-fatal but wastes cycles | Already handled, but error suppression (`2>/dev/null`) masks real issues |
| `tput cols` fails in some CI/pipe contexts | Falls back to 100 | Fine, but could default to `normal` tier |
| Stale cache across login sessions | Shows old data briefly | Add session-id to cache keys |

---

## 7. Installation & Distribution

### Current State
- Plugin system integration is well done
- SessionStart hook for auto-setup — idempotent
- Marketplace metadata is correct

### Issues
| Issue | Fix |
|-------|-----|
| `plugin.json` author points to fork origin (Thewhey-Brian), not current fork owner | Update author info if maintaining a separate fork |
| `repository` field in marketplace.json points to upstream | Update to your fork's URL |
| No CHANGELOG.md | Add changelog for version tracking |
| No CONTRIBUTING.md | Add if accepting contributions |
| Screenshots are PNGs in git history (large blobs) | Consider hosting on GitHub releases or use git-lfs |

---

## 8. Git & Project Hygiene

### Issues
- `.gitignore` is minimal — consider adding `.review/` if review artifacts should not be committed
- No `.editorconfig` for consistent formatting
- No `shellcheck` CI integration
- Commit messages are well-formatted (conventional commits style)
- Branch strategy: single `main` branch — fine for this project size

---

## 9. Feature Request: Daily Token Tracking

### Architecture Proposal

```
~/.claude/statusline-data/
├── daily.jsonl          # Append-only log of session stats
└── daily-summary.json   # Cached aggregation for current day
```

Each statusline invocation appends a record:
```json
{"ts": 1712793600, "session_id": "abc123", "tokens": {"in": 1200, "cache": 800, "out": 400}, "cost": 0.03}
```

A daily aggregation function computes:
```json
{"date": "2026-04-11", "total_tokens": 145000, "total_cost": 12.50, "sessions": 8}
```

Display in Row 4:
```
cost $1.31 (day $12.50) │ time 12m │ code +142 -38 ▲ │ day-tok 145k
```

### Implementation Steps
1. Create `~/.claude/statusline-data/` directory in setup.sh
2. Add session tracking with unique session ID (from transcript path hash)
3. Append session delta on each invocation (dedup by checking last entry)
4. Aggregate daily stats with fast jq query
5. Display in stats row

---

## 10. Action Items (Priority Ordered)

### Immediate (This Sprint)
1. **Consolidate jq calls** — Reduce from 19 to 1 for JSON parsing (~4x performance gain)
2. **Add daily token/cost tracking** — User-requested feature
3. **Remove `eval` in `mini_bar`** — Replace with case statement
4. **Add session-specific cache keys** — Prevent cross-session interference

### Short Term (Next 2 Sprints)
5. **Split statusline.sh into modules** — Improve maintainability
6. **Add rate limit status** — Re-add removed feature with better UI
7. **Add conversation turn counter** — Easy metadata from transcript
8. **Add shellcheck to CI** — Catch shell script issues automatically
9. **Fix GPU detection on newer Apple Silicon** — Test on M3/M4

### Medium Term
10. **Add session history logging** — Foundation for daily/weekly reports
11. **Add cost threshold notifications** — Budget protection
12. **Add sparkline-style trends** — Visual token throughput trend
13. **Add CHANGELOG.md** — Track changes across versions
14. **Explore `jq` alternatives** — Consider `python3 -c` for complex JSON if available

---

## Summary

| Category | Score | Notes |
|----------|-------|-------|
| Features | 6/10 | Good base, missing daily tracking and several useful metrics |
| Code Quality | 7/10 | Clean but monolithic, has eval usage and temp file issues |
| Performance | 7/10 | Good caching, but 19 jq spawns per call is costly |
| Data Accuracy | 8/10 | Mostly correct, autocompact estimation is heuristic |
| UI/UX | 8/10 | Well-designed adaptive layout, minor improvements possible |
| Stability | 7/10 | Handles most edge cases, needs jq check and cache isolation |
| Installation | 8/10 | Smooth plugin system, metadata needs fork update |
| Project Maturity | 5/10 | No tests, no CI, no changelog, no contributing guide |
| **Overall** | **7.0/10** | **Solid foundation, needs daily tracking and performance optimization** |

---

*Next review scheduled in 10 minutes. Will focus on implementation changes since this review.*
