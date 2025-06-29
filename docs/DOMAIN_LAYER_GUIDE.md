# Domain Layer Implementation Guide

## Overview

The Domain Layer is the heart of the Places MCP application, containing the core business logic and rules. This layer has **zero external dependencies** (except Python stdlib and Pydantic) and defines the fundamental concepts, behaviors, and rules of the places domain.

### Core Principles

1. **Pure Business Logic**: Contains only business rules and domain concepts
2. **Framework Agnostic**: No dependencies on external frameworks or infrastructure
3. **Rich Domain Models**: Entities with behavior, not just data containers
4. **Type Safety**: Comprehensive type hints and validation
5. **Immutability**: Prefer immutable value objects where appropriate

## Public Interfaces (Protocols)

These protocols define contracts that infrastructure implementations must follow:

```python
# places_mcp/domain/ports.py
from abc import abstractmethod
from typing import Protocol, Optional, List, Dict, Any
from datetime import datetime

from .models import Place, PlaceDetails, Photo, SearchQuery, SearchResult

class PlacesRepository(Protocol):
    """Interface for places data access"""
    
    @abstractmethod
    async def search_text(
        self,
        query: str,
        location: Optional[Dict[str, float]] = None,
        radius: Optional[int] = None,
        place_types: Optional[List[str]] = None,
        price_levels: Optional[List[str]] = None,
        rank_preference: str = "RELEVANCE"
    ) -> SearchResult:
        """Search for places using text query"""
        ...
    
    @abstractmethod
    async def search_nearby(
        self,
        location: Dict[str, float],
        radius: int,
        place_types: Optional[List[str]] = None,
        rank_preference: str = "DISTANCE"
    ) -> SearchResult:
        """Search for places near a location"""
        ...
    
    @abstractmethod
    async def get_place_details(
        self,
        place_id: str,
        fields: List[str]
    ) -> PlaceDetails:
        """Get detailed information about a specific place"""
        ...
    
    @abstractmethod
    async def get_place_photo(
        self,
        photo_reference: str,
        max_width: Optional[int] = None,
        max_height: Optional[int] = None
    ) -> bytes:
        """Retrieve photo data"""
        ...

class CacheRepository(Protocol):
    """Interface for caching functionality"""
    
    @abstractmethod
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve cached value"""
        ...
    
    @abstractmethod
    async def set(self, key: str, value: Any, ttl: int) -> None:
        """Store value in cache with TTL in seconds"""
        ...
    
    @abstractmethod
    async def delete(self, key: str) -> None:
        """Remove value from cache"""
        ...
    
    @abstractmethod
    async def exists(self, key: str) -> bool:
        """Check if key exists in cache"""
        ...

class RateLimiter(Protocol):
    """Interface for rate limiting"""
    
    @abstractmethod
    async def check_rate_limit(self, key: str) -> bool:
        """Check if request is within rate limits"""
        ...
    
    @abstractmethod
    async def record_request(self, key: str) -> None:
        """Record a request for rate limiting"""
        ...
    
    @abstractmethod
    async def get_remaining_requests(self, key: str) -> int:
        """Get number of remaining requests in current window"""
        ...
```

## Domain Models

### Core Entities

```python
# places_mcp/domain/models.py
from pydantic import BaseModel, Field, validator, root_validator
from typing import Optional, List, Dict, Any, Set
from datetime import datetime, time
from decimal import Decimal
from enum import Enum

# Value Objects and Enums

class DayOfWeek(str, Enum):
    """Days of the week"""
    MONDAY = "MONDAY"
    TUESDAY = "TUESDAY"
    WEDNESDAY = "WEDNESDAY"
    THURSDAY = "THURSDAY"
    FRIDAY = "FRIDAY"
    SATURDAY = "SATURDAY"
    SUNDAY = "SUNDAY"

class PriceLevel(str, Enum):
    """Place price levels"""
    FREE = "PRICE_LEVEL_FREE"
    INEXPENSIVE = "PRICE_LEVEL_INEXPENSIVE"
    MODERATE = "PRICE_LEVEL_MODERATE"
    EXPENSIVE = "PRICE_LEVEL_EXPENSIVE"
    VERY_EXPENSIVE = "PRICE_LEVEL_VERY_EXPENSIVE"

class RankPreference(str, Enum):
    """Search result ranking preference"""
    RELEVANCE = "RELEVANCE"
    DISTANCE = "DISTANCE"

class PlaceType(str, Enum):
    """Common place types"""
    RESTAURANT = "restaurant"
    CAFE = "cafe"
    BAR = "bar"
    HOTEL = "lodging"
    MUSEUM = "museum"
    PARK = "park"
    STORE = "store"
    SHOPPING_MALL = "shopping_mall"
    HOSPITAL = "hospital"
    PHARMACY = "pharmacy"
    ATM = "atm"
    GAS_STATION = "gas_station"
    PARKING = "parking"
    SUBWAY_STATION = "subway_station"
    TRAIN_STATION = "train_station"
    BUS_STATION = "bus_station"
    AIRPORT = "airport"

class EVConnectorType(str, Enum):
    """Electric vehicle connector types"""
    J1772 = "EV_CONNECTOR_TYPE_J1772"
    TYPE_2 = "EV_CONNECTOR_TYPE_TYPE_2"
    CHADEMO = "EV_CONNECTOR_TYPE_CHADEMO"
    CCS_1 = "EV_CONNECTOR_TYPE_CCS_1"
    CCS_2 = "EV_CONNECTOR_TYPE_CCS_2"
    TESLA = "EV_CONNECTOR_TYPE_TESLA"

# Value Objects

class Location(BaseModel):
    """Geographic coordinates"""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    
    @validator('latitude', 'longitude')
    def validate_precision(cls, v):
        """Ensure reasonable precision for coordinates"""
        return round(v, 7)  # ~1.1cm precision
    
    def distance_to(self, other: 'Location') -> float:
        """Calculate distance to another location in meters using Haversine formula"""
        from math import radians, sin, cos, sqrt, atan2
        
        R = 6371000  # Earth's radius in meters
        lat1, lon1 = radians(self.latitude), radians(self.longitude)
        lat2, lon2 = radians(other.latitude), radians(other.longitude)
        
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    
    class Config:
        frozen = True  # Make immutable

class TimeOfDay(BaseModel):
    """Time representation for opening hours"""
    hour: int = Field(..., ge=0, le=23)
    minute: int = Field(..., ge=0, le=59)
    
    def to_time(self) -> time:
        """Convert to Python time object"""
        return time(self.hour, self.minute)
    
    def __str__(self) -> str:
        return f"{self.hour:02d}:{self.minute:02d}"
    
    class Config:
        frozen = True

class OpeningHoursPeriod(BaseModel):
    """A period when a place is open"""
    open_day: DayOfWeek
    open_time: TimeOfDay
    close_day: Optional[DayOfWeek] = None
    close_time: Optional[TimeOfDay] = None
    
    @root_validator
    def validate_period(cls, values):
        """Ensure close time is after open time if on same day"""
        open_day = values.get('open_day')
        close_day = values.get('close_day')
        open_time = values.get('open_time')
        close_time = values.get('close_time')
        
        if close_day and close_time:
            if open_day == close_day and close_time.to_time() <= open_time.to_time():
                raise ValueError("Close time must be after open time on the same day")
        
        return values

class OpeningHours(BaseModel):
    """Place opening hours"""
    periods: List[OpeningHoursPeriod]
    weekday_descriptions: List[str] = Field(default_factory=list)
    
    def is_open_at(self, dt: datetime) -> bool:
        """Check if place is open at given datetime"""
        day = DayOfWeek(dt.strftime("%A").upper())
        current_time = TimeOfDay(hour=dt.hour, minute=dt.minute)
        
        for period in self.periods:
            if period.open_day == day:
                # Check if current time is within period
                if period.close_day is None or period.close_day == day:
                    # Same day closing
                    if (period.open_time.to_time() <= current_time.to_time() and
                        (period.close_time is None or current_time.to_time() < period.close_time.to_time())):
                        return True
                else:
                    # Next day closing (e.g., open past midnight)
                    if period.open_time.to_time() <= current_time.to_time():
                        return True
            
            # Check if we're in a period that started on a previous day
            if period.close_day == day and period.close_time:
                if current_time.to_time() < period.close_time.to_time():
                    return True
        
        return False

class PhoneNumber(BaseModel):
    """Validated phone number"""
    national_number: str
    international_number: str
    
    @validator('international_number')
    def validate_international_format(cls, v):
        """Ensure international format starts with +"""
        if not v.startswith('+'):
            raise ValueError("International number must start with +")
        return v
    
    class Config:
        frozen = True

class Address(BaseModel):
    """Structured address information"""
    formatted_address: str
    street_number: Optional[str] = None
    street_name: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postal_code: Optional[str] = None
    country: Optional[str] = None
    
    @validator('formatted_address')
    def validate_not_empty(cls, v):
        """Ensure formatted address is not empty"""
        if not v or not v.strip():
            raise ValueError("Formatted address cannot be empty")
        return v.strip()
    
    class Config:
        frozen = True

# Entities

class Place(BaseModel):
    """Basic place information"""
    id: str = Field(..., description="Unique place identifier")
    display_name: str = Field(..., min_length=1)
    formatted_address: Optional[str] = None
    location: Optional[Location] = None
    types: List[str] = Field(default_factory=list)
    primary_type: Optional[str] = None
    rating: Optional[float] = Field(None, ge=1.0, le=5.0)
    user_rating_count: Optional[int] = Field(None, ge=0)
    price_level: Optional[PriceLevel] = None
    
    @validator('id')
    def validate_place_id(cls, v):
        """Ensure place ID is not empty"""
        if not v or not v.strip():
            raise ValueError("Place ID cannot be empty")
        return v.strip()
    
    @validator('display_name')
    def clean_display_name(cls, v):
        """Clean and validate display name"""
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Display name cannot be empty")
        return cleaned
    
    def get_primary_type_display(self) -> str:
        """Get human-readable primary type"""
        if self.primary_type:
            return self.primary_type.replace('_', ' ').title()
        elif self.types:
            return self.types[0].replace('_', ' ').title()
        return "Place"
    
    def has_type(self, place_type: Union[str, PlaceType]) -> bool:
        """Check if place has a specific type"""
        type_str = place_type.value if isinstance(place_type, PlaceType) else place_type
        return type_str in self.types or type_str == self.primary_type

class PlaceDetails(Place):
    """Detailed place information"""
    # Contact information
    website_uri: Optional[str] = None
    phone_number: Optional[PhoneNumber] = None
    
    # Operating information
    regular_opening_hours: Optional[OpeningHours] = None
    current_opening_hours: Optional[OpeningHours] = None
    secondary_opening_hours: Optional[List[OpeningHours]] = Field(default_factory=list)
    business_status: Optional[str] = None
    
    # Additional details
    editorial_summary: Optional[str] = None
    address_components: Optional[List[Dict[str, Any]]] = Field(default_factory=list)
    plus_code: Optional[Dict[str, str]] = None
    
    # Reviews and photos
    reviews: List['Review'] = Field(default_factory=list)
    photos: List['Photo'] = Field(default_factory=list)
    
    # AI-generated content
    generative_summary: Optional['GenerativeSummary'] = None
    
    # New 2025 attributes
    payment_options: Optional['PaymentOptions'] = None
    parking_options: Optional['ParkingOptions'] = None
    accessibility_options: Optional['AccessibilityOptions'] = None
    ev_charge_options: Optional['EVChargeOptions'] = None
    
    @validator('website_uri')
    def validate_website(cls, v):
        """Ensure website URI is valid"""
        if v and not (v.startswith('http://') or v.startswith('https://')):
            raise ValueError("Website URI must start with http:// or https://")
        return v
    
    def is_currently_open(self) -> Optional[bool]:
        """Check if place is currently open"""
        if self.current_opening_hours:
            return self.current_opening_hours.is_open_at(datetime.now())
        elif self.regular_opening_hours:
            return self.regular_opening_hours.is_open_at(datetime.now())
        return None
    
    def get_top_reviews(self, count: int = 5) -> List['Review']:
        """Get top-rated reviews"""
        sorted_reviews = sorted(
            self.reviews,
            key=lambda r: (r.rating, r.publish_time),
            reverse=True
        )
        return sorted_reviews[:count]

class Review(BaseModel):
    """User review of a place"""
    author_name: str
    author_photo_uri: Optional[str] = None
    rating: float = Field(..., ge=1.0, le=5.0)
    text: Optional[str] = None
    publish_time: datetime
    relative_time_description: Optional[str] = None
    
    @validator('text')
    def clean_review_text(cls, v):
        """Clean review text"""
        if v:
            return v.strip()
        return v
    
    def get_summary(self, max_length: int = 100) -> str:
        """Get truncated review summary"""
        if not self.text:
            return ""
        if len(self.text) <= max_length:
            return self.text
        return self.text[:max_length-3] + "..."

class Photo(BaseModel):
    """Photo metadata"""
    name: str = Field(..., description="Photo resource name")
    width_px: int = Field(..., gt=0)
    height_px: int = Field(..., gt=0)
    attributions: List[str] = Field(default_factory=list)
    
    @property
    def aspect_ratio(self) -> float:
        """Calculate aspect ratio"""
        return self.width_px / self.height_px
    
    def get_scaled_dimensions(
        self,
        max_width: Optional[int] = None,
        max_height: Optional[int] = None
    ) -> tuple[int, int]:
        """Calculate scaled dimensions maintaining aspect ratio"""
        width, height = self.width_px, self.height_px
        
        if max_width and width > max_width:
            scale = max_width / width
            width = max_width
            height = int(height * scale)
        
        if max_height and height > max_height:
            scale = max_height / height
            height = max_height
            width = int(width * scale)
        
        return width, height

class GenerativeSummary(BaseModel):
    """AI-generated place summary"""
    overview: Optional[Dict[str, str]] = None  # {"text": "...", "languageCode": "en"}
    description: Optional[Dict[str, str]] = None
    
    def get_text(self, language: str = "en") -> Optional[str]:
        """Get summary text for specified language"""
        for summary in [self.overview, self.description]:
            if summary and summary.get("languageCode") == language:
                return summary.get("text")
        # Fallback to any available text
        if self.overview:
            return self.overview.get("text")
        if self.description:
            return self.description.get("text")
        return None

# New 2025 Attribute Models

class PaymentOptions(BaseModel):
    """Payment methods accepted at place"""
    accepts_credit_cards: Optional[bool] = None
    accepts_debit_cards: Optional[bool] = None
    accepts_cash_only: Optional[bool] = None
    accepts_nfc: Optional[bool] = None
    accepts_crypto: Optional[bool] = None  # Future-proofing
    
    def get_accepted_methods(self) -> List[str]:
        """Get list of accepted payment methods"""
        methods = []
        if self.accepts_credit_cards:
            methods.append("Credit Cards")
        if self.accepts_debit_cards:
            methods.append("Debit Cards")
        if self.accepts_cash_only:
            methods.append("Cash Only")
        elif self.accepts_cash_only is False:
            methods.append("Cash")
        if self.accepts_nfc:
            methods.append("NFC/Mobile Payments")
        if self.accepts_crypto:
            methods.append("Cryptocurrency")
        return methods

class ParkingOptions(BaseModel):
    """Parking availability at place"""
    paid_parking_lot: Optional[bool] = None
    paid_street_parking: Optional[bool] = None
    valet_parking: Optional[bool] = None
    free_parking: Optional[bool] = None
    free_parking_lot: Optional[bool] = None
    free_street_parking: Optional[bool] = None
    
    def has_any_parking(self) -> bool:
        """Check if any parking is available"""
        return any([
            self.paid_parking_lot,
            self.paid_street_parking,
            self.valet_parking,
            self.free_parking,
            self.free_parking_lot,
            self.free_street_parking
        ])
    
    def get_parking_types(self) -> Dict[str, List[str]]:
        """Get categorized parking types"""
        types = {"free": [], "paid": []}
        
        if self.free_parking_lot:
            types["free"].append("Parking Lot")
        if self.free_street_parking:
            types["free"].append("Street Parking")
        if self.free_parking:
            types["free"].append("General Parking")
            
        if self.paid_parking_lot:
            types["paid"].append("Parking Lot")
        if self.paid_street_parking:
            types["paid"].append("Street Parking")
        if self.valet_parking:
            types["paid"].append("Valet")
            
        return types

class AccessibilityOptions(BaseModel):
    """Accessibility features at place"""
    wheelchair_accessible_parking: Optional[bool] = None
    wheelchair_accessible_entrance: Optional[bool] = None
    wheelchair_accessible_restroom: Optional[bool] = None
    wheelchair_accessible_seating: Optional[bool] = None
    
    def get_accessible_features(self) -> List[str]:
        """Get list of accessible features"""
        features = []
        if self.wheelchair_accessible_parking:
            features.append("Accessible Parking")
        if self.wheelchair_accessible_entrance:
            features.append("Accessible Entrance")
        if self.wheelchair_accessible_restroom:
            features.append("Accessible Restroom")
        if self.wheelchair_accessible_seating:
            features.append("Accessible Seating")
        return features
    
    def is_fully_accessible(self) -> bool:
        """Check if place is fully wheelchair accessible"""
        return all([
            self.wheelchair_accessible_parking,
            self.wheelchair_accessible_entrance,
            self.wheelchair_accessible_restroom,
            self.wheelchair_accessible_seating
        ])

class EVConnectorInfo(BaseModel):
    """Electric vehicle connector information"""
    type: EVConnectorType
    max_charge_rate_kw: float = Field(..., gt=0)
    connector_count: int = Field(..., gt=0)
    availability_last_update_time: Optional[datetime] = None
    availability: Optional[str] = None  # "AVAILABILITY_AVAILABLE", "AVAILABILITY_BUSY", etc.
    
    def is_fast_charging(self) -> bool:
        """Check if this is a fast charging connector (>50kW)"""
        return self.max_charge_rate_kw > 50
    
    def get_charge_time_hours(self, battery_capacity_kwh: float) -> float:
        """Estimate charge time for given battery capacity"""
        return battery_capacity_kwh / self.max_charge_rate_kw

class EVChargeOptions(BaseModel):
    """Electric vehicle charging options"""
    connector_aggregation: List[EVConnectorInfo] = Field(default_factory=list)
    
    def get_total_connectors(self) -> int:
        """Get total number of connectors"""
        return sum(conn.connector_count for conn in self.connector_aggregation)
    
    def get_connector_types(self) -> Set[EVConnectorType]:
        """Get set of available connector types"""
        return {conn.type for conn in self.connector_aggregation}
    
    def has_fast_charging(self) -> bool:
        """Check if any fast charging is available"""
        return any(conn.is_fast_charging() for conn in self.connector_aggregation)
    
    def get_max_charge_rate(self) -> float:
        """Get maximum available charge rate"""
        if not self.connector_aggregation:
            return 0.0
        return max(conn.max_charge_rate_kw for conn in self.connector_aggregation)

# Search Models

class SearchQuery(BaseModel):
    """Search query parameters"""
    query: str = Field(..., min_length=1)
    location: Optional[Location] = None
    radius: Optional[int] = Field(None, gt=0, le=50000)  # Max 50km
    place_types: Optional[List[str]] = None
    price_levels: Optional[List[PriceLevel]] = None
    rank_preference: RankPreference = RankPreference.RELEVANCE
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    
    @validator('query')
    def clean_query(cls, v):
        """Clean and validate search query"""
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Search query cannot be empty")
        return cleaned
    
    def get_cache_key(self) -> str:
        """Generate cache key for this search"""
        parts = [
            f"search:{self.query}",
            f"loc:{self.location.latitude},{self.location.longitude}" if self.location else "loc:none",
            f"r:{self.radius}" if self.radius else "r:none",
            f"types:{','.join(sorted(self.place_types))}" if self.place_types else "types:none",
            f"price:{','.join(sorted(p.value for p in self.price_levels))}" if self.price_levels else "price:none",
            f"rank:{self.rank_preference.value}"
        ]
        return ":".join(parts)

class SearchResult(BaseModel):
    """Search operation result"""
    places: List[Place]
    query: SearchQuery
    total_results: int
    execution_time_ms: Optional[float] = None
    next_page_token: Optional[str] = None
    
    @property
    def has_more_results(self) -> bool:
        """Check if more results are available"""
        return bool(self.next_page_token)
    
    def get_places_by_type(self, place_type: Union[str, PlaceType]) -> List[Place]:
        """Filter places by type"""
        return [p for p in self.places if p.has_type(place_type)]
    
    def get_top_rated(self, min_rating: float = 4.0) -> List[Place]:
        """Get places with high ratings"""
        return [p for p in self.places if p.rating and p.rating >= min_rating]
```

## Domain Exceptions

```python
# places_mcp/domain/exceptions.py
from typing import Optional, Dict, Any

class DomainException(Exception):
    """Base exception for all domain errors"""
    def __init__(self, message: str, code: Optional[str] = None, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.code = code
        self.details = details or {}

class ValidationError(DomainException):
    """Raised when domain validation fails"""
    pass

class PlaceNotFoundError(DomainException):
    """Raised when a requested place doesn't exist"""
    def __init__(self, place_id: str):
        super().__init__(
            f"Place with ID '{place_id}' not found",
            code="PLACE_NOT_FOUND",
            details={"place_id": place_id}
        )

class InvalidLocationError(ValidationError):
    """Raised when location coordinates are invalid"""
    def __init__(self, latitude: float, longitude: float):
        super().__init__(
            f"Invalid location coordinates: lat={latitude}, lng={longitude}",
            code="INVALID_LOCATION",
            details={"latitude": latitude, "longitude": longitude}
        )

class InvalidSearchQueryError(ValidationError):
    """Raised when search parameters are invalid"""
    pass

class QuotaExceededError(DomainException):
    """Raised when API quota is exceeded"""
    def __init__(self, quota_type: str, limit: int):
        super().__init__(
            f"Quota exceeded for {quota_type}. Limit: {limit}",
            code="QUOTA_EXCEEDED",
            details={"quota_type": quota_type, "limit": limit}
        )

class RateLimitError(DomainException):
    """Raised when rate limit is exceeded"""
    def __init__(self, retry_after: Optional[int] = None):
        super().__init__(
            "Rate limit exceeded",
            code="RATE_LIMITED",
            details={"retry_after": retry_after}
        )

class InvalidFieldMaskError(ValidationError):
    """Raised when requested fields are invalid"""
    def __init__(self, invalid_fields: List[str]):
        super().__init__(
            f"Invalid field mask: {', '.join(invalid_fields)}",
            code="INVALID_FIELD_MASK",
            details={"invalid_fields": invalid_fields}
        )

class PhotoNotFoundError(DomainException):
    """Raised when a photo resource doesn't exist"""
    def __init__(self, photo_reference: str):
        super().__init__(
            f"Photo with reference '{photo_reference}' not found",
            code="PHOTO_NOT_FOUND",
            details={"photo_reference": photo_reference}
        )

class BusinessRuleViolation(DomainException):
    """Raised when a business rule is violated"""
    pass
```

## Business Rules and Invariants

```python
# places_mcp/domain/rules.py
from typing import List, Set
from datetime import datetime, timedelta

from .models import Place, PlaceDetails, SearchQuery, PriceLevel
from .exceptions import BusinessRuleViolation, ValidationError

class SearchRules:
    """Business rules for search operations"""
    
    MAX_SEARCH_RADIUS = 50000  # 50km
    MIN_SEARCH_RADIUS = 100    # 100m
    MAX_RESULTS_PER_PAGE = 20
    MAX_QUERY_LENGTH = 200
    CACHE_TTL_SECONDS = 1800  # 30 minutes per Google ToS
    
    @staticmethod
    def validate_search_query(query: SearchQuery) -> None:
        """Validate search query against business rules"""
        if len(query.query) > SearchRules.MAX_QUERY_LENGTH:
            raise ValidationError(
                f"Search query too long. Maximum {SearchRules.MAX_QUERY_LENGTH} characters"
            )
        
        if query.radius:
            if query.radius > SearchRules.MAX_SEARCH_RADIUS:
                raise ValidationError(
                    f"Search radius too large. Maximum {SearchRules.MAX_SEARCH_RADIUS}m"
                )
            if query.radius < SearchRules.MIN_SEARCH_RADIUS:
                raise ValidationError(
                    f"Search radius too small. Minimum {SearchRules.MIN_SEARCH_RADIUS}m"
                )
        
        if query.location and query.radius is None:
            raise ValidationError(
                "Location bias requires a radius to be specified"
            )
    
    @staticmethod
    def can_cache_results(timestamp: datetime) -> bool:
        """Check if results can still be cached"""
        age = datetime.utcnow() - timestamp
        return age.total_seconds() < SearchRules.CACHE_TTL_SECONDS

class PlaceFieldRules:
    """Business rules for place field access"""
    
    # Fields available in different tiers
    BASIC_FIELDS = {
        "id", "displayName", "formattedAddress", "location",
        "types", "primaryType", "rating", "userRatingCount"
    }
    
    STANDARD_FIELDS = BASIC_FIELDS | {
        "websiteUri", "phoneNumber", "regularOpeningHours",
        "priceLevel", "businessStatus", "plusCode"
    }
    
    ADVANCED_FIELDS = STANDARD_FIELDS | {
        "currentOpeningHours", "secondaryOpeningHours",
        "reviews", "photos", "editorialSummary",
        "addressComponents"
    }
    
    PREMIUM_FIELDS = ADVANCED_FIELDS | {
        "generativeSummary", "paymentOptions", "parkingOptions",
        "accessibilityOptions", "evChargeOptions"
    }
    
    @staticmethod
    def validate_field_mask(fields: List[str], tier: str = "PREMIUM") -> None:
        """Validate requested fields against allowed tier"""
        field_set = set(fields)
        
        if tier == "BASIC":
            allowed = PlaceFieldRules.BASIC_FIELDS
        elif tier == "STANDARD":
            allowed = PlaceFieldRules.STANDARD_FIELDS
        elif tier == "ADVANCED":
            allowed = PlaceFieldRules.ADVANCED_FIELDS
        else:
            allowed = PlaceFieldRules.PREMIUM_FIELDS
        
        invalid_fields = field_set - allowed
        if invalid_fields:
            raise ValidationError(
                f"Fields not available in {tier} tier: {', '.join(invalid_fields)}"
            )
    
    @staticmethod
    def get_default_fields(include_premium: bool = False) -> List[str]:
        """Get recommended default fields"""
        fields = [
            "id", "displayName", "formattedAddress", "location",
            "types", "primaryType", "rating", "userRatingCount",
            "websiteUri", "phoneNumber", "regularOpeningHours",
            "priceLevel"
        ]
        
        if include_premium:
            fields.extend([
                "generativeSummary", "photos", "reviews"
            ])
        
        return fields

class RateLimitRules:
    """Business rules for rate limiting"""
    
    DEFAULT_REQUESTS_PER_MINUTE = 100
    DEFAULT_REQUESTS_PER_HOUR = 3000
    BURST_MULTIPLIER = 1.5
    
    @staticmethod
    def calculate_retry_after(
        requests_in_window: int,
        window_seconds: int,
        limit: int
    ) -> int:
        """Calculate seconds until rate limit resets"""
        if requests_in_window < limit:
            return 0
        
        # Simple calculation - could be more sophisticated
        return window_seconds

class PhotoRules:
    """Business rules for photo operations"""
    
    MAX_PHOTO_WIDTH = 4800
    MAX_PHOTO_HEIGHT = 4800
    DEFAULT_PHOTO_WIDTH = 400
    DEFAULT_PHOTO_HEIGHT = 400
    
    @staticmethod
    def validate_photo_dimensions(
        width: Optional[int],
        height: Optional[int]
    ) -> tuple[int, int]:
        """Validate and normalize photo dimensions"""
        if width and width > PhotoRules.MAX_PHOTO_WIDTH:
            raise ValidationError(
                f"Photo width too large. Maximum {PhotoRules.MAX_PHOTO_WIDTH}px"
            )
        
        if height and height > PhotoRules.MAX_PHOTO_HEIGHT:
            raise ValidationError(
                f"Photo height too large. Maximum {PhotoRules.MAX_PHOTO_HEIGHT}px"
            )
        
        # Use defaults if not specified
        final_width = width or PhotoRules.DEFAULT_PHOTO_WIDTH
        final_height = height or PhotoRules.DEFAULT_PHOTO_HEIGHT
        
        return final_width, final_height

class PricingRules:
    """Business rules for pricing calculations"""
    
    @staticmethod
    def estimate_budget_range(price_level: PriceLevel) -> tuple[int, int]:
        """Estimate budget range for a price level (in USD)"""
        ranges = {
            PriceLevel.FREE: (0, 0),
            PriceLevel.INEXPENSIVE: (1, 10),
            PriceLevel.MODERATE: (11, 30),
            PriceLevel.EXPENSIVE: (31, 60),
            PriceLevel.VERY_EXPENSIVE: (61, 200)
        }
        return ranges.get(price_level, (0, 0))
    
    @staticmethod
    def filter_by_budget(
        places: List[Place],
        max_budget: int
    ) -> List[Place]:
        """Filter places by maximum budget"""
        result = []
        for place in places:
            if not place.price_level:
                continue  # Include places without price info
            
            _, max_price = PricingRules.estimate_budget_range(place.price_level)
            if max_price <= max_budget:
                result.append(place)
        
        return result
```

## Example Usage Patterns

```python
# Example 1: Creating and validating domain models
from places_mcp.domain.models import Place, Location, SearchQuery
from places_mcp.domain.rules import SearchRules

# Create a place with validation
place = Place(
    id="ChIJj61dQgK6j4AR4GeTYWZsKWw",
    display_name="Googleplex",
    location=Location(latitude=37.4220656, longitude=-122.0862784),
    types=["corporate_campus", "point_of_interest"],
    rating=4.3,
    user_rating_count=17203
)

# Calculate distance between places
other_location = Location(latitude=37.3861, longitude=-122.0839)
distance_meters = place.location.distance_to(other_location)
print(f"Distance: {distance_meters:.0f} meters")

# Create and validate search query
query = SearchQuery(
    query="coffee shops near me",
    location=Location(latitude=37.4220656, longitude=-122.0862784),
    radius=5000,
    rank_preference=RankPreference.DISTANCE
)

# Validate against business rules
SearchRules.validate_search_query(query)

# Example 2: Working with place details and opening hours
from places_mcp.domain.models import (
    PlaceDetails, OpeningHours, OpeningHoursPeriod,
    DayOfWeek, TimeOfDay
)
from datetime import datetime

# Create place with opening hours
place_details = PlaceDetails(
    id="ChIJj61dQgK6j4AR4GeTYWZsKWw",
    display_name="Local Coffee Shop",
    regular_opening_hours=OpeningHours(
        periods=[
            OpeningHoursPeriod(
                open_day=DayOfWeek.MONDAY,
                open_time=TimeOfDay(hour=7, minute=0),
                close_day=DayOfWeek.MONDAY,
                close_time=TimeOfDay(hour=19, minute=0)
            ),
            # ... more periods
        ],
        weekday_descriptions=[
            "Monday: 7:00 AM – 7:00 PM",
            # ... more descriptions
        ]
    )
)

# Check if currently open
is_open = place_details.is_currently_open()
print(f"Currently open: {is_open}")

# Example 3: Working with new 2025 attributes
from places_mcp.domain.models import (
    PaymentOptions, ParkingOptions, EVChargeOptions,
    EVConnectorInfo, EVConnectorType
)

# Create place with EV charging
ev_place = PlaceDetails(
    id="ChIJj61dQgK6j4AR4GeTYWZsKWw",
    display_name="Shopping Center",
    ev_charge_options=EVChargeOptions(
        connector_aggregation=[
            EVConnectorInfo(
                type=EVConnectorType.CCS_1,
                max_charge_rate_kw=150,
                connector_count=4,
                availability="AVAILABILITY_AVAILABLE"
            ),
            EVConnectorInfo(
                type=EVConnectorType.J1772,
                max_charge_rate_kw=7.2,
                connector_count=8
            )
        ]
    )
)

# Check charging capabilities
has_fast = ev_place.ev_charge_options.has_fast_charging()
total_connectors = ev_place.ev_charge_options.get_total_connectors()
print(f"Fast charging: {has_fast}, Total connectors: {total_connectors}")

# Example 4: Error handling
from places_mcp.domain.exceptions import (
    PlaceNotFoundError, InvalidLocationError,
    ValidationError
)

try:
    # Invalid location
    bad_location = Location(latitude=91, longitude=181)
except ValidationError as e:
    print(f"Validation error: {e}")

try:
    # Invalid search radius
    bad_query = SearchQuery(
        query="restaurants",
        location=Location(latitude=37.4220656, longitude=-122.0862784),
        radius=100000  # Too large
    )
    SearchRules.validate_search_query(bad_query)
except ValidationError as e:
    print(f"Search validation error: {e}")

# Example 5: Working with search results
from places_mcp.domain.models import SearchResult

# Process search results
search_result = SearchResult(
    places=[place],  # List of places
    query=query,
    total_results=15,
    execution_time_ms=127.5,
    next_page_token="CAESBk..."
)

# Filter results
top_rated = search_result.get_top_rated(min_rating=4.5)
restaurants = search_result.get_places_by_type(PlaceType.RESTAURANT)

# Check for pagination
if search_result.has_more_results:
    print(f"More results available: {search_result.next_page_token}")
```

## Testing Strategies for Domain Models

```python
# tests/unit/domain/test_models.py
import pytest
from datetime import datetime, time
from decimal import Decimal

from places_mcp.domain.models import (
    Location, Place, PlaceDetails, OpeningHours,
    OpeningHoursPeriod, DayOfWeek, TimeOfDay,
    SearchQuery, PriceLevel, RankPreference
)
from places_mcp.domain.exceptions import ValidationError

class TestLocation:
    """Test Location value object"""
    
    def test_valid_location_creation(self):
        """Test creating valid location"""
        loc = Location(latitude=37.4220656, longitude=-122.0862784)
        assert loc.latitude == 37.4220656
        assert loc.longitude == -122.0862784
    
    def test_location_precision(self):
        """Test coordinate precision rounding"""
        loc = Location(latitude=37.42206561234567, longitude=-122.08627841234567)
        assert loc.latitude == 37.4220656  # Rounded to 7 decimals
        assert loc.longitude == -122.0862784
    
    def test_invalid_latitude(self):
        """Test invalid latitude validation"""
        with pytest.raises(ValidationError):
            Location(latitude=91, longitude=0)
        
        with pytest.raises(ValidationError):
            Location(latitude=-91, longitude=0)
    
    def test_invalid_longitude(self):
        """Test invalid longitude validation"""
        with pytest.raises(ValidationError):
            Location(latitude=0, longitude=181)
        
        with pytest.raises(ValidationError):
            Location(latitude=0, longitude=-181)
    
    def test_distance_calculation(self):
        """Test distance calculation between locations"""
        loc1 = Location(latitude=37.4220656, longitude=-122.0862784)
        loc2 = Location(latitude=37.4241059, longitude=-122.0851528)
        
        distance = loc1.distance_to(loc2)
        assert 200 < distance < 300  # Approximately 250 meters
    
    def test_location_immutability(self):
        """Test that Location is immutable"""
        loc = Location(latitude=37.4220656, longitude=-122.0862784)
        with pytest.raises(AttributeError):
            loc.latitude = 38.0

class TestPlace:
    """Test Place entity"""
    
    def test_valid_place_creation(self):
        """Test creating valid place"""
        place = Place(
            id="ChIJj61dQgK6j4AR4GeTYWZsKWw",
            display_name="Googleplex",
            types=["corporate_campus", "point_of_interest"],
            rating=4.3,
            user_rating_count=17203
        )
        assert place.id == "ChIJj61dQgK6j4AR4GeTYWZsKWw"
        assert place.display_name == "Googleplex"
        assert place.rating == 4.3
    
    def test_empty_place_id_validation(self):
        """Test that empty place ID is rejected"""
        with pytest.raises(ValidationError):
            Place(id="", display_name="Test")
        
        with pytest.raises(ValidationError):
            Place(id="   ", display_name="Test")
    
    def test_display_name_cleaning(self):
        """Test display name is cleaned"""
        place = Place(
            id="test123",
            display_name="  Test Place  "
        )
        assert place.display_name == "Test Place"
    
    def test_rating_validation(self):
        """Test rating bounds validation"""
        with pytest.raises(ValidationError):
            Place(id="test", display_name="Test", rating=0.5)
        
        with pytest.raises(ValidationError):
            Place(id="test", display_name="Test", rating=5.5)
    
    def test_has_type_method(self):
        """Test place type checking"""
        place = Place(
            id="test",
            display_name="Test",
            types=["restaurant", "bar", "food"],
            primary_type="restaurant"
        )
        
        assert place.has_type("restaurant")
        assert place.has_type(PlaceType.RESTAURANT)
        assert place.has_type("bar")
        assert not place.has_type("hotel")
    
    def test_primary_type_display(self):
        """Test human-readable type display"""
        place = Place(
            id="test",
            display_name="Test",
            primary_type="shopping_mall"
        )
        assert place.get_primary_type_display() == "Shopping Mall"

class TestOpeningHours:
    """Test opening hours functionality"""
    
    def test_opening_hours_creation(self):
        """Test creating opening hours"""
        hours = OpeningHours(
            periods=[
                OpeningHoursPeriod(
                    open_day=DayOfWeek.MONDAY,
                    open_time=TimeOfDay(hour=9, minute=0),
                    close_day=DayOfWeek.MONDAY,
                    close_time=TimeOfDay(hour=17, minute=0)
                )
            ]
        )
        assert len(hours.periods) == 1
    
    def test_is_open_at(self):
        """Test checking if place is open at specific time"""
        hours = OpeningHours(
            periods=[
                OpeningHoursPeriod(
                    open_day=DayOfWeek.MONDAY,
                    open_time=TimeOfDay(hour=9, minute=0),
                    close_day=DayOfWeek.MONDAY,
                    close_time=TimeOfDay(hour=17, minute=0)
                )
            ]
        )
        
        # Monday at 10 AM - should be open
        monday_10am = datetime(2025, 6, 30, 10, 0)  # A Monday
        assert hours.is_open_at(monday_10am)
        
        # Monday at 8 AM - should be closed
        monday_8am = datetime(2025, 6, 30, 8, 0)
        assert not hours.is_open_at(monday_8am)
        
        # Tuesday at 10 AM - should be closed
        tuesday_10am = datetime(2025, 7, 1, 10, 0)
        assert not hours.is_open_at(tuesday_10am)
    
    def test_overnight_hours(self):
        """Test places open overnight"""
        hours = OpeningHours(
            periods=[
                OpeningHoursPeriod(
                    open_day=DayOfWeek.FRIDAY,
                    open_time=TimeOfDay(hour=20, minute=0),
                    close_day=DayOfWeek.SATURDAY,
                    close_time=TimeOfDay(hour=2, minute=0)
                )
            ]
        )
        
        # Friday at 11 PM - should be open
        friday_11pm = datetime(2025, 7, 4, 23, 0)
        assert hours.is_open_at(friday_11pm)
        
        # Saturday at 1 AM - should be open
        saturday_1am = datetime(2025, 7, 5, 1, 0)
        assert hours.is_open_at(saturday_1am)

class TestSearchQuery:
    """Test search query validation"""
    
    def test_valid_search_query(self):
        """Test creating valid search query"""
        query = SearchQuery(
            query="coffee shops",
            location=Location(latitude=37.4220656, longitude=-122.0862784),
            radius=5000
        )
        assert query.query == "coffee shops"
        assert query.radius == 5000
    
    def test_query_cleaning(self):
        """Test query string is cleaned"""
        query = SearchQuery(query="  coffee shops  ")
        assert query.query == "coffee shops"
    
    def test_empty_query_validation(self):
        """Test empty query is rejected"""
        with pytest.raises(ValidationError):
            SearchQuery(query="")
        
        with pytest.raises(ValidationError):
            SearchQuery(query="   ")
    
    def test_cache_key_generation(self):
        """Test cache key generation"""
        query = SearchQuery(
            query="coffee",
            location=Location(latitude=37.4220656, longitude=-122.0862784),
            radius=5000,
            place_types=["cafe", "restaurant"],
            price_levels=[PriceLevel.MODERATE, PriceLevel.INEXPENSIVE]
        )
        
        cache_key = query.get_cache_key()
        assert "search:coffee" in cache_key
        assert "loc:37.4220656,-122.0862784" in cache_key
        assert "r:5000" in cache_key
        assert "types:cafe,restaurant" in cache_key

class TestBusinessRules:
    """Test domain business rules"""
    
    def test_search_radius_validation(self):
        """Test search radius bounds"""
        from places_mcp.domain.rules import SearchRules
        
        # Valid radius
        query = SearchQuery(
            query="test",
            location=Location(latitude=0, longitude=0),
            radius=5000
        )
        SearchRules.validate_search_query(query)  # Should not raise
        
        # Too large radius
        query_large = SearchQuery(
            query="test",
            location=Location(latitude=0, longitude=0),
            radius=60000
        )
        with pytest.raises(ValidationError):
            SearchRules.validate_search_query(query_large)
        
        # Too small radius
        query_small = SearchQuery(
            query="test",
            location=Location(latitude=0, longitude=0),
            radius=50
        )
        with pytest.raises(ValidationError):
            SearchRules.validate_search_query(query_small)
    
    def test_field_mask_validation(self):
        """Test field mask tier validation"""
        from places_mcp.domain.rules import PlaceFieldRules
        
        # Valid basic fields
        PlaceFieldRules.validate_field_mask(
            ["id", "displayName", "rating"],
            tier="BASIC"
        )
        
        # Invalid field for basic tier
        with pytest.raises(ValidationError):
            PlaceFieldRules.validate_field_mask(
                ["id", "displayName", "generativeSummary"],
                tier="BASIC"
            )
        
        # Valid premium fields
        PlaceFieldRules.validate_field_mask(
            ["id", "displayName", "generativeSummary", "evChargeOptions"],
            tier="PREMIUM"
        )

# Integration test example
class TestDomainIntegration:
    """Integration tests for domain layer"""
    
    def test_complete_place_workflow(self):
        """Test complete workflow with place details"""
        # Create a detailed place
        place = PlaceDetails(
            id="test123",
            display_name="Electric Vehicle Charging Station",
            location=Location(latitude=37.4220656, longitude=-122.0862784),
            types=["electric_vehicle_charging_station", "point_of_interest"],
            rating=4.5,
            user_rating_count=150,
            ev_charge_options=EVChargeOptions(
                connector_aggregation=[
                    EVConnectorInfo(
                        type=EVConnectorType.CCS_1,
                        max_charge_rate_kw=150,
                        connector_count=4
                    )
                ]
            ),
            parking_options=ParkingOptions(
                free_parking_lot=True,
                wheelchair_accessible_parking=True
            )
        )
        
        # Test various domain behaviors
        assert place.has_type("electric_vehicle_charging_station")
        assert place.ev_charge_options.has_fast_charging()
        assert place.parking_options.has_any_parking()
        
        # Test calculations
        charge_time = place.ev_charge_options.connector_aggregation[0].get_charge_time_hours(75)
        assert charge_time == 0.5  # 75kWh / 150kW = 0.5 hours
```

## Summary

The Domain Layer provides:

1. **Pure Business Logic**: All core business rules and validations
2. **Rich Domain Models**: Entities with behavior, not just data
3. **Type Safety**: Comprehensive validation and type hints
4. **Zero Dependencies**: Only Python stdlib and Pydantic
5. **Clear Contracts**: Well-defined protocols for infrastructure
6. **Comprehensive Testing**: Unit and integration test strategies

This design ensures the domain layer remains the stable core of the application, independent of infrastructure concerns and framework changes.