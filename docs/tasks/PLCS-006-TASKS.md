# PLCS-006: Search Places MCP Tool Tasks

## Story
As an AI assistant, I want to search for places using natural language so that I can help users find locations

## Task Breakdown

### Setup Phase
- [ ] Install FastMCP in project
- [ ] Create places_mcp/server.py
- [ ] Create places_mcp/__main__.py
- [ ] Plan tool structure

### MCP Server Tests (TDD)
- [ ] Create tests/unit/test_mcp_server.py
- [ ] Test server initialization
- [ ] Test tool registration
- [ ] Test tool metadata
- [ ] Mock service calls
- [ ] Test input validation
- [ ] Test error responses
- [ ] Test progress reporting

### Server Implementation
- [ ] Create FastMCP instance
- [ ] Add server metadata
- [ ] Configure server name and description
- [ ] Setup dependency injection
- [ ] Add health check endpoint
- [ ] Configure transport options

### Search Places Tool Tests
- [ ] Create tests/unit/test_search_tool.py
- [ ] Test with valid query
- [ ] Test with location bias
- [ ] Test with invalid inputs
- [ ] Test error handling
- [ ] Test progress updates
- [ ] Test response format

### Search Places Tool Implementation
- [ ] Define @mcp.tool decorator
- [ ] Add comprehensive docstring
- [ ] Define input parameters
- [ ] Add type hints
- [ ] Inject PlacesService
- [ ] Implement search logic
- [ ] Format results for AI

### Input Validation
- [ ] Validate query parameter
- [ ] Validate location format
- [ ] Validate radius range
- [ ] Return clear error messages
- [ ] Test all validation paths

### Progress Reporting
- [ ] Use Context for updates
- [ ] Report search started
- [ ] Report results found
- [ ] Report any warnings
- [ ] Test progress flow

### Error Handling
- [ ] Catch service exceptions
- [ ] Format errors for AI understanding
- [ ] Include troubleshooting hints
- [ ] Log errors appropriately
- [ ] Test error scenarios

### Integration Setup
- [ ] Wire up dependency injection
- [ ] Create container configuration
- [ ] Setup service providers
- [ ] Test DI resolution

### E2E Tests
- [ ] Create tests/e2e/test_mcp_e2e.py
- [ ] Test full server startup
- [ ] Test tool discovery
- [ ] Test actual search
- [ ] Test stdio transport
- [ ] Verify response format

### Documentation
- [ ] Document tool usage
- [ ] Add example queries
- [ ] Document parameters
- [ ] Add troubleshooting

### Finalization
- [ ] Ensure >90% test coverage
- [ ] Test with FastMCP CLI
- [ ] Verify AI-friendly output
- [ ] Create PR that closes #6

## Code Templates

### Test Setup
```python
# tests/unit/test_search_tool.py
import pytest
from unittest.mock import AsyncMock, MagicMock
from fastmcp import Context
from places_mcp.server import mcp
from places_mcp.domain.models import Place, Location
from places_mcp.services.places import PlacesService

@pytest.fixture
def mock_service():
    service = AsyncMock(spec=PlacesService)
    service.search_places.return_value = [
        Place(
            id="test1",
            display_name="Test Pizza Place",
            formatted_address="123 Main St",
            rating=4.5,
            location=Location(latitude=40.7128, longitude=-74.0060)
        )
    ]
    return service

@pytest.fixture
def mock_context():
    ctx = MagicMock(spec=Context)
    ctx.info = AsyncMock()
    ctx.error = AsyncMock()
    ctx.report_progress = AsyncMock()
    return ctx

@pytest.mark.asyncio
async def test_search_places_tool(mock_service, mock_context):
    # Import after mocking
    from places_mcp.server import search_places
    
    # Test tool execution
    results = await search_places(
        query="pizza",
        location={"latitude": 40.7128, "longitude": -74.0060},
        radius=1000,
        ctx=mock_context,
        service=mock_service
    )
    
    # Verify service called correctly
    mock_service.search_places.assert_called_once_with(
        query="pizza",
        location={"latitude": 40.7128, "longitude": -74.0060},
        radius=1000,
        max_results=20
    )
    
    # Verify progress reported
    assert mock_context.info.called
    assert any("Searching" in str(call) for call in mock_context.info.call_args_list)
    
    # Verify results format
    assert len(results) == 1
    assert results[0]["name"] == "Test Pizza Place"
    assert results[0]["rating"] == 4.5
```

### Server Implementation
```python
# places_mcp/server.py
from fastmcp import FastMCP, Context
from typing import Optional, Dict, List, Any
from dependency_injector.wiring import inject, Provide
from places_mcp.container import Container
from places_mcp.services.places import PlacesService
from places_mcp.domain.exceptions import ValidationException, ExternalServiceException

# Create MCP server instance
mcp = FastMCP(
    "Places API MCP Server",
    description="Search for places using Google Places API"
)

@mcp.tool
@inject
async def search_places(
    query: str,
    location: Optional[Dict[str, float]] = None,
    radius: Optional[int] = None,
    max_results: int = 20,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> List[Dict[str, Any]]:
    """
    Search for places using a text query.
    
    This tool searches for places matching your query and returns detailed information
    about each place found. You can optionally specify a location to search near.
    
    Args:
        query: Text search query (e.g., "pizza in new york", "coffee shops near me")
        location: Optional location bias as {"latitude": float, "longitude": float}
        radius: Optional search radius in meters (used with location)
        max_results: Maximum number of results to return (1-50, default 20)
        
    Returns:
        List of places with details including name, address, rating, location, etc.
        
    Examples:
        - search_places("best pizza in manhattan")
        - search_places("coffee shops", location={"latitude": 40.7, "longitude": -74.0}, radius=1000)
        - search_places("vegan restaurants in san francisco", max_results=10)
        
    Error Handling:
        - Returns clear error messages if search fails
        - Includes troubleshooting suggestions
        - Reports rate limit issues
    """
    
    # Report progress
    await ctx.info(f"Searching for places matching: '{query}'")
    
    if location:
        await ctx.info(f"Using location bias: {location['latitude']:.4f}, {location['longitude']:.4f}")
    
    try:
        # Validate inputs
        if not query or not query.strip():
            await ctx.error("Query cannot be empty")
            raise ValueError("Please provide a search query")
        
        if location:
            if "latitude" not in location or "longitude" not in location:
                await ctx.error("Invalid location format")
                raise ValueError("Location must include 'latitude' and 'longitude' fields")
            
            # Validate coordinate ranges
            if not -90 <= location["latitude"] <= 90:
                raise ValueError("Latitude must be between -90 and 90")
            if not -180 <= location["longitude"] <= 180:
                raise ValueError("Longitude must be between -180 and 180")
        
        if radius is not None:
            if radius <= 0:
                raise ValueError("Radius must be a positive number")
            if radius > 50000:
                raise ValueError("Radius cannot exceed 50,000 meters")
        
        # Perform search
        await ctx.report_progress(30, 100, "Contacting Places API...")
        
        places = await service.search_places(
            query=query,
            location=location,
            radius=radius,
            max_results=max_results
        )
        
        await ctx.report_progress(70, 100, f"Processing {len(places)} results...")
        
        # Format results for AI consumption
        results = []
        for place in places:
            result = {
                "name": place.display_name,
                "place_id": place.id,
                "address": place.formatted_address,
                "rating": place.rating,
                "user_ratings_total": place.user_rating_count,
                "types": place.types
            }
            
            if place.location:
                result["location"] = {
                    "latitude": place.location.latitude,
                    "longitude": place.location.longitude
                }
            
            results.append(result)
        
        await ctx.report_progress(100, 100, "Search complete")
        await ctx.info(f"Found {len(results)} places matching your query")
        
        return results
        
    except ValidationException as e:
        await ctx.error(f"Invalid input: {str(e)}")
        raise ValueError(f"Input validation failed: {str(e)}")
        
    except ExternalServiceException as e:
        await ctx.error(f"Places API error: {str(e)}")
        error_msg = "The Places API service is temporarily unavailable. "
        if "rate limit" in str(e).lower():
            error_msg += "Rate limit exceeded. Please try again later."
        else:
            error_msg += "Please try again in a few moments."
        raise RuntimeError(error_msg)
        
    except Exception as e:
        await ctx.error(f"Unexpected error: {str(e)}")
        raise RuntimeError(f"An unexpected error occurred: {str(e)}")

@mcp.tool
async def get_server_info() -> Dict[str, Any]:
    """
    Get information about this MCP server.
    
    Returns server capabilities, version, and configuration details.
    """
    return {
        "name": "Places API MCP Server",
        "version": "1.0.0",
        "capabilities": [
            "search_places",
            "get_place_details (coming in Sprint 2)",
            "find_nearby_places (coming in Sprint 2)",
            "autocomplete_places (coming in Sprint 3)"
        ],
        "configuration": {
            "max_results_limit": 50,
            "default_max_results": 20,
            "supports_location_bias": True,
            "max_radius_meters": 50000
        }
    }
```

### Dependency Injection Setup
```python
# places_mcp/container.py
from dependency_injector import containers, providers
from places_mcp.config.settings import Settings
from places_mcp.infrastructure.google_places import PlacesAPIClient
from places_mcp.services.places import PlacesService

class Container(containers.DeclarativeContainer):
    """Dependency injection container"""
    
    # Configuration
    config = providers.Configuration()
    
    settings = providers.Singleton(
        Settings
    )
    
    # Infrastructure
    places_api_client = providers.Singleton(
        PlacesAPIClient,
        api_key=settings.provided.google_api_key.get_secret_value()
    )
    
    # Services
    places_service = providers.Factory(
        PlacesService,
        repository=places_api_client
    )
```

### Main Entry Point
```python
# places_mcp/__main__.py
import sys
from places_mcp.server import mcp
from places_mcp.container import Container
from dependency_injector.wiring import wire

def main():
    # Setup dependency injection
    container = Container()
    wire(
        modules=[sys.modules["places_mcp.server"]],
        containers=[container]
    )
    
    # Run server
    mcp.run()

if __name__ == "__main__":
    main()
```

### E2E Test
```python
# tests/e2e/test_mcp_e2e.py
import pytest
import asyncio
from fastmcp import Client
from places_mcp.server import mcp
from places_mcp.container import Container

@pytest.mark.asyncio
async def test_search_places_e2e():
    # Setup test container with mocks
    container = Container()
    container.places_api_client.override(MockPlacesRepository())
    
    # Create in-memory client
    async with Client(mcp) as client:
        # Test tool discovery
        tools = await client.list_tools()
        assert any(t.name == "search_places" for t in tools)
        
        # Test tool execution
        result = await client.call_tool(
            "search_places",
            {"query": "pizza", "max_results": 5}
        )
        
        assert "result" in result
        places = result["result"]
        assert len(places) <= 5
        assert all("name" in p for p in places)
```

## Success Criteria
- [ ] Tool works via stdio transport
- [ ] Clear documentation for AI
- [ ] Comprehensive error handling
- [ ] Progress reporting works
- [ ] >90% test coverage
- [ ] PR closes issue #6