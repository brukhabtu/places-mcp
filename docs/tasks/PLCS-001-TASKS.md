# PLCS-001: Configuration Layer Tasks

## Story
As a developer, I want to configure the server with environment variables so that I can easily deploy to different environments

## Task Breakdown

### Setup Phase
- [ ] Initialize project with `uv init places-mcp`
- [ ] Create proper package structure
- [ ] Set up pyproject.toml with dependencies
- [ ] Configure ruff and mypy
- [ ] Create places_mcp package with __init__.py

### Test Development (TDD)
- [ ] Create tests/unit/test_config.py
- [ ] Write test for Settings model initialization
- [ ] Write test for API key validation
- [ ] Write test for transport validation
- [ ] Write test for .env file loading
- [ ] Write test for missing required fields
- [ ] Write test for invalid values

### Implementation
- [ ] Create places_mcp/config/__init__.py
- [ ] Create places_mcp/config/settings.py
- [ ] Implement Settings class with pydantic
- [ ] Add GOOGLE_API_KEY field with SecretStr
- [ ] Add MCP_TRANSPORT field with enum validation
- [ ] Add CACHE_TTL with default value
- [ ] Add LOG_LEVEL with default "INFO"
- [ ] Configure .env file loading

### Validation
- [ ] Implement API key format validation
- [ ] Add custom validator for key prefix
- [ ] Validate transport options (stdio, http)
- [ ] Add helpful error messages

### Documentation
- [ ] Create .env.example with all variables
- [ ] Add docstrings to Settings class
- [ ] Document each configuration option
- [ ] Create config/README.md

### Integration
- [ ] Test .env loading in different scenarios
- [ ] Test environment variable override
- [ ] Test missing .env file handling
- [ ] Verify all tests pass

### Finalization
- [ ] Run ruff format
- [ ] Run mypy type check
- [ ] Ensure >90% test coverage
- [ ] Create feature branch
- [ ] Commit with conventional message
- [ ] Create PR that closes #1

## Code Templates

### Test Template
```python
# tests/unit/test_config.py
import pytest
from pydantic import ValidationError
from places_mcp.config import Settings

def test_settings_loads_from_env(monkeypatch):
    monkeypatch.setenv("GOOGLE_API_KEY", "test-key-123")
    monkeypatch.setenv("MCP_TRANSPORT", "stdio")
    
    settings = Settings()
    assert settings.google_api_key.get_secret_value() == "test-key-123"
    assert settings.mcp_transport == "stdio"

def test_settings_validates_api_key():
    with pytest.raises(ValidationError) as exc:
        Settings(google_api_key="", mcp_transport="stdio")
    assert "google_api_key" in str(exc.value)
```

### Implementation Template
```python
# places_mcp/config/settings.py
from pydantic import BaseSettings, SecretStr, validator
from typing import Literal

class Settings(BaseSettings):
    google_api_key: SecretStr
    mcp_transport: Literal["stdio", "http"] = "stdio"
    cache_ttl: int = 1800
    log_level: str = "INFO"
    
    @validator("google_api_key")
    def validate_api_key(cls, v: SecretStr) -> SecretStr:
        if not v.get_secret_value():
            raise ValueError("API key cannot be empty")
        return v
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
```

## Success Criteria
- [ ] All tests pass
- [ ] >90% code coverage
- [ ] No type errors from mypy
- [ ] No linting issues from ruff
- [ ] PR approved and merged
- [ ] Issue #1 automatically closed