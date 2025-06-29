# PLCS-002: Domain Models Tasks

## Story
As a developer, I want core domain models so that I can represent place data consistently

## Task Breakdown

### Setup Phase
- [ ] Create places_mcp/domain package
- [ ] Create __init__.py files
- [ ] Plan model relationships

### Location Model (TDD)
- [ ] Write tests/unit/test_location.py
- [ ] Test latitude validation (-90 to 90)
- [ ] Test longitude validation (-180 to 180)
- [ ] Test frozen model (immutable)
- [ ] Test distance_to calculation
- [ ] Implement Location model
- [ ] Implement distance_to method using haversine

### Place Model (TDD)
- [ ] Write tests/unit/test_place.py
- [ ] Test required fields (id, display_name)
- [ ] Test optional fields with defaults
- [ ] Test rating validation (0-5)
- [ ] Test types as list of strings
- [ ] Implement Place model
- [ ] Add helper methods

### SearchQuery Model (TDD)
- [ ] Write tests/unit/test_search_query.py
- [ ] Test query text validation (not empty)
- [ ] Test location bias (optional)
- [ ] Test radius validation (positive)
- [ ] Test max_results validation (1-50)
- [ ] Implement SearchQuery model
- [ ] Add query sanitization

### Domain Exceptions
- [ ] Create places_mcp/domain/exceptions.py
- [ ] Implement DomainException base
- [ ] Add ValidationException
- [ ] Add NotFoundException  
- [ ] Add QuotaExceededException
- [ ] Write tests for each exception

### Value Objects
- [ ] Implement PlaceType enum
- [ ] Implement PriceLevel enum
- [ ] Test enum validations

### Integration Tests
- [ ] Test model serialization
- [ ] Test model deserialization
- [ ] Test model relationships
- [ ] Test error scenarios

### Documentation
- [ ] Add comprehensive docstrings
- [ ] Document validation rules
- [ ] Create usage examples

### Finalization
- [ ] Ensure >90% test coverage
- [ ] Run type checking
- [ ] Fix any linting issues
- [ ] Create PR that closes #2

## Code Templates

### Location Model Tests
```python
# tests/unit/test_location.py
import pytest
from places_mcp.domain.models import Location
import math

def test_location_validates_latitude():
    with pytest.raises(ValidationError):
        Location(latitude=91, longitude=0)
    
    with pytest.raises(ValidationError):
        Location(latitude=-91, longitude=0)

def test_location_is_immutable():
    loc = Location(latitude=40.7128, longitude=-74.0060)
    with pytest.raises(AttributeError):
        loc.latitude = 50

def test_distance_to_calculation():
    nyc = Location(latitude=40.7128, longitude=-74.0060)
    la = Location(latitude=34.0522, longitude=-118.2437)
    
    distance = nyc.distance_to(la)
    assert 3900 < distance < 4000  # km
```

### Place Model Tests
```python
# tests/unit/test_place.py
def test_place_requires_minimal_fields():
    place = Place(
        id="ChIJ123",
        display_name="Test Place"
    )
    assert place.id == "ChIJ123"
    assert place.rating is None
    assert place.types == []

def test_place_validates_rating():
    with pytest.raises(ValidationError):
        Place(id="1", display_name="Test", rating=6)
```

### Model Implementations
```python
# places_mcp/domain/models.py
from pydantic import BaseModel, Field, validator
from typing import Optional, List
import math

class Location(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    
    class Config:
        frozen = True
    
    def distance_to(self, other: 'Location') -> float:
        """Calculate distance in kilometers using Haversine formula"""
        R = 6371  # Earth's radius in km
        
        lat1, lon1 = math.radians(self.latitude), math.radians(self.longitude)
        lat2, lon2 = math.radians(other.latitude), math.radians(other.longitude)
        
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a))
        
        return R * c

class Place(BaseModel):
    id: str
    display_name: str
    formatted_address: Optional[str] = None
    location: Optional[Location] = None
    rating: Optional[float] = Field(None, ge=0, le=5)
    user_rating_count: Optional[int] = Field(None, ge=0)
    types: List[str] = Field(default_factory=list)
    
    @validator('display_name')
    def name_not_empty(cls, v):
        if not v.strip():
            raise ValueError('Display name cannot be empty')
        return v
```

## Success Criteria
- [ ] All models properly validated
- [ ] Distance calculation accurate
- [ ] Models are immutable where appropriate
- [ ] >90% test coverage
- [ ] All tests pass
- [ ] PR closes issue #2