# PLCS-004: Basic Google Places API Client Tasks

## Story
As a developer, I want to connect to Google Places API so that I can search for places

## Task Breakdown

### Setup Phase
- [ ] Create places_mcp/infrastructure package
- [ ] Create __init__.py files
- [ ] Add httpx to dependencies
- [ ] Plan error handling strategy

### HTTP Client Base (TDD)
- [ ] Write tests/unit/test_http_client.py
- [ ] Test connection pooling
- [ ] Test timeout handling
- [ ] Test retry logic
- [ ] Implement BaseHTTPClient class
- [ ] Configure connection limits
- [ ] Add request/response logging

### API Client Tests (TDD)
- [ ] Create tests/unit/test_places_api_client.py
- [ ] Mock httpx responses
- [ ] Test successful search
- [ ] Test API error responses (400, 403, 429, 500)
- [ ] Test network errors
- [ ] Test timeout scenarios
- [ ] Test retry behavior
- [ ] Test response parsing

### PlacesAPIClient Implementation
- [ ] Create places_mcp/infrastructure/google_places.py
- [ ] Implement PlacesRepository interface
- [ ] Add authentication headers
- [ ] Configure base URL and endpoints
- [ ] Implement search_text method
- [ ] Parse API response to domain models
- [ ] Handle field mappings

### Error Handling
- [ ] Create infrastructure exceptions
- [ ] Map HTTP status codes to exceptions
- [ ] Handle rate limit responses
- [ ] Parse error messages from API
- [ ] Add detailed error context
- [ ] Test all error paths

### Retry Logic
- [ ] Implement exponential backoff
- [ ] Configure max retries (3)
- [ ] Add jitter to prevent thundering herd
- [ ] Only retry on retryable errors
- [ ] Test retry scenarios
- [ ] Add retry logging

### Response Parsing
- [ ] Handle place data structure
- [ ] Map to Place domain model
- [ ] Handle missing/null fields
- [ ] Parse location coordinates
- [ ] Handle types array
- [ ] Validate data integrity

### Integration Tests
- [ ] Create tests/integration/test_api_integration.py
- [ ] Test with real-like responses
- [ ] Test error scenarios
- [ ] Test performance
- [ ] Mock external API calls

### Documentation
- [ ] Document API client usage
- [ ] Add configuration examples
- [ ] Document error handling
- [ ] Add troubleshooting guide

### Finalization
- [ ] Ensure >90% test coverage
- [ ] Run performance tests
- [ ] Verify all mocks work
- [ ] Create PR that closes #4

## Code Templates

### Test Setup
```python
# tests/unit/test_places_api_client.py
import pytest
from httpx import Response, HTTPStatusError
from unittest.mock import AsyncMock, patch
from places_mcp.infrastructure.google_places import PlacesAPIClient
from places_mcp.domain.models import Place
from places_mcp.domain.exceptions import (
    NotFoundException, 
    RateLimitException,
    InvalidRequestException
)

@pytest.fixture
def mock_httpx_client():
    client = AsyncMock()
    return client

@pytest.fixture
def api_client(mock_httpx_client):
    with patch('places_mcp.infrastructure.google_places.httpx.AsyncClient', return_value=mock_httpx_client):
        return PlacesAPIClient(api_key="test-key")

@pytest.mark.asyncio
async def test_search_text_success(api_client, mock_httpx_client):
    # Mock successful response
    mock_response = Response(
        200,
        json={
            "places": [{
                "name": "places/ChIJ1",
                "displayName": {"text": "Test Place"},
                "formattedAddress": "123 Test St",
                "location": {"latitude": 40.7128, "longitude": -74.0060},
                "rating": 4.5,
                "userRatingsTotal": 100,
                "types": ["restaurant"]
            }]
        }
    )
    mock_httpx_client.post.return_value = mock_response
    
    # Test search
    results = await api_client.search_text("test")
    
    assert len(results) == 1
    assert results[0].display_name == "Test Place"
    assert results[0].rating == 4.5
```

### Implementation Template
```python
# places_mcp/infrastructure/google_places.py
import httpx
from typing import List, Optional, Dict, Any
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type
)
from places_mcp.domain.ports import PlacesRepository
from places_mcp.domain.models import Place, Location
from places_mcp.domain.exceptions import *

class PlacesAPIClient(PlacesRepository):
    """Google Places API client implementation"""
    
    BASE_URL = "https://places.googleapis.com/v1"
    
    def __init__(self, api_key: str, timeout: float = 30.0):
        self.api_key = api_key
        self.timeout = timeout
        self._client = httpx.AsyncClient(
            base_url=self.BASE_URL,
            headers={
                "X-Goog-Api-Key": api_key,
                "Content-Type": "application/json"
            },
            timeout=timeout,
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5)
        )
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=10),
        retry=retry_if_exception_type((httpx.TimeoutException, httpx.ConnectError))
    )
    async def search_text(
        self,
        query: str,
        location: Optional[Dict[str, float]] = None,
        radius: Optional[int] = None,
        max_results: int = 20
    ) -> List[Place]:
        """Search for places by text query"""
        
        request_data = {
            "textQuery": query,
            "maxResultCount": max_results
        }
        
        if location and radius:
            request_data["locationBias"] = {
                "circle": {
                    "center": location,
                    "radius": float(radius)
                }
            }
        
        try:
            response = await self._client.post(
                "/places:searchText",
                json=request_data
            )
            response.raise_for_status()
            
        except httpx.HTTPStatusError as e:
            self._handle_api_error(e)
            
        data = response.json()
        return [self._parse_place(p) for p in data.get("places", [])]
    
    def _parse_place(self, data: Dict[str, Any]) -> Place:
        """Parse API response to domain model"""
        # Extract place ID from name field
        place_id = data.get("name", "").split("/")[-1]
        
        # Parse location if available
        location = None
        if "location" in data:
            location = Location(
                latitude=data["location"]["latitude"],
                longitude=data["location"]["longitude"]
            )
        
        return Place(
            id=place_id,
            display_name=data.get("displayName", {}).get("text", ""),
            formatted_address=data.get("formattedAddress"),
            location=location,
            rating=data.get("rating"),
            user_rating_count=data.get("userRatingsTotal"),
            types=data.get("types", [])
        )
    
    def _handle_api_error(self, error: httpx.HTTPStatusError):
        """Map HTTP errors to domain exceptions"""
        status = error.response.status_code
        
        if status == 400:
            raise InvalidRequestException("Invalid request parameters")
        elif status == 403:
            raise AuthenticationException("Invalid API key")
        elif status == 404:
            raise NotFoundException("Place not found")
        elif status == 429:
            raise RateLimitException("API rate limit exceeded")
        else:
            raise ExternalServiceException(f"API error: {status}")
    
    async def close(self):
        """Clean up client resources"""
        await self._client.aclose()
    
    async def __aenter__(self):
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()
```

### Error Handling Tests
```python
@pytest.mark.asyncio
async def test_rate_limit_error(api_client, mock_httpx_client):
    # Mock 429 response
    mock_httpx_client.post.side_effect = httpx.HTTPStatusError(
        "Rate limited",
        request=None,
        response=Response(429, json={"error": "RATE_LIMIT_EXCEEDED"})
    )
    
    with pytest.raises(RateLimitException):
        await api_client.search_text("test")

@pytest.mark.asyncio
async def test_retry_on_timeout(api_client, mock_httpx_client):
    # First two calls timeout, third succeeds
    mock_httpx_client.post.side_effect = [
        httpx.TimeoutException("Timeout"),
        httpx.TimeoutException("Timeout"),
        Response(200, json={"places": []})
    ]
    
    results = await api_client.search_text("test")
    assert results == []
    assert mock_httpx_client.post.call_count == 3
```

## Success Criteria
- [ ] All tests pass
- [ ] >90% code coverage
- [ ] Retry logic works correctly
- [ ] Error mapping is accurate
- [ ] Performance acceptable (<1s)
- [ ] PR closes issue #4