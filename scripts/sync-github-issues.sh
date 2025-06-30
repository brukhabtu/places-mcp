#!/bin/bash
# Sync GitHub issues to match our documentation

echo "🔄 Syncing GitHub issues with documentation..."

# Create missing Sprint 1 issues
echo "Creating missing Sprint 1 issues..."

# PLCS-032: Test Infrastructure Setup
gh issue create \
  --title "[PLCS-032] Test Infrastructure Setup" \
  --body "## User Story
As a developer, I want comprehensive test infrastructure so that I can follow TDD practices

## Acceptance Criteria
- [ ] Pytest configuration complete
- [ ] Coverage reporting configured (>80% requirement)
- [ ] Test fixtures and utilities created
- [ ] CI/CD pipeline for tests
- [ ] Async test support
- [ ] Mock implementations ready
- [ ] Test documentation written

## Technical Notes
- Use pytest-asyncio for async tests
- Configure coverage with branch coverage
- Set up GitHub Actions for CI
- Create reusable test fixtures
- Enable parallel test execution

## Task Breakdown
See detailed tasks in: [TEST-INFRASTRUCTURE-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/TEST-INFRASTRUCTURE-TASKS.md)

## Dependencies
- Should be completed in parallel with other Sprint 1 foundation work
- Enables TDD for all other stories" \
  --label "user-story,Sprint 1,infrastructure,P0: MVP Critical,points: 3,ready" \
  --milestone "Sprint 1: MVP Foundation"

# PLCS-033: API Contract Definitions
gh issue create \
  --title "[PLCS-033] API Contract Definitions" \
  --body "## User Story
As a developer, I want API contracts defined so that parallel development is smoother

## Acceptance Criteria
- [ ] OpenAPI specification for Places API integration
- [ ] MCP protocol documentation
- [ ] Request/response schemas defined
- [ ] Error response formats documented
- [ ] Validation schemas created
- [ ] Contract tests implemented

## Technical Notes
- Use OpenAPI 3.0 specification
- Define all request/response models
- Include example requests
- Support contract-first development
- Enable code generation

## Task Breakdown
See detailed tasks in: [PLCS-033-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-033-TASKS.md)

## Dependencies
- Helps PLCS-004 (API Client) development
- Should be done early in Sprint 1" \
  --label "user-story,Sprint 1,infrastructure,P1: Core Features,points: 2,ready" \
  --milestone "Sprint 1: MVP Foundation"

echo "Updating existing issues with task breakdown links..."

# Update PLCS-001
gh issue edit 1 --body "$(gh issue view 1 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-001-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-001-TASKS.md)"

# Update PLCS-002
gh issue edit 2 --body "$(gh issue view 2 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-002-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-002-TASKS.md)"

# Update PLCS-003
gh issue edit 3 --body "$(gh issue view 3 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-003-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-003-TASKS.md)"

# Update PLCS-004
gh issue edit 4 --body "$(gh issue view 4 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-004-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-004-TASKS.md)"

# Update PLCS-005
gh issue edit 5 --body "$(gh issue view 5 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-005-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-005-TASKS.md)"

# Update PLCS-006
gh issue edit 6 --body "$(gh issue view 6 --json body -q .body)

## Task Breakdown
See detailed tasks in: [PLCS-006-TASKS.md](https://github.com/brukhabtu/places-mcp/blob/main/docs/tasks/PLCS-006-TASKS.md)"

echo "✅ GitHub issues synced!"

echo ""
echo "📊 Sprint 1 Summary:"
gh issue list --milestone "Sprint 1: MVP Foundation" --limit 10

echo ""
echo "📈 Sprint 1 Story Points:"
echo "Original: 28 points (6 stories)"
echo "Updated: 33 points (8 stories)"
echo ""
echo "New stories added:"
echo "- PLCS-032: Test Infrastructure (3 points)"
echo "- PLCS-033: API Contracts (2 points)"