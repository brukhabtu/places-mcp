# Infrastructure Layer Implementation Guide

## Overview

The Infrastructure Layer is responsible for all external integrations and technical concerns in the places-mcp project. It implements the interfaces (ports) defined by the Domain Layer and provides concrete implementations for interacting with external systems like the Google Places API, caching services, and authentication providers.

## Core Responsibilities

1. **External API Communication**: Handle all interactions with Google Places API
2. **Caching**: Implement Redis and in-memory caching strategies
3. **Rate Limiting**: Enforce API rate limits and quotas
4. **Authentication**: Manage API keys and security
5. **Error Handling**: Implement retry logic and error recovery
6. **Monitoring**: Provide logging and metrics collection
7. **Resource Management**: Handle connection pooling and cleanup

## Architecture Principles

### 1. Dependency Inversion
The Infrastructure Layer depends on Domain interfaces, not the other way around:

```python
# places_mcp/domain/ports.py
from abc import abstractmethod
from typing import Protocol, Optional, List, Any
from .models import Place, PlaceDetails, Photo

class PlacesRepository(Protocol):
    """Interface for places data access"""
    
    @abstractmethod
    async def search_text(
        self,
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None,
        **kwargs
    ) -> List[Place]:
        """Search places by text query"""
        ...
    
    @abstractmethod
    async def search_nearby(
        self,
        location: dict,
        radius: int,
        types: Optional[List[str]] = None,
        **kwargs
    ) -> List[Place]:
        """Search places near a location"""
        ...
    
    @abstractmethod
    async def get_details(
        self,
        place_id: str,
        fields: List[str]
    ) -> PlaceDetails:
        """Get detailed place information"""
        ...
    
    @abstractmethod
    async def get_photo(
        self,
        photo_reference: str,
        max_width: Optional[int] = None,
        max_height: Optional[int] = None
    ) -> bytes:
        """Download place photo"""
        ...

class CacheRepository(Protocol):
    """Interface for caching operations"""
    
    @abstractmethod
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve value from cache"""
        ...
    
    @abstractmethod
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Store value in cache with TTL"""
        ...
    
    @abstractmethod
    async def delete(self, key: str) -> None:
        """Remove value from cache"""
        ...
    
    @abstractmethod
    async def clear(self, pattern: Optional[str] = None) -> int:
        """Clear cache entries matching pattern"""
        ...

class RateLimiter(Protocol):
    """Interface for rate limiting"""
    
    @abstractmethod
    async def check_limit(self, key: str) -> bool:
        """Check if request is within rate limits"""
        ...
    
    @abstractmethod
    async def increment(self, key: str) -> int:
        """Increment request counter"""
        ...
```

### 2. Separation of Concerns
Each infrastructure component has a single, well-defined responsibility.

## Google Places API Client Implementation

### Basic Client Structure

```python
# places_mcp/infrastructure/google_places.py
import httpx
import asyncio
from typing import List, Optional, Dict, Any
from contextlib import asynccontextmanager
import logging
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log
)

from ..domain.models import Place, PlaceDetails, Location, Photo
from ..domain.ports import PlacesRepository
from ..domain.exceptions import (
    PlacesAPIError,
    RateLimitError,
    AuthenticationError,
    NotFoundError
)

logger = logging.getLogger(__name__)

class PlacesAPIClient(PlacesRepository):
    """Google Places API client with connection pooling and retry logic"""
    
    BASE_URL = "https://places.googleapis.com/v1"
    DEFAULT_TIMEOUT = 30.0
    MAX_RETRIES = 3
    
    def __init__(
        self,
        api_key: str,
        timeout: float = DEFAULT_TIMEOUT,
        max_connections: int = 10,
        max_keepalive_connections: int = 5
    ):
        self.api_key = api_key
        self.timeout = timeout
        
        # Configure connection pooling
        limits = httpx.Limits(
            max_connections=max_connections,
            max_keepalive_connections=max_keepalive_connections
        )
        
        # Create async client with pooling
        self.client = httpx.AsyncClient(
            base_url=self.BASE_URL,
            headers={
                "X-Goog-Api-Key": api_key,
                "Content-Type": "application/json",
                "User-Agent": "places-mcp/1.0"
            },
            timeout=httpx.Timeout(timeout),
            limits=limits
        )
    
    async def __aenter__(self):
        """Context manager entry"""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - cleanup resources"""
        await self.close()
    
    async def close(self):
        """Close HTTP client and cleanup resources"""
        await self.client.aclose()
    
    @retry(
        stop=stop_after_attempt(MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=4, max=10),
        retry=retry_if_exception_type((httpx.TimeoutException, httpx.NetworkError)),
        before_sleep=before_sleep_log(logger, logging.WARNING)
    )
    async def _make_request(
        self,
        method: str,
        endpoint: str,
        **kwargs
    ) -> Dict[str, Any]:
        """Make HTTP request with retry logic"""
        try:
            response = await self.client.request(
                method=method,
                url=endpoint,
                **kwargs
            )
            
            # Handle different status codes
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 401:
                raise AuthenticationError("Invalid API key")
            elif response.status_code == 403:
                raise AuthenticationError("API key lacks required permissions")
            elif response.status_code == 404:
                raise NotFoundError(f"Resource not found: {endpoint}")
            elif response.status_code == 429:
                # Extract retry-after header if available
                retry_after = response.headers.get("Retry-After", "60")
                raise RateLimitError(f"Rate limit exceeded. Retry after {retry_after}s")
            else:
                error_data = response.json()
                error_message = error_data.get("error", {}).get("message", "Unknown error")
                raise PlacesAPIError(f"API error ({response.status_code}): {error_message}")
                
        except httpx.TimeoutException as e:
            logger.error(f"Request timeout: {str(e)}")
            raise PlacesAPIError(f"Request timed out after {self.timeout}s")
        except httpx.NetworkError as e:
            logger.error(f"Network error: {str(e)}")
            raise PlacesAPIError(f"Network error: {str(e)}")
    
    async def search_text(
        self,
        query: str,
        location: Optional[dict] = None,
        radius: Optional[int] = None,
        language: Optional[str] = None,
        region: Optional[str] = None,
        price_levels: Optional[List[str]] = None,
        open_now: Optional[bool] = None,
        min_rating: Optional[float] = None,
        max_result_count: int = 20
    ) -> List[Place]:
        """Search places by text query with all available parameters"""
        
        # Build request payload
        data = {
            "textQuery": query,
            "maxResultCount": max_result_count
        }
        
        # Add location bias if provided
        if location and radius:
            data["locationBias"] = {
                "circle": {
                    "center": {
                        "latitude": location.get("latitude"),
                        "longitude": location.get("longitude")
                    },
                    "radius": float(radius)
                }
            }
        
        # Add optional parameters
        if language:
            data["languageCode"] = language
        if region:
            data["regionCode"] = region
        if price_levels:
            data["priceLevels"] = price_levels
        if open_now is not None:
            data["openNow"] = open_now
        if min_rating:
            data["minRating"] = min_rating
        
        # Make API request
        response = await self._make_request(
            method="POST",
            endpoint="/places:searchText",
            json=data
        )
        
        # Parse response
        places_data = response.get("places", [])
        return [self._parse_place(p) for p in places_data]
    
    async def search_nearby(
        self,
        location: dict,
        radius: int,
        types: Optional[List[str]] = None,
        language: Optional[str] = None,
        max_result_count: int = 20,
        rank_preference: str = "RELEVANCE"
    ) -> List[Place]:
        """Search places near a specific location"""
        
        data = {
            "locationRestriction": {
                "circle": {
                    "center": {
                        "latitude": location.get("latitude"),
                        "longitude": location.get("longitude")
                    },
                    "radius": float(radius)
                }
            },
            "maxResultCount": max_result_count,
            "rankPreference": rank_preference
        }
        
        if types:
            data["includedTypes"] = types
        if language:
            data["languageCode"] = language
        
        response = await self._make_request(
            method="POST",
            endpoint="/places:searchNearby",
            json=data
        )
        
        places_data = response.get("places", [])
        return [self._parse_place(p) for p in places_data]
    
    async def get_details(
        self,
        place_id: str,
        fields: List[str],
        language: Optional[str] = None
    ) -> PlaceDetails:
        """Get detailed information about a specific place"""
        
        # Validate place_id format
        if not place_id or "/" in place_id:
            raise ValueError("Invalid place_id format")
        
        # Build field mask
        field_mask = ",".join(fields)
        
        # Prepare headers with field mask
        headers = {"X-Goog-FieldMask": field_mask}
        if language:
            headers["X-Goog-Language-Code"] = language
        
        response = await self._make_request(
            method="GET",
            endpoint=f"/places/{place_id}",
            headers=headers
        )
        
        return self._parse_place_details(response)
    
    async def get_photo(
        self,
        photo_reference: str,
        max_width: Optional[int] = None,
        max_height: Optional[int] = None
    ) -> bytes:
        """Download a place photo"""
        
        params = {}
        if max_width:
            params["maxWidthPx"] = max_width
        if max_height:
            params["maxHeightPx"] = max_height
        
        # Photos use a different endpoint pattern
        photo_url = f"{photo_reference}/media"
        
        response = await self.client.get(
            photo_url,
            params=params,
            follow_redirects=True
        )
        
        if response.status_code != 200:
            raise PlacesAPIError(f"Failed to download photo: {response.status_code}")
        
        return response.content
    
    def _parse_place(self, data: dict) -> Place:
        """Parse place data from API response"""
        
        # Extract place ID from resource name
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
            formatted_address=data.get("formattedAddress", ""),
            location=location,
            rating=data.get("rating"),
            user_rating_count=data.get("userRatingCount"),
            types=data.get("types", []),
            price_level=data.get("priceLevel"),
            business_status=data.get("businessStatus", "OPERATIONAL")
        )
    
    def _parse_place_details(self, data: dict) -> PlaceDetails:
        """Parse detailed place data from API response"""
        
        # Start with basic place data
        place = self._parse_place(data)
        
        # Parse photos
        photos = []
        for photo_data in data.get("photos", []):
            photos.append(Photo(
                name=photo_data.get("name", ""),
                width_px=photo_data.get("widthPx"),
                height_px=photo_data.get("heightPx"),
                attributions=photo_data.get("authorAttributions", [])
            ))
        
        # Create detailed place object
        return PlaceDetails(
            **place.dict(),
            website_uri=data.get("websiteUri"),
            international_phone_number=data.get("internationalPhoneNumber"),
            formatted_phone_number=data.get("nationalPhoneNumber"),
            opening_hours=data.get("regularOpeningHours"),
            current_opening_hours=data.get("currentOpeningHours"),
            secondary_opening_hours=data.get("secondaryOpeningHours"),
            reviews=data.get("reviews", []),
            photos=photos,
            generative_summary=data.get("generativeSummary"),
            payment_options=data.get("paymentOptions"),
            parking_options=data.get("parkingOptions"),
            accessibility_options=data.get("accessibilityOptions"),
            ev_charge_options=data.get("evChargeOptions"),
            dine_in=data.get("dineIn"),
            takeout=data.get("takeout"),
            delivery=data.get("delivery"),
            reservable=data.get("reservable"),
            serves_breakfast=data.get("servesBreakfast"),
            serves_lunch=data.get("servesLunch"),
            serves_dinner=data.get("servesDinner"),
            serves_beer=data.get("servesBeer"),
            serves_wine=data.get("servesWine"),
            serves_vegetarian_food=data.get("servesVegetarianFood"),
            outdoor_seating=data.get("outdoorSeating"),
            live_music=data.get("liveMusic"),
            menu_for_children=data.get("menuForChildren"),
            serves_cocktails=data.get("servesCocktails"),
            serves_dessert=data.get("servesDessert"),
            serves_coffee=data.get("servesCoffee"),
            good_for_children=data.get("goodForChildren"),
            allows_dogs=data.get("allowsDogs"),
            restroom=data.get("restroom"),
            good_for_groups=data.get("goodForGroups"),
            good_for_watching_sports=data.get("goodForWatchingSports"),
            utc_offset_minutes=data.get("utcOffsetMinutes"),
            editorial_summary=data.get("editorialSummary"),
            address_components=data.get("addressComponents", [])
        )
```

## Cache Manager Implementations

### Redis Cache Implementation

```python
# places_mcp/infrastructure/cache/redis_cache.py
import json
import pickle
from typing import Optional, Any, Union
import redis.asyncio as redis
from contextlib import asynccontextmanager
import logging

from ...domain.ports import CacheRepository
from ...domain.exceptions import CacheError

logger = logging.getLogger(__name__)

class RedisCacheManager(CacheRepository):
    """Redis-based cache implementation with connection pooling"""
    
    def __init__(
        self,
        url: str = "redis://localhost:6379",
        max_connections: int = 10,
        decode_responses: bool = False,
        serialization: str = "json"  # "json" or "pickle"
    ):
        self.url = url
        self.serialization = serialization
        
        # Create connection pool
        self.pool = redis.ConnectionPool.from_url(
            url,
            max_connections=max_connections,
            decode_responses=decode_responses
        )
        self.redis = redis.Redis(connection_pool=self.pool)
    
    async def __aenter__(self):
        """Context manager entry"""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - cleanup resources"""
        await self.close()
    
    async def close(self):
        """Close Redis connections"""
        await self.redis.close()
        await self.pool.disconnect()
    
    def _serialize(self, value: Any) -> bytes:
        """Serialize value for storage"""
        if self.serialization == "json":
            return json.dumps(value, default=str).encode("utf-8")
        else:
            return pickle.dumps(value)
    
    def _deserialize(self, data: bytes) -> Any:
        """Deserialize value from storage"""
        if self.serialization == "json":
            return json.loads(data.decode("utf-8"))
        else:
            return pickle.loads(data)
    
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve value from cache"""
        try:
            data = await self.redis.get(key)
            if data is None:
                return None
            
            return self._deserialize(data)
            
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            raise CacheError(f"Failed to get cache key {key}: {str(e)}")
        except Exception as e:
            logger.error(f"Cache get error: {str(e)}")
            return None
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Store value in cache with TTL in seconds"""
        try:
            serialized = self._serialize(value)
            await self.redis.setex(key, ttl, serialized)
            
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            raise CacheError(f"Failed to set cache key {key}: {str(e)}")
        except Exception as e:
            logger.error(f"Cache set error: {str(e)}")
            raise CacheError(f"Failed to serialize value for key {key}: {str(e)}")
    
    async def delete(self, key: str) -> None:
        """Remove value from cache"""
        try:
            await self.redis.delete(key)
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            raise CacheError(f"Failed to delete cache key {key}: {str(e)}")
    
    async def clear(self, pattern: Optional[str] = None) -> int:
        """Clear cache entries matching pattern"""
        try:
            if pattern:
                # Use SCAN to find matching keys
                keys = []
                async for key in self.redis.scan_iter(match=pattern):
                    keys.append(key)
                
                if keys:
                    return await self.redis.delete(*keys)
                return 0
            else:
                # Clear all keys (use with caution)
                await self.redis.flushdb()
                return -1  # Indicate full clear
                
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            raise CacheError(f"Failed to clear cache: {str(e)}")
    
    async def exists(self, key: str) -> bool:
        """Check if key exists in cache"""
        try:
            return bool(await self.redis.exists(key))
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            return False
    
    async def expire(self, key: str, ttl: int) -> bool:
        """Update TTL for existing key"""
        try:
            return bool(await self.redis.expire(key, ttl))
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            return False
    
    async def get_ttl(self, key: str) -> Optional[int]:
        """Get remaining TTL for key"""
        try:
            ttl = await self.redis.ttl(key)
            return ttl if ttl > 0 else None
        except redis.ConnectionError as e:
            logger.error(f"Redis connection error: {str(e)}")
            return None
```

### In-Memory Cache Implementation

```python
# places_mcp/infrastructure/cache/memory_cache.py
import asyncio
import time
from typing import Optional, Any, Dict, Tuple
from collections import OrderedDict
import fnmatch
import logging

from ...domain.ports import CacheRepository

logger = logging.getLogger(__name__)

class InMemoryCacheManager(CacheRepository):
    """Thread-safe in-memory cache with TTL support"""
    
    def __init__(self, max_size: int = 1000, cleanup_interval: int = 60):
        self.max_size = max_size
        self.cleanup_interval = cleanup_interval
        self._cache: OrderedDict[str, Tuple[Any, float]] = OrderedDict()
        self._lock = asyncio.Lock()
        self._cleanup_task: Optional[asyncio.Task] = None
        self._running = False
    
    async def __aenter__(self):
        """Start cleanup task"""
        self._running = True
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Stop cleanup task"""
        await self.close()
    
    async def close(self):
        """Stop background tasks"""
        self._running = False
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
    
    async def _cleanup_loop(self):
        """Background task to remove expired entries"""
        while self._running:
            try:
                await asyncio.sleep(self.cleanup_interval)
                await self._remove_expired()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Cache cleanup error: {str(e)}")
    
    async def _remove_expired(self):
        """Remove all expired entries"""
        async with self._lock:
            current_time = time.time()
            expired_keys = [
                key for key, (_, expiry) in self._cache.items()
                if expiry <= current_time
            ]
            
            for key in expired_keys:
                del self._cache[key]
            
            if expired_keys:
                logger.debug(f"Removed {len(expired_keys)} expired cache entries")
    
    async def _evict_if_needed(self):
        """Evict oldest entries if cache is full"""
        while len(self._cache) >= self.max_size:
            # Remove oldest entry (first in OrderedDict)
            self._cache.popitem(last=False)
    
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve value from cache"""
        async with self._lock:
            if key not in self._cache:
                return None
            
            value, expiry = self._cache[key]
            
            # Check if expired
            if expiry <= time.time():
                del self._cache[key]
                return None
            
            # Move to end (LRU behavior)
            self._cache.move_to_end(key)
            return value
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Store value in cache with TTL"""
        async with self._lock:
            # Calculate expiry time
            expiry = time.time() + ttl
            
            # Remove old entry if exists
            if key in self._cache:
                del self._cache[key]
            
            # Evict if needed
            await self._evict_if_needed()
            
            # Add new entry
            self._cache[key] = (value, expiry)
    
    async def delete(self, key: str) -> None:
        """Remove value from cache"""
        async with self._lock:
            self._cache.pop(key, None)
    
    async def clear(self, pattern: Optional[str] = None) -> int:
        """Clear cache entries matching pattern"""
        async with self._lock:
            if pattern:
                # Find matching keys
                matching_keys = [
                    key for key in self._cache.keys()
                    if fnmatch.fnmatch(key, pattern)
                ]
                
                # Remove matching entries
                for key in matching_keys:
                    del self._cache[key]
                
                return len(matching_keys)
            else:
                # Clear all
                count = len(self._cache)
                self._cache.clear()
                return count
    
    async def exists(self, key: str) -> bool:
        """Check if key exists and is not expired"""
        async with self._lock:
            if key not in self._cache:
                return False
            
            _, expiry = self._cache[key]
            if expiry <= time.time():
                del self._cache[key]
                return False
            
            return True
    
    async def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        async with self._lock:
            current_time = time.time()
            expired_count = sum(
                1 for _, expiry in self._cache.values()
                if expiry <= current_time
            )
            
            return {
                "size": len(self._cache),
                "max_size": self.max_size,
                "expired_count": expired_count,
                "hit_rate": 0.0  # Would need to track hits/misses
            }
```

## Rate Limiter Implementation

```python
# places_mcp/infrastructure/rate_limiter.py
import time
import asyncio
from typing import Dict, Optional, Tuple
from collections import defaultdict
import logging

from ..domain.ports import RateLimiter
from ..domain.exceptions import RateLimitError

logger = logging.getLogger(__name__)

class TokenBucketRateLimiter(RateLimiter):
    """Token bucket rate limiter implementation"""
    
    def __init__(
        self,
        rate: int,  # Tokens per second
        burst: int,  # Maximum burst size
        window: int = 60  # Time window in seconds
    ):
        self.rate = rate
        self.burst = burst
        self.window = window
        self._buckets: Dict[str, Tuple[float, float]] = {}
        self._lock = asyncio.Lock()
    
    async def check_limit(self, key: str) -> bool:
        """Check if request is within rate limits"""
        async with self._lock:
            current_time = time.time()
            
            if key not in self._buckets:
                # Initialize bucket
                self._buckets[key] = (float(self.burst), current_time)
                return True
            
            tokens, last_update = self._buckets[key]
            
            # Calculate tokens to add based on time elapsed
            time_elapsed = current_time - last_update
            tokens_to_add = time_elapsed * self.rate
            tokens = min(self.burst, tokens + tokens_to_add)
            
            # Check if we have tokens available
            if tokens >= 1:
                return True
            
            return False
    
    async def increment(self, key: str) -> int:
        """Consume a token and return remaining tokens"""
        async with self._lock:
            current_time = time.time()
            
            if key not in self._buckets:
                # Initialize bucket and consume one token
                self._buckets[key] = (float(self.burst - 1), current_time)
                return self.burst - 1
            
            tokens, last_update = self._buckets[key]
            
            # Calculate tokens to add
            time_elapsed = current_time - last_update
            tokens_to_add = time_elapsed * self.rate
            tokens = min(self.burst, tokens + tokens_to_add)
            
            # Check if we can consume a token
            if tokens < 1:
                wait_time = (1 - tokens) / self.rate
                raise RateLimitError(
                    f"Rate limit exceeded. Retry after {wait_time:.2f} seconds"
                )
            
            # Consume token
            tokens -= 1
            self._buckets[key] = (tokens, current_time)
            
            return int(tokens)
    
    async def reset(self, key: str) -> None:
        """Reset rate limit for a key"""
        async with self._lock:
            self._buckets.pop(key, None)
    
    async def get_wait_time(self, key: str) -> float:
        """Get wait time until next request is allowed"""
        async with self._lock:
            if key not in self._buckets:
                return 0.0
            
            tokens, last_update = self._buckets[key]
            current_time = time.time()
            
            # Calculate current tokens
            time_elapsed = current_time - last_update
            tokens_to_add = time_elapsed * self.rate
            tokens = min(self.burst, tokens + tokens_to_add)
            
            if tokens >= 1:
                return 0.0
            
            # Calculate wait time
            return (1 - tokens) / self.rate


class SlidingWindowRateLimiter(RateLimiter):
    """Sliding window rate limiter for more accurate rate limiting"""
    
    def __init__(
        self,
        max_requests: int,
        window_seconds: int,
        redis_client: Optional[Any] = None  # Optional Redis for distributed limiting
    ):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.redis_client = redis_client
        self._local_windows: Dict[str, list] = defaultdict(list)
        self._lock = asyncio.Lock()
    
    async def check_limit(self, key: str) -> bool:
        """Check if request is within rate limits"""
        if self.redis_client:
            return await self._check_limit_redis(key)
        else:
            return await self._check_limit_local(key)
    
    async def increment(self, key: str) -> int:
        """Record request and return remaining capacity"""
        if self.redis_client:
            return await self._increment_redis(key)
        else:
            return await self._increment_local(key)
    
    async def _check_limit_local(self, key: str) -> bool:
        """Local sliding window check"""
        async with self._lock:
            current_time = time.time()
            window_start = current_time - self.window_seconds
            
            # Remove old entries
            self._local_windows[key] = [
                ts for ts in self._local_windows[key]
                if ts > window_start
            ]
            
            # Check if under limit
            return len(self._local_windows[key]) < self.max_requests
    
    async def _increment_local(self, key: str) -> int:
        """Local sliding window increment"""
        async with self._lock:
            current_time = time.time()
            window_start = current_time - self.window_seconds
            
            # Remove old entries
            self._local_windows[key] = [
                ts for ts in self._local_windows[key]
                if ts > window_start
            ]
            
            # Check limit
            if len(self._local_windows[key]) >= self.max_requests:
                oldest_request = min(self._local_windows[key])
                wait_time = self.window_seconds - (current_time - oldest_request)
                raise RateLimitError(
                    f"Rate limit exceeded. Retry after {wait_time:.2f} seconds"
                )
            
            # Add new request
            self._local_windows[key].append(current_time)
            return self.max_requests - len(self._local_windows[key])
    
    async def _check_limit_redis(self, key: str) -> bool:
        """Redis-based sliding window check"""
        # Implementation would use Redis sorted sets
        # with timestamps as scores
        raise NotImplementedError("Redis rate limiting not implemented")
    
    async def _increment_redis(self, key: str) -> int:
        """Redis-based sliding window increment"""
        raise NotImplementedError("Redis rate limiting not implemented")
```

## Authentication Manager

```python
# places_mcp/infrastructure/auth.py
import os
import logging
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

from ..domain.exceptions import AuthenticationError

logger = logging.getLogger(__name__)

class AuthManager:
    """Manage API authentication and key rotation"""
    
    def __init__(
        self,
        api_key: Optional[str] = None,
        key_rotation_interval: Optional[timedelta] = None,
        public_key_path: Optional[str] = None
    ):
        self.api_key = api_key or os.getenv("GOOGLE_API_KEY")
        if not self.api_key:
            raise AuthenticationError("No API key provided")
        
        self.key_rotation_interval = key_rotation_interval
        self._last_rotation = datetime.utcnow()
        self._public_key = None
        
        if public_key_path:
            self._load_public_key(public_key_path)
    
    def _load_public_key(self, path: str):
        """Load RSA public key for JWT validation"""
        try:
            with open(path, "rb") as f:
                self._public_key = serialization.load_pem_public_key(
                    f.read(),
                    backend=default_backend()
                )
        except Exception as e:
            logger.error(f"Failed to load public key: {str(e)}")
            raise AuthenticationError(f"Invalid public key: {str(e)}")
    
    def get_api_key(self) -> str:
        """Get current API key"""
        if self.key_rotation_interval:
            self._check_rotation()
        return self.api_key
    
    def _check_rotation(self):
        """Check if key rotation is needed"""
        if not self.key_rotation_interval:
            return
        
        time_since_rotation = datetime.utcnow() - self._last_rotation
        if time_since_rotation >= self.key_rotation_interval:
            self._rotate_key()
    
    def _rotate_key(self):
        """Rotate API key (implementation depends on key management system)"""
        # This would integrate with your key management system
        # For example: AWS Secrets Manager, HashiCorp Vault, etc.
        logger.warning("Key rotation not implemented")
        self._last_rotation = datetime.utcnow()
    
    def validate_jwt(self, token: str) -> Dict[str, Any]:
        """Validate JWT token for authenticated requests"""
        if not self._public_key:
            raise AuthenticationError("No public key configured for JWT validation")
        
        try:
            payload = jwt.decode(
                token,
                self._public_key,
                algorithms=["RS256"]
            )
            return payload
        except jwt.ExpiredSignatureError:
            raise AuthenticationError("Token has expired")
        except jwt.InvalidTokenError as e:
            raise AuthenticationError(f"Invalid token: {str(e)}")
    
    def create_api_headers(self) -> Dict[str, str]:
        """Create headers for API requests"""
        return {
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-Api-Version": "v1"
        }
```

## Error Handling and Retries

```python
# places_mcp/infrastructure/resilience.py
import asyncio
import random
from typing import TypeVar, Callable, Any, Optional, Type, Tuple
from functools import wraps
import logging

from ..domain.exceptions import (
    PlacesAPIError,
    RateLimitError,
    AuthenticationError,
    NotFoundError
)

logger = logging.getLogger(__name__)

T = TypeVar("T")

class RetryConfig:
    """Configuration for retry behavior"""
    def __init__(
        self,
        max_attempts: int = 3,
        initial_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        jitter: bool = True,
        retryable_exceptions: Tuple[Type[Exception], ...] = (
            PlacesAPIError,
            asyncio.TimeoutError,
            ConnectionError
        )
    ):
        self.max_attempts = max_attempts
        self.initial_delay = initial_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.jitter = jitter
        self.retryable_exceptions = retryable_exceptions


def with_retry(config: Optional[RetryConfig] = None):
    """Decorator for adding retry logic to async functions"""
    if config is None:
        config = RetryConfig()
    
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> T:
            last_exception = None
            
            for attempt in range(config.max_attempts):
                try:
                    return await func(*args, **kwargs)
                    
                except config.retryable_exceptions as e:
                    last_exception = e
                    
                    if attempt == config.max_attempts - 1:
                        logger.error(
                            f"{func.__name__} failed after {config.max_attempts} attempts: {str(e)}"
                        )
                        raise
                    
                    # Calculate delay with exponential backoff
                    delay = min(
                        config.initial_delay * (config.exponential_base ** attempt),
                        config.max_delay
                    )
                    
                    # Add jitter to prevent thundering herd
                    if config.jitter:
                        delay *= (0.5 + random.random())
                    
                    logger.warning(
                        f"{func.__name__} attempt {attempt + 1} failed: {str(e)}. "
                        f"Retrying in {delay:.2f}s..."
                    )
                    
                    await asyncio.sleep(delay)
                    
                except (AuthenticationError, NotFoundError):
                    # Don't retry on auth or not found errors
                    raise
                    
                except RateLimitError as e:
                    # Extract retry-after if available
                    if hasattr(e, "retry_after"):
                        delay = e.retry_after
                    else:
                        delay = config.max_delay
                    
                    logger.warning(f"Rate limited. Waiting {delay}s before retry...")
                    await asyncio.sleep(delay)
                    
            raise last_exception
            
        return wrapper
    return decorator


class CircuitBreaker:
    """Circuit breaker pattern for preventing cascading failures"""
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        expected_exception: Type[Exception] = Exception
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.expected_exception = expected_exception
        
        self._failure_count = 0
        self._last_failure_time: Optional[float] = None
        self._state = "closed"  # closed, open, half-open
    
    async def call(self, func: Callable[..., T], *args, **kwargs) -> T:
        """Execute function with circuit breaker protection"""
        if self._state == "open":
            if self._should_attempt_reset():
                self._state = "half-open"
            else:
                raise PlacesAPIError("Circuit breaker is open")
        
        try:
            result = await func(*args, **kwargs)
            self._on_success()
            return result
            
        except self.expected_exception as e:
            self._on_failure()
            raise
    
    def _should_attempt_reset(self) -> bool:
        """Check if we should try to reset the circuit"""
        return (
            self._last_failure_time and
            asyncio.get_event_loop().time() - self._last_failure_time >= self.recovery_timeout
        )
    
    def _on_success(self):
        """Handle successful call"""
        self._failure_count = 0
        self._state = "closed"
    
    def _on_failure(self):
        """Handle failed call"""
        self._failure_count += 1
        self._last_failure_time = asyncio.get_event_loop().time()
        
        if self._failure_count >= self.failure_threshold:
            self._state = "open"
            logger.error(f"Circuit breaker opened after {self._failure_count} failures")
```

## Monitoring and Logging

```python
# places_mcp/infrastructure/monitoring.py
import time
import logging
from typing import Dict, Any, Optional, Callable
from functools import wraps
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from collections import defaultdict
import asyncio

logger = logging.getLogger(__name__)

@dataclass
class Metrics:
    """Container for performance metrics"""
    request_count: int = 0
    error_count: int = 0
    total_duration: float = 0.0
    cache_hits: int = 0
    cache_misses: int = 0
    rate_limit_hits: int = 0
    
    @property
    def average_duration(self) -> float:
        """Calculate average request duration"""
        if self.request_count == 0:
            return 0.0
        return self.total_duration / self.request_count
    
    @property
    def error_rate(self) -> float:
        """Calculate error rate"""
        if self.request_count == 0:
            return 0.0
        return self.error_count / self.request_count
    
    @property
    def cache_hit_rate(self) -> float:
        """Calculate cache hit rate"""
        total_cache_requests = self.cache_hits + self.cache_misses
        if total_cache_requests == 0:
            return 0.0
        return self.cache_hits / total_cache_requests


class MetricsCollector:
    """Collect and report metrics"""
    
    def __init__(self, namespace: str = "places_mcp"):
        self.namespace = namespace
        self.metrics: Dict[str, Metrics] = defaultdict(Metrics)
        self._lock = asyncio.Lock()
    
    @asynccontextmanager
    async def timer(self, operation: str):
        """Context manager for timing operations"""
        start_time = time.time()
        
        try:
            yield
            
        finally:
            duration = time.time() - start_time
            async with self._lock:
                self.metrics[operation].request_count += 1
                self.metrics[operation].total_duration += duration
            
            logger.debug(f"{operation} completed in {duration:.3f}s")
    
    async def increment_counter(self, metric: str, value: int = 1):
        """Increment a counter metric"""
        async with self._lock:
            if metric == "error":
                self.metrics["global"].error_count += value
            elif metric == "cache_hit":
                self.metrics["global"].cache_hits += value
            elif metric == "cache_miss":
                self.metrics["global"].cache_misses += value
            elif metric == "rate_limit":
                self.metrics["global"].rate_limit_hits += value
    
    async def get_metrics(self) -> Dict[str, Any]:
        """Get all collected metrics"""
        async with self._lock:
            result = {}
            
            for operation, metrics in self.metrics.items():
                result[operation] = {
                    "request_count": metrics.request_count,
                    "error_count": metrics.error_count,
                    "average_duration": metrics.average_duration,
                    "error_rate": metrics.error_rate,
                    "cache_hit_rate": metrics.cache_hit_rate,
                    "rate_limit_hits": metrics.rate_limit_hits
                }
            
            return result
    
    def log_metrics(self):
        """Log current metrics"""
        asyncio.create_task(self._log_metrics_async())
    
    async def _log_metrics_async(self):
        """Async logging of metrics"""
        metrics = await self.get_metrics()
        logger.info(f"Metrics: {metrics}")


def monitored(collector: MetricsCollector, operation: str):
    """Decorator for monitoring function performance"""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            async with collector.timer(operation):
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    await collector.increment_counter("error")
                    raise
        
        return wrapper
    return decorator


class StructuredLogger:
    """Structured logging with context"""
    
    def __init__(self, name: str):
        self.logger = logging.getLogger(name)
        self.context: Dict[str, Any] = {}
    
    def with_context(self, **kwargs) -> "StructuredLogger":
        """Create new logger with additional context"""
        new_logger = StructuredLogger(self.logger.name)
        new_logger.context = {**self.context, **kwargs}
        return new_logger
    
    def _format_message(self, message: str, **kwargs) -> str:
        """Format message with context"""
        context = {**self.context, **kwargs}
        if context:
            context_str = " ".join(f"{k}={v}" for k, v in context.items())
            return f"{message} | {context_str}"
        return message
    
    def info(self, message: str, **kwargs):
        """Log info with context"""
        self.logger.info(self._format_message(message, **kwargs))
    
    def error(self, message: str, **kwargs):
        """Log error with context"""
        self.logger.error(self._format_message(message, **kwargs))
    
    def warning(self, message: str, **kwargs):
        """Log warning with context"""
        self.logger.warning(self._format_message(message, **kwargs))
    
    def debug(self, message: str, **kwargs):
        """Log debug with context"""
        self.logger.debug(self._format_message(message, **kwargs))
```

## Testing Infrastructure Components

### Mock Implementations for Testing

```python
# places_mcp/infrastructure/testing/mocks.py
from typing import List, Dict, Any, Optional
import asyncio
from unittest.mock import MagicMock

from ...domain.models import Place, PlaceDetails, Location
from ...domain.ports import PlacesRepository, CacheRepository, RateLimiter

class MockPlacesRepository(PlacesRepository):
    """Mock implementation for testing"""
    
    def __init__(self):
        self.search_text_calls = []
        self.get_details_calls = []
        self._search_results = []
        self._details_results = {}
    
    def set_search_results(self, results: List[Place]):
        """Set mock search results"""
        self._search_results = results
    
    def set_details_result(self, place_id: str, details: PlaceDetails):
        """Set mock details result"""
        self._details_results[place_id] = details
    
    async def search_text(self, query: str, **kwargs) -> List[Place]:
        """Mock search implementation"""
        self.search_text_calls.append({"query": query, **kwargs})
        await asyncio.sleep(0.01)  # Simulate network delay
        return self._search_results
    
    async def search_nearby(self, location: dict, radius: int, **kwargs) -> List[Place]:
        """Mock nearby search"""
        return self._search_results
    
    async def get_details(self, place_id: str, fields: List[str]) -> PlaceDetails:
        """Mock get details"""
        self.get_details_calls.append({"place_id": place_id, "fields": fields})
        await asyncio.sleep(0.01)
        
        if place_id in self._details_results:
            return self._details_results[place_id]
        
        # Return default mock details
        return PlaceDetails(
            id=place_id,
            display_name="Mock Place",
            formatted_address="123 Mock St",
            location=Location(latitude=0.0, longitude=0.0),
            rating=4.5,
            user_rating_count=100
        )
    
    async def get_photo(self, photo_reference: str, **kwargs) -> bytes:
        """Mock photo download"""
        return b"mock_photo_data"


class MockCache(CacheRepository):
    """Mock cache for testing"""
    
    def __init__(self):
        self._cache: Dict[str, Any] = {}
        self.get_calls = []
        self.set_calls = []
    
    async def get(self, key: str) -> Optional[Any]:
        """Mock get"""
        self.get_calls.append(key)
        return self._cache.get(key)
    
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Mock set"""
        self.set_calls.append({"key": key, "ttl": ttl})
        self._cache[key] = value
    
    async def delete(self, key: str) -> None:
        """Mock delete"""
        self._cache.pop(key, None)
    
    async def clear(self, pattern: Optional[str] = None) -> int:
        """Mock clear"""
        if pattern:
            # Simple pattern matching
            keys_to_delete = [
                k for k in self._cache.keys()
                if pattern in k
            ]
            for key in keys_to_delete:
                del self._cache[key]
            return len(keys_to_delete)
        else:
            count = len(self._cache)
            self._cache.clear()
            return count


class MockRateLimiter(RateLimiter):
    """Mock rate limiter for testing"""
    
    def __init__(self, should_limit: bool = False):
        self.should_limit = should_limit
        self.check_calls = []
        self.increment_calls = []
    
    async def check_limit(self, key: str) -> bool:
        """Mock check"""
        self.check_calls.append(key)
        return not self.should_limit
    
    async def increment(self, key: str) -> int:
        """Mock increment"""
        self.increment_calls.append(key)
        if self.should_limit:
            from ...domain.exceptions import RateLimitError
            raise RateLimitError("Mock rate limit exceeded")
        return 10  # Mock remaining capacity
```

### Integration Test Fixtures

```python
# places_mcp/infrastructure/testing/fixtures.py
import pytest
import asyncio
from typing import AsyncGenerator
import redis.asyncio as redis
from testcontainers.redis import RedisContainer

from ..cache.redis_cache import RedisCacheManager
from ..cache.memory_cache import InMemoryCacheManager
from ..google_places import PlacesAPIClient

@pytest.fixture
async def redis_container():
    """Provide Redis test container"""
    with RedisContainer() as container:
        yield container

@pytest.fixture
async def redis_cache(redis_container) -> AsyncGenerator[RedisCacheManager, None]:
    """Provide Redis cache manager for tests"""
    cache = RedisCacheManager(
        url=redis_container.get_connection_url()
    )
    async with cache:
        yield cache

@pytest.fixture
async def memory_cache() -> AsyncGenerator[InMemoryCacheManager, None]:
    """Provide in-memory cache for tests"""
    cache = InMemoryCacheManager(max_size=100)
    async with cache:
        yield cache

@pytest.fixture
async def places_client(monkeypatch) -> PlacesAPIClient:
    """Provide mocked Places API client"""
    # Set fake API key for tests
    monkeypatch.setenv("GOOGLE_API_KEY", "test-api-key")
    
    client = PlacesAPIClient(api_key="test-api-key")
    
    # Mock the HTTP client to prevent real API calls
    import httpx
    mock_response = httpx.Response(
        200,
        json={"places": []},
        request=httpx.Request("POST", "https://test.com")
    )
    
    client.client.request = AsyncMock(return_value=mock_response)
    
    yield client
    
    await client.close()

@pytest.fixture
def sample_place() -> Place:
    """Provide sample place for tests"""
    return Place(
        id="ChIJN1t_tDeuEmsRUsoyG83frY4",
        display_name="Google Sydney",
        formatted_address="48 Pirrama Rd, Pyrmont NSW 2009, Australia",
        location=Location(
            latitude=-33.866489,
            longitude=151.195841
        ),
        rating=4.5,
        user_rating_count=1000,
        types=["corporate_office", "point_of_interest"]
    )

@pytest.fixture
def sample_place_details() -> PlaceDetails:
    """Provide sample place details for tests"""
    return PlaceDetails(
        id="ChIJN1t_tDeuEmsRUsoyG83frY4",
        display_name="Google Sydney",
        formatted_address="48 Pirrama Rd, Pyrmont NSW 2009, Australia",
        location=Location(
            latitude=-33.866489,
            longitude=151.195841
        ),
        rating=4.5,
        user_rating_count=1000,
        types=["corporate_office", "point_of_interest"],
        website_uri="https://google.com.au",
        international_phone_number="+61 2 9374 4000",
        opening_hours={
            "periods": [
                {
                    "open": {"day": 1, "time": "0900"},
                    "close": {"day": 1, "time": "1700"}
                }
            ],
            "weekdayText": [
                "Monday: 9:00 AM – 5:00 PM"
            ]
        }
    )
```

## Best Practices Summary

### 1. **Async/Await Patterns**
- Use `async with` for resource management
- Implement proper connection pooling
- Handle concurrent requests efficiently
- Clean up resources in context managers

### 2. **Error Handling**
- Implement specific exception types
- Use exponential backoff for retries
- Handle rate limits gracefully
- Provide meaningful error messages

### 3. **Resource Management**
- Use connection pooling for HTTP clients
- Implement circuit breakers for failing services
- Clean up resources properly
- Monitor resource usage

### 4. **Testing**
- Use mock implementations for unit tests
- Use test containers for integration tests
- Test error scenarios thoroughly
- Verify retry and circuit breaker behavior

### 5. **Monitoring**
- Log all external API calls
- Track performance metrics
- Monitor error rates
- Set up alerts for failures

### 6. **Security**
- Never log API keys
- Rotate keys regularly
- Validate all inputs
- Use HTTPS for all connections

## Configuration Example

```python
# places_mcp/infrastructure/config.py
from pydantic import BaseSettings, Field
from typing import Optional

class InfrastructureConfig(BaseSettings):
    """Infrastructure layer configuration"""
    
    # Google Places API
    google_api_key: str = Field(..., env="GOOGLE_API_KEY")
    places_api_timeout: float = Field(default=30.0, env="PLACES_API_TIMEOUT")
    places_max_retries: int = Field(default=3, env="PLACES_MAX_RETRIES")
    
    # Redis Cache
    redis_url: str = Field(default="redis://localhost:6379", env="REDIS_URL")
    cache_ttl: int = Field(default=1800, env="CACHE_TTL")  # 30 minutes
    
    # Rate Limiting
    rate_limit_requests: int = Field(default=100, env="RATE_LIMIT_REQUESTS")
    rate_limit_window: int = Field(default=60, env="RATE_LIMIT_WINDOW")
    
    # Connection Pooling
    max_connections: int = Field(default=10, env="MAX_CONNECTIONS")
    max_keepalive: int = Field(default=5, env="MAX_KEEPALIVE")
    
    # Monitoring
    enable_metrics: bool = Field(default=True, env="ENABLE_METRICS")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
```

## Dependency Injection Setup

```python
# places_mcp/infrastructure/container.py
from dependency_injector import containers, providers

from .config import InfrastructureConfig
from .google_places import PlacesAPIClient
from .cache.redis_cache import RedisCacheManager
from .cache.memory_cache import InMemoryCacheManager
from .rate_limiter import TokenBucketRateLimiter
from .auth import AuthManager
from .monitoring import MetricsCollector

class InfrastructureContainer(containers.DeclarativeContainer):
    """DI container for infrastructure components"""
    
    config = providers.Configuration()
    
    # Metrics collector
    metrics_collector = providers.Singleton(
        MetricsCollector,
        namespace="places_mcp"
    )
    
    # Authentication
    auth_manager = providers.Singleton(
        AuthManager,
        api_key=config.google_api_key
    )
    
    # Rate limiter
    rate_limiter = providers.Singleton(
        TokenBucketRateLimiter,
        rate=config.rate_limit_requests,
        burst=config.rate_limit_requests * 2,
        window=config.rate_limit_window
    )
    
    # Cache implementation (switch based on config)
    cache_manager = providers.Selector(
        config.cache_type,
        redis=providers.Singleton(
            RedisCacheManager,
            url=config.redis_url
        ),
        memory=providers.Singleton(
            InMemoryCacheManager,
            max_size=1000
        )
    )
    
    # Places API client
    places_client = providers.Singleton(
        PlacesAPIClient,
        api_key=config.google_api_key,
        timeout=config.places_api_timeout,
        max_connections=config.max_connections
    )
```

This comprehensive guide provides a complete implementation blueprint for the Infrastructure Layer, covering all essential components with production-ready patterns and best practices.