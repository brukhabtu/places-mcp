#!/bin/bash
# Track sprint velocity

SPRINT=${1:-1}
MILESTONE="Sprint ${SPRINT}: *"

echo "=== Sprint ${SPRINT} Velocity ==="

# Get all issues in sprint
ISSUES=$(gh issue list --milestone "${MILESTONE}" --limit 100 --json state,labels)

# Calculate points
TOTAL=0
COMPLETED=0

while read -r issue; do
  STATE=$(echo "$issue" | jq -r .state)
  POINTS=$(echo "$issue" | jq -r '.labels[] | select(.name | startswith("points:")) | .name' | sed 's/points: //')
  
  if [ -n "$POINTS" ]; then
    TOTAL=$((TOTAL + POINTS))
    if [ "$STATE" = "CLOSED" ]; then
      COMPLETED=$((COMPLETED + POINTS))
    fi
  fi
done < <(echo "$ISSUES" | jq -c '.[]')

echo "Completed: ${COMPLETED} points"
echo "Total: ${TOTAL} points"
if [ $TOTAL -gt 0 ]; then
  echo "Progress: $((COMPLETED * 100 / TOTAL))%"
fi
