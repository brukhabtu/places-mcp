#!/usr/bin/env python3
"""
Google Places MCP Server - Simple implementation using FastMCP's OpenAPI integration
"""

import os
import json
from pathlib import Path
import httpx
from fastmcp import FastMCP

# Load the Google Places OpenAPI specification
spec_path = Path("openapi-specification/dist/google-maps-platform-openapi3.json")

# Read the OpenAPI spec
with open(spec_path) as f:
    openapi_spec = json.load(f)

# Create HTTP client for Google Maps API
# The API key will be added as a query parameter to all requests
client = httpx.AsyncClient(
    base_url="https://maps.googleapis.com",
    params={"key": os.environ.get("GOOGLE_API_KEY", "")},
    timeout=30.0
)

# Create MCP server from OpenAPI spec
# This automatically creates tools for all Places API endpoints!
mcp = FastMCP.from_openapi(
    openapi_spec=openapi_spec,
    client=client,
    name="Google Places MCP Server"
)

# The OpenAPI spec includes these endpoints which become MCP tools:
# - placeDetails: Get detailed information about a place
# - textSearch: Search for places by text query  
# - nearbySearch: Search for places near a location
# - findPlaceFromText: Find a specific place from text
# - autocomplete: Get place predictions as user types
# - queryAutocomplete: Get query predictions
# - placePhoto: Get photos for places

if __name__ == "__main__":
    print("Starting Google Places MCP Server...")
    print(f"Available tools: {[tool.name for tool in mcp.list_tools()]}")
    mcp.run()