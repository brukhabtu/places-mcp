#!/bin/bash
# Execute sprint stories in order - designed for AI implementation

set -e

SPRINT=${1:-1}
echo "🚀 Executing Sprint ${SPRINT} Stories"

# Function to work on a story
work_on_story() {
    local STORY_NUMBER=$1
    local BRANCH_NAME=$2
    local COMMIT_MSG=$3
    
    echo ""
    echo "📋 Working on PLCS-${STORY_NUMBER}"
    
    # View issue details
    gh issue view ${STORY_NUMBER}
    
    # Create and switch to feature branch
    git checkout main
    git pull origin main
    git checkout -b ${BRANCH_NAME}
    
    echo "🔧 Ready to implement PLCS-${STORY_NUMBER}"
    echo "Branch: ${BRANCH_NAME}"
    echo ""
    echo "After implementation, run:"
    echo "  git add -A"
    echo "  git commit -m \"${COMMIT_MSG}\""
    echo "  gh pr create --fill"
}

# Sprint 1 execution order
if [ "$SPRINT" = "1" ]; then
    echo "Executing Sprint 1: MVP Foundation"
    
    # PLCS-001: Configuration
    work_on_story "001" \
        "feature/PLCS-001-configuration" \
        "feat(config): implement environment configuration

- Add Settings model with Pydantic
- Support GOOGLE_API_KEY and MCP_TRANSPORT
- Load from .env files with validation
- Add comprehensive unit tests

Closes #1"

    # PLCS-002: Domain Models
    work_on_story "002" \
        "feature/PLCS-002-domain-models" \
        "feat(domain): implement core domain models

- Add Place, Location, SearchQuery models
- Implement validation rules
- Add distance calculation method
- Create domain exceptions
- Add comprehensive tests

Closes #2"
    
    # PLCS-003: Repository Interfaces
    work_on_story "003" \
        "feature/PLCS-003-repository-interfaces" \
        "feat(domain): define repository interfaces

- Create PlacesRepository protocol
- Define method signatures
- Add mock implementation
- Document interface patterns

Closes #3"
    
    # Continue with remaining stories...
fi

# Progress check function
check_progress() {
    echo ""
    echo "📊 Sprint ${SPRINT} Progress:"
    echo "========================"
    
    # Completed stories
    echo "✅ Completed:"
    gh issue list --milestone "Sprint ${SPRINT}: *" --state closed
    
    echo ""
    echo "🔄 In Progress:"
    gh issue list --milestone "Sprint ${SPRINT}: *" --state open --label "in-progress"
    
    echo ""
    echo "📝 Remaining:"
    gh issue list --milestone "Sprint ${SPRINT}: *" --state open --label "ready"
    
    # Calculate velocity
    ./scripts/sprint-velocity.sh ${SPRINT}
}

# Show current progress
check_progress