#!/bin/bash
# Setup GitHub project management for Places MCP Server

set -e

echo "🚀 Setting up GitHub project management..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo -e "${BLUE}Repository: ${REPO}${NC}"

# Create labels
echo -e "\n${YELLOW}Creating labels...${NC}"

# Priority labels
gh label create "P0: MVP Critical" --color "FF0000" --description "Must have for MVP" || true
gh label create "P1: Core Features" --color "FF6600" --description "Needed for production" || true
gh label create "P2: Enhancements" --color "FFAA00" --description "Improve experience" || true
gh label create "P3: Nice to Have" --color "FFDD00" --description "Future consideration" || true

# Sprint labels
gh label create "Sprint 1" --color "0052CC" --description "MVP Foundation" || true
gh label create "Sprint 2" --color "0052CC" --description "Core Features" || true
gh label create "Sprint 3" --color "0052CC" --description "Performance" || true
gh label create "Sprint 4" --color "0052CC" --description "Advanced Features" || true
gh label create "Sprint 5" --color "0052CC" --description "Production Ready" || true

# Layer labels
gh label create "layer: configuration" --color "5319E7" --description "Configuration layer" || true
gh label create "layer: domain" --color "5319E7" --description "Domain layer" || true
gh label create "layer: infrastructure" --color "5319E7" --description "Infrastructure layer" || true
gh label create "layer: application" --color "5319E7" --description "Application layer" || true
gh label create "layer: presentation" --color "5319E7" --description "Presentation layer" || true

# Type labels
gh label create "user-story" --color "1D76DB" --description "User story" || true
gh label create "task" --color "1D76DB" --description "Development task" || true
gh label create "bug" --color "E11D21" --description "Something isn't working" || true
gh label create "tech-debt" --color "006B75" --description "Technical debt" || true
gh label create "documentation" --color "D4C5F9" --description "Documentation improvements" || true

# Status labels
gh label create "blocked" --color "000000" --description "Blocked by dependency" || true
gh label create "ready" --color "0E8A16" --description "Ready to work on" || true
gh label create "in-progress" --color "FFA500" --description "Currently being worked on" || true
gh label create "review" --color "C2E0C6" --description "In code review" || true

# Story point labels
for points in 1 2 3 5 8 13 21; do
  gh label create "points: ${points}" --color "EDEDED" --description "${points} story points" || true
done

echo -e "${GREEN}✓ Labels created${NC}"

# Create milestones
echo -e "\n${YELLOW}Creating milestones...${NC}"

# Calculate sprint dates (2-week sprints starting next Monday)
NEXT_MONDAY=$(date -d "next Monday" +%Y-%m-%d)

gh api repos/${REPO}/milestones \
  --method POST \
  --field title="Sprint 1: MVP Foundation" \
  --field description="Basic search functionality working end-to-end" \
  --field due_on="${NEXT_MONDAY}T23:59:59Z" || true

gh api repos/${REPO}/milestones \
  --method POST \
  --field title="Sprint 2: Core Features" \
  --field description="Full search capabilities with details and nearby search" \
  --field due_on="$(date -d "${NEXT_MONDAY} + 14 days" +%Y-%m-%d)T23:59:59Z" || true

gh api repos/${REPO}/milestones \
  --method POST \
  --field title="Sprint 3: Performance" \
  --field description="Cached and rate-limited service" \
  --field due_on="$(date -d "${NEXT_MONDAY} + 28 days" +%Y-%m-%d)T23:59:59Z" || true

gh api repos/${REPO}/milestones \
  --method POST \
  --field title="Sprint 4: Advanced Features" \
  --field description="Rich search features with business logic" \
  --field due_on="$(date -d "${NEXT_MONDAY} + 42 days" +%Y-%m-%d)T23:59:59Z" || true

gh api repos/${REPO}/milestones \
  --method POST \
  --field title="Sprint 5: Production Ready" \
  --field description="Deployable, monitored, documented system" \
  --field due_on="$(date -d "${NEXT_MONDAY} + 56 days" +%Y-%m-%d)T23:59:59Z" || true

echo -e "${GREEN}✓ Milestones created${NC}"

# Create project board
echo -e "\n${YELLOW}Creating project board...${NC}"

# Create project (this might fail if it already exists)
PROJECT_ID=$(gh project create --owner "@me" --title "Places MCP Server" \
  --body "Agile development board for Places MCP Server" \
  --format json | jq -r .id) || true

if [ -z "$PROJECT_ID" ]; then
  # Try to find existing project
  PROJECT_ID=$(gh project list --owner "@me" --format json | \
    jq -r '.projects[] | select(.title == "Places MCP Server") | .id' | head -1)
fi

if [ -n "$PROJECT_ID" ]; then
  echo -e "${GREEN}✓ Project board ready: ID ${PROJECT_ID}${NC}"
else
  echo -e "${YELLOW}⚠ Could not create/find project board${NC}"
fi

# Create initial Sprint 1 issues
echo -e "\n${YELLOW}Creating Sprint 1 user stories...${NC}"

# PLCS-001
gh issue create \
  --title "[PLCS-001] Basic configuration with environment variables" \
  --body "## User Story
As a developer, I want to configure the server with environment variables so that I can easily deploy to different environments

## Acceptance Criteria
- [ ] Settings model created with Pydantic
- [ ] Support for GOOGLE_API_KEY and MCP_TRANSPORT
- [ ] .env file loading implemented
- [ ] Configuration validates on startup
- [ ] Documentation includes configuration guide

## Technical Notes
- Use pydantic-settings for environment management
- Create .env.example file
- Add validation for API key format" \
  --label "user-story,Sprint 1,layer: configuration,P0: MVP Critical,points: 3,ready" \
  --milestone "Sprint 1: MVP Foundation" || true

# PLCS-002
gh issue create \
  --title "[PLCS-002] Core domain models for places" \
  --body "## User Story
As a developer, I want core domain models so that I can represent place data consistently

## Acceptance Criteria
- [ ] Place model with validation
- [ ] Location model with coordinate validation
- [ ] SearchQuery model for search parameters
- [ ] Domain exceptions defined
- [ ] All models have comprehensive tests

## Technical Notes
- Use Pydantic for model definitions
- Include methods for distance calculation
- Follow domain-driven design principles" \
  --label "user-story,Sprint 1,layer: domain,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 1: MVP Foundation" || true

echo -e "${GREEN}✓ Initial issues created${NC}"

# Create helper scripts
echo -e "\n${YELLOW}Creating helper scripts...${NC}"

# Daily standup script
cat > scripts/daily-standup.sh << 'EOF'
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
EOF
chmod +x scripts/daily-standup.sh

# Sprint velocity script
cat > scripts/sprint-velocity.sh << 'EOF'
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
EOF
chmod +x scripts/sprint-velocity.sh

# Issue creation helper
cat > scripts/create-story.sh << 'EOF'
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
EOF
chmod +x scripts/create-story.sh

echo -e "${GREEN}✓ Helper scripts created${NC}"

echo -e "\n${GREEN}🎉 GitHub project setup complete!${NC}"
echo -e "\nNext steps:"
echo -e "1. View your project board: ${BLUE}gh project list${NC}"
echo -e "2. Create remaining Sprint 1 stories: ${BLUE}./scripts/create-story.sh${NC}"
echo -e "3. Run daily standup: ${BLUE}./scripts/daily-standup.sh${NC}"
echo -e "4. Track velocity: ${BLUE}./scripts/sprint-velocity.sh 1${NC}"