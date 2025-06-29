# Application Layer Implementation Guide

## Overview

The Application Layer is the orchestration hub of the Places MCP Server, responsible for coordinating business logic, managing transactions, and bridging the gap between the MCP interface (Presentation Layer) and external integrations (Infrastructure Layer). This layer enforces business rules while maintaining clean separation of concerns.

## Core Principles

### 1. Service Orchestration
- Services coordinate multiple operations across domain and infrastructure layers
- Each service has a single, well-defined responsibility
- Services never directly access infrastructure - always through interfaces

### 2. Business Logic Isolation
- All business rules and workflows live in the application layer
- Domain models remain pure and free from application concerns
- Infrastructure details never leak into business logic

### 3. Transaction Management
- Services define transaction boundaries
- Ensure data consistency across operations
- Handle partial failures gracefully

## Service Architecture

### Service Base Class

```python
# places_mcp/services/base.py
from abc import ABC
from typing import Optional, TypeVar, Generic
from contextvars import ContextVar
from ..domain.ports import CacheRepository, EventPublisher
from ..infrastructure.telemetry import Tracer

T = TypeVar('T')
request_context: ContextVar[dict] = ContextVar('request_context', default={})

class BaseService(ABC):
    """Base class for all application services"""
    
    def __init__(
        self,
        cache: Optional[CacheRepository] = None,
        event_publisher: Optional[EventPublisher] = None,
        tracer: Optional[Tracer] = None
    ):
        self.cache = cache
        self.event_publisher = event_publisher
        self.tracer = tracer
        self._metrics = {}
    
    async def _with_telemetry(self, operation: str, func, *args, **kwargs):
        """Wrap operations with telemetry"""
        if self.tracer:
            with self.tracer.span(f"{self.__class__.__name__}.{operation}") as span:
                try:
                    result = await func(*args, **kwargs)
                    span.set_status("ok")
                    return result
                except Exception as e:
                    span.set_status("error", str(e))
                    raise
        else:
            return await func(*args, **kwargs)
    
    async def _publish_event(self, event_type: str, data: dict):
        """Publish domain events"""
        if self.event_publisher:
            await self.event_publisher.publish(event_type, {
                **data,
                'context': request_context.get(),
                'service': self.__class__.__name__
            })
```

## Core Services Implementation

### 1. PlacesService (Main Orchestrator)

The PlacesService acts as the primary orchestrator, delegating to specialized services while maintaining overall workflow control.

```python
# places_mcp/services/places.py
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from ..domain.models import Place, PlaceDetails, SearchQuery, SearchResult
from ..domain.ports import PlacesRepository, CacheRepository
from ..domain.exceptions import PlaceNotFoundError, QuotaExceededError
from .base import BaseService
from .search import SearchService
from .details import DetailsService
from .photo import PhotoService

class PlacesService(BaseService):
    """Main orchestrator service for places operations"""
    
    def __init__(
        self,
        repository: PlacesRepository,
        search_service: SearchService,
        details_service: DetailsService,
        photo_service: PhotoService,
        cache: CacheRepository,
        **kwargs
    ):
        super().__init__(cache=cache, **kwargs)
        self.repository = repository
        self.search_service = search_service
        self.details_service = details_service
        self.photo_service = photo_service
        self._request_history: List[Dict[str, Any]] = []
    
    async def search_places(
        self,
        query: str,
        location: Optional[Dict[str, float]] = None,
        radius: Optional[int] = None,
        place_types: Optional[List[str]] = None,
        min_rating: Optional[float] = None,
        open_now: bool = False,
        price_levels: Optional[List[int]] = None
    ) -> SearchResult:
        """
        Orchestrate place search with business logic enforcement
        
        Business Rules:
        1. Query must be non-empty and less than 200 characters
        2. Radius must be between 1 and 50000 meters
        3. Results are filtered by business rules
        4. Search history is maintained for analytics
        """
        # Validate input
        query = query.strip()
        if not query or len(query) > 200:
            raise ValueError("Query must be between 1 and 200 characters")
        
        if radius and (radius < 1 or radius > 50000):
            raise ValueError("Radius must be between 1 and 50000 meters")
        
        # Track request
        request_data = {
            'query': query,
            'location': location,
            'radius': radius,
            'timestamp': datetime.utcnow(),
            'filters': {
                'types': place_types,
                'min_rating': min_rating,
                'open_now': open_now,
                'price_levels': price_levels
            }
        }
        self._request_history.append(request_data)
        
        # Delegate to search service
        search_result = await self._with_telemetry(
            'search_places',
            self.search_service.search,
            query=query,
            location=location,
            radius=radius,
            place_types=place_types
        )
        
        # Apply business filters
        filtered_places = self._apply_business_filters(
            search_result.places,
            min_rating=min_rating,
            open_now=open_now,
            price_levels=price_levels
        )
        
        # Publish event
        await self._publish_event('places.searched', {
            'query': query,
            'result_count': len(filtered_places),
            'filters_applied': bool(min_rating or open_now or price_levels)
        })
        
        return SearchResult(
            places=filtered_places,
            total_count=len(filtered_places),
            query=query,
            location=location,
            radius=radius
        )
    
    def _apply_business_filters(
        self,
        places: List[Place],
        min_rating: Optional[float] = None,
        open_now: bool = False,
        price_levels: Optional[List[int]] = None
    ) -> List[Place]:
        """Apply business-specific filtering rules"""
        filtered = places
        
        if min_rating:
            filtered = [p for p in filtered if p.rating and p.rating >= min_rating]
        
        if open_now:
            # This would require checking opening_hours from details
            # For now, we'll pass through
            pass
        
        if price_levels:
            filtered = [p for p in filtered if p.price_level in price_levels]
        
        return filtered
    
    async def get_place_with_details(
        self,
        place_id: str,
        include_photos: bool = True,
        include_reviews: bool = True,
        language: str = "en"
    ) -> PlaceDetails:
        """
        Get comprehensive place information with related data
        
        This orchestrates multiple service calls to build a complete
        place profile including details, photos, and reviews.
        """
        # Get basic details
        details = await self._with_telemetry(
            'get_place_details',
            self.details_service.get_details,
            place_id=place_id,
            language=language
        )
        
        # Enrich with photos if requested
        if include_photos and details.photos:
            photo_metadata = await self._with_telemetry(
                'get_photo_metadata',
                self.photo_service.get_photos_metadata,
                photo_references=[p.name for p in details.photos[:10]]  # Limit to 10
            )
            details.photo_urls = photo_metadata
        
        # Process reviews if included
        if include_reviews and details.reviews:
            details.reviews = self._process_reviews(details.reviews)
        
        # Publish event
        await self._publish_event('places.details_retrieved', {
            'place_id': place_id,
            'has_photos': bool(details.photos),
            'has_reviews': bool(details.reviews),
            'rating': details.rating
        })
        
        return details
    
    def _process_reviews(self, reviews: List[Dict]) -> List[Dict]:
        """Apply business logic to reviews"""
        # Sort by helpfulness and recency
        processed = sorted(
            reviews,
            key=lambda r: (r.get('rating', 0), r.get('time', 0)),
            reverse=True
        )
        
        # Limit to top 20 reviews
        return processed[:20]
    
    async def get_analytics(self) -> Dict[str, Any]:
        """Get search analytics and usage patterns"""
        recent_searches = self._request_history[-100:]  # Last 100 searches
        
        # Calculate metrics
        search_volume = len(recent_searches)
        time_window = timedelta(hours=24)
        recent_cutoff = datetime.utcnow() - time_window
        
        recent_volume = sum(
            1 for r in recent_searches 
            if r['timestamp'] > recent_cutoff
        )
        
        # Popular queries
        query_counts = {}
        for request in recent_searches:
            query = request['query'].lower()
            query_counts[query] = query_counts.get(query, 0) + 1
        
        popular_queries = sorted(
            query_counts.items(),
            key=lambda x: x[1],
            reverse=True
        )[:10]
        
        return {
            'total_searches': search_volume,
            'searches_24h': recent_volume,
            'popular_queries': [
                {'query': q, 'count': c} for q, c in popular_queries
            ],
            'avg_results': self._calculate_avg_results(),
            'filter_usage': self._calculate_filter_usage(recent_searches)
        }
    
    def _calculate_avg_results(self) -> float:
        """Calculate average number of results per search"""
        # Implementation would track this metric
        return 15.7  # Placeholder
    
    def _calculate_filter_usage(self, searches: List[Dict]) -> Dict[str, int]:
        """Calculate how often filters are used"""
        filter_counts = {
            'location': 0,
            'rating': 0,
            'open_now': 0,
            'price': 0
        }
        
        for search in searches:
            if search.get('location'):
                filter_counts['location'] += 1
            if search['filters'].get('min_rating'):
                filter_counts['rating'] += 1
            if search['filters'].get('open_now'):
                filter_counts['open_now'] += 1
            if search['filters'].get('price_levels'):
                filter_counts['price'] += 1
        
        return filter_counts
```

### 2. SearchService Implementation

Handles all search-related operations with caching and optimization strategies.

```python
# places_mcp/services/search.py
from typing import List, Optional, Dict, Set
from datetime import datetime
import hashlib
import json
from ..domain.models import Place, SearchQuery, SearchResult, Location
from ..domain.ports import PlacesRepository, CacheRepository
from ..domain.exceptions import InvalidLocationError, SearchError
from .base import BaseService

class SearchService(BaseService):
    """Service for search operations with caching and optimization"""
    
    CACHE_TTL = 1800  # 30 minutes as per Google TOS
    MAX_RESULTS = 20
    
    def __init__(
        self,
        repository: PlacesRepository,
        cache: CacheRepository,
        **kwargs
    ):
        super().__init__(cache=cache, **kwargs)
        self.repository = repository
        self._search_cache: Dict[str, SearchResult] = {}
        self._popular_searches: Set[str] = set()
    
    async def search(
        self,
        query: str,
        location: Optional[Dict[str, float]] = None,
        radius: Optional[int] = None,
        place_types: Optional[List[str]] = None,
        region_code: str = "US"
    ) -> SearchResult:
        """
        Execute search with intelligent caching and optimization
        
        Optimization strategies:
        1. Cache frequently searched queries
        2. Pre-fetch related searches
        3. Batch similar queries
        """
        # Normalize query
        normalized_query = self._normalize_query(query)
        
        # Generate cache key
        cache_key = self._generate_cache_key(
            normalized_query, location, radius, place_types
        )
        
        # Check cache
        cached_result = await self._get_cached_result(cache_key)
        if cached_result:
            self._track_popular_search(normalized_query)
            return cached_result
        
        # Validate location if provided
        if location:
            self._validate_location(location)
        
        try:
            # Execute search
            places = await self.repository.search_text(
                textQuery=normalized_query,
                locationBias=self._build_location_bias(location, radius),
                includedTypes=place_types,
                regionCode=region_code,
                maxResultCount=self.MAX_RESULTS
            )
            
            # Create result
            result = SearchResult(
                places=places,
                total_count=len(places),
                query=normalized_query,
                location=Location(**location) if location else None,
                radius=radius,
                search_metadata={
                    'cached': False,
                    'timestamp': datetime.utcnow().isoformat(),
                    'normalized_query': normalized_query
                }
            )
            
            # Cache result
            await self._cache_result(cache_key, result)
            
            # Track for optimization
            self._track_popular_search(normalized_query)
            
            # Pre-fetch related searches if popular
            if normalized_query in self._popular_searches:
                await self._prefetch_related_searches(normalized_query, location)
            
            return result
            
        except Exception as e:
            raise SearchError(f"Search failed: {str(e)}") from e
    
    def _normalize_query(self, query: str) -> str:
        """Normalize search query for better caching"""
        # Convert to lowercase and strip
        normalized = query.lower().strip()
        
        # Remove common words that don't affect search
        stop_words = {'the', 'a', 'an', 'near', 'in', 'at', 'by'}
        words = normalized.split()
        filtered = [w for w in words if w not in stop_words]
        
        return ' '.join(filtered)
    
    def _generate_cache_key(
        self,
        query: str,
        location: Optional[Dict[str, float]],
        radius: Optional[int],
        place_types: Optional[List[str]]
    ) -> str:
        """Generate deterministic cache key"""
        key_parts = [
            query,
            json.dumps(location, sort_keys=True) if location else "none",
            str(radius) if radius else "none",
            ','.join(sorted(place_types)) if place_types else "none"
        ]
        
        key_string = '|'.join(key_parts)
        return f"search:{hashlib.sha256(key_string.encode()).hexdigest()[:16]}"
    
    async def _get_cached_result(self, cache_key: str) -> Optional[SearchResult]:
        """Retrieve cached search result"""
        if not self.cache:
            return None
        
        cached_data = await self.cache.get(cache_key)
        if cached_data:
            # Update metadata to indicate cache hit
            cached_data['search_metadata']['cached'] = True
            cached_data['search_metadata']['cache_hit_time'] = datetime.utcnow().isoformat()
            return SearchResult(**cached_data)
        
        return None
    
    async def _cache_result(self, cache_key: str, result: SearchResult):
        """Cache search result with TTL"""
        if not self.cache:
            return
        
        await self.cache.set(
            cache_key,
            result.model_dump(),
            ttl=self.CACHE_TTL
        )
    
    def _validate_location(self, location: Dict[str, float]):
        """Validate location coordinates"""
        lat = location.get('latitude')
        lng = location.get('longitude')
        
        if lat is None or lng is None:
            raise InvalidLocationError("Location must include latitude and longitude")
        
        if not (-90 <= lat <= 90):
            raise InvalidLocationError("Latitude must be between -90 and 90")
        
        if not (-180 <= lng <= 180):
            raise InvalidLocationError("Longitude must be between -180 and 180")
    
    def _build_location_bias(
        self,
        location: Optional[Dict[str, float]],
        radius: Optional[int]
    ) -> Optional[Dict]:
        """Build location bias for API request"""
        if not location:
            return None
        
        return {
            "circle": {
                "center": location,
                "radius": float(radius if radius else 5000)  # Default 5km
            }
        }
    
    def _track_popular_search(self, query: str):
        """Track popular searches for optimization"""
        # Simple implementation - in production, use Redis sorted set
        self._popular_searches.add(query)
        
        # Keep only top 100 popular searches
        if len(self._popular_searches) > 100:
            # In production, remove least popular
            self._popular_searches.pop()
    
    async def _prefetch_related_searches(
        self,
        query: str,
        location: Optional[Dict[str, float]]
    ):
        """Pre-fetch related searches for popular queries"""
        # Generate related queries
        related_queries = self._generate_related_queries(query)
        
        # Pre-fetch in background (fire and forget)
        for related_query in related_queries[:3]:  # Limit to 3
            cache_key = self._generate_cache_key(
                related_query, location, None, None
            )
            
            # Check if already cached
            if await self.cache.exists(cache_key):
                continue
            
            # In production, use background task queue
            # For now, we'll skip actual pre-fetching
            pass
    
    def _generate_related_queries(self, query: str) -> List[str]:
        """Generate related search queries"""
        related = []
        
        # Add variations
        if "restaurant" in query:
            related.extend([
                query.replace("restaurant", "cafe"),
                query.replace("restaurant", "dining"),
                f"{query} takeout"
            ])
        elif "coffee" in query:
            related.extend([
                query.replace("coffee", "cafe"),
                f"{query} shop",
                "starbucks" if "starbucks" not in query else query
            ])
        
        return related
    
    async def search_nearby(
        self,
        location: Dict[str, float],
        radius: int = 1000,
        place_types: Optional[List[str]] = None,
        rank_by: str = "prominence"
    ) -> SearchResult:
        """
        Search for places near a specific location
        
        This is optimized for "near me" type searches
        """
        # Validate inputs
        self._validate_location(location)
        
        if radius < 1 or radius > 50000:
            raise ValueError("Radius must be between 1 and 50000 meters")
        
        # Build query based on types
        if place_types:
            query = f"{' '.join(place_types)} near me"
        else:
            query = "places near me"
        
        # Use main search with location bias
        return await self.search(
            query=query,
            location=location,
            radius=radius,
            place_types=place_types
        )
```

### 3. DetailsService Implementation

Manages place details retrieval with field optimization and caching.

```python
# places_mcp/services/details.py
from typing import List, Optional, Set, Dict
from datetime import datetime
from ..domain.models import PlaceDetails, OpeningHours, Review
from ..domain.ports import PlacesRepository, CacheRepository
from ..domain.exceptions import PlaceNotFoundError
from .base import BaseService

class DetailsService(BaseService):
    """Service for place details operations"""
    
    # Field groups for optimization
    BASIC_FIELDS = {
        "id", "displayName", "formattedAddress", "location",
        "rating", "userRatingCount", "types"
    }
    
    CONTACT_FIELDS = {
        "nationalPhoneNumber", "internationalPhoneNumber",
        "websiteUri", "googleMapsUri"
    }
    
    ATMOSPHERE_FIELDS = {
        "priceLevel", "servesBreakfast", "servesLunch", "servesDinner",
        "servesBeer", "servesWine", "servesVegetarianFood",
        "outdoorSeating", "liveMusic", "allowsDogs"
    }
    
    BUSINESS_FIELDS = {
        "currentOpeningHours", "currentSecondaryOpeningHours",
        "regularOpeningHours", "regularSecondaryOpeningHours",
        "businessStatus", "utcOffsetMinutes"
    }
    
    ACCESSIBILITY_FIELDS = {
        "accessibilityOptions", "parkingOptions",
        "paymentOptions", "evChargeOptions"
    }
    
    MEDIA_FIELDS = {"photos", "reviews", "generativeSummary"}
    
    CACHE_TTL = 3600  # 1 hour for details
    
    def __init__(
        self,
        repository: PlacesRepository,
        cache: CacheRepository,
        **kwargs
    ):
        super().__init__(cache=cache, **kwargs)
        self.repository = repository
        self._field_stats: Dict[str, int] = {}
    
    async def get_details(
        self,
        place_id: str,
        fields: Optional[List[str]] = None,
        language: str = "en",
        reviews_limit: int = 20,
        photos_limit: int = 10
    ) -> PlaceDetails:
        """
        Get place details with intelligent field selection
        
        Optimizations:
        1. Only request necessary fields
        2. Cache commonly requested field combinations
        3. Separate caching for expensive fields (photos, reviews)
        """
        # Determine fields to fetch
        requested_fields = self._determine_fields(fields)
        
        # Check cache
        cache_key = f"details:{place_id}:{language}:{','.join(sorted(requested_fields))}"
        cached = await self._get_cached_details(cache_key)
        if cached:
            return cached
        
        try:
            # Fetch from repository
            details_data = await self.repository.get_place(
                place_id=place_id,
                fields=requested_fields,
                languageCode=language
            )
            
            # Process and enhance data
            details = self._process_details(
                details_data,
                reviews_limit=reviews_limit,
                photos_limit=photos_limit
            )
            
            # Cache result
            await self._cache_details(cache_key, details)
            
            # Track field usage
            self._track_field_usage(requested_fields)
            
            # Publish event
            await self._publish_event('places.details_fetched', {
                'place_id': place_id,
                'fields_count': len(requested_fields),
                'has_premium_fields': bool(requested_fields & self.MEDIA_FIELDS)
            })
            
            return details
            
        except Exception as e:
            if "NOT_FOUND" in str(e):
                raise PlaceNotFoundError(f"Place {place_id} not found")
            raise
    
    def _determine_fields(self, requested: Optional[List[str]]) -> Set[str]:
        """Determine which fields to fetch based on request"""
        if not requested:
            # Default to basic + contact fields
            return self.BASIC_FIELDS | self.CONTACT_FIELDS
        
        # Convert to set and validate
        field_set = set(requested)
        
        # Expand field groups
        expanded = set()
        for field in field_set:
            if field == "basic":
                expanded.update(self.BASIC_FIELDS)
            elif field == "contact":
                expanded.update(self.CONTACT_FIELDS)
            elif field == "atmosphere":
                expanded.update(self.ATMOSPHERE_FIELDS)
            elif field == "business":
                expanded.update(self.BUSINESS_FIELDS)
            elif field == "accessibility":
                expanded.update(self.ACCESSIBILITY_FIELDS)
            elif field == "media":
                expanded.update(self.MEDIA_FIELDS)
            elif field == "all":
                expanded.update(
                    self.BASIC_FIELDS | self.CONTACT_FIELDS |
                    self.ATMOSPHERE_FIELDS | self.BUSINESS_FIELDS |
                    self.ACCESSIBILITY_FIELDS | self.MEDIA_FIELDS
                )
            else:
                expanded.add(field)
        
        return expanded
    
    def _process_details(
        self,
        data: Dict,
        reviews_limit: int,
        photos_limit: int
    ) -> PlaceDetails:
        """Process raw API data into domain model"""
        # Extract place ID from name field
        place_id = data.get("name", "").split("/")[-1]
        
        # Process basic fields
        details = PlaceDetails(
            id=place_id,
            display_name=data.get("displayName", {}).get("text", ""),
            formatted_address=data.get("formattedAddress", ""),
            location=data.get("location"),
            rating=data.get("rating"),
            user_rating_count=data.get("userRatingCount"),
            types=data.get("types", []),
            price_level=data.get("priceLevel"),
            website_uri=data.get("websiteUri"),
            phone_number=data.get("nationalPhoneNumber"),
            international_phone_number=data.get("internationalPhoneNumber"),
            google_maps_uri=data.get("googleMapsUri"),
            business_status=data.get("businessStatus")
        )
        
        # Process opening hours
        if "currentOpeningHours" in data:
            details.opening_hours = self._process_opening_hours(
                data["currentOpeningHours"]
            )
        
        # Process photos
        if "photos" in data:
            details.photos = data["photos"][:photos_limit]
            details.photo_attributions = [
                photo.get("authorAttributions", [])
                for photo in details.photos
            ]
        
        # Process reviews
        if "reviews" in data:
            details.reviews = [
                self._process_review(r)
                for r in data["reviews"][:reviews_limit]
            ]
        
        # Process accessibility options
        if "accessibilityOptions" in data:
            details.accessibility_options = data["accessibilityOptions"]
        
        # Process parking options
        if "parkingOptions" in data:
            details.parking_options = data["parkingOptions"]
        
        # Process payment options
        if "paymentOptions" in data:
            details.payment_options = data["paymentOptions"]
        
        # Process EV charging
        if "evChargeOptions" in data:
            details.ev_charge_options = data["evChargeOptions"]
        
        # Generative summary
        if "generativeSummary" in data:
            details.generative_summary = data["generativeSummary"]
        
        return details
    
    def _process_opening_hours(self, hours_data: Dict) -> OpeningHours:
        """Process opening hours into structured format"""
        return OpeningHours(
            open_now=hours_data.get("openNow", False),
            periods=hours_data.get("periods", []),
            weekday_descriptions=hours_data.get("weekdayDescriptions", []),
            secondary_hours_type=hours_data.get("secondaryHoursType")
        )
    
    def _process_review(self, review_data: Dict) -> Review:
        """Process review data"""
        return Review(
            rating=review_data.get("rating"),
            text=review_data.get("text", {}).get("text", ""),
            author_name=review_data.get("authorAttribution", {}).get("displayName", ""),
            author_photo_uri=review_data.get("authorAttribution", {}).get("photoUri"),
            publish_time=review_data.get("publishTime"),
            relative_publish_time=review_data.get("relativePublishTimeDescription")
        )
    
    async def _get_cached_details(self, cache_key: str) -> Optional[PlaceDetails]:
        """Retrieve cached details"""
        if not self.cache:
            return None
        
        cached_data = await self.cache.get(cache_key)
        if cached_data:
            return PlaceDetails(**cached_data)
        
        return None
    
    async def _cache_details(self, cache_key: str, details: PlaceDetails):
        """Cache place details"""
        if not self.cache:
            return
        
        await self.cache.set(
            cache_key,
            details.model_dump(),
            ttl=self.CACHE_TTL
        )
    
    def _track_field_usage(self, fields: Set[str]):
        """Track which fields are requested most"""
        for field in fields:
            self._field_stats[field] = self._field_stats.get(field, 0) + 1
    
    async def get_multiple_details(
        self,
        place_ids: List[str],
        fields: Optional[List[str]] = None,
        language: str = "en"
    ) -> List[PlaceDetails]:
        """
        Get details for multiple places efficiently
        
        Uses batching and parallel requests where possible
        """
        # Limit batch size
        if len(place_ids) > 10:
            raise ValueError("Maximum 10 places per batch")
        
        # Check cache for each place
        results = []
        uncached_ids = []
        
        for place_id in place_ids:
            cache_key = f"details:{place_id}:{language}:basic"
            cached = await self._get_cached_details(cache_key)
            if cached:
                results.append(cached)
            else:
                uncached_ids.append(place_id)
        
        # Fetch uncached places
        if uncached_ids:
            # In production, use asyncio.gather for parallel requests
            for place_id in uncached_ids:
                try:
                    details = await self.get_details(
                        place_id=place_id,
                        fields=fields,
                        language=language
                    )
                    results.append(details)
                except PlaceNotFoundError:
                    # Skip places that don't exist
                    continue
        
        return results
```

### 4. PhotoService Implementation

Handles photo operations with optimization for bandwidth and costs.

```python
# places_mcp/services/photo.py
from typing import List, Optional, Dict, Tuple
from datetime import datetime
import hashlib
from ..domain.models import Photo, PhotoMetadata
from ..domain.ports import PlacesRepository, CacheRepository
from ..domain.exceptions import PhotoNotFoundError, PhotoQuotaExceededError
from .base import BaseService

class PhotoService(BaseService):
    """Service for photo operations with optimization and quota management"""
    
    CACHE_TTL = 86400  # 24 hours for photo URLs
    MAX_PHOTO_WIDTH = 4800
    MAX_PHOTO_HEIGHT = 4800
    DEFAULT_WIDTH = 400
    DEFAULT_HEIGHT = 400
    
    # Monthly quota tracking
    MONTHLY_QUOTA = 25000  # Example quota
    
    def __init__(
        self,
        repository: PlacesRepository,
        cache: CacheRepository,
        **kwargs
    ):
        super().__init__(cache=cache, **kwargs)
        self.repository = repository
        self._quota_tracker: Dict[str, int] = {}
    
    async def get_photo_url(
        self,
        photo_reference: str,
        max_width: Optional[int] = None,
        max_height: Optional[int] = None,
        skip_https_redirect: bool = False
    ) -> str:
        """
        Get photo URL with size optimization and caching
        
        Business rules:
        1. Optimize dimensions to reduce bandwidth
        2. Cache URLs to minimize API calls
        3. Track quota usage
        """
        # Optimize dimensions
        width, height = self._optimize_dimensions(max_width, max_height)
        
        # Check quota
        await self._check_quota()
        
        # Generate cache key
        cache_key = self._generate_photo_cache_key(
            photo_reference, width, height
        )
        
        # Check cache
        cached_url = await self._get_cached_url(cache_key)
        if cached_url:
            return cached_url
        
        try:
            # Get photo URL from API
            photo_url = await self.repository.get_photo_url(
                photo_name=photo_reference,
                maxWidthPx=width,
                maxHeightPx=height,
                skipHttpsRedirect=skip_https_redirect
            )
            
            # Cache URL
            await self._cache_url(cache_key, photo_url)
            
            # Track quota usage
            await self._track_quota_usage()
            
            # Publish event
            await self._publish_event('photo.url_generated', {
                'photo_reference': photo_reference,
                'width': width,
                'height': height,
                'cached': False
            })
            
            return photo_url
            
        except Exception as e:
            if "NOT_FOUND" in str(e):
                raise PhotoNotFoundError(f"Photo {photo_reference} not found")
            raise
    
    async def get_photos_metadata(
        self,
        photo_references: List[str],
        target_size: Tuple[int, int] = (400, 400)
    ) -> List[PhotoMetadata]:
        """
        Get metadata for multiple photos with batch optimization
        
        Returns metadata including optimized URLs for the target size
        """
        if len(photo_references) > 10:
            raise ValueError("Maximum 10 photos per batch")
        
        metadata_list = []
        
        for reference in photo_references:
            try:
                # Get optimized URL
                url = await self.get_photo_url(
                    photo_reference=reference,
                    max_width=target_size[0],
                    max_height=target_size[1]
                )
                
                # Create metadata
                metadata = PhotoMetadata(
                    reference=reference,
                    url=url,
                    width=target_size[0],
                    height=target_size[1],
                    cached=True  # Will be true if from cache
                )
                
                metadata_list.append(metadata)
                
            except PhotoNotFoundError:
                # Skip missing photos
                continue
        
        return metadata_list
    
    def _optimize_dimensions(
        self,
        requested_width: Optional[int],
        requested_height: Optional[int]
    ) -> Tuple[int, int]:
        """
        Optimize photo dimensions for performance and cost
        
        Strategy:
        1. Use standard sizes when possible (better caching)
        2. Limit maximum dimensions
        3. Maintain aspect ratio constraints
        """
        # Standard sizes for better cache hit rate
        STANDARD_SIZES = [
            (200, 200),   # Thumbnail
            (400, 400),   # Small
            (800, 800),   # Medium
            (1200, 1200), # Large
            (2400, 2400)  # Extra large
        ]
        
        # Use defaults if not specified
        width = requested_width or self.DEFAULT_WIDTH
        height = requested_height or self.DEFAULT_HEIGHT
        
        # Cap at maximum
        width = min(width, self.MAX_PHOTO_WIDTH)
        height = min(height, self.MAX_PHOTO_HEIGHT)
        
        # Find nearest standard size
        for std_width, std_height in STANDARD_SIZES:
            if width <= std_width and height <= std_height:
                return (std_width, std_height)
        
        # Use exact dimensions if larger than all standards
        return (width, height)
    
    def _generate_photo_cache_key(
        self,
        reference: str,
        width: int,
        height: int
    ) -> str:
        """Generate cache key for photo URL"""
        key_string = f"{reference}:{width}:{height}"
        hash_digest = hashlib.md5(key_string.encode()).hexdigest()[:8]
        return f"photo:{hash_digest}"
    
    async def _get_cached_url(self, cache_key: str) -> Optional[str]:
        """Retrieve cached photo URL"""
        if not self.cache:
            return None
        
        return await self.cache.get(cache_key)
    
    async def _cache_url(self, cache_key: str, url: str):
        """Cache photo URL"""
        if not self.cache:
            return
        
        await self.cache.set(cache_key, url, ttl=self.CACHE_TTL)
    
    async def _check_quota(self):
        """Check if quota is exceeded"""
        current_month = datetime.utcnow().strftime("%Y-%m")
        usage = self._quota_tracker.get(current_month, 0)
        
        if usage >= self.MONTHLY_QUOTA:
            raise PhotoQuotaExceededError(
                f"Monthly photo quota ({self.MONTHLY_QUOTA}) exceeded"
            )
    
    async def _track_quota_usage(self):
        """Track quota usage by month"""
        current_month = datetime.utcnow().strftime("%Y-%m")
        self._quota_tracker[current_month] = \
            self._quota_tracker.get(current_month, 0) + 1
        
        # In production, persist this to database
        if self.cache:
            await self.cache.set(
                f"photo_quota:{current_month}",
                self._quota_tracker[current_month],
                ttl=2592000  # 30 days
            )
    
    async def preload_photos(
        self,
        place_details: dict,
        sizes: List[Tuple[int, int]] = None
    ) -> Dict[str, List[str]]:
        """
        Preload photos for a place in multiple sizes
        
        Useful for preparing photos for different display contexts
        """
        if not sizes:
            sizes = [(200, 200), (400, 400), (800, 800)]
        
        photos = place_details.get("photos", [])[:5]  # Limit to 5 photos
        preloaded = {}
        
        for photo in photos:
            photo_ref = photo.get("name", "")
            if not photo_ref:
                continue
            
            urls = []
            for width, height in sizes:
                try:
                    url = await self.get_photo_url(
                        photo_reference=photo_ref,
                        max_width=width,
                        max_height=height
                    )
                    urls.append({
                        "size": f"{width}x{height}",
                        "url": url
                    })
                except PhotoNotFoundError:
                    continue
            
            if urls:
                preloaded[photo_ref] = urls
        
        return preloaded
    
    def get_quota_status(self) -> Dict[str, any]:
        """Get current quota usage status"""
        current_month = datetime.utcnow().strftime("%Y-%m")
        usage = self._quota_tracker.get(current_month, 0)
        
        return {
            "month": current_month,
            "used": usage,
            "limit": self.MONTHLY_QUOTA,
            "remaining": max(0, self.MONTHLY_QUOTA - usage),
            "percentage_used": round((usage / self.MONTHLY_QUOTA) * 100, 2)
        }
```

## Business Logic and Workflows

### 1. Search Workflow

```python
# Example of a complete search workflow with business logic

async def search_restaurants_workflow(
    places_service: PlacesService,
    query: str,
    user_location: Dict[str, float],
    dietary_restrictions: List[str] = None,
    budget: str = "moderate"
) -> Dict[str, Any]:
    """
    Complete workflow for searching restaurants with user preferences
    """
    # Map budget to price levels
    price_levels = {
        "cheap": [1, 2],
        "moderate": [2, 3],
        "expensive": [3, 4]
    }.get(budget, [1, 2, 3, 4])
    
    # Build search query with dietary restrictions
    search_query = query
    if dietary_restrictions:
        search_query += f" {' '.join(dietary_restrictions)}"
    
    # Search for places
    search_result = await places_service.search_places(
        query=search_query,
        location=user_location,
        radius=5000,  # 5km radius
        place_types=["restaurant", "cafe"],
        min_rating=3.5,
        open_now=True,
        price_levels=price_levels
    )
    
    # Get details for top results
    top_places = search_result.places[:5]
    detailed_places = []
    
    for place in top_places:
        details = await places_service.get_place_with_details(
            place_id=place.id,
            include_photos=True,
            include_reviews=True
        )
        detailed_places.append(details)
    
    # Sort by rating and distance
    detailed_places.sort(
        key=lambda p: (p.rating or 0, -p.user_rating_count or 0),
        reverse=True
    )
    
    return {
        "query": search_query,
        "total_found": search_result.total_count,
        "filters_applied": {
            "dietary": dietary_restrictions,
            "budget": budget,
            "open_now": True,
            "min_rating": 3.5
        },
        "results": detailed_places,
        "search_metadata": search_result.search_metadata
    }
```

### 2. Caching Strategy

```python
# places_mcp/services/cache_strategy.py
from typing import Optional, Dict, Any
from datetime import datetime, timedelta

class CacheStrategy:
    """
    Intelligent caching strategy for the application layer
    """
    
    # Cache TTLs by data type
    TTL_CONFIG = {
        "search_results": 1800,      # 30 minutes (Google TOS)
        "place_details": 3600,       # 1 hour
        "place_photos": 86400,       # 24 hours
        "analytics": 300,            # 5 minutes
        "popular_searches": 3600,    # 1 hour
    }
    
    # Cache warming configuration
    WARM_CACHE_QUERIES = [
        "restaurants near me",
        "coffee shops",
        "gas stations",
        "hotels",
        "tourist attractions"
    ]
    
    @staticmethod
    def should_cache(data_type: str, result_count: int) -> bool:
        """Determine if results should be cached"""
        # Don't cache empty results
        if result_count == 0:
            return False
        
        # Don't cache single results with low confidence
        if data_type == "search_results" and result_count == 1:
            return False
        
        return True
    
    @staticmethod
    def get_ttl(data_type: str, is_popular: bool = False) -> int:
        """Get TTL for cache entry"""
        base_ttl = CacheStrategy.TTL_CONFIG.get(data_type, 1800)
        
        # Extend TTL for popular items
        if is_popular:
            return int(base_ttl * 1.5)
        
        return base_ttl
    
    @staticmethod
    def generate_cache_tags(data_type: str, **kwargs) -> List[str]:
        """Generate cache tags for invalidation"""
        tags = [f"type:{data_type}"]
        
        if "place_id" in kwargs:
            tags.append(f"place:{kwargs['place_id']}")
        
        if "location" in kwargs:
            lat = kwargs["location"].get("latitude", 0)
            lng = kwargs["location"].get("longitude", 0)
            # Grid-based location tag (0.01 degree grid)
            grid_lat = int(lat * 100)
            grid_lng = int(lng * 100)
            tags.append(f"grid:{grid_lat}:{grid_lng}")
        
        return tags
```

## Transaction Boundaries

### 1. Transaction Management

```python
# places_mcp/services/transaction.py
from contextlib import asynccontextmanager
from typing import Optional, Any
import asyncio

class TransactionManager:
    """
    Manages transaction boundaries in the application layer
    """
    
    def __init__(self):
        self._active_transactions: Dict[str, Any] = {}
        self._lock = asyncio.Lock()
    
    @asynccontextmanager
    async def transaction(self, transaction_id: str):
        """
        Create a transaction boundary
        
        Usage:
            async with transaction_manager.transaction("search_123"):
                # Perform operations
                pass
        """
        async with self._lock:
            self._active_transactions[transaction_id] = {
                "start_time": datetime.utcnow(),
                "operations": []
            }
        
        try:
            yield self
            # Commit transaction
            await self._commit(transaction_id)
        except Exception as e:
            # Rollback transaction
            await self._rollback(transaction_id)
            raise
        finally:
            async with self._lock:
                self._active_transactions.pop(transaction_id, None)
    
    async def _commit(self, transaction_id: str):
        """Commit transaction"""
        transaction = self._active_transactions.get(transaction_id)
        if transaction:
            # Log successful transaction
            duration = (datetime.utcnow() - transaction["start_time"]).total_seconds()
            print(f"Transaction {transaction_id} committed in {duration}s")
    
    async def _rollback(self, transaction_id: str):
        """Rollback transaction"""
        transaction = self._active_transactions.get(transaction_id)
        if transaction:
            # Rollback operations
            for operation in reversed(transaction["operations"]):
                if operation.get("rollback_func"):
                    await operation["rollback_func"]()
```

### 2. Saga Pattern Implementation

```python
# places_mcp/services/saga.py
from typing import List, Callable, Any
from dataclasses import dataclass

@dataclass
class SagaStep:
    """Represents a step in a saga"""
    name: str
    action: Callable
    compensation: Callable
    args: dict = None

class SagaOrchestrator:
    """
    Implements the Saga pattern for distributed transactions
    """
    
    async def execute_saga(self, steps: List[SagaStep]) -> Any:
        """
        Execute a saga with automatic compensation on failure
        """
        completed_steps = []
        result = None
        
        try:
            for step in steps:
                # Execute step
                step_result = await step.action(**(step.args or {}))
                completed_steps.append((step, step_result))
                result = step_result
                
                # Log step completion
                print(f"Saga step '{step.name}' completed")
            
            return result
            
        except Exception as e:
            # Compensate in reverse order
            print(f"Saga failed at step '{step.name}': {str(e)}")
            
            for completed_step, step_result in reversed(completed_steps):
                try:
                    await completed_step.compensation(step_result)
                    print(f"Compensated step '{completed_step.name}'")
                except Exception as comp_error:
                    print(f"Compensation failed for '{completed_step.name}': {str(comp_error)}")
            
            raise

# Example usage
async def place_review_saga(places_service: PlacesService, review_data: dict):
    """Saga for submitting a place review"""
    saga = SagaOrchestrator()
    
    steps = [
        SagaStep(
            name="validate_place",
            action=lambda: places_service.get_place_details(review_data["place_id"]),
            compensation=lambda x: None  # No compensation needed
        ),
        SagaStep(
            name="check_user_eligibility",
            action=lambda: check_user_can_review(review_data["user_id"]),
            compensation=lambda x: None
        ),
        SagaStep(
            name="submit_review",
            action=lambda: submit_review_to_api(review_data),
            compensation=lambda x: delete_review(x["review_id"])
        ),
        SagaStep(
            name="update_cache",
            action=lambda: invalidate_place_cache(review_data["place_id"]),
            compensation=lambda x: None
        )
    ]
    
    return await saga.execute_saga(steps)
```

## Error Propagation

### 1. Error Handling Strategy

```python
# places_mcp/services/errors.py
from typing import Optional, Dict, Any
from enum import Enum

class ErrorSeverity(Enum):
    """Error severity levels"""
    LOW = "low"        # Log and continue
    MEDIUM = "medium"  # Retry with backoff
    HIGH = "high"      # Fail fast
    CRITICAL = "critical"  # Alert and fail

class ServiceError(Exception):
    """Base service layer exception"""
    
    def __init__(
        self,
        message: str,
        severity: ErrorSeverity = ErrorSeverity.MEDIUM,
        retry_after: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        super().__init__(message)
        self.severity = severity
        self.retry_after = retry_after
        self.details = details or {}
        self.timestamp = datetime.utcnow()

class ErrorHandler:
    """Centralized error handling for services"""
    
    @staticmethod
    async def handle_error(
        error: Exception,
        context: Dict[str, Any]
    ) -> Optional[Any]:
        """
        Handle errors with appropriate strategies
        """
        if isinstance(error, ServiceError):
            if error.severity == ErrorSeverity.LOW:
                # Log and continue with default
                print(f"Low severity error: {error}")
                return context.get("default_value")
            
            elif error.severity == ErrorSeverity.MEDIUM:
                # Retry with exponential backoff
                if context.get("retry_count", 0) < 3:
                    await asyncio.sleep(2 ** context.get("retry_count", 0))
                    raise  # Let caller retry
                else:
                    # Max retries exceeded
                    raise ServiceError(
                        f"Max retries exceeded: {error}",
                        severity=ErrorSeverity.HIGH
                    )
            
            elif error.severity in (ErrorSeverity.HIGH, ErrorSeverity.CRITICAL):
                # Fail fast
                if error.severity == ErrorSeverity.CRITICAL:
                    # Send alert
                    await send_critical_alert(error, context)
                raise
        
        # Handle specific infrastructure errors
        elif "QUOTA_EXCEEDED" in str(error):
            raise ServiceError(
                "API quota exceeded",
                severity=ErrorSeverity.HIGH,
                retry_after=3600,  # Retry after 1 hour
                details={"error_type": "quota"}
            )
        
        elif "INVALID_ARGUMENT" in str(error):
            raise ServiceError(
                f"Invalid request: {error}",
                severity=ErrorSeverity.LOW,
                details={"error_type": "validation"}
            )
        
        # Unknown error - fail fast
        raise ServiceError(
            f"Unexpected error: {error}",
            severity=ErrorSeverity.HIGH,
            details={"original_error": str(error)}
        )

# Decorator for automatic error handling
def with_error_handling(default_value=None):
    """Decorator for automatic error handling in services"""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            context = {
                "function": func.__name__,
                "default_value": default_value,
                "retry_count": 0
            }
            
            while context["retry_count"] < 3:
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    result = await ErrorHandler.handle_error(e, context)
                    if result is not None:
                        return result
                    context["retry_count"] += 1
            
            raise ServiceError(
                f"Failed after {context['retry_count']} retries",
                severity=ErrorSeverity.HIGH
            )
        
        return wrapper
    return decorator
```

## Service Testing Strategies

### 1. Unit Testing Services

```python
# tests/unit/services/test_places_service.py
import pytest
from unittest.mock import Mock, AsyncMock
from places_mcp.services.places import PlacesService
from places_mcp.domain.models import Place, SearchResult

@pytest.fixture
def mock_repository():
    """Mock repository for testing"""
    repo = Mock()
    repo.search_text = AsyncMock()
    repo.get_place = AsyncMock()
    return repo

@pytest.fixture
def mock_cache():
    """Mock cache for testing"""
    cache = Mock()
    cache.get = AsyncMock(return_value=None)
    cache.set = AsyncMock()
    return cache

@pytest.fixture
def places_service(mock_repository, mock_cache):
    """Create service with mocked dependencies"""
    search_service = Mock()
    details_service = Mock()
    photo_service = Mock()
    
    return PlacesService(
        repository=mock_repository,
        search_service=search_service,
        details_service=details_service,
        photo_service=photo_service,
        cache=mock_cache
    )

class TestPlacesService:
    
    @pytest.mark.asyncio
    async def test_search_places_validates_input(self, places_service):
        """Test input validation"""
        # Empty query
        with pytest.raises(ValueError, match="Query must be between"):
            await places_service.search_places("")
        
        # Query too long
        with pytest.raises(ValueError, match="Query must be between"):
            await places_service.search_places("a" * 201)
        
        # Invalid radius
        with pytest.raises(ValueError, match="Radius must be between"):
            await places_service.search_places("coffee", radius=60000)
    
    @pytest.mark.asyncio
    async def test_search_places_uses_cache(self, places_service, mock_cache):
        """Test cache usage"""
        # Setup cached result
        cached_result = SearchResult(
            places=[Place(id="1", display_name="Test Place")],
            total_count=1,
            query="coffee"
        )
        mock_cache.get.return_value = cached_result.model_dump()
        
        # Execute search
        result = await places_service.search_places("coffee")
        
        # Verify cache was checked
        mock_cache.get.assert_called_once()
        assert result.places[0].display_name == "Test Place"
    
    @pytest.mark.asyncio
    async def test_search_places_applies_filters(self, places_service):
        """Test business filter application"""
        # Setup search service response
        places = [
            Place(id="1", display_name="Place 1", rating=4.5),
            Place(id="2", display_name="Place 2", rating=3.0),
            Place(id="3", display_name="Place 3", rating=5.0)
        ]
        places_service.search_service.search = AsyncMock(
            return_value=SearchResult(places=places, total_count=3, query="test")
        )
        
        # Search with rating filter
        result = await places_service.search_places("test", min_rating=4.0)
        
        # Verify filtering
        assert len(result.places) == 2
        assert all(p.rating >= 4.0 for p in result.places)
    
    @pytest.mark.asyncio
    async def test_get_analytics(self, places_service):
        """Test analytics calculation"""
        # Add some search history
        places_service._request_history = [
            {
                'query': 'coffee',
                'timestamp': datetime.utcnow(),
                'filters': {'min_rating': None, 'open_now': False}
            },
            {
                'query': 'restaurant',
                'timestamp': datetime.utcnow() - timedelta(hours=2),
                'filters': {'min_rating': 4.0, 'open_now': True}
            }
        ]
        
        # Get analytics
        analytics = await places_service.get_analytics()
        
        # Verify metrics
        assert analytics['total_searches'] == 2
        assert analytics['searches_24h'] == 2
        assert len(analytics['popular_queries']) > 0
```

### 2. Integration Testing

```python
# tests/integration/test_service_integration.py
import pytest
from places_mcp.container import Container
from places_mcp.services.places import PlacesService

@pytest.fixture
async def container():
    """Create DI container for integration tests"""
    container = Container()
    container.config.from_dict({
        'google_api_key': 'test_key',
        'redis_url': 'redis://localhost:6379/1'  # Test database
    })
    yield container
    # Cleanup
    await container.shutdown_resources()

@pytest.fixture
async def places_service(container):
    """Get service from container"""
    return container.places_service()

class TestServiceIntegration:
    
    @pytest.mark.asyncio
    async def test_search_to_details_workflow(self, places_service):
        """Test complete search to details workflow"""
        # Search for places
        search_result = await places_service.search_places(
            "coffee shops",
            location={"latitude": 37.7749, "longitude": -122.4194}
        )
        
        assert search_result.total_count > 0
        
        # Get details for first result
        first_place = search_result.places[0]
        details = await places_service.get_place_with_details(
            place_id=first_place.id,
            include_photos=True
        )
        
        assert details.id == first_place.id
        assert details.display_name
        assert details.formatted_address
    
    @pytest.mark.asyncio
    async def test_caching_behavior(self, places_service):
        """Test that caching works correctly"""
        query = "unique test query"
        
        # First search - cache miss
        result1 = await places_service.search_places(query)
        
        # Second search - cache hit
        result2 = await places_service.search_places(query)
        
        # Results should be identical
        assert len(result1.places) == len(result2.places)
        assert result1.places[0].id == result2.places[0].id
```

### 3. Service Mocking for E2E Tests

```python
# tests/mocks/mock_services.py
from typing import List, Optional
from places_mcp.services.places import PlacesService
from places_mcp.domain.models import Place, PlaceDetails, SearchResult

class MockPlacesService(PlacesService):
    """Mock service for E2E testing"""
    
    def __init__(self):
        # Initialize without dependencies
        self._mock_places = [
            Place(
                id="mock_place_1",
                display_name="Mock Coffee Shop",
                formatted_address="123 Test St, Test City, TC 12345",
                rating=4.5,
                user_rating_count=100,
                types=["cafe", "restaurant"]
            ),
            Place(
                id="mock_place_2",
                display_name="Mock Restaurant",
                formatted_address="456 Test Ave, Test City, TC 12345",
                rating=4.0,
                user_rating_count=200,
                types=["restaurant"]
            )
        ]
    
    async def search_places(self, query: str, **kwargs) -> SearchResult:
        """Return mock search results"""
        # Filter based on query
        filtered = [
            p for p in self._mock_places
            if query.lower() in p.display_name.lower()
        ]
        
        return SearchResult(
            places=filtered,
            total_count=len(filtered),
            query=query,
            location=kwargs.get('location'),
            radius=kwargs.get('radius')
        )
    
    async def get_place_with_details(
        self,
        place_id: str,
        **kwargs
    ) -> PlaceDetails:
        """Return mock place details"""
        place = next((p for p in self._mock_places if p.id == place_id), None)
        
        if not place:
            raise PlaceNotFoundError(f"Place {place_id} not found")
        
        return PlaceDetails(
            **place.model_dump(),
            website_uri="https://example.com",
            phone_number="+1234567890",
            opening_hours={
                "open_now": True,
                "weekday_descriptions": [
                    "Monday: 7:00 AM – 10:00 PM",
                    "Tuesday: 7:00 AM – 10:00 PM"
                ]
            }
        )
```

## Service Composition Patterns

### 1. Facade Pattern

```python
# places_mcp/services/facades.py
from typing import List, Dict, Any
from .places import PlacesService
from .recommendation import RecommendationService
from .analytics import AnalyticsService

class PlaceDiscoveryFacade:
    """
    Facade for complex place discovery workflows
    
    Simplifies client interaction by providing high-level methods
    that orchestrate multiple services
    """
    
    def __init__(
        self,
        places_service: PlacesService,
        recommendation_service: RecommendationService,
        analytics_service: AnalyticsService
    ):
        self.places = places_service
        self.recommendations = recommendation_service
        self.analytics = analytics_service
    
    async def discover_places_for_user(
        self,
        user_id: str,
        location: Dict[str, float],
        preferences: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Complete place discovery workflow for a user
        
        1. Get user's search history
        2. Generate recommendations
        3. Search for places
        4. Filter and rank results
        5. Track user engagement
        """
        # Get user context
        user_history = await self.analytics.get_user_history(user_id)
        
        # Generate search queries based on preferences and history
        recommended_queries = await self.recommendations.generate_queries(
            user_history=user_history,
            preferences=preferences,
            location=location
        )
        
        # Execute searches in parallel
        all_results = []
        for query in recommended_queries[:3]:  # Limit to top 3
            results = await self.places.search_places(
                query=query,
                location=location,
                radius=preferences.get('search_radius', 5000)
            )
            all_results.extend(results.places)
        
        # Deduplicate and rank
        unique_places = self._deduplicate_places(all_results)
        ranked_places = await self.recommendations.rank_places(
            places=unique_places,
            user_preferences=preferences
        )
        
        # Get details for top places
        top_places = []
        for place in ranked_places[:10]:
            details = await self.places.get_place_with_details(
                place_id=place.id,
                include_photos=True
            )
            top_places.append(details)
        
        # Track discovery event
        await self.analytics.track_event(
            user_id=user_id,
            event_type="place_discovery",
            data={
                "queries_used": recommended_queries,
                "places_found": len(unique_places),
                "places_shown": len(top_places)
            }
        )
        
        return {
            "recommendations": top_places,
            "search_queries": recommended_queries,
            "total_found": len(unique_places),
            "personalization_score": await self._calculate_personalization_score(
                top_places, preferences
            )
        }
    
    def _deduplicate_places(self, places: List[Place]) -> List[Place]:
        """Remove duplicate places"""
        seen = set()
        unique = []
        
        for place in places:
            if place.id not in seen:
                seen.add(place.id)
                unique.append(place)
        
        return unique
    
    async def _calculate_personalization_score(
        self,
        places: List[PlaceDetails],
        preferences: Dict[str, Any]
    ) -> float:
        """Calculate how well results match preferences"""
        if not places:
            return 0.0
        
        scores = []
        for place in places:
            score = 0.0
            
            # Check type preferences
            preferred_types = preferences.get('place_types', [])
            if preferred_types:
                matching_types = set(place.types) & set(preferred_types)
                score += len(matching_types) / len(preferred_types)
            
            # Check rating preference
            min_rating = preferences.get('min_rating', 0)
            if place.rating and place.rating >= min_rating:
                score += 0.5
            
            # Check price preference
            preferred_price = preferences.get('price_level')
            if preferred_price and place.price_level == preferred_price:
                score += 0.5
            
            scores.append(score)
        
        return sum(scores) / len(scores)
```

### 2. Pipeline Pattern

```python
# places_mcp/services/pipeline.py
from typing import List, Callable, Any, Optional
from dataclasses import dataclass

@dataclass
class PipelineStage:
    """Represents a stage in a processing pipeline"""
    name: str
    processor: Callable
    error_handler: Optional[Callable] = None
    condition: Optional[Callable] = None

class ServicePipeline:
    """
    Pipeline for composing service operations
    
    Allows building complex workflows from simple stages
    """
    
    def __init__(self, name: str):
        self.name = name
        self.stages: List[PipelineStage] = []
    
    def add_stage(self, stage: PipelineStage) -> 'ServicePipeline':
        """Add a stage to the pipeline"""
        self.stages.append(stage)
        return self
    
    async def execute(self, initial_data: Any) -> Any:
        """Execute the pipeline"""
        data = initial_data
        
        for stage in self.stages:
            # Check condition
            if stage.condition and not await stage.condition(data):
                continue
            
            try:
                # Process stage
                data = await stage.processor(data)
                
            except Exception as e:
                if stage.error_handler:
                    data = await stage.error_handler(e, data)
                else:
                    raise
        
        return data

# Example: Place enrichment pipeline
def create_place_enrichment_pipeline(
    details_service: DetailsService,
    photo_service: PhotoService,
    review_service: ReviewService
) -> ServicePipeline:
    """Create a pipeline for enriching place data"""
    
    pipeline = ServicePipeline("place_enrichment")
    
    # Stage 1: Fetch basic details
    pipeline.add_stage(PipelineStage(
        name="fetch_details",
        processor=lambda place: details_service.get_details(
            place_id=place['id'],
            fields=['basic', 'contact']
        )
    ))
    
    # Stage 2: Add photos (conditional)
    pipeline.add_stage(PipelineStage(
        name="add_photos",
        processor=lambda details: photo_service.enrich_with_photos(details),
        condition=lambda details: details.get('include_photos', True)
    ))
    
    # Stage 3: Add reviews (with error handling)
    async def add_reviews_with_fallback(details):
        try:
            return await review_service.enrich_with_reviews(details)
        except Exception:
            # Continue without reviews
            details['reviews'] = []
            return details
    
    pipeline.add_stage(PipelineStage(
        name="add_reviews",
        processor=add_reviews_with_fallback
    ))
    
    # Stage 4: Calculate quality score
    pipeline.add_stage(PipelineStage(
        name="calculate_score",
        processor=lambda details: {
            **details,
            'quality_score': calculate_place_quality_score(details)
        }
    ))
    
    return pipeline
```

## Best Practices Summary

1. **Service Design**
   - Single responsibility per service
   - Clear interfaces and contracts
   - Dependency injection for testability

2. **Business Logic**
   - Centralize in application layer
   - Keep domain models pure
   - Use value objects for complex validation

3. **Caching Strategy**
   - Cache at service boundaries
   - Use intelligent TTLs
   - Implement cache warming for popular data

4. **Error Handling**
   - Categorize errors by severity
   - Implement retry strategies
   - Fail fast for critical errors

5. **Testing**
   - Mock external dependencies
   - Test business logic in isolation
   - Use integration tests for workflows

6. **Performance**
   - Batch operations where possible
   - Use async/await effectively
   - Monitor service metrics

7. **Composition**
   - Use facades for complex workflows
   - Implement pipelines for data processing
   - Keep services loosely coupled

This comprehensive guide provides a solid foundation for implementing the Application Layer in the Places MCP Server, ensuring clean architecture, maintainable code, and robust business logic implementation.