# PLCS-003: Repository Interfaces Tasks

## Story
As a developer, I want repository interfaces defined so that I can implement them in the infrastructure layer

## Task Breakdown

### Setup Phase
- [ ] Create places_mcp/domain/ports.py
- [ ] Import necessary typing modules
- [ ] Plan interface methods

### PlacesRepository Interface
- [ ] Define PlacesRepository as Protocol
- [ ] Add search_text method signature
- [ ] Add get_details method signature (for Sprint 2)
- [ ] Add proper type hints for all parameters
- [ ] Add return type annotations
- [ ] Document each method's purpose

### CacheRepository Interface  
- [ ] Define CacheRepository as Protocol
- [ ] Add get method signature
- [ ] Add set method signature with TTL
- [ ] Add delete method signature
- [ ] Add clear method signature
- [ ] Document caching strategy

### RateLimiter Interface
- [ ] Define RateLimiter as Protocol
- [ ] Add check_limit method
- [ ] Add reset method
- [ ] Document rate limiting approach

### Mock Implementations
- [ ] Create places_mcp/tests/mocks.py
- [ ] Implement MockPlacesRepository
- [ ] Add sample place data
- [ ] Implement search logic
- [ ] Implement MockCacheRepository
- [ ] Add in-memory storage

### Test Mock Implementations
- [ ] Write tests/unit/test_mocks.py
- [ ] Test mock search returns data
- [ ] Test mock cache operations
- [ ] Test interface compliance

### Documentation
- [ ] Document interface patterns
- [ ] Add usage examples
- [ ] Explain Protocol benefits
- [ ] Document testing approach

### Finalization
- [ ] Verify all type hints
- [ ] Run mypy strict mode
- [ ] Create PR that closes #3

## Code Templates

### Protocol Definitions
```python
# places_mcp/domain/ports.py
from typing import Protocol, List, Optional, Any
from .models import Place, PlaceDetails, SearchQuery

class PlacesRepository(Protocol):
    """Interface for places data access"""
    
    async def search_text(
        self, 
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None,
        max_results: int = 20
    ) -> List[Place]:
        """Search for places by text query
        
        Args:
            query: Text search query
            location: Optional dict with lat/lng for bias
            radius: Optional radius in meters
            max_results: Maximum results to return
            
        Returns:
            List of places matching the query
        """
        ...
    
    async def get_details(
        self,
        place_id: str,
        fields: List[str]
    ) -> PlaceDetails:
        """Get detailed information about a place
        
        Args:
            place_id: Unique place identifier
            fields: List of fields to retrieve
            
        Returns:
            Detailed place information
        """
        ...

class CacheRepository(Protocol):
    """Interface for caching operations"""
    
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve value from cache"""
        ...
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Store value in cache with TTL in seconds"""
        ...
    
    async def delete(self, key: str) -> None:
        """Remove value from cache"""
        ...
```

### Mock Implementation
```python
# places_mcp/tests/mocks.py
from typing import List, Optional, Any, Dict
from places_mcp.domain.models import Place, Location
from places_mcp.domain.ports import PlacesRepository, CacheRepository

class MockPlacesRepository:
    """Mock implementation for testing"""
    
    def __init__(self):
        self.places = [
            Place(
                id="ChIJ1",
                display_name="Joe's Pizza",
                formatted_address="123 Main St, New York, NY",
                location=Location(latitude=40.7128, longitude=-74.0060),
                rating=4.5,
                types=["restaurant", "food"]
            ),
            Place(
                id="ChIJ2", 
                display_name="Pizza Palace",
                formatted_address="456 Broadway, New York, NY",
                location=Location(latitude=40.7200, longitude=-74.0100),
                rating=4.2,
                types=["restaurant", "food"]
            )
        ]
    
    async def search_text(
        self,
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None,
        max_results: int = 20
    ) -> List[Place]:
        # Simple search implementation
        results = [
            p for p in self.places
            if query.lower() in p.display_name.lower()
        ]
        return results[:max_results]

class MockCacheRepository:
    """In-memory cache for testing"""
    
    def __init__(self):
        self._cache: Dict[str, Any] = {}
    
    async def get(self, key: str) -> Optional[Any]:
        return self._cache.get(key)
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        self._cache[key] = value  # Ignore TTL for mock
```

### Tests for Mocks
```python
# tests/unit/test_mocks.py
import pytest
from places_mcp.tests.mocks import MockPlacesRepository, MockCacheRepository

@pytest.mark.asyncio
async def test_mock_places_search():
    repo = MockPlacesRepository()
    results = await repo.search_text("pizza")
    assert len(results) == 2
    assert all("pizza" in p.display_name.lower() for p in results)

@pytest.mark.asyncio
async def test_mock_cache_operations():
    cache = MockCacheRepository()
    
    # Test set and get
    await cache.set("key1", "value1", 300)
    value = await cache.get("key1")
    assert value == "value1"
    
    # Test missing key
    assert await cache.get("missing") is None
```

## Success Criteria
- [ ] Interfaces follow Protocol pattern
- [ ] All methods have type hints
- [ ] Mock implementations work correctly
- [ ] Tests verify interface compliance
- [ ] Documentation is complete
- [ ] PR closes issue #3