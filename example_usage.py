#!/usr/bin/env python3
"""
Example usage of the Google Places MCP Server

This demonstrates how an LLM would interact with the Places API through MCP.
"""

import asyncio
from fastmcp import FastMCP

# Note: In actual usage, the LLM would connect to the running MCP server
# This is just to show what tools are available

async def main():
    # Example queries that could be made through the MCP tools:
    
    print("Example MCP tool calls:")
    print("\n1. Search for coffee shops near a location:")
    print("""
    Tool: nearbySearch
    Parameters: {
        "location": "37.7749,-122.4194",  # San Francisco coordinates
        "radius": 1000,
        "type": "cafe"
    }
    """)
    
    print("\n2. Get details about a specific place:")
    print("""
    Tool: placeDetails
    Parameters: {
        "place_id": "ChIJN1t_tDeuEmsRUsoyG83frY4",
        "fields": "name,rating,formatted_address,photos,reviews"
    }
    """)
    
    print("\n3. Search for restaurants by text:")
    print("""
    Tool: textSearch
    Parameters: {
        "query": "best pizza in New York",
        "type": "restaurant"
    }
    """)
    
    print("\n4. Get autocomplete suggestions:")
    print("""
    Tool: autocomplete
    Parameters: {
        "input": "Times Sq",
        "types": "establishment"
    }
    """)

if __name__ == "__main__":
    asyncio.run(main())