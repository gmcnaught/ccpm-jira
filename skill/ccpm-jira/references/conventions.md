# Conventions — File Formats, Paths & Rules

Read this before doing any file operations across all phases.

---

## Directory Structure

```
.claude/
├── prds/
│   └── <feature-name>.md          # Product requirement documents
├── epics/
│   ├── <feature-name>/
│   │   ├── epic.md                # Technical epic
│   │   ├── <N>.md                 # Task files (named by Jira issue number after sync)
│   │   ├── <N>-analysis.md        # Parallel work stream analysis
│   │   ├── jira-mapping.md        # Issue key → URL mapping
│   │   ├── execution-status.md    # Active agents tracker
│   │   └── updates/
│   │       └── <issue_N>/
│   │           ├── stream-A.md    # Per-agent progress
│   │           ├── progress.md    # Overall issue progress
│   │           └── execution.md  # Execution state
│   └── archived/
│       └── <feature-name>/        # Completed epics
├── jira-config.md                 # Jira project config (project key, base URL)
└── context/                       # Project context docs (separate system)
```

---

## Frontmatter Schemas

### PRD (.claude/prds/<name>.md)
```yaml
---
name: <feature-name>        # kebab-case, matches filename
description: <one-liner>    # used in lists and summaries
status: backlog | active | completed
created: <ISO 8601>         # date -u +"%Y-%m-%dT%H:%M:%SZ"
---
```

### Epic (.claude/epics/<name>/epic.md)
```yaml
---
name: <feature-name>
status: backlog | in-progress | completed
created: <ISO 8601>
updated: <ISO 8601>
progress: 0%                # recalculated when tasks close
prd: .claude/prds/<name>.md
jira: https://<org>.atlassian.net/browse/<PROJ-N>  # set on sync
---
```

### Task (.claude/epics/<name>/<N>.md)
```yaml
---
name: <Task Title>
status: open | in-progress | closed
created: <ISO 8601>
updated: <ISO 8601>
jira: https://<org>.atlassian.net/browse/<PROJ-N>  # set on sync
depends_on: []              # issue numbers this must wait for
parallel: true              # can run concurrently with non-conflicting tasks
conflicts_with: []          # issue numbers that touch the same files
---
```

### Progress (.claude/epics/<name>/updates/<N>/progress.md)
```yaml
---
issue: <N>
started: <ISO 8601>
last_sync: <ISO 8601>
completion: 0%
---
```

---

## Datetime Rule

Always get real current datetime from the system — never use placeholder text:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

---

## Frontmatter Update Pattern

When updating a single frontmatter field in an existing file:
```bash
sed -i.bak "/^<field>:/c\\<field>: <value>" <file>
rm <file>.bak
```

When stripping frontmatter to get body content for Jira:
```bash
sed '1,/^---$/d; 1,/^---$/d' <file> > /tmp/body.md
```

---

## Jira Operations

### Project Config Preflight (run before any Jira write operation)

Check `.claude/jira-config.md` exists and has `project_key` and `base_url` set.

If missing, call `mcp__plugin_atlassian_atlassian__getAllProjects` to list available projects, ask the user to confirm the project, then create the config file:
```markdown
---
project_key: PROJ
base_url: https://yourorg.atlassian.net
epic_issue_type: Epic
task_issue_type: Story
bug_issue_type: Bug
---
```

### Authentication
Jira operations use the configured Atlassian MCP plugin. If tool calls fail, ask the user to verify the MCP server is configured and authenticated.

### Getting Jira Keys
```bash
# From a task file's jira field (extracts key like PROJ-123):
grep 'jira:' <file> | grep -oE '[A-Z]+-[0-9]+'
```

### Issue Type IDs
Before creating issues, get issue type IDs for the project:
Call `mcp__plugin_atlassian_atlassian__getCreateIssueMetaIssueTypes` with `projectIdOrKey: "<PROJ>"`.
Cache the IDs in memory for the current operation — do not re-fetch per task.

### Current User
Call `mcp__plugin_atlassian_atlassian__getCurrentUser` once to get your `accountId` for assignee operations.

---

## Git / Worktree Conventions

- One branch per epic: `epic/<name>`
- Worktrees live at `../epic-<name>/` (sibling to project root)
- Always start branches from an up-to-date main:
  ```bash
  git checkout main && git pull origin main
  git worktree add ../epic-<name> -b epic/<name>
  ```
- Commit format inside epics: `Issue #<N>: <description>`
- Never use `--force` in any git operation

---

## Naming Conventions

- Feature names: kebab-case, lowercase, letters/numbers/hyphens, starts with a letter
- Task files before sync: `001.md`, `002.md`, ... (sequential)
- Task files after sync: renamed to Jira issue number (e.g., `1234.md` for `PROJ-1234`; use the numeric part only to preserve script compatibility)
- Labels applied on sync: `epic`, `epic-<name>`, `feature` (for epics); `task`, `epic-<name>` (for tasks)

---

## Epic Progress Calculation

```bash
total=$(ls .claude/epics/<name>/[0-9]*.md 2>/dev/null | wc -l)
closed=$(grep -l '^status: closed' .claude/epics/<name>/[0-9]*.md 2>/dev/null | wc -l)
progress=$((closed * 100 / total))
```

Update epic frontmatter when any task closes.
