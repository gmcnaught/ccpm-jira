# Execute — Start Building with Parallel Agents

This phase covers analyzing Jira issues for parallel work streams and launching agents to execute them.

---

## Issue Analysis

**Trigger**: User wants to understand how to parallelize work on an issue before starting.

### Preflight
- The user provides a Jira key (e.g., `PROJ-123`). Extract the numeric part (`123`) to find the local task file: check `.claude/epics/*/123.md`, then search for `jira:.*PROJ-123` in frontmatter.
- If not found: "❌ No local task for <key>. Run a sync first."

### Process

Get issue details: call `mcp__plugin_atlassian_atlassian__getIssue` with `issueIdOrKey: "<key>"`.

Read the local task file fully. Identify independent work streams by asking:
- Which files will be created/modified?
- Which changes can happen simultaneously without conflict?
- What are the dependencies between changes?

**Common stream patterns:**
- Database Layer: schema, migrations, models
- Service Layer: business logic, data access
- API Layer: endpoints, validation, middleware
- UI Layer: components, pages, styles
- Test Layer: unit tests, integration tests

Create `.claude/epics/<epic_name>/<numeric_N>-analysis.md` (using the numeric part of the Jira key):

```markdown
---
issue: <N>
title: <title>
analyzed: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
estimated_hours: <total>
parallelization_factor: <1.0-5.0>
---

# Parallel Work Analysis: Issue #<N>

## Overview

## Parallel Streams

### Stream A: <Name>
**Scope**: 
**Files**: 
**Can Start**: immediately
**Estimated Hours**: 
**Dependencies**: none

### Stream B: <Name>
**Scope**: 
**Files**: 
**Can Start**: after Stream A
**Dependencies**: Stream A

## Coordination Points
### Shared Files
### Sequential Requirements

## Conflict Risk Assessment

## Parallelization Strategy

## Expected Timeline
- With parallel execution: <max_stream_hours>h wall time
- Without: <sum_all_hours>h
- Efficiency gain: <pct>%
```

**Output**: "✅ Analysis complete for <jira_key> — N parallel streams identified. Ready to start? Say: start <jira_key>"

---

## Starting an Issue

**Trigger**: User wants to begin work on a specific Jira issue.

### Preflight
1. Verify issue exists and is open: call `mcp__plugin_atlassian_atlassian__getIssue` with `issueIdOrKey: "<key>"`, check the status is not Done/Closed.
2. Find local task file (as above) — use the numeric part of the key for the filename.
3. Check for analysis file: `.claude/epics/*/<numeric_N>-analysis.md` — if missing, run analysis first (or do both in sequence: analyze then start).
4. Verify epic worktree exists: `git worktree list | grep "epic-<name>"` — if not: "❌ No worktree. Sync the epic first."

### Process

**Step 1 — Read the analysis**, identify which streams can start immediately vs. which have dependencies.

**Step 2 — Create progress tracking:**
```bash
mkdir -p .claude/epics/<epic>/updates/<numeric_N>
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

Create `.claude/epics/<epic>/updates/<numeric_N>/stream-<X>.md` for each stream:
```markdown
---
issue: <N>
stream: <stream_name>
started: <datetime>
status: in_progress
---
## Scope
## Progress
- Starting implementation
```

**Step 3 — Launch parallel agents** for each stream that can start immediately:

```yaml
Task:
  description: "<jira_key> Stream <X>"
  subagent_type: "general-purpose"
  prompt: |
    You are working on <jira_key> in the epic worktree at: ../epic-<name>/

    Your stream: <stream_name>
    Your scope — files to modify: <file_patterns>
    Work to complete: <stream_description>

    Instructions:
    1. Read full task from: .claude/epics/<epic>/<numeric_N>.md
    2. Read analysis from: .claude/epics/<epic>/<numeric_N>-analysis.md
    3. Work ONLY in your assigned files
    4. Commit frequently: "<jira_key>: <specific change>"
    5. Update progress in: .claude/epics/<epic>/updates/<numeric_N>/stream-<X>.md
    6. If you need to touch files outside your scope, note it in your progress file and wait
    7. Never use --force on git operations

    Complete your stream's work and mark status: completed when done.
```

Streams with unmet dependencies are queued — launch them as their dependencies complete.

**Step 4 — Assign and transition in Jira:**

Get current user: call `mcp__plugin_atlassian_atlassian__getCurrentUser` to get `accountId`.

Assign the issue: call `mcp__plugin_atlassian_atlassian__editIssue`:
```json
{ "issueIdOrKey": "<key>", "fields": { "assignee": { "accountId": "<accountId>" } } }
```

Transition to In Progress: call `mcp__plugin_atlassian_atlassian__getTransitions` then `mcp__plugin_atlassian_atlassian__doTransition` with the "In Progress" transition ID.

**Step 5 — Create execution status file** at `.claude/epics/<epic>/updates/<numeric_N>/execution.md`:
```markdown
## Active Streams
- Stream A: <name> — Started <time>
- Stream B: <name> — Started <time>

## Queued
- Stream C: <name> — Waiting on Stream A

## Completed
(none yet)
```

**Output:**
```
✅ Started work on <jira_key>

Launched N agents:
  Stream A: <name> ✓ Started
  Stream B: <name> ✓ Started
  Stream C: <name> ⏸ Waiting (depends on A)

Monitor: check progress in .claude/epics/<epic>/updates/<numeric_N>/
Sync updates: "sync <jira_key>"
```

---

## Starting a Full Epic

**Trigger**: User wants to launch parallel agents across all ready issues in an epic at once.

### Preflight
- Verify `.claude/epics/<name>/epic.md` exists and has a `jira:` field (i.e., it's been synced).
- Check for uncommitted changes: `git status --porcelain` — block if dirty.
- Verify epic branch exists: `git branch -a | grep "epic/<name>"`

### Process

**Step 1 — Read all task files** in `.claude/epics/<name>/`. Parse frontmatter for `status`, `depends_on`, `parallel`.

**Step 2 — Categorize tasks:**
- Ready: status=open, no unmet depends_on
- Blocked: has unmet depends_on
- In Progress: already has an execution file
- Complete: status=closed

**Step 3 — Analyze any ready tasks** that don't have an analysis file yet (run issue analysis inline).

**Step 4 — Launch agents** for all ready tasks following the same per-issue agent launch pattern above.

**Step 5 — Create/update** `.claude/epics/<name>/execution-status.md` with all active agents and queued issues.

**Step 6 — As agents complete**, check if blocked issues are now unblocked and launch those agents.

---

## Agent Coordination Rules

When multiple agents work in the same worktree simultaneously:

- Each agent works only on files in its assigned stream scope.
- Agents commit frequently with `Issue #<N>: <description>` format.
- Before modifying a shared file, check `git status <file>` — if another agent has it modified, wait and pull first.
- Agents sync via commits: `git pull --rebase origin epic/<name>` before starting new file work.
- Conflicts are never auto-resolved — agents report them and pause.
- No `--force` flags ever.

Shared files that commonly need coordination (types, config, package.json) should be handled by one designated stream; others pull after that commit.
