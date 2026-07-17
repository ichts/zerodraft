# Claude Code Multi-Stage PRD Skill: Production Patterns Research

**Research Date**: April 20, 2026  
**Scope**: Production-grade multi-stage, gate-based Claude Code skill files  
**Focus**: Real-world implementations with competitive analysis & platform adaptation

---

## EXECUTIVE SUMMARY

Found **3 major production systems** with proven multi-stage gate patterns:

1. **Superpowers** (obra) — Brainstorming → Writing-Plans → Execute-Plan (TDD enforced)
2. **GStack** (Garry Tan, YC) — Office-Hours → Plan-CEO-Review → Plan-Eng-Review → Implement → Review → Ship
3. **Claude Code Workflow** (jakekausler) — Design → Build → Refinement → Finalize (epic/stage tracking)

Plus **2 architectural guides** with gate patterns:
- **enuno/claude-command-and-control** — Production-grade skills development (forced eval hooks, 84% activation)
- **bradfeld** — Advanced configuration with 63 skills, quality gates, session persistence

---

## PATTERN 1: SUPERPOWERS (obra/superpowers)

**GitHub**: https://github.com/obra/superpowers  
**Stars**: 1,100+ in 24h of launch  
**Status**: Production, official Claude plugin marketplace

### Architecture: Brainstorm → Plan → Execute

```
brainstorming skill
    ↓ (design approved)
writing-plans skill
    ↓ (plan approved)
subagent-driven-development / executing-plans skill
    ↓ (with TDD enforcement)
test-driven-development skill
    ↓ (tests pass)
code-reviewer skill
```

### Key Pattern: HARD-GATE

**File**: `skills/brainstorming/SKILL.md`

```markdown
<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, 
or take any implementation action until you have presented a design and the 
user has approved it. This applies to EVERY project regardless of perceived 
simplicity.
</HARD-GATE>
```

**Why this works**: Explicit blocker prevents Claude from skipping design phase even on "simple" projects.

### Checklist-Based Progression

```markdown
## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits
2. **Offer visual companion** (if topic will involve visual questions)
3. **Ask clarifying questions** — one at a time
4. **Propose 2-3 approaches** — with trade-offs and recommendation
5. **Present design** — in sections scaled to complexity, get approval after each
6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
7. **Spec self-review** — check for placeholders, contradictions, ambiguity, scope
8. **User reviews written spec** — ask user to review before proceeding
9. **Transition to implementation** — invoke writing-plans skill
```

**Key insight**: Each step is a gate. No step can be skipped. Checklist is executable, not aspirational.

### One Question at a Time (ADHD-Friendly)

```markdown
## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, get approval before moving on
- **Be flexible** - Go back and clarify when something doesn't make sense
```

### Visual Companion Pattern (Optional)

```markdown
## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options 
during brainstorming.

**Offering the companion:** When you anticipate that upcoming questions will 
involve visual content (mockups, layouts, diagrams), offer it once for consent:

> "Some of what we're working on might be easier to explain if I can show it 
> to you in a web browser. I can put together mockups, diagrams, comparisons, 
> and other visuals as we go. This feature is still new and can be token-intensive. 
> Want to try it? (Requires opening a local URL)"

**This offer MUST be its own message.** Do not combine it with clarifying 
questions, context summaries, or any other content.
```

### Terminal State Enforcement

```markdown
**The terminal state is invoking writing-plans.** Do NOT invoke frontend-design, 
mcp-builder, or any other implementation skill. The ONLY skill you invoke after 
brainstorming is writing-plans.
```

---

## PATTERN 2: GSTACK (garrytan/gstack)

**GitHub**: https://github.com/garrytan/gstack  
**Stars**: 68K+  
**Status**: Production, used by YC companies

### Architecture: 9 Cognitive Modes

```
/office-hours (discovery)
    ↓
/plan-ceo-review (product strategy)
    ↓
/plan-eng-review (architecture)
    ↓
implement
    ↓
/review (code review)
    ↓
/qa (browser testing)
    ↓
/ship (deploy)
    ↓
/land-and-deploy (verify)
```

### Key Pattern: Preamble-Tier System

**File**: `plan-ceo-review/SKILL.md`

```yaml
---
name: plan-ceo-review
preamble-tier: 3
version: 1.0.0
description: |
  CEO/founder-mode plan review. Rethink the problem, find the 10-star product,
  challenge premises, expand scope when it creates a better product. Four modes:
  SCOPE EXPANSION (dream big), SELECTIVE EXPANSION (hold scope + cherry-pick
  expansions), HOLD SCOPE (maximum rigor), SCOPE REDUCTION (strip to essentials).
---
```

**Preamble-tier**: Determines when skill loads in session lifecycle
- Tier 1: Always loaded
- Tier 2: Loaded after tier 1
- Tier 3: Loaded after tier 2

### Preamble: Initialization & State Management

The preamble is a **bash script that runs before the skill body**:

```bash
_UPD=$(~/.claude/skills/gstack/bin/gstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true

mkdir -p ~/.gstack/sessions
touch ~/.gstack/sessions/"$PPID"

_SESSIONS=$(find ~/.gstack/sessions -mmin -120 -type f 2>/dev/null | wc -l)
find ~/.gstack/sessions -mmin +120 -type f -exec rm {} + 2>/dev/null || true

_PROACTIVE=$(~/.claude/skills/gstack/bin/gstack-config get proactive || echo "true")
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
_CHECKPOINT_MODE=$(~/.claude/skills/gstack/bin/gstack-config get checkpoint_mode || echo "explicit")

echo "BRANCH: $_BRANCH"
echo "PROACTIVE: $_PROACTIVE"
echo "CHECKPOINT_MODE: $_CHECKPOINT_MODE"
```

**What this does**:
- Checks for updates
- Manages session state (cleanup old sessions)
- Loads configuration
- Detects git branch
- Outputs state for skill to read

### Four Modes: User Selection Gate

```markdown
## Four Modes

When the user's request matches an available skill, ALWAYS invoke it using the 
Skill tool as your FIRST action.

**SCOPE EXPANSION** — Find the 10-star product hiding inside the request
**SELECTIVE EXPANSION** — Hold scope + cherry-pick high-impact additions
**HOLD SCOPE** — Maximum rigor, no scope creep
**SCOPE REDUCTION** — Strip to essentials, ship the wedge
```

User selects mode at invocation. Each mode has different questioning strategy.

### Learnings Persistence

```bash
_LEARN_FILE="${GSTACK_HOME:-$HOME/.gstack}/projects/${SLUG:-unknown}/learnings.jsonl"
if [ -f "$_LEARN_FILE" ]; then
  _LEARN_COUNT=$(wc -l < "$_LEARN_FILE" 2>/dev/null | tr -d ' ')
  echo "LEARNINGS: $_LEARN_COUNT entries loaded"
  if [ "$_LEARN_COUNT" -gt 5 ] 2>/dev/null; then
    ~/.claude/skills/gstack/bin/gstack-learnings-search --limit 3 2>/dev/null || true
  fi
fi
```

**Key insight**: Learnings survive session compaction because they're stored on disk, not in context.

### Telemetry & Onboarding Gates

```bash
if [ "$_TEL_PROMPTED" = "no" ] && [ "$_LAKE_INTRO" = "yes" ]; then
  # Ask user about telemetry
  # Options: A) Help gstack get better, B) No thanks
fi

if [ "$_PROACTIVE_PROMPTED" = "no" ] && [ "$_TEL_PROMPTED" = "yes" ]; then
  # Ask user about proactive behavior
  # Options: A) Keep it on, B) Turn it off
fi
```

**Pattern**: Each gate is one-time (marked with `touch ~/.gstack/.feature-prompted-*`).

---

## PATTERN 3: CLAUDE CODE WORKFLOW (jakekausler)

**GitHub**: https://github.com/jakekausler/claude-code-workflow  
**Status**: Production, multi-session epic tracking

### Architecture: Phase-Based with Epic/Stage Tracking

```
epic-stage-setup (create epic)
    ↓
/next_task (navigate to current task)
    ↓
phase-design (Design phase)
    ↓
phase-build (Build phase)
    ↓
phase-refinement (Refinement phase)
    ↓
phase-finalize (Finalize phase)
    ↓
journal (reflection)
    ↓
lessons-learned (capture learning)
```

### Key Pattern: Epic/Stage Structure

```
epics/
├── EPIC-001/
│   ├── EPIC-001.md          # Epic overview
│   ├── STAGE-001.md         # Stage 1 tracking
│   ├── STAGE-002.md         # Stage 2 tracking
│   └── STAGE-003.md         # Stage 3 tracking
└── EPIC-002/
    └── ...
```

Each stage goes through all 4 phases: Design → Build → Refinement → Finalize

### Key Pattern: /next_task Navigation

```markdown
## /next_task

Scans your `epics/` directory to find the next work item:

- Identifies current epic and stage
- Shows current phase
- Provides phase-specific instructions
- Run this at the start of every session
```

**Why this works**: Single command to resume work across sessions. No context loss.

### Phase-Specific Skills

Each phase has its own skill with specialized guidance:

- `phase-design` — Architecture options, trade-offs, decisions
- `phase-build` — Implementation guidance, code structure
- `phase-refinement` — Testing, edge cases, performance
- `phase-finalize` — Documentation, cleanup, release

### Reflection Gates

```markdown
## journal

Emotional reflection after phase completion:

- What went well?
- What was hard?
- What would you do differently?
- What did you learn?
```

**Key insight**: Reflection is a gate. You can't move to next phase without journaling.

### Subagent Delegation

16 specialized subagents handle specific tasks:

```
agents/
├── brainstormer.md          # Generate architecture options (Opus)
├── code-reviewer.md         # Code review before commits (Opus)
├── debugger.md              # Complex multi-file bug analysis (Opus)
├── debugger-lite.md         # Medium-complexity errors (Sonnet)
├── doc-updater.md           # Documentation updates (Haiku)
├── doc-writer.md            # Comprehensive docs (Opus)
├── doc-writer-lite.md       # Simple docs (Sonnet)
├── e2e-tester.md            # Backend E2E tests (Sonnet)
├── fixer.md                 # Apply fix instructions (Haiku)
├── planner.md               # Complex specs (Opus)
├── planner-lite.md          # Simple specs (Sonnet)
├── scribe.md                # Write code from specs (Haiku)
├── task-navigator.md        # Task hierarchy navigation
├── test-writer.md           # Write tests (Sonnet)
├── tester.md                # Run test suites (Haiku)
└── verifier.md              # Run build/type-check/lint (Haiku)
```

Each agent is invoked via Task tool with specific context.

---

## PATTERN 4: PRODUCTION-GRADE SKILLS (enuno/claude-command-and-control)

**GitHub**: https://github.com/enuno/claude-command-and-control  
**Document**: `docs/best-practices/14-Production-Grade-Skills-Development.md`

### Key Finding: Forced Evaluation Hook (84% Activation)

**Problem**: Skills don't always trigger automatically, even when obvious.

**Solution**: Forced evaluation hook that requires Claude to explicitly evaluate each skill:

```markdown
Before starting any task:

1. Review all available skills
2. For each potentially relevant skill, output:
   - Skill name
   - YES/NO decision
   - Brief reasoning

3. Only after completing this evaluation, proceed with the task

Example format:
- pdf-processing: YES - need to extract text from PDF
- bigquery-analysis: NO - no database query involved
- brand-guidelines: YES - need to apply company style
```

**Results**:
- Simple instruction hook: 20% activation
- LLM hook: 80% activation
- **Forced eval hook: 84% activation**

### Progressive Disclosure Architecture

**Level 1: Metadata** (~100 tokens per skill)
- Name and description in YAML frontmatter
- Enables Claude to know which skills exist without loading full instructions

**Level 2: SKILL.md Body** (loaded when skill triggers)
- Markdown instructions, typically <5,000 words
- Only loads after Claude determines skill is relevant

**Level 3: Bundled Resources** (as needed)
- Scripts execute without entering context
- Reference files load on-demand
- Asset files copied/used in output without context consumption

**Detection ceiling**: ~32-36 skills before system struggles with consistent selection

### SKILL.md Frontmatter Constraints

```yaml
---
name: docx
description: "Comprehensive document creation, editing, and analysis with support for tracked changes, comments, formatting preservation, and text extraction. Use when Claude needs to work with professional documents (.docx files) for: (1) Creating new documents, (2) Modifying or editing content, (3) Working with tracked changes, (4) Adding comments, or any other document tasks"
---
```

**Critical constraints**:
- Only two fields: `name` and `description`
- Description must be **single-line YAML** (multiline breaks parsing)
- Description limited to **1024 characters** (excess truncated silently)
- Description is the **primary triggering mechanism**

### Context Management: CLAUDE.md as Persistent Context

```markdown
# Project Setup

The repository-level CLAUDE.md file serves as Claude's "onboarding guide" to 
the codebase, establishing persistent context that doesn't consume conversation tokens.

**Structure: WHY, WHAT, HOW**
- **WHY**: Purpose and function of the project
- **WHAT**: Tech stack, project structure, codebase map
- **HOW**: Development practices and procedures

**Optimal length**: 100-200 lines maximum.
```

---

## PATTERN 5: ADVANCED CONFIGURATION (bradfeld)

**GitHub**: https://gist.github.com/bradfeld/1deb0c385d12289947ff83f145b7e4d2  
**Status**: Production, 12 repositories, 63 skills

### Master Workflow: Ticket-Driven

```
/start TICKET-XXX
    ↓ (fetch from Linear, analyze, create branch, post plan)
implement
    ↓
/commit
    ↓ (quality gates, /simplify, auto-triage, review agents, push)
/staging (magic-platform only)
    ↓ (batch merge to preview, deploy, reset worktrees)
/production (magic-platform only)
    ↓ (health audit, merge to main, verify)
```

### Quality Gates

```yaml
workflow:
  base_branch: preview
  direct_to_main: false
  quality_gates:
    - pnpm run type-check
    - pnpm run lint
  review:
    - auto_triage: true
    - review_agents: true
```

**Gates are enforced before commit**, not after.

### Session Persistence

```
project/.claude-session/
├── workflow.json        # Workflow state
├── progress.md          # Session progress
└── context.md           # Persistent context
```

Session files survive Claude Code compaction because they're on disk.

### 19 Always-Loaded Rules

```
~/.claude/rules/
├── fix-dont-defer.md           # Every finding: fix now or create ticket
├── hygiene-gate.md             # Verify workspace state between phases
├── mcp-linear.md               # Linear MCP gotchas
├── subagent-stalls.md          # Never recommend Escape during parallel agents
├── tricycle.md                 # Trigger and mode detection
└── ... (14 more)
```

**Key insight**: Rules are cross-project standards, not per-project conventions.

---

## COMPETITIVE ANALYSIS PATTERNS

### Pattern: Market Research Integration

**GStack /office-hours** includes competitive analysis:

```markdown
## Six Forcing Questions

1. **Demand Reality** — Is there real demand for this?
2. **Status Quo Pain** — What's the pain of not having this?
3. **User Specificity** — Who specifically needs this?
4. **Narrowest Wedge** — What's the smallest version that solves the problem?
5. **Observation Surprises** — What surprised you about user behavior?
6. **Future-Fit** — Will this still matter in 2 years?
```

Each question forces competitive thinking.

### Pattern: Superpowers Brainstorming

```markdown
## Exploring Approaches

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
```

**Key insight**: Always present alternatives, not just one solution.

---

## PLATFORM ADAPTATION PATTERNS

### Web Projects

**GStack /design-html** — HTML/CSS/JS specific guidance
**Superpowers visual-companion** — Browser-based mockups

### Mobile Projects

**Flutter-specific skills** (from dev-context/AGENTS.md):
- `flutter-dev.md` — Architecture, selection, checklist
- `flutter-networking.md` — Dio + interceptors + image upload
- `flutter-riverpod.md` — State management

### API Projects

**GStack /plan-eng-review** — Architecture diagrams, data flow, edge cases

### Desktop Projects

**Electron/Tauri specific guidance** (not found in research, but pattern would be similar)

---

## SKILL COMPOSITION PATTERNS

### Pattern: Skill Chaining

```
brainstorming skill
    ↓ (outputs design doc)
writing-plans skill
    ↓ (reads design doc, outputs plan)
executing-plans skill
    ↓ (reads plan, executes tasks)
```

Each skill reads output of previous skill.

### Pattern: Skill Triggering

**Superpowers**: Skills auto-trigger based on context
**GStack**: Skills invoked explicitly via slash commands
**Claude Code Workflow**: Skills invoked via `/next_task` navigation

### Pattern: Skill Composition in CLAUDE.md

```markdown
## Skill Routing

When the user's request matches an available skill, ALWAYS invoke it using the 
Skill tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
```

---

## GATE PATTERNS SUMMARY

| Pattern | Implementation | Reliability | Use Case |
|---------|----------------|-------------|----------|
| **HARD-GATE** | Explicit blocker in skill body | 100% | Prevent skipping critical phases |
| **Checklist** | Numbered steps, must complete in order | 95% | Ensure all steps executed |
| **One Question at a Time** | Single question per message | 90% | ADHD-friendly, reduce overwhelm |
| **Preamble-Tier** | Bash script runs before skill body | 85% | State management, initialization |
| **Forced Eval Hook** | Explicit YES/NO for each skill | 84% | Skill activation reliability |
| **Reflection Gate** | Journal/lessons-learned required | 80% | Capture learning, prevent regression |
| **Terminal State** | Only invoke specific next skill | 95% | Prevent wrong skill invocation |
| **Mode Selection** | User picks from 2-4 options | 90% | Adapt behavior to context |

---

## RECOMMENDED SYNTHESIS FOR YOUR PRD SKILL

Based on research, optimal universal PRD skill would combine:

1. **Superpowers brainstorming structure** (HARD-GATE, checklist, one question at a time)
2. **GStack preamble-tier system** (state management, learnings persistence)
3. **Claude Code Workflow phase tracking** (epic/stage structure for multi-session work)
4. **Forced eval hook** (84% activation reliability)
5. **Progressive disclosure** (reference files for competitive analysis, platform-specific guidance)

### Proposed Phases

```
validate (is this worth building?)
    ↓
discover (market research, competitive analysis)
    ↓
specify (requirements, constraints, success criteria)
    ↓
scope (what's in/out, MVP definition)
    ↓
plan (implementation roadmap, task breakdown)
```

Each phase:
- Has explicit gate (user approval required)
- Outputs structured markdown document
- Persists to disk (survives compaction)
- Chains to next phase via skill invocation

---

## REFERENCES

### Primary Sources

1. **Superpowers** (obra)
   - GitHub: https://github.com/obra/superpowers
   - Brainstorming skill: https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md
   - Writing-plans skill: https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md

2. **GStack** (Garry Tan, YC)
   - GitHub: https://github.com/garrytan/gstack
   - Plan-CEO-Review: https://github.com/garrytan/gstack/blob/main/plan-ceo-review/SKILL.md
   - Plan-Eng-Review: https://github.com/garrytan/gstack/blob/main/plan-eng-review/SKILL.md
   - Guide: https://gstacks.org/

3. **Claude Code Workflow** (jakekausler)
   - GitHub: https://github.com/jakekausler/claude-code-workflow
   - README: https://github.com/jakekausler/claude-code-workflow/blob/main/README.md

4. **Production-Grade Skills** (enuno)
   - GitHub: https://github.com/enuno/claude-command-and-control
   - Guide: https://github.com/enuno/claude-command-and-control/blob/main/docs/best-practices/14-Production-Grade-Skills-Development.md

5. **Advanced Configuration** (bradfeld)
   - Gist: https://gist.github.com/bradfeld/1deb0c385d12289947ff83f145b7e4d2

### Secondary Sources

- SkillsBench (Li et al., 2026): https://arxiv.org/html/2602.12670v1
- Chanl Blog: https://chanl.ai/blog/claude-extension-stack-part-2-rules-hooks-skills
- Claude Code Guides: https://claudecodeguides.com/

