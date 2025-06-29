#!/bin/bash
# Create remaining Sprint 1 stories for AI implementation

echo "📝 Creating remaining Sprint 1 stories..."

# PLCS-003: Repository interface definitions
gh issue create \
  --title "[PLCS-003] Repository interface definitions" \
  --body "## User Story
As a developer, I want repository interfaces defined so that I can implement them in the infrastructure layer

## Acceptance Criteria
- [ ] PlacesRepository protocol created with type hints
- [ ] search_text method signature defined
- [ ] get_details method signature defined (for Sprint 2)
- [ ] Mock implementation for testing
- [ ] Documentation of interface patterns

## Technical Notes
- Use Python Protocol from typing
- Define clear method signatures with type hints
- Create MockPlacesRepository for testing
- Follow dependency inversion principle" \
  --label "user-story,Sprint 1,layer: domain,P0: MVP Critical,points: 2,ready" \
  --milestone "Sprint 1: MVP Foundation"

# PLCS-004: Basic Google Places API client
gh issue create \
  --title "[PLCS-004] Basic Google Places API client" \
  --body "## User Story
As a developer, I want to connect to Google Places API so that I can search for places

## Acceptance Criteria
- [ ] PlacesAPIClient implements PlacesRepository interface
- [ ] Authentication with API key works
- [ ] search_text endpoint implemented
- [ ] Proper error handling for API errors
- [ ] Response parsing to domain models
- [ ] Connection pooling with httpx
- [ ] Comprehensive tests with mocked responses

## Technical Notes
- Use httpx for async HTTP client
- Implement exponential backoff for retries
- Map API errors to domain exceptions
- Use proper async/await patterns
- Test with mocked HTTP responses" \
  --label "user-story,Sprint 1,layer: infrastructure,P0: MVP Critical,points: 8,ready" \
  --milestone "Sprint 1: MVP Foundation"

# PLCS-005: PlacesService implementation
gh issue create \
  --title "[PLCS-005] PlacesService implementation" \
  --body "## User Story
As a developer, I want a service to orchestrate place searches so that business logic is separated from infrastructure

## Acceptance Criteria
- [ ] PlacesService class created
- [ ] Dependency injection of repository
- [ ] search_places method implemented
- [ ] Basic error handling and logging
- [ ] Result transformation if needed
- [ ] Service tests with mocked repository

## Technical Notes
- Accept PlacesRepository in constructor
- Add basic telemetry/logging
- Transform infrastructure errors to service errors
- Keep service thin for Sprint 1
- Use dependency injection pattern" \
  --label "user-story,Sprint 1,layer: application,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 1: MVP Foundation"

# PLCS-006: Search places MCP tool
gh issue create \
  --title "[PLCS-006] Search places MCP tool" \
  --body "## User Story
As an AI assistant, I want to search for places using natural language so that I can help users find locations

## Acceptance Criteria
- [ ] FastMCP server setup with proper metadata
- [ ] search_places tool implemented
- [ ] Query parameter with validation
- [ ] Optional location and radius parameters
- [ ] Progress reporting via context
- [ ] Clear error messages for AI understanding
- [ ] Tool works via stdio transport
- [ ] Comprehensive documentation in tool description

## Technical Notes
- Use @mcp.tool decorator
- Inject PlacesService using DI
- Add input validation with clear errors
- Use Context for progress updates
- Test with mock service
- Ensure tool description helps LLMs understand usage" \
  --label "user-story,Sprint 1,layer: presentation,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 1: MVP Foundation"

echo "✅ All Sprint 1 stories created!"
echo ""
echo "📊 Sprint 1 Summary:"
gh issue list --milestone "Sprint 1: MVP Foundation"