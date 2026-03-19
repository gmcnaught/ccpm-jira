# Sync — Push to Jira & Track Progress

This phase covers pushing local epics/tasks to Jira as issues, syncing progress as comments, and closing issues when work is done.

All Jira operations use the Atlassian MCP tools (`mcp__plugin_atlassian_atlassian__*`).

---

## Jira Config Preflight

**Run before any Jira write operation.**

1. Read `.claude/jira-config.md` — extract `project_key` and `base_url`.
2. If the file is missing or incomplete:
   - Call `mcp__plugin_atlassian_atlassian__getAllProjects` to list available projects.
   - Ask the user: "Which Jira project should I sync to? (e.g., PROJ)"
   - Create `.claude/jira-config.md`:
     ```markdown
     ---
     project_key: PROJ
     base_url: https://yourorg.atlassian.net
     epic_issue_type: Epic
     task_issue_type: Story
     bug_issue_type: Bug
     ---
     ```

---

## ADF Helper

Jira's description and comment fields require Atlassian Document Format (ADF). Wrap body text as:

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {
      "type": "paragraph",
      "content": [{ "type": "text", "text": "<body content here>" }]
    }
  ]
}
```

For multi-section content, use one paragraph node per section. Preserve the full body text.

---

## Epic Sync — Push Epic + Tasks to Jira

**Trigger**: User wants to push a local epic and its tasks to Jira as issues.

### Preflight
- Run Jira Config Preflight above.
- Verify `.claude/epics/<name>/epic.md` exists.
- Verify numbered task files exist — if none: "❌ No tasks to sync. Decompose the epic first."
- Get issue type IDs: call `mcp__plugin_atlassian_atlassian__getCreateIssueMetaIssueTypes` with `projectIdOrKey: "<PROJ>"`. Find the IDs for Epic, Story (or Task), and Bug types.

### Process

**Step 1 — Create epic issue:**

Strip frontmatter from `epic.md` to get body content. Call `mcp__plugin_atlassian_atlassian__createIssue`:
```json
{
  "fields": {
    "project": { "key": "<PROJ>" },
    "summary": "Epic: <name>",
    "description": { "<ADF body>" },
    "issuetype": { "name": "Epic" },
    "labels": ["epic", "feature"]
  }
}
```

Capture the returned `key` (e.g., `PROJ-123`) — this is the epic Jira key.

**Step 2 — Create task sub-issues:**

For <5 tasks: create sequentially.
For ≥5 tasks: use parallel Task agents (3–4 tasks per batch).

Per task — strip frontmatter, then call `mcp__plugin_atlassian_atlassian__createIssue`:
```json
{
  "fields": {
    "project": { "key": "<PROJ>" },
    "summary": "<task_name>",
    "description": { "<ADF body>" },
    "issuetype": { "name": "Story" },
    "parent": { "key": "<epic_key>" },
    "labels": ["task"]
  }
}
```

Capture each returned `key` (e.g., `PROJ-124`).

**Step 3 — Rename task files and update references:**

After all issues are created, build the old→new mapping (e.g., `001` → `124`).
Use the **numeric part only** of each Jira key for the filename (e.g., `PROJ-124` → `124.md`).

```bash
# For each task, extract numeric part and rename:
mv .claude/epics/<name>/001.md .claude/epics/<name>/124.md
# Update depends_on arrays in all task files to use new numbers
sed -i.bak "s/\b001\b/124/g" .claude/epics/<name>/*.md
rm .claude/epics/<name>/*.bak
```

**Step 4 — Update frontmatter:**
```bash
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# In epic.md:
sed -i.bak "/^jira:/c\\jira: <base_url>/browse/<epic_key>" .claude/epics/<name>/epic.md
sed -i.bak "/^updated:/c\\updated: $current_date" .claude/epics/<name>/epic.md
rm .claude/epics/<name>/epic.md.bak

# In each task file:
sed -i.bak "/^jira:/c\\jira: <base_url>/browse/<task_key>" <task_file>
sed -i.bak "/^updated:/c\\updated: $current_date" <task_file>
rm <task_file>.bak
```

**Step 5 — Create worktree for the epic:**
```bash
git checkout main && git pull origin main
git worktree add ../epic-<name> -b epic/<name>
```

**Step 6 — Create jira-mapping.md:**
```markdown
# Jira Issue Mapping
Epic: <epic_key> - <base_url>/browse/<epic_key>
Tasks:
- <PROJ-N>: <title> - <base_url>/browse/<PROJ-N>
Synced: <datetime>
```

**Output:**
```
✅ Synced epic <name> to Jira
  Epic: <epic_key>
  Tasks: N sub-issues
  Worktree: ../epic-<name>
  Next: "start working on <epic_key>" or "start the <name> epic"
```

---

## Issue Sync — Post Progress to Jira

**Trigger**: User wants to sync local development progress to a Jira issue as a comment.

### Preflight
- Extract Jira key from task file: `grep 'jira:' <file> | grep -oE '[A-Z]+-[0-9]+'`
- Call `mcp__plugin_atlassian_atlassian__getIssue` with `issueIdOrKey: "<key>"` to confirm the issue exists.
- Check `.claude/epics/*/updates/<N>/` exists with a `progress.md` file.
- Check `last_sync` in progress.md — if synced <5 minutes ago, confirm before proceeding.

### Process

Gather updates from `.claude/epics/<epic>/updates/<N>/` (progress.md, notes.md, commits.md).

Format the comment body and call `mcp__plugin_atlassian_atlassian__addComment`:
```json
{
  "issueIdOrKey": "<jira_key>",
  "body": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "heading",
        "attrs": { "level": 2 },
        "content": [{ "type": "text", "text": "Progress Update - <date>" }]
      },
      {
        "type": "paragraph",
        "content": [{ "type": "text", "text": "✅ Completed Work\n<details>\n\n🔄 In Progress\n<details>\n\n📝 Technical Notes\n<details>\n\n📊 Acceptance Criteria Status\n<details>\n\n🚀 Next Steps\n<details>\n\n⚠️ Blockers\n<details>" }]
      },
      {
        "type": "paragraph",
        "content": [{ "type": "text", "text": "Progress: N% | Synced at <timestamp>" }]
      }
    ]
  }
}
```

After posting: update `last_sync` in progress.md frontmatter, update `updated` in the task file.

Add sync marker to local files to prevent duplicate comments:
```markdown
<!-- SYNCED: <datetime> -->
```

---

## Closing an Issue

**Trigger**: User marks a task complete.

### Process

1. Find the local task file (`.claude/epics/*/<N>.md`).
2. Extract Jira key: `grep 'jira:' <file> | grep -oE '[A-Z]+-[0-9]+'`
3. Update frontmatter: `status: closed`, `updated: <now>`.
4. Get available transitions: call `mcp__plugin_atlassian_atlassian__getTransitions` with `issueIdOrKey: "<key>"`.
5. Find the transition with name matching "Done" (or "Resolved", "Closed" — pick the terminal state).
6. Post completion comment via `mcp__plugin_atlassian_atlassian__addComment`:
   ```json
   {
     "issueIdOrKey": "<key>",
     "body": {
       "type": "doc", "version": 1,
       "content": [{"type": "paragraph", "content": [{"type": "text", "text": "✅ Task completed — all acceptance criteria met."}]}]
     }
   }
   ```
7. Transition to Done: call `mcp__plugin_atlassian_atlassian__doTransition`:
   ```json
   { "issueIdOrKey": "<key>", "transition": { "id": "<done_transition_id>" } }
   ```
8. Update the epic issue's description to check off the task. Get the epic Jira key from `epic.md` frontmatter, then call `mcp__plugin_atlassian_atlassian__editIssue` to update the description.
9. Recalculate and update epic progress: `progress = closed_tasks / total_tasks * 100`

---

## Merging an Epic

**Trigger**: User wants to merge a completed epic back to main.

### Preflight
- Verify worktree `../epic-<name>` exists.
- Check for uncommitted changes in the worktree — block if dirty.
- Warn if any task issues still have non-Done status in Jira (check local task files for `status: closed`).

### Process

```bash
# From worktree: run project tests if detectable
cd ../epic-<name>
# detect and run: npm test / pytest / cargo test / go test / etc.

# From main repo:
git checkout main && git pull origin main
git merge epic/<name> --no-ff -m "Merge epic: <name>"
git push origin main

# Cleanup
git worktree remove ../epic-<name>
git branch -d epic/<name>
git push origin --delete epic/<name>

# Archive
mkdir -p .claude/epics/archived/
mv .claude/epics/<name> .claude/epics/archived/
```

Close the Jira epic:
1. Get epic Jira key from `.claude/epics/archived/<name>/epic.md`.
2. Get transitions: `mcp__plugin_atlassian_atlassian__getTransitions`.
3. Transition to Done: `mcp__plugin_atlassian_atlassian__doTransition`.
4. Add final comment: "Epic completed and merged to main."

Update epic.md frontmatter: `status: completed`.

---

## Reporting a Bug Against a Completed Issue

**Trigger**: User finds a bug while testing a completed or in-progress issue — e.g. "found a bug in PROJ-123", "email validation is broken, came up while testing PROJ-123".

### Process

**Step 1 — Read the original issue for context:**

Call `mcp__plugin_atlassian_atlassian__getIssue` with `issueIdOrKey: "<original_key>"`.
Also read the local task file if it exists: `.claude/epics/*/<N>.md` (where N is the numeric part of the key).

**Step 2 — Create a local bug task file:**

```markdown
---
name: Bug: <short description>
status: open
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
updated: <same>
jira: (will be set on sync)
depends_on: []
parallel: false
conflicts_with: []
bug_for: <original_N>
---

# Bug: <short description>

## Context
Found while working on / testing <original_key>: <original title>

## Description
<what's broken>

## Steps to Reproduce
<steps>

## Expected vs Actual
- Expected:
- Actual:

## Acceptance Criteria
- [ ] Bug is fixed
- [ ] Original issue <original_key> behaviour is unaffected

## Effort Estimate
- Size: XS/S
```

Save to `.claude/epics/<same_epic_as_original>/bug-<original_N>-<slug>.md`

**Step 3 — Create a linked Jira bug issue:**

Run Jira Config Preflight, then call `mcp__plugin_atlassian_atlassian__createIssue`:
```json
{
  "fields": {
    "project": { "key": "<PROJ>" },
    "summary": "Bug: <short description>",
    "description": {
      "type": "doc", "version": 1,
      "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Follow-up to <original_key>: <original_title>\n\n<bug description>"}]}]
    },
    "issuetype": { "name": "Bug" },
    "labels": ["bug"]
  }
}
```

**Step 4 — Update the local file** with the Jira key and rename: `bug-<original_N>-<slug>.md` → `<new_N>.md` (using numeric part of new Jira key).

Update `jira:` frontmatter with the full URL.

**Output:**
```
✅ Bug issue created: <new_key> — "Bug: <short description>"
  Linked to: <original_key>
  Epic: <epic_name>

Start fixing it: "start working on <new_key>"
```
