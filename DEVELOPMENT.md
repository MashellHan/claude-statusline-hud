# Development Model — claude-statusline-hud

## Team Roles & Collaboration

This project follows a **3-role agent collaboration model**:

```
┌─────────────────────────────────────────────────────────┐
│                    Development Flow                      │
│                                                          │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│   │   LEAD   │───▶│   DEV    │───▶│  TESTER  │          │
│   │ REVIEWER │◀───│  AGENT   │◀───│  AGENT   │          │
│   └──────────┘    └──────────┘    └──────────┘          │
│        │               │               │                 │
│   .review/*.md    statusline.sh    tests/                │
│   DEVELOPMENT.md  setup.sh         e2e checks            │
│                   teardown.sh                            │
└─────────────────────────────────────────────────────────┘
```

### Lead & Reviewer (This Agent)

**Responsibilities:**
- Write review documents (`.review/review-NNN.md`)
- Define feature requirements and priorities
- Analyze bugs, propose fixes via documentation (NOT code)
- Track project scores and quality metrics
- Maintain the feature roadmap
- Competitive analysis and feature brainstorming
- Escalate blockers when items are stalled

**Output:** `.review/` folder documents — reviews, specs, roadmaps

**Does NOT:** Write implementation code, run tests, modify `statusline.sh`

### Dev Agent

**Responsibilities:**
- Read review documents for bug reports, feature specs, and action items
- Implement features and fixes in `statusline.sh`, `setup.sh`, etc.
- **MUST auto-commit and push after EVERY change** (see Auto-Commit Rule below)
- Follow the priority queue in the latest review document
- Respond to CRITICAL items before starting new features
- After committing, sync to marketplace install path if applicable

**Input:** `.review/review-NNN.md` action items  
**Output:** Code commits on `main` branch

**Auto-Commit Rule (MANDATORY):**
> Every code change MUST be committed and pushed immediately after implementation.
> Never leave changes in the working tree uncommitted. The reviewer checks
> `git log` and `git diff` — uncommitted code is invisible to the review process
> and will NOT be deployed.
>
> ```bash
> # After every change:
> git add -A && git commit -m "<type>: <description>" && git push
> ```

### Tester Agent

**Responsibilities:**
- Validate implementations against review requirements
- Run the statusline with test JSON payloads
- Verify data accuracy (token counts, costs, formatting)
- Check edge cases (empty data, zero values, compact terminal)
- Report test results for the reviewer to assess

**Input:** New commits from Dev Agent  
**Output:** Test results, bug reports

## Workflow

```
1. Lead/Reviewer writes review-NNN.md
   ├── Identifies bugs and issues
   ├── Specifies feature requirements
   ├── Provides copy-paste-ready specs (NOT code)
   └── Sets priority: CRITICAL > HIGH > MEDIUM > LOW

2. Dev Agent reads latest review
   ├── Works CRITICAL items first
   ├── Implements fixes/features
   ├── Commits with conventional messages
   └── Pushes to main

3. Tester Agent validates
   ├── Tests new features
   ├── Checks data accuracy
   └── Reports results

4. Lead/Reviewer creates next review
   ├── Checks git log for new commits
   ├── Reviews diffs
   ├── Updates scores
   └── Assigns next priorities
```

## Communication Protocol

- **Lead → Dev:** Via `.review/review-NNN.md` action items
- **Lead → Tester:** Via review docs (test criteria sections)
- **Dev → Lead:** Via git commits (lead reviews diffs)
- **Tester → Lead:** Via test reports (lead incorporates into reviews)

## Deployment Protocol

After committing code changes, Dev Agent MUST sync to the marketplace install:

```bash
# Sync repo → marketplace (what actually runs in Claude Code)
cp plugins/claude-statusline-hud/scripts/statusline.sh \
   ~/.claude/plugins/marketplaces/claude-statusline-hud/plugins/claude-statusline-hud/scripts/statusline.sh

# Clear caches to force fresh data
rm -f /tmp/.claude_sl_daily_* /tmp/.claude_sl_*
```

Without this step, the user continues running the old version.

## Current Status

- **Reviews completed:** 13 (001-013)
- **Overall score:** 8.3/10 (rate limit display + daily token fix both deployed)
- **Features done:** 7 of 15 (daily tracking, git state, burn rate, token fix, layout, transcript scanning, rate limits)
- **BLOCKING:** None
- **Next priority:** Native session_id (P1.2) → budget alerts (P1.3) → autocompact countdown (P1.4)
- **Roadmap:** See `.review/feature-roadmap-v2.md` for comprehensive priority queue
- **Key discovery:** Official statusline JSON has `rate_limits` fields — first-to-market opportunity
