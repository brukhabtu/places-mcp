#!/bin/bash
# Create all remaining sprint issues (Sprints 2-5)

echo "📝 Creating all remaining sprint issues..."

# Sprint 2 Issues
echo "Creating Sprint 2 issues..."

# PLCS-007
gh issue create \
  --title "[PLCS-007] Comprehensive place detail models" \
  --body "## User Story
As a developer, I want comprehensive place detail models so that I can represent all Google Places API fields

## Acceptance Criteria
- [ ] PlaceDetails model with all fields
- [ ] OpeningHours model with special hours
- [ ] Review model with author info
- [ ] Photo model with attribution
- [ ] Support for 2025 fields (EV charging, accessibility)
- [ ] Proper validation for all fields
- [ ] Tests for all models

## Technical Notes
- Extend Place model for PlaceDetails
- Handle complex nested structures
- Support generative AI summaries
- Validate business hours logic" \
  --label "user-story,Sprint 2,layer: domain,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-008
gh issue create \
  --title "[PLCS-008] Place details endpoint implementation" \
  --body "## User Story
As a developer, I want to retrieve detailed place information so that users can see comprehensive data

## Acceptance Criteria
- [ ] Implement get_place_details in API client
- [ ] Support field mask for cost optimization
- [ ] Handle large response payloads
- [ ] Parse all detail fields correctly
- [ ] Error handling for invalid place IDs
- [ ] Integration tests with mock data

## Technical Notes
- Use field masks to reduce costs
- Handle null/missing fields gracefully
- Map API response to domain models" \
  --label "user-story,Sprint 2,layer: infrastructure,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-009
gh issue create \
  --title "[PLCS-009] Nearby search endpoint implementation" \
  --body "## User Story
As a developer, I want to search for places near a location so that users can find nearby businesses

## Acceptance Criteria
- [ ] Implement nearby search in API client
- [ ] Support location and radius parameters
- [ ] Type filtering (restaurant, cafe, etc.)
- [ ] Rank by distance or prominence
- [ ] Handle location-based errors
- [ ] Comprehensive tests

## Technical Notes
- Validate coordinates
- Support multiple place types
- Implement proper pagination" \
  --label "user-story,Sprint 2,layer: infrastructure,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-010
gh issue create \
  --title "[PLCS-010] Robust error handling and retries" \
  --body "## User Story
As a developer, I want robust error handling so that the service is reliable

## Acceptance Criteria
- [ ] Exponential backoff implementation
- [ ] Custom exceptions for each error type
- [ ] Rate limit detection and handling
- [ ] Network error recovery
- [ ] Timeout handling
- [ ] Circuit breaker pattern
- [ ] Comprehensive error tests

## Technical Notes
- Max 3 retries with backoff
- Map HTTP codes to exceptions
- Log all errors appropriately
- Graceful degradation" \
  --label "user-story,Sprint 2,layer: infrastructure,P0: MVP Critical,points: 8,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-011
gh issue create \
  --title "[PLCS-011] Separate services for different operations" \
  --body "## User Story
As a developer, I want separate services so that business logic is well organized

## Acceptance Criteria
- [ ] Create SearchService
- [ ] Create DetailsService
- [ ] Move logic from PlacesService
- [ ] Maintain single responsibility
- [ ] Add telemetry to each service
- [ ] Service integration tests

## Technical Notes
- Each service handles one domain
- Share base service class
- Consistent error handling
- Dependency injection pattern" \
  --label "user-story,Sprint 2,layer: application,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-012
gh issue create \
  --title "[PLCS-012] Get place details MCP tool" \
  --body "## User Story
As an AI assistant, I want to get detailed place information so that I can answer specific questions

## Acceptance Criteria
- [ ] Implement get_place_details tool
- [ ] Support field selection
- [ ] Progress reporting for slow requests
- [ ] Clear error messages
- [ ] Comprehensive tool documentation
- [ ] Integration tests

## Technical Notes
- Allow field mask input
- Default to common fields
- Handle large responses
- Format output for AI consumption" \
  --label "user-story,Sprint 2,layer: presentation,P0: MVP Critical,points: 3,ready" \
  --milestone "Sprint 2: Core Features"

# PLCS-013
gh issue create \
  --title "[PLCS-013] Find nearby places MCP tool" \
  --body "## User Story
As an AI assistant, I want to find places near a location so that I can help with local recommendations

## Acceptance Criteria
- [ ] Implement find_nearby_places tool
- [ ] Location input with validation
- [ ] Place type filtering
- [ ] Radius configuration
- [ ] Sort by distance/prominence
- [ ] Clear documentation

## Technical Notes
- Validate coordinates
- Support type combinations
- Default sensible radius
- Return structured data" \
  --label "user-story,Sprint 2,layer: presentation,P0: MVP Critical,points: 3,ready" \
  --milestone "Sprint 2: Core Features"

# Sprint 3 Issues
echo "Creating Sprint 3 issues..."

# PLCS-014
gh issue create \
  --title "[PLCS-014] Redis cache implementation" \
  --body "## User Story
As a developer, I want to cache API responses so that the service is fast and cost-effective

## Acceptance Criteria
- [ ] Implement Redis cache manager
- [ ] Connection pooling
- [ ] Serialization/deserialization
- [ ] TTL management (30 days max)
- [ ] In-memory fallback cache
- [ ] Cache key strategies
- [ ] Integration tests

## Technical Notes
- Use redis-py with async
- Handle connection failures
- Implement cache aside pattern
- Monitor cache performance" \
  --label "user-story,Sprint 3,layer: infrastructure,P1: Core Features,points: 8,ready" \
  --milestone "Sprint 3: Performance"

# PLCS-015
gh issue create \
  --title "[PLCS-015] Rate limiting implementation" \
  --body "## User Story
As a developer, I want to prevent API quota exhaustion so that the service stays available

## Acceptance Criteria
- [ ] Token bucket implementation
- [ ] Per-user rate limiting
- [ ] Queue for excess requests
- [ ] Rate limit headers
- [ ] Configurable limits
- [ ] Distributed rate limiting
- [ ] Comprehensive tests

## Technical Notes
- 100 QPS default limit
- Use Redis for distributed state
- Return 429 when exceeded
- Clear error messages" \
  --label "user-story,Sprint 3,layer: infrastructure,P1: Core Features,points: 8,ready" \
  --milestone "Sprint 3: Performance"

# PLCS-016
gh issue create \
  --title "[PLCS-016] Intelligent caching strategies" \
  --body "## User Story
As a developer, I want intelligent caching so that popular queries are fast

## Acceptance Criteria
- [ ] Cache warming for popular queries
- [ ] Cache invalidation logic
- [ ] Optimize cache keys
- [ ] Monitor hit rates
- [ ] Adaptive TTL based on popularity
- [ ] Cache analytics

## Technical Notes
- Warm cache on startup
- Track query patterns
- Invalidate on updates
- Target >30% hit rate" \
  --label "user-story,Sprint 3,layer: application,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 3: Performance"

# PLCS-017
gh issue create \
  --title "[PLCS-017] Photo management service" \
  --body "## User Story
As a developer, I want photo management capabilities so that place photos are accessible

## Acceptance Criteria
- [ ] Create PhotoService
- [ ] Size optimization logic
- [ ] URL generation
- [ ] Attribution handling
- [ ] Caching photo metadata
- [ ] Tests for photo operations

## Technical Notes
- Handle multiple sizes
- Respect attribution requirements
- Cache photo URLs
- Validate dimensions" \
  --label "user-story,Sprint 3,layer: application,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 3: Performance"

# PLCS-018
gh issue create \
  --title "[PLCS-018] Autocomplete places MCP tool" \
  --body "## User Story
As an AI assistant, I want autocomplete suggestions so that I can help users find places as they type

## Acceptance Criteria
- [ ] Implement autocomplete_places tool
- [ ] Session token support
- [ ] Real-time suggestions
- [ ] Location biasing
- [ ] Type filtering
- [ ] Clear documentation

## Technical Notes
- Manage session tokens
- Debounce support hints
- Return structured predictions
- Cost optimization tips" \
  --label "user-story,Sprint 3,layer: presentation,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 3: Performance"

# PLCS-019
gh issue create \
  --title "[PLCS-019] API usage statistics resource" \
  --body "## User Story
As an AI assistant, I want to know about API usage so that I can inform users about limits

## Acceptance Criteria
- [ ] Implement usage stats resource
- [ ] Show request counts
- [ ] Cache hit rates
- [ ] Quota remaining
- [ ] Cost estimates
- [ ] Historical trends

## Technical Notes
- Track in Redis
- Calculate hit rates
- Estimate costs
- Return as MCP resource" \
  --label "user-story,Sprint 3,layer: presentation,P1: Core Features,points: 3,ready" \
  --milestone "Sprint 3: Performance"

# Sprint 4 Issues
echo "Creating Sprint 4 issues..."

# PLCS-020
gh issue create \
  --title "[PLCS-020] Business rules for search operations" \
  --body "## User Story
As a developer, I want business rules for search so that complex requirements are enforced

## Acceptance Criteria
- [ ] SearchRules class implementation
- [ ] Budget filtering logic
- [ ] Dietary restriction filters
- [ ] Opening hours validation
- [ ] Distance constraints
- [ ] Rule composition
- [ ] Comprehensive tests

## Technical Notes
- Implement as domain service
- Support rule chaining
- Clear rule violations
- Extensible design" \
  --label "user-story,Sprint 4,layer: domain,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 4: Advanced Features"

# PLCS-021
gh issue create \
  --title "[PLCS-021] Complex search criteria support" \
  --body "## User Story
As a user, I want to search with complex criteria so that I find exactly what I need

## Acceptance Criteria
- [ ] Multi-criteria search
- [ ] Dietary restrictions (vegan, halal, etc.)
- [ ] Budget filtering by price level
- [ ] Open now/at specific time
- [ ] Minimum rating filter
- [ ] Combine multiple filters
- [ ] Performance optimization

## Technical Notes
- Build query dynamically
- Apply filters efficiently
- Cache complex queries
- Return relevant results" \
  --label "user-story,Sprint 4,layer: application,P1: Core Features,points: 8,ready" \
  --milestone "Sprint 4: Advanced Features"

# PLCS-022
gh issue create \
  --title "[PLCS-022] Batch operations for efficiency" \
  --body "## User Story
As a developer, I want batch operations so that multiple requests are efficient

## Acceptance Criteria
- [ ] Batch place details fetching
- [ ] Parallel request processing
- [ ] Request deduplication
- [ ] Error handling per item
- [ ] Progress tracking
- [ ] Optimize API calls

## Technical Notes
- Limit concurrency
- Handle partial failures
- Return structured results
- Monitor performance" \
  --label "user-story,Sprint 4,layer: application,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 4: Advanced Features"

# PLCS-023
gh issue create \
  --title "[PLCS-023] Transaction support with saga pattern" \
  --body "## User Story
As a developer, I want transaction support so that complex workflows are reliable

## Acceptance Criteria
- [ ] Saga pattern implementation
- [ ] Compensation logic
- [ ] State persistence
- [ ] Timeout handling
- [ ] Rollback capability
- [ ] Transaction monitoring
- [ ] Integration tests

## Technical Notes
- Use event sourcing
- Implement compensations
- Handle timeouts
- Ensure consistency" \
  --label "user-story,Sprint 4,layer: application,P1: Core Features,points: 8,ready" \
  --milestone "Sprint 4: Advanced Features"

# PLCS-024
gh issue create \
  --title "[PLCS-024] Advanced search filters in tools" \
  --body "## User Story
As an AI assistant, I want advanced search filters so that I can find specific places

## Acceptance Criteria
- [ ] Enhance search tool with filters
- [ ] Price level constraints
- [ ] Opening hours filtering
- [ ] Rating thresholds
- [ ] Dietary restrictions
- [ ] Clear filter documentation

## Technical Notes
- Optional parameters
- Validate combinations
- Show filter options
- Example queries" \
  --label "user-story,Sprint 4,layer: presentation,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 4: Advanced Features"

# PLCS-025
gh issue create \
  --title "[PLCS-025] Recent searches resource" \
  --body "## User Story
As an AI assistant, I want to track search history so that I can reference previous queries

## Acceptance Criteria
- [ ] Implement recent searches resource
- [ ] Store last 100 searches
- [ ] Include timestamps
- [ ] Search analytics
- [ ] Privacy-aware storage
- [ ] Clear old entries

## Technical Notes
- Use Redis with expiry
- Anonymize if needed
- Return structured data
- Include search context" \
  --label "user-story,Sprint 4,layer: presentation,P1: Core Features,points: 3,ready" \
  --milestone "Sprint 4: Advanced Features"

# Sprint 5 Issues
echo "Creating Sprint 5 issues..."

# PLCS-026
gh issue create \
  --title "[PLCS-026] Multi-environment configuration support" \
  --body "## User Story
As an operator, I want environment-specific configs so that deployment is flexible

## Acceptance Criteria
- [ ] Environment detection
- [ ] Config file per environment
- [ ] Override mechanisms
- [ ] Secret management
- [ ] Validation per environment
- [ ] Hot reload capability
- [ ] Documentation

## Technical Notes
- Support dev/staging/prod
- Use environment variables
- Secure secret handling
- Clear precedence rules" \
  --label "user-story,Sprint 5,layer: configuration,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 5: Production Ready"

# PLCS-027
gh issue create \
  --title "[PLCS-027] Comprehensive monitoring implementation" \
  --body "## User Story
As an operator, I want comprehensive monitoring so that I can ensure reliability

## Acceptance Criteria
- [ ] OpenTelemetry integration
- [ ] Custom metrics collection
- [ ] Distributed tracing
- [ ] Error tracking
- [ ] Performance metrics
- [ ] Dashboard setup
- [ ] Alert configuration

## Technical Notes
- Use OTEL standards
- Track key metrics
- Implement sampling
- Low overhead" \
  --label "user-story,Sprint 5,layer: infrastructure,P1: Core Features,points: 8,ready" \
  --milestone "Sprint 5: Production Ready"

# PLCS-028
gh issue create \
  --title "[PLCS-028] Production-grade structured logging" \
  --body "## User Story
As an operator, I want structured logging so that debugging is efficient

## Acceptance Criteria
- [ ] Structured log format
- [ ] Log levels configuration
- [ ] Correlation IDs
- [ ] Sensitive data masking
- [ ] Log aggregation support
- [ ] Performance optimization
- [ ] Search capabilities

## Technical Notes
- JSON log format
- Use structlog
- Mask secrets/PII
- Include context" \
  --label "user-story,Sprint 5,layer: infrastructure,P1: Core Features,points: 5,ready" \
  --milestone "Sprint 5: Production Ready"

# PLCS-029
gh issue create \
  --title "[PLCS-029] Comprehensive test coverage" \
  --body "## User Story
As a developer, I want comprehensive tests so that the code is reliable

## Acceptance Criteria
- [ ] Unit tests >80% coverage
- [ ] Integration test suite
- [ ] E2E test scenarios
- [ ] Performance tests
- [ ] Security tests
- [ ] Load testing
- [ ] CI/CD integration

## Technical Notes
- Use pytest-cov
- Mock external services
- Test error paths
- Automate in CI" \
  --label "user-story,Sprint 5,all-layers,P0: MVP Critical,points: 8,ready" \
  --milestone "Sprint 5: Production Ready"

# PLCS-030
gh issue create \
  --title "[PLCS-030] Docker and Kubernetes deployment" \
  --body "## User Story
As an operator, I want container deployment so that scaling is easy

## Acceptance Criteria
- [ ] Dockerfile optimization
- [ ] Multi-stage builds
- [ ] Kubernetes manifests
- [ ] Helm charts
- [ ] Health checks
- [ ] Resource limits
- [ ] Deployment automation

## Technical Notes
- Minimal image size
- Security scanning
- Rolling updates
- Auto-scaling rules" \
  --label "user-story,Sprint 5,layer: infrastructure,P0: MVP Critical,points: 8,ready" \
  --milestone "Sprint 5: Production Ready"

# PLCS-031
gh issue create \
  --title "[PLCS-031] Complete documentation" \
  --body "## User Story
As a user, I want complete documentation so that I can use the service effectively

## Acceptance Criteria
- [ ] API documentation
- [ ] Deployment guide
- [ ] Configuration guide
- [ ] Troubleshooting guide
- [ ] Architecture diagrams
- [ ] Code examples
- [ ] Video tutorials

## Technical Notes
- Use MkDocs
- Include examples
- Keep updated
- Version documentation" \
  --label "user-story,Sprint 5,documentation,P0: MVP Critical,points: 5,ready" \
  --milestone "Sprint 5: Production Ready"

echo "✅ All sprint issues created!"
echo ""
echo "📊 Summary by Sprint:"
for sprint in 1 2 3 4 5; do
  echo "Sprint $sprint:"
  gh issue list --milestone "Sprint $sprint:" --limit 50
  echo ""
done