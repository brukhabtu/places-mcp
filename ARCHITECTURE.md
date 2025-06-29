# Places MCP Server Architecture

## Overview

A Model Context Protocol (MCP) server that provides AI assistants with access to Google Places API functionality. Built with FastMCP 2.0, Python 3.13, and following strict separation of concerns.

## Architecture Layers

### 1. Presentation Layer (MCP Interface)
**Responsibility**: Expose tools and resources via MCP protocol
**Location**: `places_mcp/server.py`
**Components**:
- FastMCP server instance
- Tool definitions with proper type hints
- Resource endpoints
- Error handling and validation

### 2. Application Layer (Business Logic)
**Responsibility**: Orchestrate operations and enforce business rules
**Location**: `places_mcp/services/`
**Components**:
- `PlacesService`: Main service orchestrator
- `SearchService`: Search-specific logic
- `DetailsService`: Place details operations
- `PhotoService`: Photo management

### 3. Domain Layer (Core Models)
**Responsibility**: Define core business entities
**Location**: `places_mcp/domain/`
**Components**:
- `Place`: Core place entity
- `SearchQuery`: Search parameters model
- `PlaceDetails`: Detailed place information
- `Photo`: Photo metadata model

### 4. Infrastructure Layer (External Integration)
**Responsibility**: Handle Google Places API communication
**Location**: `places_mcp/infrastructure/`
**Components**:
- `PlacesAPIClient`: API client wrapper
- `AuthManager`: API key and auth management
- `RateLimiter`: Rate limiting implementation
- `CacheManager`: Response caching

### 5. Configuration Layer
**Responsibility**: Manage configuration and secrets
**Location**: `places_mcp/config/`
**Components**:
- `Settings`: Pydantic settings model
- YAML configuration with `!env` tags
- Environment variable management

## Layer Separation Enforcement

### 1. Dependency Rules
- Dependencies flow inward only (Presentation → Application → Domain)
- Domain layer has zero external dependencies
- Infrastructure implements interfaces defined in Domain

### 2. Interface Contracts
```python
# places_mcp/domain/ports.py
from abc import ABC, abstractmethod
from typing import Protocol

class PlacesRepository(Protocol):
    """Interface for places data access"""
    async def search_text(self, query: str, **kwargs) -> list[Place]:
        ...
    
    async def get_details(self, place_id: str, fields: list[str]) -> PlaceDetails:
        ...

class CacheRepository(Protocol):
    """Interface for caching"""
    async def get(self, key: str) -> Optional[Any]:
        ...
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        ...
```

### 3. Dependency Injection
```python
# places_mcp/container.py
from dependency_injector import containers, providers

class Container(containers.DeclarativeContainer):
    config = providers.Configuration()
    
    # Infrastructure
    places_client = providers.Singleton(
        PlacesAPIClient,
        api_key=config.google_api_key
    )
    
    cache_manager = providers.Singleton(
        RedisCacheManager,
        url=config.redis_url
    )
    
    # Services
    places_service = providers.Factory(
        PlacesService,
        repository=places_client,
        cache=cache_manager
    )
```

## Project Structure

```
places-mcp/
├── places_mcp/
│   ├── __init__.py
│   ├── __main__.py          # Entry point
│   ├── server.py            # MCP server definition
│   ├── container.py         # DI container
│   ├── domain/
│   │   ├── __init__.py
│   │   ├── models.py        # Domain entities
│   │   ├── ports.py         # Interface definitions
│   │   └── exceptions.py    # Domain exceptions
│   ├── services/
│   │   ├── __init__.py
│   │   ├── places.py        # Main service
│   │   ├── search.py        # Search operations
│   │   └── details.py       # Details operations
│   ├── infrastructure/
│   │   ├── __init__.py
│   │   ├── google_places.py # API client
│   │   ├── cache.py         # Cache implementation
│   │   └── auth.py          # Authentication
│   └── config/
│       ├── __init__.py
│       ├── settings.py      # Pydantic settings
│       └── config.yaml      # YAML config
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── docs/
│   ├── FASTMCP_2.0_GUIDE.md
│   └── GOOGLE_PLACES_API_GUIDE.md
├── pyproject.toml
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Implementation Details

### 1. MCP Server Definition
```python
# places_mcp/server.py
from fastmcp import FastMCP, Context
from dependency_injector.wiring import inject, Provide
from .container import Container
from .services import PlacesService

mcp = FastMCP("Places API MCP Server")

@mcp.tool
@inject
async def search_places(
    query: str,
    location: Optional[dict] = None,
    radius: Optional[int] = None,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> list[dict]:
    """Search for places using text query"""
    await ctx.info(f"Searching for: {query}")
    
    try:
        results = await service.search_text(
            query=query,
            location=location,
            radius=radius
        )
        await ctx.info(f"Found {len(results)} places")
        return [place.dict() for place in results]
    except Exception as e:
        await ctx.error(f"Search failed: {str(e)}")
        raise

@mcp.tool
@inject
async def get_place_details(
    place_id: str,
    fields: list[str] = None,
    ctx: Context = None,
    service: PlacesService = Provide[Container.places_service]
) -> dict:
    """Get detailed information about a place"""
    if not fields:
        fields = ["displayName", "formattedAddress", "rating"]
    
    details = await service.get_place_details(place_id, fields)
    return details.dict()

@mcp.resource("places://recent-searches")
@inject
async def get_recent_searches(
    service: PlacesService = Provide[Container.places_service]
) -> list[dict]:
    """Get recent search queries"""
    return await service.get_recent_searches()
```

### 2. Service Layer
```python
# places_mcp/services/places.py
from ..domain.models import Place, PlaceDetails, SearchQuery
from ..domain.ports import PlacesRepository, CacheRepository

class PlacesService:
    def __init__(
        self,
        repository: PlacesRepository,
        cache: CacheRepository
    ):
        self.repository = repository
        self.cache = cache
        self._recent_searches: list[SearchQuery] = []
    
    async def search_text(
        self,
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None
    ) -> list[Place]:
        # Check cache
        cache_key = f"search:{query}:{location}:{radius}"
        cached = await self.cache.get(cache_key)
        if cached:
            return cached
        
        # Perform search
        results = await self.repository.search_text(
            query=query,
            location=location,
            radius=radius
        )
        
        # Cache results (30 minutes as per Google TOS)
        await self.cache.set(cache_key, results, ttl=1800)
        
        # Track search
        self._recent_searches.append(SearchQuery(
            query=query,
            location=location,
            radius=radius
        ))
        
        return results
```

### 3. Domain Models
```python
# places_mcp/domain/models.py
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

class Location(BaseModel):
    latitude: float
    longitude: float

class Place(BaseModel):
    id: str
    display_name: str
    formatted_address: Optional[str] = None
    location: Optional[Location] = None
    rating: Optional[float] = None
    user_rating_count: Optional[int] = None
    types: List[str] = Field(default_factory=list)

class PlaceDetails(Place):
    website_uri: Optional[str] = None
    phone_number: Optional[str] = None
    opening_hours: Optional[dict] = None
    price_level: Optional[str] = None
    reviews: List[dict] = Field(default_factory=list)
    photos: List[dict] = Field(default_factory=list)
    generative_summary: Optional[dict] = None
    # New 2025 fields
    payment_options: Optional[dict] = None
    parking_options: Optional[dict] = None
    accessibility_options: Optional[dict] = None
    ev_charge_options: Optional[dict] = None

class SearchQuery(BaseModel):
    query: str
    location: Optional[dict] = None
    radius: Optional[int] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)
```

### 4. Infrastructure Implementation
```python
# places_mcp/infrastructure/google_places.py
import httpx
from typing import List, Optional
from ..domain.models import Place, PlaceDetails
from ..domain.ports import PlacesRepository

class PlacesAPIClient(PlacesRepository):
    BASE_URL = "https://places.googleapis.com/v1"
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.client = httpx.AsyncClient(
            headers={
                "X-Goog-Api-Key": api_key,
                "Content-Type": "application/json"
            }
        )
    
    async def search_text(
        self,
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None
    ) -> List[Place]:
        data = {
            "textQuery": query,
            "maxResultCount": 20
        }
        
        if location and radius:
            data["locationBias"] = {
                "circle": {
                    "center": location,
                    "radius": float(radius)
                }
            }
        
        response = await self.client.post(
            f"{self.BASE_URL}/places:searchText",
            json=data
        )
        response.raise_for_status()
        
        places_data = response.json().get("places", [])
        return [self._parse_place(p) for p in places_data]
    
    def _parse_place(self, data: dict) -> Place:
        return Place(
            id=data.get("name", "").split("/")[-1],
            display_name=data.get("displayName", {}).get("text", ""),
            formatted_address=data.get("formattedAddress", ""),
            location=Location(
                latitude=data.get("location", {}).get("latitude"),
                longitude=data.get("location", {}).get("longitude")
            ) if data.get("location") else None,
            rating=data.get("rating"),
            user_rating_count=data.get("userRatingCount"),
            types=data.get("types", [])
        )
```

### 5. Configuration
```python
# places_mcp/config/settings.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from typing import Optional

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8"
    )
    
    # API Configuration
    google_api_key: str = Field(..., env="GOOGLE_API_KEY")
    
    # Cache Configuration
    redis_url: Optional[str] = Field(
        default="redis://localhost:6379",
        env="REDIS_URL"
    )
    cache_ttl: int = Field(default=1800, env="CACHE_TTL")
    
    # Rate Limiting
    rate_limit_requests: int = Field(default=100, env="RATE_LIMIT_REQUESTS")
    rate_limit_window: int = Field(default=60, env="RATE_LIMIT_WINDOW")
    
    # MCP Server
    mcp_transport: str = Field(default="stdio", env="MCP_TRANSPORT")
    mcp_port: Optional[int] = Field(default=8000, env="MCP_PORT")
```

## Testing Strategy

### 1. Unit Tests
- Test each layer in isolation
- Mock external dependencies
- Use pytest-asyncio for async tests

### 2. Integration Tests
- Test layer interactions
- Use test containers for Redis
- Mock Google Places API responses

### 3. E2E Tests
- Test complete MCP server functionality
- Use FastMCP test client
- Verify tool and resource responses

## Security Considerations

1. **API Key Management**
   - Never commit API keys
   - Use environment variables
   - Implement key rotation

2. **Input Validation**
   - Validate all tool inputs
   - Sanitize user queries
   - Implement request size limits

3. **Rate Limiting**
   - Implement per-client limits
   - Use Redis for distributed limiting
   - Return proper error messages

## Monitoring and Observability

1. **Logging**
   - Structured logging with context
   - Log all API requests
   - Track error rates

2. **Metrics**
   - Request latency
   - Cache hit rates
   - API quota usage

3. **Tracing**
   - OpenTelemetry integration
   - Trace requests across layers
   - Monitor external API calls

## Deployment

### Docker
```dockerfile
FROM python:3.13-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Copy and install Python dependencies
COPY pyproject.toml .
RUN uv pip install -e .

# Copy application
COPY . .

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uv", "run", "python", "-m", "places_mcp"]
```

### Docker Compose
```yaml
version: '3.8'

services:
  places-mcp:
    build: .
    environment:
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}
      - REDIS_URL=redis://redis:6379
      - MCP_TRANSPORT=http
    ports:
      - "8000:8000"
    depends_on:
      - redis
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

## Next Steps

1. Initialize project with `uv init places-mcp`
2. Set up dependency injection container
3. Implement domain models with Pydantic
4. Create infrastructure adapters
5. Build service layer with business logic
6. Define MCP tools and resources
7. Add comprehensive tests
8. Set up CI/CD pipeline
9. Deploy to production