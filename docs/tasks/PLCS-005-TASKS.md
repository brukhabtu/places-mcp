# PLCS-005: PlacesService Implementation Tasks

## Story
As a developer, I want a service to orchestrate place searches so that business logic is separated from infrastructure

## Task Breakdown

### Setup Phase
- [ ] Create places_mcp/services package
- [ ] Create __init__.py files
- [ ] Design service interface
- [ ] Plan dependency injection

### Base Service Class (TDD)
- [ ] Create tests/unit/test_base_service.py
- [ ] Test telemetry integration
- [ ] Test error handling
- [ ] Test context propagation
- [ ] Implement BaseService class
- [ ] Add logging setup
- [ ] Add metrics collection

### PlacesService Tests (TDD)
- [ ] Create tests/unit/test_places_service.py
- [ ] Mock PlacesRepository
- [ ] Test successful search
- [ ] Test empty results
- [ ] Test error propagation
- [ ] Test input validation
- [ ] Test logging behavior
- [ ] Test metrics emission

### PlacesService Implementation
- [ ] Create places_mcp/services/places.py
- [ ] Inherit from BaseService
- [ ] Constructor with repository injection
- [ ] Implement search_places method
- [ ] Add input sanitization
- [ ] Transform results if needed
- [ ] Add operation context

### Error Transformation
- [ ] Map infrastructure errors to service errors
- [ ] Add user-friendly error messages
- [ ] Preserve error context
- [ ] Test all error mappings
- [ ] Document error codes

### Logging and Telemetry
- [ ] Add structured logging
- [ ] Log search queries (sanitized)
- [ ] Log response times
- [ ] Log result counts
- [ ] Add correlation IDs
- [ ] Test log output

### Business Logic
- [ ] Validate search parameters
- [ ] Apply default values
- [ ] Sanitize user input
- [ ] Format results consistently
- [ ] Add result metadata

### Integration Tests
- [ ] Create tests/integration/test_service_integration.py
- [ ] Test with real repository
- [ ] Test error scenarios
- [ ] Test performance
- [ ] Verify logging

### Documentation
- [ ] Document service patterns
- [ ] Add usage examples
- [ ] Document error handling
- [ ] Add architectural notes

### Finalization
- [ ] Ensure >90% test coverage
- [ ] Review service design
- [ ] Optimize performance
- [ ] Create PR that closes #5

## Code Templates

### Test Setup
```python
# tests/unit/test_places_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock
from places_mcp.services.places import PlacesService
from places_mcp.domain.models import Place, Location
from places_mcp.domain.exceptions import NotFoundException, ValidationException
from places_mcp.tests.mocks import MockPlacesRepository

@pytest.fixture
def mock_repository():
    return MockPlacesRepository()

@pytest.fixture
def places_service(mock_repository):
    return PlacesService(repository=mock_repository)

@pytest.mark.asyncio
async def test_search_places_success(places_service):
    # Test successful search
    results = await places_service.search_places(
        query="pizza",
        location={"latitude": 40.7128, "longitude": -74.0060},
        radius=1000
    )
    
    assert len(results) > 0
    assert all(isinstance(r, Place) for r in results)
    assert all("pizza" in r.display_name.lower() for r in results)

@pytest.mark.asyncio
async def test_search_places_empty_query(places_service):
    # Test validation
    with pytest.raises(ValidationException) as exc:
        await places_service.search_places(query="")
    
    assert "Query cannot be empty" in str(exc.value)

@pytest.mark.asyncio
async def test_search_places_logs_metrics(places_service, caplog):
    # Test logging
    await places_service.search_places("test")
    
    assert "Searching places" in caplog.text
    assert "query=test" in caplog.text
    assert "Found 2 places" in caplog.text
```

### Base Service Implementation
```python
# places_mcp/services/base.py
import logging
import time
from typing import Optional, Dict, Any
from abc import ABC
import uuid

class BaseService(ABC):
    """Base class for all services"""
    
    def __init__(self, name: str):
        self.name = name
        self.logger = logging.getLogger(f"places_mcp.services.{name}")
        self._metrics = {}
    
    async def _execute_with_telemetry(
        self,
        operation: str,
        func,
        *args,
        **kwargs
    ):
        """Execute function with logging and metrics"""
        correlation_id = str(uuid.uuid4())
        start_time = time.time()
        
        self.logger.info(
            f"Starting {operation}",
            extra={
                "operation": operation,
                "correlation_id": correlation_id,
                "args": args,
                "kwargs": kwargs
            }
        )
        
        try:
            result = await func(*args, **kwargs)
            duration = time.time() - start_time
            
            self.logger.info(
                f"Completed {operation}",
                extra={
                    "operation": operation,
                    "correlation_id": correlation_id,
                    "duration_ms": duration * 1000,
                    "success": True
                }
            )
            
            self._record_metric(f"{operation}_duration", duration)
            self._record_metric(f"{operation}_success", 1)
            
            return result
            
        except Exception as e:
            duration = time.time() - start_time
            
            self.logger.error(
                f"Failed {operation}",
                extra={
                    "operation": operation,
                    "correlation_id": correlation_id,
                    "duration_ms": duration * 1000,
                    "error": str(e),
                    "error_type": type(e).__name__
                }
            )
            
            self._record_metric(f"{operation}_duration", duration)
            self._record_metric(f"{operation}_failure", 1)
            
            raise
    
    def _record_metric(self, name: str, value: float):
        """Record metric for monitoring"""
        if name not in self._metrics:
            self._metrics[name] = []
        self._metrics[name].append(value)
```

### PlacesService Implementation
```python
# places_mcp/services/places.py
from typing import List, Optional, Dict
from places_mcp.services.base import BaseService
from places_mcp.domain.ports import PlacesRepository
from places_mcp.domain.models import Place
from places_mcp.domain.exceptions import ValidationException

class PlacesService(BaseService):
    """Service for place-related operations"""
    
    def __init__(self, repository: PlacesRepository):
        super().__init__("places")
        self.repository = repository
    
    async def search_places(
        self,
        query: str,
        location: Optional[Dict[str, float]] = None,
        radius: Optional[int] = None,
        max_results: int = 20
    ) -> List[Place]:
        """Search for places with business logic"""
        
        # Validate input
        if not query or not query.strip():
            raise ValidationException("Query cannot be empty")
        
        if len(query) < 2:
            raise ValidationException("Query must be at least 2 characters")
        
        if radius and radius <= 0:
            raise ValidationException("Radius must be positive")
        
        if max_results < 1 or max_results > 50:
            raise ValidationException("Max results must be between 1 and 50")
        
        # Sanitize query
        sanitized_query = query.strip()
        
        # Log search parameters (sanitized)
        self.logger.info(
            "Searching places",
            extra={
                "query": sanitized_query[:50],  # Limit logged query length
                "has_location": location is not None,
                "radius": radius,
                "max_results": max_results
            }
        )
        
        # Execute search with telemetry
        async def _search():
            return await self.repository.search_text(
                query=sanitized_query,
                location=location,
                radius=radius,
                max_results=max_results
            )
        
        results = await self._execute_with_telemetry(
            "search_places",
            _search
        )
        
        # Log results summary
        self.logger.info(
            f"Found {len(results)} places",
            extra={
                "result_count": len(results),
                "query": sanitized_query[:50]
            }
        )
        
        return results
    
    async def get_service_stats(self) -> Dict[str, Any]:
        """Get service statistics"""
        return {
            "service": self.name,
            "metrics": self._metrics,
            "status": "healthy"
        }
```

### Error Handling Tests
```python
# tests/unit/test_places_service_errors.py
@pytest.mark.asyncio
async def test_repository_error_propagation(places_service, mock_repository):
    # Mock repository to raise error
    mock_repository.search_text = AsyncMock(
        side_effect=ExternalServiceException("API Error")
    )
    
    with pytest.raises(ExternalServiceException) as exc:
        await places_service.search_places("test")
    
    assert "API Error" in str(exc.value)

@pytest.mark.asyncio
async def test_validation_errors():
    service = PlacesService(MockPlacesRepository())
    
    # Test empty query
    with pytest.raises(ValidationException) as exc:
        await service.search_places("")
    assert "empty" in str(exc.value).lower()
    
    # Test short query
    with pytest.raises(ValidationException) as exc:
        await service.search_places("a")
    assert "2 characters" in str(exc.value)
    
    # Test invalid radius
    with pytest.raises(ValidationException) as exc:
        await service.search_places("test", radius=-100)
    assert "positive" in str(exc.value).lower()
```

### Integration Test
```python
# tests/integration/test_service_integration.py
@pytest.mark.asyncio
async def test_service_with_real_repository():
    # Use mock that simulates real behavior
    repository = MockPlacesRepository()
    service = PlacesService(repository)
    
    # Test full flow
    results = await service.search_places(
        query="pizza in new york",
        location={"latitude": 40.7128, "longitude": -74.0060},
        radius=5000,
        max_results=10
    )
    
    assert len(results) <= 10
    assert all(isinstance(r, Place) for r in results)
    
    # Verify metrics were recorded
    stats = await service.get_service_stats()
    assert "search_places_duration" in stats["metrics"]
    assert "search_places_success" in stats["metrics"]
```

## Success Criteria
- [ ] All tests pass
- [ ] >90% code coverage
- [ ] Clean separation from infrastructure
- [ ] Proper error handling
- [ ] Comprehensive logging
- [ ] PR closes issue #5