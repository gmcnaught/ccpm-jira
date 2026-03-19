#!/bin/bash

echo "Initializing..."
echo ""
echo ""

echo " ██████╗ ██████╗██████╗ ███╗   ███╗"
echo "██╔════╝██╔════╝██╔══██╗████╗ ████║"
echo "██║     ██║     ██████╔╝██╔████╔██║"
echo "╚██████╗╚██████╗██║     ██║ ╚═╝ ██║"
echo " ╚═════╝ ╚═════╝╚═╝     ╚═╝     ╚═╝"

echo "┌─────────────────────────────────┐"
echo "│ Claude Code Project Management  │"
echo "│ by https://x.com/aroussi        │"
echo "└─────────────────────────────────┘"
echo "https://github.com/automazeio/ccpm"
echo ""
echo ""

echo "🚀 Initializing Claude Code PM System"
echo "======================================"
echo ""

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p .claude/prds
mkdir -p .claude/epics
mkdir -p .claude/rules
mkdir -p .claude/agents
mkdir -p .claude/scripts/pm
echo "  ✅ Directories created"

# Copy scripts if in main repo
if [ -d "scripts/pm" ] && [ ! "$(pwd)" = *"/.claude"* ]; then
  echo ""
  echo "📝 Copying PM scripts..."
  cp -r scripts/pm/* .claude/scripts/pm/
  chmod +x .claude/scripts/pm/*.sh
  echo "  ✅ Scripts copied and made executable"
fi

# Check for git
echo ""
echo "🔗 Checking Git configuration..."
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo "  ✅ Git repository detected"

  if git remote -v | grep -q origin; then
    remote_url=$(git remote get-url origin)
    echo "  ✅ Remote configured: $remote_url"
  else
    echo "  ⚠️ No remote configured"
    echo "  Add with: git remote add origin <url>"
  fi
else
  echo "  ⚠️ Not a git repository"
  echo "  Initialize with: git init"
fi

# Check for Jira config
echo ""
echo "🔧 Checking Jira configuration..."
if [ -f ".claude/jira-config.md" ]; then
  project_key=$(grep "^project_key:" .claude/jira-config.md | sed 's/^project_key: *//')
  base_url=$(grep "^base_url:" .claude/jira-config.md | sed 's/^base_url: *//')
  echo "  ✅ Jira config found"
  echo "     Project: $project_key"
  echo "     URL: $base_url"
else
  echo "  ⚠️ No Jira config found"
  echo ""
  echo "  To configure Jira, create .claude/jira-config.md:"
  cat << 'JIRA_CONFIG'
---
project_key: PROJ
base_url: https://yourorg.atlassian.net
epic_issue_type: Epic
task_issue_type: Story
bug_issue_type: Bug
---
JIRA_CONFIG
  echo ""
  echo "  Or say: 'sync the <epic> epic to Jira' and the config will be created interactively."
fi

# Create CLAUDE.md if it doesn't exist
if [ ! -f "CLAUDE.md" ]; then
  echo ""
  echo "📄 Creating CLAUDE.md..."
  cat > CLAUDE.md << 'EOF'
# CLAUDE.md

> Think carefully and implement the most concise solution that changes as little code as possible.

## Project-Specific Instructions

Add your project-specific instructions here.

## Testing

Always run tests before committing:
- `npm test` or equivalent for your stack

## Code Style

Follow existing patterns in the codebase.
EOF
  echo "  ✅ CLAUDE.md created"
fi

# Summary
echo ""
echo "✅ Initialization Complete!"
echo "=========================="
echo ""
echo "🎯 Next Steps:"
echo "  1. Create your first PRD: 'create a PRD for <feature-name>'"
echo "  2. Check status: 'what's our status'"
echo "  3. Configure Jira: create .claude/jira-config.md with your project key"
echo ""
echo "📚 Documentation: README.md"

exit 0
