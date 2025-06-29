# FastMCP 2.0 Comprehensive Guide

## Overview

FastMCP 2.0 is a Python framework for building Model Context Protocol (MCP) servers and clients. It provides a "fast, simple, and Pythonic" way to expose data and functionality to Large Language Models (LLMs).

## Core Concepts

### 1. Model Context Protocol (MCP)
- A standardized protocol for LLM-to-application communication
- Three main components:
  - **Resources**: Read-only data endpoints (like GET)
  - **Tools**: Function calls that can perform actions (like POST)
  - **Prompts**: Reusable interaction templates

### 2. Key Features in 2.0
- Complete ecosystem beyond server building
- Client libraries for consuming MCP servers
- Authentication systems (Bearer tokens, JWT)
- Deployment tools and patterns
- AI platform integrations
- Testing frameworks
- Production infrastructure

## Installation

```bash
# Using pip
pip install fastmcp==2.9.2

# Using uv (recommended)
uv add fastmcp==2.9.2

# Developer installation
git clone https://github.com/jlowin/fastmcp
cd fastmcp
uv pip install -e .
```

**Note**: FastMCP 2.9.2 was released in June 2024. This guide includes features up to that version.

```bash
```

## Basic Server Implementation

### Simple Server

```python
from fastmcp import FastMCP

# Create server instance
mcp = FastMCP("My Server")

# Define a tool
@mcp.tool
def add(a: int, b: int) -> int:
    """Add two numbers"""
    return a + b

# Define a resource
@mcp.resource("data://config")
def get_config() -> dict:
    """Get server configuration"""
    return {"version": "1.0", "debug": False}

# Run server
if __name__ == "__main__":
    mcp.run()  # Default: stdio transport
```

### Advanced Server with Context

```python
from fastmcp import FastMCP, Context
import asyncio

mcp = FastMCP("Advanced Server")

@mcp.tool
async def process_file(file_path: str, ctx: Context) -> dict:
    """Process a file with progress reporting"""
    # Log information
    await ctx.info(f"Processing {file_path}")
    
    # Report progress
    await ctx.report_progress(0, 100, "Starting")
    
    # Simulate work
    await asyncio.sleep(1)
    await ctx.report_progress(50, 100, "Halfway done")
    
    # Ask LLM for help
    result = await ctx.sample(f"Analyze this file path: {file_path}")
    
    await ctx.report_progress(100, 100, "Complete")
    return {"analysis": result.text}
```

## Authentication

### Bearer Token Authentication

```python
# Server with public key validation
mcp.run(
    transport="http",
    port=8000,
    auth_public_key="<YOUR_PUBLIC_KEY_PEM_HERE>"  # Replace with actual RSA public key
)

# Or with JWKS URI
mcp.run(
    transport="http",
    port=8000,
    auth_jwks_uri="https://auth.example.com/.well-known/jwks.json"
)
```

## Type Conversion

### Automatic Type Handling with Pydantic

```python
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class TaskRequest(BaseModel):
    title: str
    description: Optional[str] = None
    due_date: Optional[datetime] = None
    tags: List[str] = Field(default_factory=list)

@mcp.tool
def create_task(task: TaskRequest) -> dict:
    """Create task with automatic type conversion"""
    # FastMCP handles JSON -> Pydantic conversion
    return {
        "id": "task-123",
        "title": task.title,
        "due": task.due_date.isoformat() if task.due_date else None
    }
```

## Client Usage

```python
from fastmcp import Client
import asyncio

async def main():
    # Connect to various server types
    client = Client("https://api.example.com/mcp")  # HTTP server
    # Or connect via stdio transport
    # client = Client(["python", "my_server.py"], transport="stdio")
    
    async with client:
        # List available operations
        tools = await client.list_tools()
        resources = await client.list_resources()
        
        # Call a tool
        result = await client.call_tool("add", {"a": 5, "b": 3})
        
        # Read a resource
        config = await client.read_resource("data://config")

asyncio.run(main())
```

## Middleware

```python
from starlette.middleware.base import BaseHTTPMiddleware

class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # Rate limiting logic here
        return await call_next(request)

# Apply middleware
app = mcp.get_app()
app.add_middleware(RateLimitMiddleware)
```

## Server Composition

```python
# Modular servers
weather_mcp = FastMCP("Weather")
news_mcp = FastMCP("News")

# Composite server
main_mcp = FastMCP("Main")
main_mcp.mount("weather", weather_mcp)  # Tools: weather/get_forecast
main_mcp.mount("news", news_mcp)        # Tools: news/get_headlines
```

## Tool Transformation

```python
from fastmcp import tool_transformation

# Rename and modify existing tools
@tool_transformation
def enhanced_tool(original_func):
    """Wrap tool with validation"""
    def wrapper(*args, **kwargs):
        # Add validation/logging
        result = original_func(*args, **kwargs)
        # Post-process result
        return result
    return wrapper
```

## Deployment

### Docker
```dockerfile
FROM python:3.11-slim
WORKDIR /app

# Install uv properly
RUN apt-get update && apt-get install -y curl
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Copy and install dependencies
COPY pyproject.toml .
RUN uv pip install -e .

# Copy application code
COPY . .

CMD ["uv", "run", "python", "-m", "server", "--transport", "http"]
```

### Claude Desktop Integration
```json
{
    "mcpServers": {
        "my-server": {
            "command": "uv",
            "args": ["run", "my_server.py"],
            "env": {"API_KEY": "secret"}
        }
    }
}
```

## Best Practices

1. **Use Type Hints**: Enable automatic validation and conversion
2. **Implement Context**: Use for logging, progress, and LLM interaction
3. **Handle Errors**: Return clear error messages
4. **Document Tools**: Provide clear descriptions for LLM understanding
5. **Use Async**: For I/O operations and better performance
6. **Test Thoroughly**: Use FastMCP's testing utilities
7. **Monitor Performance**: Implement logging and metrics
8. **Version Your API**: Use semantic versioning for tools/resources

## Common Patterns

### Resource with Parameters
```python
@mcp.resource("user://{user_id}")
async def get_user(user_id: str) -> dict:
    """Get user by ID"""
    return {"id": user_id, "name": "John Doe"}
```

### Tool with File Upload
```python
@mcp.tool
async def analyze_image(image_data: str) -> dict:
    """Analyze base64-encoded image"""
    # Decode and process image
    return {"objects_detected": 5}
```

### Streaming Responses
```python
@mcp.tool
async def stream_data(ctx: Context):
    """Stream data with progress"""
    for i in range(10):
        await ctx.info(f"Processing chunk {i}")
        await asyncio.sleep(0.1)
    return "Complete"
```

## Troubleshooting

1. **Import Errors**: Ensure fastmcp is installed in your environment
2. **Transport Issues**: Check firewall/port settings for HTTP transport
3. **Authentication Failures**: Verify public key/JWKS configuration
4. **Type Conversion Errors**: Ensure Pydantic models match expected schema
5. **Performance Issues**: Use async operations and connection pooling

## Resources

- Official Docs: https://gofastmcp.com
- GitHub: https://github.com/jlowin/fastmcp
- PyPI: https://pypi.org/project/fastmcp/
- Discord Community: Available through GitHub