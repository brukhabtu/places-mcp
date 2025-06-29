#!/bin/bash
# Daily standup report

echo "=== Daily Standup Report ==="
echo "Date: $(date)"
echo ""

echo "## My Issues In Progress"
gh issue list --label "in-progress" --assignee @me
echo ""

echo "## Blocked Issues"
gh issue list --label "blocked"
echo ""

echo "## Recently Completed (Last 3 days)"
gh issue list --state closed --limit 5 --assignee @me --search "closed:>$(date -d '3 days ago' +%Y-%m-%d)"
echo ""

echo "## Sprint Progress"
./scripts/sprint-velocity.sh 1
