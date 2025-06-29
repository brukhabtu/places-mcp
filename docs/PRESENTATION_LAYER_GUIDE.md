# Presentation Layer Implementation Guide

## Overview

The Presentation Layer is responsible for exposing the Places API functionality through the Model Context Protocol (MCP). This guide covers the implementation of MCP tools and resources using FastMCP 2.0, with a focus on clear documentation, proper async patterns, and robust error handling.

## Table of Contents

1. [MCP Server Setup](#mcp-server-setup)
2. [Tool Implementations](#tool-implementations)
3. [Resource Endpoints](#resource-endpoints)
4. [Input Validation and Sanitization](#input-validation-and-sanitization)
5. [Error Handling and User Feedback](#error-handling-and-user-feedback)
6. [Context Usage for Progress and Logging](#context-usage-for-progress-and-logging)
7. [Integration with Dependency Injection](#integration-with-dependency-injection)
8. [Testing MCP Tools and Resources](#testing-mcp-tools-and-resources)

## MCP Server Setup

### Basic Server Structure

```python
# places_mcp/server.py
from fastmcp import FastMCP, Context
from typing import Optional, List, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create MCP server instance
mcp = FastMCP(
    "Google Places MCP Server",
    description="Access Google Places API functionality through MCP"
)

# Server metadata for LLMs
mcp.metadata = {
    "version": "1.0.0",
    "author": "Places MCP Team",
    "capabilities": [
        "search_places",
        "get_place_details",
        "find_nearby_places",
        "get_place_photos",
        "autocomplete_places"
    ]
}
```

### Server Configuration

```python
# places_mcp/__main__.py
import asyncio
from .server import mcp
from .container import Container
from .config import Settings

async def main():
    """Main entry point for the MCP server"""
    # Load configuration
    settings = Settings()
    
    # Initialize dependency container
    container = Container()
    container.config.from_pydantic(settings)
    
    # Wire dependencies
    container.wire(modules=[".server"])
    
    # Run server based on transport configuration
    if settings.mcp_transport == "stdio":
        await mcp.run()
    elif settings.mcp_transport == "http":
        await mcp.run(
            transport="http",
            port=settings.mcp_port,
            auth_public_key=settings.auth_public_key if settings.auth_enabled else None
        )
    else:
        raise ValueError(f"Unsupported transport: {settings.mcp_transport}")

if __name__ == "__main__":
    asyncio.run(main())
```

## Tool Implementations

### Search Places Tool

```python
@mcp.tool
@inject
async def search_places(
    query: str,
    location: Optional[Dict[str, float]] = None,
    radius: Optional[int] = None,
    max_results: Optional[int] = 20,
    price_levels: Optional[List[str]] = None,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> List[Dict[str, Any]]:
    """
    Search for places using a text query.
    
    This tool searches for places matching your query and returns relevant results.
    It's ideal for finding businesses, landmarks, or any type of location.
    
    Args:
        query: Natural language search query (e.g., "coffee shops near me", "best pizza in NYC")
        location: Optional center point as {"latitude": float, "longitude": float}
        radius: Optional search radius in meters (max: 50000)
        max_results: Maximum number of results to return (default: 20, max: 60)
        price_levels: Optional list of price levels to filter by:
            - "PRICE_LEVEL_FREE"
            - "PRICE_LEVEL_INEXPENSIVE" 
            - "PRICE_LEVEL_MODERATE"
            - "PRICE_LEVEL_EXPENSIVE"
            - "PRICE_LEVEL_VERY_EXPENSIVE"
        ctx: MCP context for progress reporting and logging
        
    Returns:
        List of place dictionaries containing:
        - id: Unique place identifier
        - display_name: Human-readable place name
        - formatted_address: Full address
        - location: Coordinates as {"latitude": float, "longitude": float}
        - rating: Average rating (1-5)
        - user_rating_count: Number of ratings
        - types: List of place types (e.g., ["restaurant", "food"])
        - price_level: Price level indicator
        
    Examples:
        >>> # Simple search
        >>> results = await search_places("coffee shops in Seattle")
        
        >>> # Search with location bias
        >>> results = await search_places(
        ...     "restaurants",
        ...     location={"latitude": 40.7128, "longitude": -74.0060},
        ...     radius=5000
        ... )
        
        >>> # Search with filters
        >>> results = await search_places(
        ...     "italian restaurants",
        ...     price_levels=["PRICE_LEVEL_MODERATE", "PRICE_LEVEL_EXPENSIVE"]
        ... )
    """
    # Input validation
    if not query or not query.strip():
        raise ValueError("Query cannot be empty")
    
    if radius and (radius < 1 or radius > 50000):
        raise ValueError("Radius must be between 1 and 50000 meters")
    
    if max_results and (max_results < 1 or max_results > 60):
        raise ValueError("Max results must be between 1 and 60")
    
    # Log search request
    await ctx.info(f"Searching for places: '{query}'")
    if location:
        await ctx.info(f"Location bias: {location['latitude']}, {location['longitude']}")
    
    try:
        # Report initial progress
        await ctx.report_progress(0, 100, "Starting search...")
        
        # Build search parameters
        search_params = SearchQuery(
            query=query,
            location=location,
            radius=radius,
            max_results=max_results,
            price_levels=price_levels
        )
        
        # Execute search
        await ctx.report_progress(30, 100, "Querying Google Places API...")
        results = await service.search_places(search_params)
        
        # Convert results to dictionaries
        await ctx.report_progress(80, 100, "Processing results...")
        place_dicts = [place.model_dump(exclude_none=True) for place in results]
        
        # Log results
        await ctx.info(f"Found {len(place_dicts)} places matching '{query}'")
        await ctx.report_progress(100, 100, "Search complete")
        
        return place_dicts
        
    except Exception as e:
        error_msg = f"Search failed: {str(e)}"
        await ctx.error(error_msg)
        logger.error(error_msg, exc_info=True)
        raise ValueError(error_msg) from e
```

### Get Place Details Tool

```python
@mcp.tool
@inject
async def get_place_details(
    place_id: str,
    fields: Optional[List[str]] = None,
    include_reviews: bool = False,
    include_photos: bool = False,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> Dict[str, Any]:
    """
    Get detailed information about a specific place.
    
    This tool retrieves comprehensive information about a place using its unique ID.
    You can customize which fields to retrieve to optimize for cost and performance.
    
    Args:
        place_id: Unique place identifier (obtained from search results)
        fields: Optional list of specific fields to retrieve. If None, returns basic fields.
            Available fields:
            - Basic: displayName, formattedAddress, location, types
            - Contact: internationalPhoneNumber, websiteUri
            - Business: regularOpeningHours, currentOpeningHours, priceLevel
            - Ratings: rating, userRatingCount
            - Atmosphere: paymentOptions, parkingOptions, accessibilityOptions
            - Content: generativeSummary, reviews, photos
            - New 2025: evChargeOptions
        include_reviews: Whether to include user reviews (default: False)
        include_photos: Whether to include photo metadata (default: False)
        ctx: MCP context for progress reporting
        
    Returns:
        Dictionary containing requested place details
        
    Examples:
        >>> # Get basic details
        >>> details = await get_place_details("ChIJj61dQgK6j4AR4GeTYWZsKWw")
        
        >>> # Get specific fields
        >>> details = await get_place_details(
        ...     "ChIJj61dQgK6j4AR4GeTYWZsKWw",
        ...     fields=["displayName", "rating", "websiteUri", "regularOpeningHours"]
        ... )
        
        >>> # Get full details with reviews and photos
        >>> details = await get_place_details(
        ...     "ChIJj61dQgK6j4AR4GeTYWZsKWw",
        ...     include_reviews=True,
        ...     include_photos=True
        ... )
    """
    # Validate place ID format
    if not place_id or not place_id.strip():
        raise ValueError("Place ID cannot be empty")
    
    if not place_id.startswith("ChIJ") and len(place_id) < 10:
        raise ValueError("Invalid place ID format")
    
    await ctx.info(f"Fetching details for place: {place_id}")
    
    try:
        # Default fields if none specified
        if not fields:
            fields = [
                "id", "displayName", "formattedAddress", "location",
                "rating", "userRatingCount", "types", "priceLevel"
            ]
        
        # Add review/photo fields if requested
        if include_reviews and "reviews" not in fields:
            fields.append("reviews")
        if include_photos and "photos" not in fields:
            fields.append("photos")
        
        # Validate field names
        valid_fields = {
            "id", "displayName", "formattedAddress", "location", "types",
            "rating", "userRatingCount", "priceLevel", "websiteUri",
            "internationalPhoneNumber", "regularOpeningHours", "currentOpeningHours",
            "reviews", "photos", "generativeSummary", "paymentOptions",
            "parkingOptions", "accessibilityOptions", "evChargeOptions"
        }
        
        invalid_fields = set(fields) - valid_fields
        if invalid_fields:
            raise ValueError(f"Invalid fields: {', '.join(invalid_fields)}")
        
        await ctx.report_progress(30, 100, "Retrieving place details...")
        
        # Get place details
        details = await service.get_place_details(place_id, fields)
        
        await ctx.report_progress(100, 100, "Details retrieved")
        await ctx.info(f"Retrieved details for: {details.display_name}")
        
        return details.model_dump(exclude_none=True)
        
    except Exception as e:
        error_msg = f"Failed to get place details: {str(e)}"
        await ctx.error(error_msg)
        raise ValueError(error_msg) from e
```

### Find Nearby Places Tool

```python
@mcp.tool
@inject
async def find_nearby_places(
    location: Dict[str, float],
    radius: int,
    place_types: Optional[List[str]] = None,
    keyword: Optional[str] = None,
    min_rating: Optional[float] = None,
    open_now: bool = False,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> List[Dict[str, Any]]:
    """
    Find places near a specific location.
    
    This tool searches for places within a circular area around a given point.
    It's perfect for finding nearby amenities, businesses, or points of interest.
    
    Args:
        location: Center point as {"latitude": float, "longitude": float}
        radius: Search radius in meters (max: 50000)
        place_types: Optional list of place types to filter by. Common types:
            - "restaurant", "cafe", "bar"
            - "hotel", "lodging"
            - "shopping_mall", "store", "supermarket"
            - "hospital", "pharmacy", "doctor"
            - "bank", "atm"
            - "gas_station", "parking", "ev_charger"
            - "tourist_attraction", "museum", "park"
        keyword: Optional keyword to filter results (e.g., "vegetarian", "24 hours")
        min_rating: Optional minimum rating filter (1.0 - 5.0)
        open_now: Only return places that are currently open (default: False)
        ctx: MCP context for progress reporting
        
    Returns:
        List of nearby places sorted by distance
        
    Examples:
        >>> # Find all restaurants within 1km
        >>> places = await find_nearby_places(
        ...     location={"latitude": 37.7749, "longitude": -122.4194},
        ...     radius=1000,
        ...     place_types=["restaurant"]
        ... )
        
        >>> # Find highly-rated cafes that are open now
        >>> places = await find_nearby_places(
        ...     location={"latitude": 40.7128, "longitude": -74.0060},
        ...     radius=2000,
        ...     place_types=["cafe"],
        ...     min_rating=4.0,
        ...     open_now=True
        ... )
    """
    # Validate inputs
    if not location or "latitude" not in location or "longitude" not in location:
        raise ValueError("Location must include latitude and longitude")
    
    if not -90 <= location["latitude"] <= 90:
        raise ValueError("Latitude must be between -90 and 90")
    
    if not -180 <= location["longitude"] <= 180:
        raise ValueError("Longitude must be between -180 and 180")
    
    if radius < 1 or radius > 50000:
        raise ValueError("Radius must be between 1 and 50000 meters")
    
    if min_rating and (min_rating < 1.0 or min_rating > 5.0):
        raise ValueError("Min rating must be between 1.0 and 5.0")
    
    await ctx.info(f"Searching for nearby places at {location['latitude']}, {location['longitude']}")
    
    try:
        await ctx.report_progress(20, 100, "Preparing nearby search...")
        
        # Build search parameters
        search_params = {
            "location": location,
            "radius": radius,
            "types": place_types,
            "keyword": keyword,
            "min_rating": min_rating,
            "open_now": open_now
        }
        
        # Execute search
        await ctx.report_progress(50, 100, "Searching nearby places...")
        results = await service.search_nearby(**search_params)
        
        # Sort by distance
        await ctx.report_progress(80, 100, "Sorting by distance...")
        sorted_results = sorted(results, key=lambda p: p.distance or float('inf'))
        
        # Convert to dictionaries
        place_dicts = [place.model_dump(exclude_none=True) for place in sorted_results]
        
        await ctx.info(f"Found {len(place_dicts)} nearby places within {radius}m")
        await ctx.report_progress(100, 100, "Search complete")
        
        return place_dicts
        
    except Exception as e:
        error_msg = f"Nearby search failed: {str(e)}"
        await ctx.error(error_msg)
        raise ValueError(error_msg) from e
```

### Autocomplete Places Tool

```python
@mcp.tool
@inject
async def autocomplete_places(
    input_text: str,
    session_token: Optional[str] = None,
    location_bias: Optional[Dict[str, float]] = None,
    location_restriction: Optional[Dict[str, Any]] = None,
    types: Optional[List[str]] = None,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> Dict[str, Any]:
    """
    Get place predictions as the user types.
    
    This tool provides real-time place suggestions based on partial input.
    Use session tokens to group requests for billing optimization.
    
    Args:
        input_text: Partial text input from the user (min 1 character)
        session_token: Optional session token to group autocomplete requests
        location_bias: Optional location to bias results towards
        location_restriction: Optional strict location bounds as:
            {"circle": {"center": {...}, "radius": float}} or
            {"rectangle": {"southwest": {...}, "northeast": {...}}}
        types: Optional place type filters (e.g., ["restaurant", "cafe"])
        ctx: MCP context
        
    Returns:
        Dictionary containing:
        - predictions: List of place predictions
        - session_token: Token to use for subsequent requests
        
    Examples:
        >>> # Simple autocomplete
        >>> result = await autocomplete_places("pizza in san")
        
        >>> # With session token for billing optimization
        >>> result = await autocomplete_places(
        ...     "coffee",
        ...     session_token="abc123",
        ...     location_bias={"latitude": 37.7749, "longitude": -122.4194}
        ... )
    """
    if not input_text or len(input_text) < 1:
        raise ValueError("Input text must be at least 1 character")
    
    await ctx.info(f"Autocomplete for: '{input_text}'")
    
    try:
        result = await service.autocomplete(
            input_text=input_text,
            session_token=session_token,
            location_bias=location_bias,
            location_restriction=location_restriction,
            types=types
        )
        
        await ctx.info(f"Found {len(result['predictions'])} suggestions")
        return result
        
    except Exception as e:
        error_msg = f"Autocomplete failed: {str(e)}"
        await ctx.error(error_msg)
        raise ValueError(error_msg) from e
```

## Resource Endpoints

### Recent Searches Resource

```python
@mcp.resource("places://recent-searches")
@inject
async def get_recent_searches(
    limit: int = 10,
    service: PlacesService = Provide[Container.places_service]
) -> Dict[str, Any]:
    """
    Get recently performed searches.
    
    Returns:
        Dictionary containing:
        - searches: List of recent search queries with timestamps
        - total_count: Total number of searches in history
    """
    recent = await service.get_recent_searches(limit=limit)
    return {
        "searches": [search.model_dump() for search in recent],
        "total_count": len(recent),
        "resource_type": "recent_searches",
        "generated_at": datetime.utcnow().isoformat()
    }
```

### Cached Places Resource

```python
@mcp.resource("places://cached/{place_id}")
@inject
async def get_cached_place(
    place_id: str,
    service: PlacesService = Provide[Container.places_service]
) -> Optional[Dict[str, Any]]:
    """
    Get cached place details if available.
    
    Args:
        place_id: Unique place identifier
        
    Returns:
        Cached place details or None if not in cache
    """
    cached = await service.get_from_cache(place_id)
    if cached:
        return {
            "place": cached.model_dump(),
            "cached_at": cached.cached_at.isoformat(),
            "expires_at": cached.expires_at.isoformat(),
            "resource_type": "cached_place"
        }
    return None
```

### API Statistics Resource

```python
@mcp.resource("places://stats")
@inject
async def get_api_statistics(
    service: PlacesService = Provide[Container.places_service]
) -> Dict[str, Any]:
    """
    Get API usage statistics.
    
    Returns:
        Dictionary containing:
        - total_requests: Total API requests made
        - cache_hits: Number of cache hits
        - cache_hit_rate: Percentage of requests served from cache
        - avg_response_time: Average API response time in ms
        - quota_usage: Current quota usage information
    """
    stats = await service.get_statistics()
    return {
        "resource_type": "api_statistics",
        "statistics": stats.model_dump(),
        "generated_at": datetime.utcnow().isoformat()
    }
```

## Input Validation and Sanitization

### Pydantic Models for Validation

```python
# places_mcp/domain/validation.py
from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict, Any
from datetime import datetime

class LocationInput(BaseModel):
    """Validated location coordinates"""
    latitude: float = Field(..., ge=-90, le=90, description="Latitude in degrees")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude in degrees")
    
    @validator("latitude", "longitude")
    def validate_precision(cls, v):
        # Limit precision to 6 decimal places
        return round(v, 6)

class SearchInput(BaseModel):
    """Validated search parameters"""
    query: str = Field(..., min_length=1, max_length=200)
    location: Optional[LocationInput] = None
    radius: Optional[int] = Field(None, ge=1, le=50000)
    max_results: Optional[int] = Field(20, ge=1, le=60)
    price_levels: Optional[List[str]] = None
    
    @validator("query")
    def sanitize_query(cls, v):
        # Remove excessive whitespace and special characters
        return " ".join(v.strip().split())
    
    @validator("price_levels")
    def validate_price_levels(cls, v):
        if v:
            valid_levels = {
                "PRICE_LEVEL_FREE",
                "PRICE_LEVEL_INEXPENSIVE",
                "PRICE_LEVEL_MODERATE",
                "PRICE_LEVEL_EXPENSIVE",
                "PRICE_LEVEL_VERY_EXPENSIVE"
            }
            invalid = set(v) - valid_levels
            if invalid:
                raise ValueError(f"Invalid price levels: {invalid}")
        return v

class PlaceIdInput(BaseModel):
    """Validated place ID"""
    place_id: str = Field(..., min_length=10, max_length=100)
    
    @validator("place_id")
    def validate_place_id_format(cls, v):
        # Basic validation for place ID format
        if not v.strip():
            raise ValueError("Place ID cannot be empty")
        # Remove any potential SQL injection attempts
        if any(char in v for char in ["'", '"', ";", "--", "/*", "*/"]):
            raise ValueError("Invalid characters in place ID")
        return v.strip()
```

### Input Sanitization Utilities

```python
# places_mcp/utils/sanitization.py
import re
import html
from typing import Any, Dict, List

def sanitize_string(value: str, max_length: int = 1000) -> str:
    """Sanitize string input"""
    if not value:
        return ""
    
    # HTML escape
    value = html.escape(value)
    
    # Remove control characters
    value = re.sub(r'[\x00-\x1F\x7F-\x9F]', '', value)
    
    # Normalize whitespace
    value = ' '.join(value.split())
    
    # Truncate to max length
    return value[:max_length]

def sanitize_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    """Recursively sanitize dictionary values"""
    sanitized = {}
    for key, value in data.items():
        if isinstance(value, str):
            sanitized[key] = sanitize_string(value)
        elif isinstance(value, dict):
            sanitized[key] = sanitize_dict(value)
        elif isinstance(value, list):
            sanitized[key] = sanitize_list(value)
        else:
            sanitized[key] = value
    return sanitized

def sanitize_list(data: List[Any]) -> List[Any]:
    """Sanitize list values"""
    return [
        sanitize_string(item) if isinstance(item, str)
        else sanitize_dict(item) if isinstance(item, dict)
        else sanitize_list(item) if isinstance(item, list)
        else item
        for item in data
    ]
```

## Error Handling and User Feedback

### Custom Exception Classes

```python
# places_mcp/domain/exceptions.py
class PlacesMCPError(Exception):
    """Base exception for Places MCP"""
    def __init__(self, message: str, details: Optional[Dict] = None):
        super().__init__(message)
        self.details = details or {}

class ValidationError(PlacesMCPError):
    """Input validation error"""
    pass

class APIError(PlacesMCPError):
    """Google Places API error"""
    def __init__(self, message: str, status_code: int, api_response: Optional[Dict] = None):
        super().__init__(message, {"status_code": status_code, "api_response": api_response})
        self.status_code = status_code

class QuotaExceededError(APIError):
    """API quota exceeded"""
    pass

class RateLimitError(APIError):
    """Rate limit exceeded"""
    def __init__(self, message: str, retry_after: Optional[int] = None):
        super().__init__(message, 429)
        self.retry_after = retry_after

class NotFoundError(APIError):
    """Resource not found"""
    def __init__(self, resource_type: str, resource_id: str):
        super().__init__(
            f"{resource_type} not found: {resource_id}",
            404,
            {"resource_type": resource_type, "resource_id": resource_id}
        )
```

### Error Handler Decorator

```python
# places_mcp/utils/error_handling.py
from functools import wraps
from typing import Callable
import logging

logger = logging.getLogger(__name__)

def handle_mcp_errors(func: Callable) -> Callable:
    """Decorator to handle and transform errors for MCP tools"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        ctx = kwargs.get("ctx")
        
        try:
            return await func(*args, **kwargs)
            
        except ValidationError as e:
            # User-friendly validation errors
            error_msg = f"Invalid input: {str(e)}"
            if ctx:
                await ctx.error(error_msg)
            logger.warning(f"Validation error in {func.__name__}: {e}", extra=e.details)
            raise ValueError(error_msg) from e
            
        except QuotaExceededError as e:
            # Quota errors with helpful guidance
            error_msg = "API quota exceeded. Please check your Google Cloud Console for quota limits."
            if ctx:
                await ctx.error(error_msg)
            logger.error(f"Quota exceeded in {func.__name__}: {e}")
            raise ValueError(error_msg) from e
            
        except RateLimitError as e:
            # Rate limit with retry information
            retry_msg = f" Retry after {e.retry_after} seconds." if e.retry_after else ""
            error_msg = f"Rate limit exceeded.{retry_msg}"
            if ctx:
                await ctx.error(error_msg)
            logger.warning(f"Rate limit in {func.__name__}: {e}")
            raise ValueError(error_msg) from e
            
        except NotFoundError as e:
            # Not found errors
            error_msg = str(e)
            if ctx:
                await ctx.error(error_msg)
            logger.info(f"Not found in {func.__name__}: {e}")
            raise ValueError(error_msg) from e
            
        except APIError as e:
            # Other API errors
            error_msg = f"Google Places API error: {str(e)}"
            if ctx:
                await ctx.error(error_msg)
            logger.error(f"API error in {func.__name__}: {e}", extra=e.details)
            raise ValueError(error_msg) from e
            
        except Exception as e:
            # Unexpected errors
            error_msg = f"An unexpected error occurred: {str(e)}"
            if ctx:
                await ctx.error(error_msg)
            logger.exception(f"Unexpected error in {func.__name__}")
            raise ValueError(error_msg) from e
    
    return wrapper
```

### Apply Error Handling to Tools

```python
# Updated tool with error handling
@mcp.tool
@handle_mcp_errors
@inject
async def search_places(
    query: str,
    location: Optional[Dict[str, float]] = None,
    # ... other parameters
) -> List[Dict[str, Any]]:
    # Validation using Pydantic
    search_input = SearchInput(
        query=query,
        location=LocationInput(**location) if location else None,
        # ... other fields
    )
    
    # Tool implementation continues...
```

## Context Usage for Progress and Logging

### Enhanced Context Utilities

```python
# places_mcp/utils/context.py
from fastmcp import Context
from typing import Optional, Any
import time

class MCPContextManager:
    """Enhanced context management for MCP tools"""
    
    def __init__(self, ctx: Optional[Context]):
        self.ctx = ctx
        self.start_time = time.time()
        self.operation_name = None
    
    async def start_operation(self, name: str, total_steps: int = 100):
        """Start a new operation with progress tracking"""
        self.operation_name = name
        self.total_steps = total_steps
        self.current_step = 0
        
        if self.ctx:
            await self.ctx.info(f"Starting: {name}")
            await self.ctx.report_progress(0, total_steps, f"Initializing {name}")
    
    async def update_progress(self, step: int, message: str):
        """Update operation progress"""
        self.current_step = step
        if self.ctx:
            await self.ctx.report_progress(step, self.total_steps, message)
    
    async def log_info(self, message: str, **kwargs):
        """Log informational message with metadata"""
        if self.ctx:
            metadata = {
                "operation": self.operation_name,
                "elapsed_time": time.time() - self.start_time,
                **kwargs
            }
            await self.ctx.info(f"{message} | {metadata}")
    
    async def log_warning(self, message: str, **kwargs):
        """Log warning message"""
        if self.ctx:
            await self.ctx.warning(f"⚠️ {message}")
    
    async def log_error(self, message: str, error: Optional[Exception] = None):
        """Log error message"""
        if self.ctx:
            error_detail = f" ({type(error).__name__}: {str(error)})" if error else ""
            await self.ctx.error(f"❌ {message}{error_detail}")
    
    async def complete_operation(self, result_summary: str):
        """Mark operation as complete"""
        if self.ctx:
            elapsed = time.time() - self.start_time
            await self.ctx.report_progress(
                self.total_steps, 
                self.total_steps, 
                f"✓ {self.operation_name} complete"
            )
            await self.ctx.info(f"Completed in {elapsed:.2f}s: {result_summary}")
```

### Using Enhanced Context

```python
@mcp.tool
async def search_with_context(query: str, ctx: Context = None) -> List[Dict]:
    """Example tool using enhanced context management"""
    context_mgr = MCPContextManager(ctx)
    
    try:
        await context_mgr.start_operation("Place Search", total_steps=100)
        
        # Validation phase
        await context_mgr.update_progress(10, "Validating input...")
        # ... validation logic
        
        # API call phase
        await context_mgr.update_progress(30, "Calling Google Places API...")
        await context_mgr.log_info("API Request", endpoint="searchText", query=query)
        # ... API call
        
        # Processing phase
        await context_mgr.update_progress(70, "Processing results...")
        # ... processing logic
        
        # Complete
        await context_mgr.complete_operation(f"Found {len(results)} places")
        return results
        
    except Exception as e:
        await context_mgr.log_error("Search failed", error=e)
        raise
```

## Integration with Dependency Injection

### Container Setup

```python
# places_mcp/container.py
from dependency_injector import containers, providers
from .services import PlacesService, SearchService, DetailsService
from .infrastructure import PlacesAPIClient, RedisCacheManager
from .config import Settings

class Container(containers.DeclarativeContainer):
    """DI container for Places MCP"""
    
    # Configuration
    config = providers.Configuration()
    
    # Infrastructure providers
    places_client = providers.Singleton(
        PlacesAPIClient,
        api_key=config.google_api_key,
        timeout=config.api_timeout,
        max_retries=config.api_max_retries
    )
    
    cache_manager = providers.Singleton(
        RedisCacheManager,
        url=config.redis_url,
        ttl=config.cache_ttl,
        key_prefix="places_mcp"
    )
    
    rate_limiter = providers.Singleton(
        RateLimiter,
        requests_per_minute=config.rate_limit_requests,
        cache=cache_manager
    )
    
    # Service providers
    search_service = providers.Factory(
        SearchService,
        api_client=places_client,
        cache=cache_manager,
        rate_limiter=rate_limiter
    )
    
    details_service = providers.Factory(
        DetailsService,
        api_client=places_client,
        cache=cache_manager
    )
    
    places_service = providers.Factory(
        PlacesService,
        search_service=search_service,
        details_service=details_service,
        cache=cache_manager
    )
```

### Wiring Dependencies

```python
# places_mcp/__init__.py
from .container import Container
from .server import mcp

# Create container instance
container = Container()

# Wire container to modules
container.wire(modules=[
    ".server",
    ".tools",
    ".resources"
])

__all__ = ["mcp", "container"]
```

### Using Injected Dependencies

```python
# places_mcp/tools/search.py
from dependency_injector.wiring import inject, Provide
from ..container import Container
from ..services import PlacesService

@inject
async def search_places_impl(
    query: str,
    service: PlacesService = Provide[Container.places_service]
) -> List[Dict]:
    """Implementation with injected service"""
    return await service.search_places(query)
```

## Testing MCP Tools and Resources

### Unit Testing Tools

```python
# tests/unit/test_tools.py
import pytest
from unittest.mock import AsyncMock, MagicMock
from places_mcp.server import search_places
from places_mcp.domain.models import Place
from fastmcp import Context

@pytest.fixture
def mock_context():
    """Mock MCP context"""
    ctx = MagicMock(spec=Context)
    ctx.info = AsyncMock()
    ctx.error = AsyncMock()
    ctx.report_progress = AsyncMock()
    return ctx

@pytest.fixture
def mock_places_service():
    """Mock places service"""
    service = AsyncMock()
    return service

@pytest.mark.asyncio
async def test_search_places_success(mock_context, mock_places_service):
    """Test successful place search"""
    # Arrange
    mock_places_service.search_places.return_value = [
        Place(
            id="test123",
            display_name="Test Place",
            formatted_address="123 Test St",
            rating=4.5
        )
    ]
    
    # Act
    result = await search_places(
        query="test query",
        ctx=mock_context,
        service=mock_places_service
    )
    
    # Assert
    assert len(result) == 1
    assert result[0]["display_name"] == "Test Place"
    mock_context.info.assert_called()
    mock_context.report_progress.assert_called()

@pytest.mark.asyncio
async def test_search_places_validation_error(mock_context, mock_places_service):
    """Test search with invalid input"""
    # Act & Assert
    with pytest.raises(ValueError, match="Query cannot be empty"):
        await search_places(
            query="",
            ctx=mock_context,
            service=mock_places_service
        )
    
    mock_context.error.assert_called_once()

@pytest.mark.asyncio
async def test_search_places_api_error(mock_context, mock_places_service):
    """Test search with API error"""
    # Arrange
    mock_places_service.search_places.side_effect = APIError(
        "API Error",
        status_code=403
    )
    
    # Act & Assert
    with pytest.raises(ValueError, match="Google Places API error"):
        await search_places(
            query="test",
            ctx=mock_context,
            service=mock_places_service
        )
```

### Integration Testing

```python
# tests/integration/test_mcp_server.py
import pytest
from fastmcp.testing import MCPTestClient
from places_mcp.server import mcp
from places_mcp.container import Container

@pytest.fixture
async def test_client():
    """Create test client with mocked dependencies"""
    container = Container()
    
    # Override with test configuration
    container.config.google_api_key.override("test_key")
    container.config.redis_url.override("redis://localhost:6379/15")
    
    # Create test client
    async with MCPTestClient(mcp) as client:
        yield client

@pytest.mark.asyncio
async def test_tool_listing(test_client):
    """Test listing available tools"""
    tools = await test_client.list_tools()
    
    assert len(tools) > 0
    tool_names = [tool["name"] for tool in tools]
    assert "search_places" in tool_names
    assert "get_place_details" in tool_names

@pytest.mark.asyncio
async def test_search_places_integration(test_client):
    """Test search places tool integration"""
    result = await test_client.call_tool(
        "search_places",
        {
            "query": "coffee shops",
            "max_results": 5
        }
    )
    
    assert "result" in result
    assert isinstance(result["result"], list)

@pytest.mark.asyncio
async def test_resource_access(test_client):
    """Test resource endpoint access"""
    resource = await test_client.read_resource("places://recent-searches")
    
    assert resource is not None
    assert "searches" in resource
    assert "total_count" in resource
```

### End-to-End Testing

```python
# tests/e2e/test_full_flow.py
import pytest
import asyncio
from places_mcp import mcp, container
from places_mcp.config import Settings

@pytest.fixture
def e2e_settings():
    """E2E test settings"""
    return Settings(
        google_api_key="test_api_key",
        mcp_transport="stdio",
        redis_url="redis://localhost:6379/14"
    )

@pytest.mark.asyncio
async def test_full_search_flow(e2e_settings):
    """Test complete search and details flow"""
    # Initialize container with test settings
    container.config.from_pydantic(e2e_settings)
    
    # Simulate tool calls
    search_result = await mcp.call_tool(
        "search_places",
        {"query": "pizza in New York"}
    )
    
    assert len(search_result) > 0
    place_id = search_result[0]["id"]
    
    # Get place details
    details = await mcp.call_tool(
        "get_place_details",
        {"place_id": place_id, "include_reviews": True}
    )
    
    assert details["id"] == place_id
    assert "display_name" in details
```

### Testing Best Practices

1. **Mock External Dependencies**: Always mock Google Places API calls in unit tests
2. **Test Validation**: Ensure input validation works correctly
3. **Test Error Scenarios**: Cover all error paths
4. **Test Context Usage**: Verify progress reporting and logging
5. **Use Fixtures**: Create reusable test fixtures for common setups
6. **Test Async Behavior**: Use pytest-asyncio for async testing
7. **Coverage Goals**: Aim for >90% code coverage

## Summary

This Presentation Layer Guide provides comprehensive coverage of:

1. **MCP Server Setup**: Complete server initialization with FastMCP
2. **Tool Implementations**: Detailed tool definitions with clear documentation
3. **Resource Endpoints**: RESTful-style resource access patterns
4. **Input Validation**: Robust validation using Pydantic models
5. **Error Handling**: User-friendly error messages and proper exception handling
6. **Context Usage**: Advanced progress reporting and logging
7. **Dependency Injection**: Clean architecture with DI container
8. **Testing**: Comprehensive testing strategies and examples

The implementation focuses on:
- Clear documentation for LLM understanding
- Proper async/await patterns throughout
- Strong typing with Python type hints
- Descriptive error messages for AI assistants
- Progress reporting for long-running operations
- Clean separation of concerns
- Testable and maintainable code

This guide serves as the foundation for building a production-ready MCP server that exposes Google Places API functionality to AI assistants in a safe, efficient, and user-friendly manner.