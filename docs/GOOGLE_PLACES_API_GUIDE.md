# Google Places API (New) Comprehensive Guide - 2025

## Overview

Google Places API (New) is the next-generation version of Google's place information service. As of 2025, the legacy Places API can no longer be enabled for new projects. The new API provides enhanced features including AI-powered summaries, detailed business attributes, and improved search capabilities.

## Key Changes in 2025

1. **Legacy API Deprecation**: Places API (Legacy) is no longer available for new projects
2. **EEA Terms**: New terms apply for European Economic Area users starting July 8, 2025
3. **Enhanced AI Features**: New AI-generated place and review summaries
4. **Expanded Attributes**: Payment options, parking, EV charging, accessibility

## API Endpoints

### 1. Place Details (New)
- **Endpoint**: `https://places.googleapis.com/v1/places/{place_id}`
- **Method**: GET
- **Purpose**: Retrieve comprehensive information about a specific place
- **Key Features**:
  - More cost-effective than search when you have Place ID
  - Customizable field masks for optimized responses
  - AI-generated summaries available

```http
GET https://places.googleapis.com/v1/places/ChIJj61dQgK6j4AR4GeTYWZsKWw
X-Goog-Api-Key: YOUR_API_KEY
X-Goog-FieldMask: id,displayName,formattedAddress,rating,userRatingCount,websiteUri,regularOpeningHours,priceLevel,photos,reviews,generativeSummary
```

### 2. Text Search (New)
- **Endpoint**: `https://places.googleapis.com/v1/places:searchText`
- **Method**: POST
- **Purpose**: Search places using natural language queries
- **Headers**: `Content-Type: application/json`, `X-Goog-Api-Key: YOUR_API_KEY`

```json
{
  "textQuery": "Spicy Vegetarian Food in Sydney, Australia",
  "maxResultCount": 10,
  "locationBias": {
    "circle": {
      "center": {
        "latitude": -33.8670522,
        "longitude": 151.1957362
      },
      "radius": 5000.0
    }
  },
  "rankPreference": "RELEVANCE",
  "priceLevels": ["PRICE_LEVEL_MODERATE", "PRICE_LEVEL_EXPENSIVE"]
}
```

### 3. Nearby Search (New)
- **Endpoint**: `https://places.googleapis.com/v1/places:searchNearby`
- **Method**: POST
- **Purpose**: Find places within a specified area
- **Headers**: `Content-Type: application/json`, `X-Goog-Api-Key: YOUR_API_KEY`

```json
{
  "locationRestriction": {
    "circle": {
      "center": {
        "latitude": 37.4220656,
        "longitude": -122.0862784
      },
      "radius": 1000.0
    }
  },
  "includedTypes": ["restaurant", "cafe"],
  "maxResultCount": 20,
  "rankPreference": "DISTANCE"
}
```

### 4. Autocomplete (New)
- **Endpoint**: `https://places.googleapis.com/v1/places:autocomplete`
- **Method**: POST
- **Purpose**: Provide place predictions as user types
- **Features**: Session tokens for grouping requests

```json
{
  "input": "pizza in new",
  "sessionToken": "12345",
  "locationBias": {
    "circle": {
      "center": {
        "latitude": 40.7128,
        "longitude": -74.0060
      },
      "radius": 50000.0
    }
  }
}
```

### 5. Place Photos (New)
- **Endpoint**: `https://places.googleapis.com/v1/{photo_name}/media`
- **Method**: GET
- **Purpose**: Retrieve place photos with customizable dimensions

```http
GET https://places.googleapis.com/v1/places/ChIJj61dQgK6j4AR4GeTYWZsKWw/photos/AXCi2Q4.../media?maxHeightPx=400&maxWidthPx=400&key=YOUR_API_KEY

# Note: The photo name in the URL should be the complete photo resource name returned from a place details request
```

## Authentication

### API Key
- Required for all requests
- Must be restricted by IP or referrer for security
- Format: `X-Goog-Api-Key: YOUR_API_KEY` header or `?key=YOUR_API_KEY` parameter

### OAuth 2.0
- Available for Places API (New)
- Provides user-context requests
- Better for applications with user accounts
- Required scope: `https://www.googleapis.com/auth/maps-platform.places`

## Field Masks

Optimize costs by requesting only needed fields:

```
# Basic Information
displayName,formattedAddress,location

# Detailed Information
rating,userRatingCount,priceLevel,types,websiteUri,internationalPhoneNumber

# Operating Hours
regularOpeningHours,currentOpeningHours,secondaryOpeningHours

# Reviews and Photos
reviews,photos,generativeSummary

# New Attributes (2025) - Enterprise + Atmosphere SKU
paymentOptions,parkingOptions,accessibilityOptions,evChargeOptions
```

## New Fields in 2025

### Payment Options
```json
"paymentOptions": {
  "acceptsCreditCards": true,
  "acceptsDebitCards": true,
  "acceptsCashOnly": false,
  "acceptsNfc": true
}
```

### Parking Options
```json
"parkingOptions": {
  "paidParkingLot": true,
  "paidStreetParking": true,
  "valetParking": false,
  "freeParking": false,
  "freeParkingLot": false,
  "freeStreetParking": false
}
```

### EV Charging
```json
"evChargeOptions": {
  "connectorAggregation": [
    {
      "type": "EV_CONNECTOR_TYPE_J1772",
      "maxChargeRateKw": 7.2,
      "connectorCount": 2,
      "availabilityLastUpdateTime": "2025-06-29T10:00:00Z",
      "availability": "AVAILABILITY_AVAILABLE"
    }
  ]
}
```

### Accessibility
```json
"accessibilityOptions": {
  "wheelchairAccessibleParking": true,
  "wheelchairAccessibleEntrance": true,
  "wheelchairAccessibleRestroom": true,
  "wheelchairAccessibleSeating": true
}
```

## AI-Generated Content

### Generative Summary
New AI-powered summaries provide concise place descriptions:

```json
"generativeSummary": {
  "overview": {
    "text": "Popular Italian restaurant known for authentic wood-fired pizzas and homemade pasta. Family-friendly atmosphere with outdoor seating.",
    "languageCode": "en"
  },
  "description": {
    "text": "This cozy neighborhood gem serves traditional Italian cuisine...",
    "languageCode": "en"
  }
}
```

**Attribution Required**: Must display "Summary provided by AI" when using generative content.

## Rate Limits and Quotas

1. **Queries Per Second (QPS)**:
   - Default: 100 QPS
   - Can be increased via quota request

2. **Daily Limits**:
   - Varies by billing plan
   - Monitor usage in Google Cloud Console

3. **Session Tokens**:
   - Group autocomplete requests
   - Session expires when place is selected or abandoned
   - Pricing: First 12 requests charged individually, 13+ requests free within same session
   - Reduces billing for autocomplete sessions

## Best Practices

### 1. Cost Optimization
- Use Place IDs when available (cheaper than search)
- Implement field masks to request only needed data
- Cache results within terms of service limits
- Use session tokens for autocomplete

### 2. Performance
- Implement exponential backoff for retries
- Use location biasing for better results
- Batch requests when possible
- Monitor latency metrics

### 3. Error Handling

| Error Code | Description | Action |
|------------|-------------|--------|
| 400 | Invalid request | Check parameters and request format |
| 403 | Authentication/quota issues | Verify API key and quotas |
| 404 | Place not found | Verify place ID is valid |
| 429 | Rate limit exceeded | Implement backoff and retry |
| 500 | Server error | Retry with exponential backoff |

### 4. Search Optimization
- Use specific queries for better results
- Apply appropriate location restrictions
- Filter by place types when applicable
- Consider rank preference (RELEVANCE vs DISTANCE)

## Code Examples

### Python Implementation
```python
import requests
from typing import Optional, Dict, List

class PlacesAPIClient:
    BASE_URL = "https://places.googleapis.com/v1"
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.headers = {
            "X-Goog-Api-Key": api_key,
            "Content-Type": "application/json"
        }
    
    def search_text(self, query: str, location: Optional[Dict] = None) -> List[Dict]:
        """Search places by text query"""
        data = {
            "textQuery": query,
            "maxResultCount": 20
        }
        
        if location:
            data["locationBias"] = {
                "circle": {
                    "center": location,
                    "radius": 5000.0
                }
            }
        
        response = requests.post(
            f"{self.BASE_URL}/places:searchText",
            headers=self.headers,
            json=data
        )
        response.raise_for_status()
        return response.json().get("places", [])
    
    def get_place_details(self, place_id: str, fields: List[str]) -> Dict:
        """Get detailed place information"""
        field_mask = ",".join(fields)
        headers = {**self.headers, "X-Goog-FieldMask": field_mask}
        
        response = requests.get(
            f"{self.BASE_URL}/places/{place_id}",
            headers=headers
        )
        response.raise_for_status()
        return response.json()
```

## Migration from Legacy API

### Endpoint Mapping
| Legacy Endpoint | New Endpoint |
|----------------|--------------|
| `/place/details/json` | `/v1/places/{place_id}` |
| `/place/nearbysearch/json` | `/v1/places:searchNearby` |
| `/place/textsearch/json` | `/v1/places:searchText` |
| `/place/autocomplete/json` | `/v1/places:autocomplete` |

### Key Differences
1. **Request Format**: JSON POST instead of GET with query parameters
2. **Field Selection**: Explicit field masks required
3. **Response Format**: Cleaner JSON structure
4. **New Features**: AI summaries, enhanced attributes
5. **Authentication**: Header-based API key preferred

## Compliance and Legal

1. **Attribution Requirements**:
   - Display "Powered by Google" logo
   - Show place attributions
   - Mark AI-generated content

2. **Data Usage**:
   - No scraping or mass downloading
   - Respect cache time limits (30 days max)
   - No creating competing services

3. **Privacy**:
   - Don't store user location without consent
   - Follow GDPR/privacy regulations
   - Implement proper data retention policies

## Monitoring and Debugging

### Google Cloud Console
- Monitor API usage and quotas
- View error rates and latency
- Set up billing alerts
- Access detailed logs

### Logging Best Practices
```python
import logging

logger = logging.getLogger("places_api")

# Log all API requests
logger.info(f"Places API request: {endpoint}", extra={
    "place_id": place_id,
    "fields": fields,
    "response_time": response_time
})

# Log errors with context
logger.error(f"Places API error: {error_code}", extra={
    "request_id": request_id,
    "error_message": error_message
})
```

## Resources

- Official Documentation: https://developers.google.com/maps/documentation/places/web-service
- API Console: https://console.cloud.google.com/apis/library/places.googleapis.com
- Pricing: https://developers.google.com/maps/billing/gmp-billing
- Support: https://developers.google.com/maps/support