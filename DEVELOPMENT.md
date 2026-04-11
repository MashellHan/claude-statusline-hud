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
- Commit and push changes with conventional commit messages
- Follow the priority queue in the latest review document
- Respond to CRITICAL items before starting new features

**Input:** `.review/review-NNN.md` action items  
**Output:** Code commits on `main` branch

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

## Current Status

- **Reviews completed:** 8 (001-008)
- **Overall score:** 8.5/10 (trending up from 7.0)
- **Features done:** 5 of 15 (daily tracking, git state, burn rate, token fix, layout)
- **Next priority:** Autocompact countdown (P1), cost budget alerts (P1)
