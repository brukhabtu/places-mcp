# Test Infrastructure Setup Tasks

## Objective
Set up comprehensive test infrastructure to enable TDD for all other agents

## Task Breakdown

### Project Test Structure
- [ ] Create tests/ directory structure
- [ ] Create tests/unit/ for unit tests
- [ ] Create tests/integration/ for integration tests
- [ ] Create tests/e2e/ for end-to-end tests
- [ ] Create tests/fixtures/ for test data
- [ ] Add __init__.py files

### Pytest Configuration
- [ ] Create pytest.ini in project root
- [ ] Configure test discovery paths
- [ ] Set default markers
- [ ] Configure test output format
- [ ] Add asyncio mode
- [ ] Set minimum coverage threshold

### Coverage Configuration
- [ ] Create .coveragerc file
- [ ] Configure source paths
- [ ] Set coverage targets (>80%)
- [ ] Exclude test files from coverage
- [ ] Configure HTML report output
- [ ] Add branch coverage

### Test Dependencies
- [ ] Add pytest to dev dependencies
- [ ] Add pytest-asyncio for async tests
- [ ] Add pytest-cov for coverage
- [ ] Add pytest-mock for mocking
- [ ] Add httpx for API testing
- [ ] Add faker for test data

### Common Fixtures
- [ ] Create conftest.py in tests/
- [ ] Add async test fixtures
- [ ] Create mock service fixtures
- [ ] Create test data fixtures
- [ ] Add database fixtures (future)
- [ ] Add cleanup fixtures

### Test Utilities
- [ ] Create tests/utils.py
- [ ] Add test data builders
- [ ] Add assertion helpers
- [ ] Add async test helpers
- [ ] Add response mockers
- [ ] Add time/date helpers

### Mock Implementations
- [ ] Create tests/mocks/ directory
- [ ] Move MockPlacesRepository here
- [ ] Add MockCacheRepository
- [ ] Add MockRateLimiter
- [ ] Ensure all mocks follow interfaces

### CI/CD Configuration
- [ ] Create .github/workflows/test.yml
- [ ] Run tests on push/PR
- [ ] Upload coverage reports
- [ ] Fail if coverage drops
- [ ] Run linting checks
- [ ] Run type checking

### Documentation
- [ ] Create tests/README.md
- [ ] Document test structure
- [ ] Document running tests
- [ ] Document writing tests
- [ ] Add TDD guidelines

## Code Templates

### pytest.ini
```ini
[tool:pytest]
minversion = 7.0
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
asyncio_mode = auto
addopts = 
    -ra
    --strict-markers
    --cov=places_mcp
    --cov-branch
    --cov-report=term-missing:skip-covered
    --cov-report=html
    --cov-report=xml
    --cov-fail-under=80
markers =
    unit: Unit tests
    integration: Integration tests
    e2e: End-to-end tests
    slow: Slow tests
```

### .coveragerc
```ini
[run]
source = places_mcp
branch = True
omit = 
    */tests/*
    */test_*
    */__main__.py
    */migrations/*

[report]
exclude_lines =
    pragma: no cover
    def __repr__
    raise AssertionError
    raise NotImplementedError
    if __name__ == .__main__.:
    if TYPE_CHECKING:
    @abstract

[html]
directory = htmlcov
```

### conftest.py
```python
# tests/conftest.py
import pytest
import asyncio
from typing import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock

# Configure async tests
pytest_plugins = ('pytest_asyncio',)

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture
async def mock_places_repository():
    """Mock PlacesRepository for testing"""
    from places_mcp.tests.mocks import MockPlacesRepository
    repo = MockPlacesRepository()
    yield repo

@pytest.fixture
async def mock_cache_repository():
    """Mock CacheRepository for testing"""
    from places_mcp.tests.mocks import MockCacheRepository
    cache = MockCacheRepository()
    yield cache

@pytest.fixture
def mock_context():
    """Mock FastMCP Context"""
    ctx = MagicMock()
    ctx.info = AsyncMock()
    ctx.error = AsyncMock()
    ctx.warning = AsyncMock()
    ctx.report_progress = AsyncMock()
    return ctx

@pytest.fixture
def test_settings(monkeypatch):
    """Test settings with environment variables"""
    monkeypatch.setenv("GOOGLE_API_KEY", "test-api-key")
    monkeypatch.setenv("MCP_TRANSPORT", "stdio")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")
    
    from places_mcp.config.settings import Settings
    return Settings()

@pytest.fixture(autouse=True)
async def cleanup():
    """Cleanup after each test"""
    yield
    # Add any cleanup logic here

# Test markers
def pytest_configure(config):
    config.addinivalue_line(
        "markers", "unit: mark test as a unit test"
    )
    config.addinivalue_line(
        "markers", "integration: mark test as an integration test"
    )
    config.addinivalue_line(
        "markers", "e2e: mark test as an end-to-end test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow"
    )
```

### Test Utilities
```python
# tests/utils.py
from typing import Dict, Any, List
from datetime import datetime
import random
import string
from places_mcp.domain.models import Place, Location

class TestDataBuilder:
    """Build test data for tests"""
    
    @staticmethod
    def build_place(**kwargs) -> Place:
        """Build a test Place object"""
        defaults = {
            "id": f"ChIJ{''.join(random.choices(string.ascii_letters, k=10))}",
            "display_name": "Test Place",
            "formatted_address": "123 Test St, Test City",
            "location": TestDataBuilder.build_location(),
            "rating": round(random.uniform(3.0, 5.0), 1),
            "user_rating_count": random.randint(10, 1000),
            "types": ["restaurant", "food"]
        }
        defaults.update(kwargs)
        return Place(**defaults)
    
    @staticmethod
    def build_location(**kwargs) -> Location:
        """Build a test Location object"""
        defaults = {
            "latitude": round(random.uniform(-90, 90), 6),
            "longitude": round(random.uniform(-180, 180), 6)
        }
        defaults.update(kwargs)
        return Location(**defaults)
    
    @staticmethod
    def build_search_response(count: int = 5) -> Dict[str, Any]:
        """Build mock API response"""
        return {
            "places": [
                {
                    "name": f"places/ChIJ{i}",
                    "displayName": {"text": f"Place {i}"},
                    "formattedAddress": f"{i} Main St",
                    "location": {
                        "latitude": 40.7 + i * 0.01,
                        "longitude": -74.0 + i * 0.01
                    },
                    "rating": 4.0 + i * 0.1,
                    "userRatingsTotal": 100 + i * 10,
                    "types": ["restaurant"]
                }
                for i in range(count)
            ]
        }

# Async test helpers
async def async_return(value):
    """Helper to return async value in tests"""
    return value

def assert_place_equal(place1: Place, place2: Place, check_location: bool = True):
    """Assert two places are equal"""
    assert place1.id == place2.id
    assert place1.display_name == place2.display_name
    assert place1.formatted_address == place2.formatted_address
    assert place1.rating == place2.rating
    assert place1.types == place2.types
    
    if check_location and place1.location and place2.location:
        assert abs(place1.location.latitude - place2.location.latitude) < 0.0001
        assert abs(place1.location.longitude - place2.location.longitude) < 0.0001
```

### GitHub Actions Test Workflow
```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12", "3.13"]
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install uv
      uses: astral-sh/setup-uv@v4
    
    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v5
      with:
        python-version: ${{ matrix.python-version }}
    
    - name: Install dependencies
      run: |
        uv venv
        uv pip install -e ".[dev]"
    
    - name: Run linting
      run: |
        uv run ruff check .
        uv run ruff format --check .
    
    - name: Run type checking
      run: |
        uv run mypy places_mcp
    
    - name: Run tests
      run: |
        uv run pytest -v --cov-report=xml
    
    - name: Upload coverage
      uses: codecov/codecov-action@v4
      with:
        file: ./coverage.xml
        fail_ci_if_error: true
```

### Test Documentation
```markdown
# Testing Guide

## Running Tests

### All tests
```bash
uv run pytest
```

### Unit tests only
```bash
uv run pytest -m unit
```

### With coverage
```bash
uv run pytest --cov=places_mcp --cov-report=html
```

### Watch mode
```bash
uv run pytest-watch
```

## Writing Tests

### TDD Process
1. Write test first (red)
2. Write minimal code to pass (green)
3. Refactor (refactor)

### Test Structure
```python
def test_should_do_something():
    # Arrange
    data = setup_test_data()
    
    # Act
    result = function_under_test(data)
    
    # Assert
    assert result == expected
```

### Async Tests
```python
@pytest.mark.asyncio
async def test_async_function():
    result = await async_function()
    assert result is not None
```

## Test Organization

- `tests/unit/` - Fast, isolated tests
- `tests/integration/` - Test component interactions
- `tests/e2e/` - Full system tests
- `tests/fixtures/` - Test data files
```

## Success Criteria
- [ ] All test infrastructure in place
- [ ] Tests can run in parallel
- [ ] Coverage reporting works
- [ ] CI/CD pipeline ready
- [ ] Documentation complete