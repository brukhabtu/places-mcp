#!/bin/bash
# Helper to create user stories

echo "Create User Story"
echo "================"

read -p "Story ID (e.g., PLCS-007): " STORY_ID
read -p "Title: " TITLE
read -p "Role (e.g., developer, AI assistant): " ROLE
read -p "Feature: " FEATURE
read -p "Benefit: " BENEFIT
read -p "Sprint (1-5): " SPRINT
read -p "Layer (configuration/domain/infrastructure/application/presentation): " LAYER
read -p "Priority (P0/P1/P2/P3): " PRIORITY
read -p "Points (1/2/3/5/8/13): " POINTS

BODY="## User Story
As a ${ROLE}, I want ${FEATURE} so that ${BENEFIT}

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Technical Notes
- Add implementation notes here"

gh issue create \
  --title "[${STORY_ID}] ${TITLE}" \
  --body "${BODY}" \
  --label "user-story,Sprint ${SPRINT},layer: ${LAYER},${PRIORITY}: *,points: ${POINTS}" \
  --milestone "Sprint ${SPRINT}: *"
