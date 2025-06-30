# PLCS-033: API Contract Definitions Tasks

## Story
As a developer, I want API contracts defined so that parallel development is smoother

## Task Breakdown

### Setup Phase
- [ ] Create docs/contracts directory
- [ ] Install OpenAPI tools
- [ ] Plan contract structure
- [ ] Set up validation tools

### MCP Protocol Documentation
- [ ] Document MCP tool interface
- [ ] Define request formats
- [ ] Define response formats
- [ ] Document error formats
- [ ] Create MCP examples

### Places API Contract
- [ ] Create places-api-v1.yaml
- [ ] Define search endpoint schema
- [ ] Define details endpoint schema
- [ ] Define nearby endpoint schema
- [ ] Add authentication schemas
- [ ] Document rate limits

### Request Schemas
- [ ] SearchRequest schema
- [ ] DetailsRequest schema
- [ ] NearbyRequest schema
- [ ] Location schema
- [ ] Add validation rules

### Response Schemas
- [ ] Place response schema
- [ ] PlaceDetails response schema
- [ ] Error response schema
- [ ] List response wrapper
- [ ] Pagination schema

### Contract Tests
- [ ] Install schemathesis
- [ ] Create contract test suite
- [ ] Test request validation
- [ ] Test response validation
- [ ] Add to CI pipeline

### Code Generation
- [ ] Configure openapi-generator
- [ ] Generate TypeScript types
- [ ] Generate Python models
- [ ] Verify generated code
- [ ] Document usage

### Documentation
- [ ] Create API reference docs
- [ ] Add example requests
- [ ] Document error codes
- [ ] Create integration guide

### Finalization
- [ ] Validate OpenAPI spec
- [ ] Run contract tests
- [ ] Update related issues
- [ ] Create PR

## Code Templates

### OpenAPI Specification
```yaml
# docs/contracts/places-api-v1.yaml
openapi: 3.0.3
info:
  title: Places MCP API
  version: 1.0.0
  description: |
    API contracts for the Places MCP Server.
    This defines the interface between the MCP tools and the Places service.

servers:
  - url: http://localhost:8000
    description: Local development

paths:
  /tools/search_places:
    post:
      summary: Search for places
      operationId: searchPlaces
      tags:
        - Places
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SearchRequest'
      responses:
        '200':
          description: Successful search
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SearchResponse'
        '400':
          $ref: '#/components/responses/BadRequest'
        '429':
          $ref: '#/components/responses/RateLimited'

components:
  schemas:
    SearchRequest:
      type: object
      required:
        - query
      properties:
        query:
          type: string
          minLength: 2
          maxLength: 200
          description: Search query text
          example: "pizza in new york"
        location:
          $ref: '#/components/schemas/Location'
        radius:
          type: integer
          minimum: 1
          maximum: 50000
          description: Search radius in meters
        maxResults:
          type: integer
          minimum: 1
          maximum: 50
          default: 20
          
    Location:
      type: object
      required:
        - latitude
        - longitude
      properties:
        latitude:
          type: number
          format: double
          minimum: -90
          maximum: 90
        longitude:
          type: number
          format: double
          minimum: -180
          maximum: 180
          
    SearchResponse:
      type: object
      properties:
        places:
          type: array
          items:
            $ref: '#/components/schemas/Place'
        totalResults:
          type: integer
          
    Place:
      type: object
      required:
        - id
        - displayName
      properties:
        id:
          type: string
          pattern: '^[A-Za-z0-9_-]+$'
        displayName:
          type: string
        formattedAddress:
          type: string
        location:
          $ref: '#/components/schemas/Location'
        rating:
          type: number
          format: float
          minimum: 0
          maximum: 5
        userRatingCount:
          type: integer
          minimum: 0
        types:
          type: array
          items:
            type: string
            
    Error:
      type: object
      required:
        - code
        - message
      properties:
        code:
          type: string
          enum:
            - INVALID_REQUEST
            - NOT_FOUND
            - RATE_LIMITED
            - INTERNAL_ERROR
        message:
          type: string
        details:
          type: object
          
  responses:
    BadRequest:
      description: Invalid request
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
    RateLimited:
      description: Rate limit exceeded
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
```

### Contract Tests
```python
# tests/contract/test_api_contracts.py
import pytest
import schemathesis
from pathlib import Path

# Load OpenAPI schema
schema_path = Path(__file__).parent.parent.parent / "docs/contracts/places-api-v1.yaml"
schema = schemathesis.from_path(str(schema_path))

@schema.parametrize()
def test_api_contract(case):
    """Test all endpoints against OpenAPI contract"""
    response = case.call()
    case.validate_response(response)

@pytest.mark.contract
def test_search_request_validation():
    """Test search request validation"""
    from jsonschema import validate, ValidationError
    import yaml
    
    with open(schema_path) as f:
        spec = yaml.safe_load(f)
    
    search_schema = spec["components"]["schemas"]["SearchRequest"]
    
    # Valid request
    valid_request = {
        "query": "pizza",
        "location": {"latitude": 40.7, "longitude": -74.0},
        "radius": 1000,
        "maxResults": 10
    }
    validate(valid_request, search_schema)  # Should not raise
    
    # Invalid request - empty query
    with pytest.raises(ValidationError):
        validate({"query": ""}, search_schema)
```

### MCP Protocol Documentation
```markdown
# MCP Protocol Specification

## Tool: search_places

### Request Format
```json
{
  "tool": "search_places",
  "arguments": {
    "query": "string (required)",
    "location": {
      "latitude": "number",
      "longitude": "number"
    },
    "radius": "number (optional)",
    "max_results": "number (optional, default: 20)"
  }
}
```

### Response Format
```json
{
  "result": [
    {
      "name": "string",
      "place_id": "string",
      "address": "string",
      "rating": "number",
      "user_ratings_total": "number",
      "types": ["string"],
      "location": {
        "latitude": "number",
        "longitude": "number"
      }
    }
  ]
}
```

### Error Format
```json
{
  "error": {
    "type": "string",
    "message": "string"
  }
}
```
```

### Code Generation Config
```yaml
# openapi-generator-config.yaml
generatorName: python
outputDir: ./generated/python
additionalProperties:
  packageName: places_mcp_client
  packageVersion: 1.0.0
  
---
generatorName: typescript-axios
outputDir: ./generated/typescript
additionalProperties:
  npmName: places-mcp-client
  npmVersion: 1.0.0
```

## Success Criteria
- [ ] OpenAPI spec validates
- [ ] Contract tests pass
- [ ] Code generation works
- [ ] Documentation complete
- [ ] All endpoints covered
- [ ] PR merged