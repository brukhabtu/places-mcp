# Google Places MCP Server

A simple MCP (Model Context Protocol) server that provides access to the Google Places API using FastMCP's OpenAPI integration.

## Overview

This implementation leverages FastMCP 2.0's `from_openapi` feature to automatically generate an MCP server from Google's official OpenAPI specification. With just 30 lines of code, it exposes all Google Places API endpoints as MCP tools that LLMs can use.

## Features

The MCP server automatically provides tools for all Google Places API endpoints:

- **placeDetails** - Get detailed information about a specific place
- **textSearch** - Search for places using a text query
- **nearbySearch** - Search for places near a specific location
- **findPlaceFromText** - Find a specific place from a text input
- **autocomplete** - Get place predictions as users type
- **queryAutocomplete** - Get query predictions for place searches
- **placePhoto** - Retrieve photos for places

## Prerequisites

- Python 3.13+
- Google Maps API key with Places API enabled
- FastMCP 2.0+

## Installation

1. Clone the repository with the Google OpenAPI specification:
```bash
git clone https://github.com/googlemaps/openapi-specification.git
```

2. Install dependencies:
```bash
pip install fastmcp httpx
```

3. Set your Google API key:
```bash
export GOOGLE_API_KEY="your-api-key-here"
```

## Usage

1. Run the MCP server:
```bash
python places_mcp.py
```

2. The server will start and display available tools:
```
Starting Google Places MCP Server...
Available tools: ['placeDetails', 'textSearch', 'nearbySearch', 'findPlaceFromText', 'autocomplete', 'queryAutocomplete', 'placePhoto']
```

3. Connect your LLM client to the MCP server to access Google Places functionality.

## How It Works

FastMCP's `from_openapi` method:
1. Reads the Google Maps OpenAPI specification
2. Automatically generates MCP tools for each API endpoint
3. Handles parameter validation and request formatting
4. Manages authentication via the HTTP client

The implementation is minimal because FastMCP handles all the complexity of:
- Parsing OpenAPI schemas
- Creating tool definitions
- Validating parameters
- Making HTTP requests
- Handling responses

## Example Tool Usage

When connected to an LLM, you can make requests like:

```json
{
  "tool": "nearbySearch",
  "parameters": {
    "location": "37.7749,-122.4194",
    "radius": 1000,
    "type": "restaurant"
  }
}
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│     LLM     │────▶│  MCP Server  │────▶│ Google Places   │
│   Client    │◀────│  (FastMCP)   │◀────│      API        │
└─────────────┘     └──────────────┘     └─────────────────┘
```

## License

This project uses the Google Maps OpenAPI specification which is licensed under Apache 2.0.