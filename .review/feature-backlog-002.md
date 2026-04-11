# Feature Backlog & Planning — Review Addendum

**Date:** 2026-04-11  
**From:** Lead & Reviewer

## Priority Queue (Updated)

```
P0 ████ CRITICAL — Fix daily token tracking (review-009)
         ↳ Scan ALL transcript files, not just statusline sessions
         ↳ 656x undercount confirmed. This blocks everything.

P1 ████ After P0 is fixed:
    1. Cost budget alerts (CLAUDE_SL_DAILY_BUDGET env var)
    2. Autocompact countdown timer (⏳ ~3 turns at 80%+)
    3. Rate limit tracking (if API data available)

P2 ████ Polish features:
    4. Session health score (composite 0-100)
    5. MCP health monitor
    6. Tool success/failure ratio
    7. Project stack detection
    8. Message counter + density

P3 ████ Nice-to-have:
    9. Sparkline token history (mini chart)
    10. Process resource attribution
    11. Config status summary
    12. Multi-day trend comparison
```

## Feature: Rate Limit Tracking (P1)

If the Claude API or statusline JSON provides rate limit info (e.g., `rate_limit.remaining`, `rate_limit.reset_at`), display:

```
rl 847/1000 │ reset 2m
```

Show warning when remaining < 20%:
```
⚠️ rl 42/1000 │ reset 45s
```

**Dev agent:** Check if `context_window` or any other field in the statusline JSON contains rate limit data. If not, check if the transcript JSONL has it in API response headers.

## Feature: Cost Budget Alerts (P1)

```bash
# User sets via env var:
export CLAUDE_SL_DAILY_BUDGET=50  # $50/day

# Display in Row 4:
cost $12.45 (day $48.72/50 ⚠️)    # when > 90%
cost $12.45 (day $32.10/50)         # when < 90%
```

## Reminder: All New Features BLOCKED Until P0 Is Fixed

The transcript-based daily scanning from review-009 must land first. Without accurate daily data, budget alerts and trends are meaningless.
