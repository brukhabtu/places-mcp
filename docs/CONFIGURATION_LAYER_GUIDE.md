# Configuration Layer Implementation Guide

## Overview

The Configuration Layer provides a robust, type-safe system for managing application settings, secrets, and environment-specific configurations. This guide covers the implementation of a modern configuration system using Pydantic Settings, YAML files with environment variable interpolation, and best practices for secret management.

## Core Principles

1. **Type Safety**: All configuration values are validated at startup
2. **Secret Protection**: Sensitive data never appears in code or logs
3. **Environment Flexibility**: Easy switching between dev/staging/production
4. **Fail Fast**: Invalid configuration causes immediate startup failure
5. **Single Source of Truth**: One configuration system for the entire application

## Architecture

```
places_mcp/
├── config/
│   ├── __init__.py
│   ├── settings.py          # Pydantic Settings models
│   ├── loader.py            # YAML loader with !env support
│   ├── validators.py        # Custom validation logic
│   └── environments/
│       ├── base.yaml        # Shared configuration
│       ├── development.yaml # Dev-specific settings
│       ├── staging.yaml     # Staging settings
│       └── production.yaml  # Production settings
```

## Pydantic Settings Implementation

### Base Settings Model

```python
# places_mcp/config/settings.py
from pydantic import Field, SecretStr, validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional, Literal
from pathlib import Path

class Settings(BaseSettings):
    """Application settings with validation and type safety."""
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_nested_delimiter="__",  # Allows REDIS__HOST=localhost
        case_sensitive=False,
        extra="forbid"  # Fail on unknown fields
    )
    
    # Environment
    environment: Literal["development", "staging", "production"] = Field(
        default="development",
        description="Runtime environment"
    )
    
    # API Configuration
    google_api_key: SecretStr = Field(
        ...,  # Required field
        description="Google Places API key",
        min_length=10
    )
    
    # Server Configuration
    host: str = Field(default="0.0.0.0", description="Server host")
    port: int = Field(default=8000, description="Server port", gt=0, le=65535)
    
    # Cache Configuration
    cache: CacheSettings = Field(default_factory=lambda: CacheSettings())
    
    # Rate Limiting
    rate_limit: RateLimitSettings = Field(
        default_factory=lambda: RateLimitSettings()
    )
    
    # Logging
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(
        default="INFO",
        description="Logging level"
    )
    
    # Advanced Features
    enable_telemetry: bool = Field(
        default=True,
        description="Enable OpenTelemetry integration"
    )
    
    @validator("google_api_key")
    def validate_api_key(cls, v: SecretStr) -> SecretStr:
        """Validate Google API key format."""
        if not v.get_secret_value().startswith("AIza"):
            raise ValueError("Invalid Google API key format")
        return v
    
    @property
    def is_production(self) -> bool:
        """Check if running in production."""
        return self.environment == "production"
    
    @property
    def is_development(self) -> bool:
        """Check if running in development."""
        return self.environment == "development"

class CacheSettings(BaseSettings):
    """Cache-specific configuration."""
    
    provider: Literal["redis", "memory"] = Field(
        default="memory",
        description="Cache provider"
    )
    
    # Redis settings
    redis_url: Optional[str] = Field(
        default=None,
        description="Redis connection URL"
    )
    redis_host: str = Field(default="localhost")
    redis_port: int = Field(default=6379)
    redis_password: Optional[SecretStr] = Field(default=None)
    redis_db: int = Field(default=0)
    
    # Cache behavior
    ttl: int = Field(
        default=1800,
        description="Default TTL in seconds",
        gt=0
    )
    max_entries: int = Field(
        default=1000,
        description="Maximum cache entries (memory provider)"
    )
    
    @property
    def redis_dsn(self) -> str:
        """Construct Redis DSN from components."""
        if self.redis_url:
            return self.redis_url
        
        auth = f":{self.redis_password.get_secret_value()}@" if self.redis_password else ""
        return f"redis://{auth}{self.redis_host}:{self.redis_port}/{self.redis_db}"

class RateLimitSettings(BaseSettings):
    """Rate limiting configuration."""
    
    enabled: bool = Field(default=True)
    requests_per_minute: int = Field(default=60, gt=0)
    requests_per_hour: int = Field(default=1000, gt=0)
    burst_size: int = Field(default=10, gt=0)
    
    # Per-endpoint overrides
    search_rpm: Optional[int] = Field(default=None)
    details_rpm: Optional[int] = Field(default=None)
```

## YAML Configuration with !env Tags

### YAML Loader Implementation

```python
# places_mcp/config/loader.py
import yaml
import os
from pathlib import Path
from typing import Any, Dict, Optional
import re

class EnvVarLoader(yaml.SafeLoader):
    """YAML loader with !env tag support."""
    pass

def env_var_constructor(loader: EnvVarLoader, node: yaml.ScalarNode) -> str:
    """
    Extract environment variable value.
    Supports:
    - !env VAR_NAME
    - !env VAR_NAME:default_value
    - !env "VAR_NAME:default with spaces"
    """
    value = loader.construct_scalar(node)
    
    # Parse VAR_NAME:default pattern
    match = re.match(r'^([A-Z_][A-Z0-9_]*):(.*)$', value)
    if match:
        var_name, default = match.groups()
        return os.environ.get(var_name, default)
    
    # Simple variable without default
    if value not in os.environ:
        raise ValueError(f"Environment variable '{value}' not found")
    
    return os.environ[value]

# Register the !env tag
EnvVarLoader.add_constructor('!env', env_var_constructor)

def load_yaml_config(file_path: Path) -> Dict[str, Any]:
    """Load YAML configuration with environment variable support."""
    if not file_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {file_path}")
    
    with open(file_path, 'r') as f:
        return yaml.load(f, Loader=EnvVarLoader)

def merge_configs(*configs: Dict[str, Any]) -> Dict[str, Any]:
    """Deep merge multiple configuration dictionaries."""
    result = {}
    
    for config in configs:
        for key, value in config.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = merge_configs(result[key], value)
            else:
                result[key] = value
    
    return result

class ConfigurationLoader:
    """Load and merge configuration from multiple sources."""
    
    def __init__(self, config_dir: Path, environment: str = "development"):
        self.config_dir = config_dir
        self.environment = environment
    
    def load(self) -> Dict[str, Any]:
        """Load configuration for the current environment."""
        # Load base configuration
        base_config = self._load_file("base.yaml")
        
        # Load environment-specific configuration
        env_file = f"{self.environment}.yaml"
        env_config = self._load_file(f"environments/{env_file}")
        
        # Merge configurations
        return merge_configs(base_config, env_config)
    
    def _load_file(self, filename: str) -> Dict[str, Any]:
        """Load a single configuration file."""
        file_path = self.config_dir / filename
        if file_path.exists():
            return load_yaml_config(file_path)
        return {}
```

### YAML Configuration Examples

```yaml
# config/environments/base.yaml
# Shared configuration across all environments

server:
  host: "0.0.0.0"
  port: !env "PORT:8000"
  workers: !env "WORKERS:4"

google:
  api_key: !env GOOGLE_API_KEY
  base_url: "https://places.googleapis.com/v1"
  timeout: 30

cache:
  provider: !env "CACHE_PROVIDER:memory"
  ttl: 1800
  max_entries: 1000

rate_limit:
  enabled: true
  requests_per_minute: 60
  requests_per_hour: 1000

logging:
  level: !env "LOG_LEVEL:INFO"
  format: "json"
  
telemetry:
  enabled: !env "ENABLE_TELEMETRY:false"
  service_name: "places-mcp"
  exporter: !env "OTEL_EXPORTER:console"
```

```yaml
# config/environments/development.yaml
# Development-specific overrides

cache:
  provider: "memory"
  ttl: 300  # Shorter TTL for development

logging:
  level: "DEBUG"
  format: "console"  # Human-readable format

rate_limit:
  enabled: false  # No rate limiting in dev

telemetry:
  enabled: false
```

```yaml
# config/environments/production.yaml
# Production configuration

server:
  workers: !env WORKERS

cache:
  provider: "redis"
  redis:
    url: !env REDIS_URL
    password: !env REDIS_PASSWORD
    
logging:
  level: !env "LOG_LEVEL:WARNING"
  
telemetry:
  enabled: true
  exporter: !env "OTEL_EXPORTER:otlp"
  endpoint: !env OTEL_ENDPOINT
```

## Environment Variable Handling

### Best Practices

```python
# places_mcp/config/env.py
import os
from pathlib import Path
from typing import Optional, Dict, Any
from dotenv import load_dotenv

class EnvironmentManager:
    """Manage environment variables and .env files."""
    
    def __init__(self, env_file: Optional[Path] = None):
        self.env_file = env_file or Path(".env")
        self._original_env: Dict[str, str] = {}
    
    def load(self) -> None:
        """Load environment variables from file."""
        if self.env_file.exists():
            load_dotenv(self.env_file)
    
    def validate_required(self, required_vars: list[str]) -> None:
        """Validate that required environment variables are set."""
        missing = [var for var in required_vars if not os.getenv(var)]
        
        if missing:
            raise EnvironmentError(
                f"Missing required environment variables: {', '.join(missing)}"
            )
    
    def get_with_prefix(self, prefix: str) -> Dict[str, str]:
        """Get all environment variables with a specific prefix."""
        return {
            key[len(prefix):]: value
            for key, value in os.environ.items()
            if key.startswith(prefix)
        }
    
    def set_temporary(self, **kwargs) -> None:
        """Temporarily set environment variables (useful for testing)."""
        for key, value in kwargs.items():
            self._original_env[key] = os.environ.get(key, '')
            os.environ[key] = str(value)
    
    def restore(self) -> None:
        """Restore original environment variables."""
        for key, value in self._original_env.items():
            if value:
                os.environ[key] = value
            elif key in os.environ:
                del os.environ[key]
        self._original_env.clear()

# Usage example
def validate_environment() -> None:
    """Validate environment on startup."""
    env_manager = EnvironmentManager()
    env_manager.load()
    
    # Check required variables based on environment
    environment = os.getenv("ENVIRONMENT", "development")
    
    required_vars = ["GOOGLE_API_KEY"]
    
    if environment == "production":
        required_vars.extend([
            "REDIS_URL",
            "OTEL_ENDPOINT",
            "SENTRY_DSN"
        ])
    
    env_manager.validate_required(required_vars)
```

## Secret Management Best Practices

### 1. Secret Storage

```python
# places_mcp/config/secrets.py
from typing import Optional, Dict, Any
import json
import base64
from pathlib import Path
from cryptography.fernet import Fernet
from pydantic import SecretStr

class SecretManager:
    """Manage application secrets securely."""
    
    def __init__(self, key: Optional[str] = None):
        """Initialize with encryption key."""
        if key:
            self.cipher = Fernet(key.encode())
        else:
            self.cipher = None
    
    def encrypt_file(self, input_path: Path, output_path: Path) -> None:
        """Encrypt a secrets file."""
        if not self.cipher:
            raise ValueError("Encryption key required")
        
        with open(input_path, 'rb') as f:
            encrypted = self.cipher.encrypt(f.read())
        
        with open(output_path, 'wb') as f:
            f.write(encrypted)
    
    def decrypt_file(self, input_path: Path) -> Dict[str, Any]:
        """Decrypt and load secrets file."""
        if not self.cipher:
            raise ValueError("Encryption key required")
        
        with open(input_path, 'rb') as f:
            decrypted = self.cipher.decrypt(f.read())
        
        return json.loads(decrypted)
    
    @staticmethod
    def mask_secret(value: str, visible_chars: int = 4) -> str:
        """Mask a secret value for logging."""
        if len(value) <= visible_chars * 2:
            return "***"
        
        return f"{value[:visible_chars]}...{value[-visible_chars:]}"
    
    @staticmethod
    def validate_secret_strength(secret: str, min_length: int = 32) -> bool:
        """Validate secret strength."""
        if len(secret) < min_length:
            return False
        
        # Check for entropy (simplified)
        unique_chars = len(set(secret))
        return unique_chars >= min_length // 2

class SecretStr(pydantic.SecretStr):
    """Enhanced SecretStr with additional security features."""
    
    def __repr__(self) -> str:
        return f"SecretStr('***')"
    
    def __str__(self) -> str:
        return "***"
    
    def masked(self, visible_chars: int = 4) -> str:
        """Get masked version of secret."""
        return SecretManager.mask_secret(
            self.get_secret_value(),
            visible_chars
        )
```

### 2. Secret Rotation

```python
# places_mcp/config/rotation.py
from datetime import datetime, timedelta
from typing import Optional, Protocol
import asyncio

class SecretProvider(Protocol):
    """Protocol for secret providers."""
    
    async def get_secret(self, key: str) -> str:
        """Get current secret value."""
        ...
    
    async def rotate_secret(self, key: str) -> str:
        """Rotate and return new secret."""
        ...

class SecretRotationManager:
    """Manage automatic secret rotation."""
    
    def __init__(
        self,
        provider: SecretProvider,
        rotation_interval: timedelta = timedelta(days=30)
    ):
        self.provider = provider
        self.rotation_interval = rotation_interval
        self._rotation_tasks: Dict[str, asyncio.Task] = {}
    
    async def start_rotation(self, secret_key: str) -> None:
        """Start automatic rotation for a secret."""
        if secret_key in self._rotation_tasks:
            return
        
        task = asyncio.create_task(
            self._rotation_loop(secret_key)
        )
        self._rotation_tasks[secret_key] = task
    
    async def _rotation_loop(self, secret_key: str) -> None:
        """Rotation loop for a specific secret."""
        while True:
            await asyncio.sleep(self.rotation_interval.total_seconds())
            
            try:
                new_secret = await self.provider.rotate_secret(secret_key)
                await self._notify_rotation(secret_key, new_secret)
            except Exception as e:
                # Log error but continue rotation attempts
                print(f"Secret rotation failed for {secret_key}: {e}")
    
    async def _notify_rotation(self, key: str, new_value: str) -> None:
        """Notify application of secret rotation."""
        # Implement notification logic
        pass
```

## Configuration Validation

### Custom Validators

```python
# places_mcp/config/validators.py
from pydantic import BaseModel, validator, root_validator
from typing import Optional, Dict, Any
import re
from urllib.parse import urlparse

class ConfigValidator:
    """Custom configuration validators."""
    
    @staticmethod
    def validate_url(url: str) -> str:
        """Validate URL format."""
        parsed = urlparse(url)
        if not all([parsed.scheme, parsed.netloc]):
            raise ValueError(f"Invalid URL: {url}")
        return url
    
    @staticmethod
    def validate_api_key_format(key: str, prefix: str) -> str:
        """Validate API key format."""
        if not key.startswith(prefix):
            raise ValueError(f"API key must start with {prefix}")
        if len(key) < 32:
            raise ValueError("API key too short")
        return key
    
    @staticmethod
    def validate_port_range(port: int) -> int:
        """Validate port is in valid range."""
        if not 1 <= port <= 65535:
            raise ValueError(f"Port must be between 1-65535, got {port}")
        return port

class AdvancedSettings(BaseSettings):
    """Settings with advanced validation."""
    
    # Database settings
    database_url: str
    database_pool_size: int = Field(default=10, ge=1, le=100)
    
    # API settings
    api_keys: Dict[str, SecretStr]
    allowed_origins: list[str] = Field(default_factory=list)
    
    @validator("database_url")
    def validate_database_url(cls, v: str) -> str:
        """Validate database URL format."""
        if not v.startswith(("postgresql://", "postgres://")):
            raise ValueError("Only PostgreSQL is supported")
        return ConfigValidator.validate_url(v)
    
    @validator("allowed_origins", each_item=True)
    def validate_origin(cls, v: str) -> str:
        """Validate each origin."""
        return ConfigValidator.validate_url(v)
    
    @root_validator
    def validate_api_keys(cls, values: Dict[str, Any]) -> Dict[str, Any]:
        """Validate all API keys have correct format."""
        api_keys = values.get("api_keys", {})
        
        for name, key in api_keys.items():
            if name == "google" and not key.get_secret_value().startswith("AIza"):
                raise ValueError("Invalid Google API key format")
        
        return values
```

## Multiple Environment Support

### Environment Management

```python
# places_mcp/config/environments.py
from enum import Enum
from typing import Dict, Any, Optional
from pathlib import Path
import os

class Environment(str, Enum):
    """Supported environments."""
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"
    TEST = "test"

class EnvironmentConfig:
    """Environment-specific configuration management."""
    
    def __init__(self, base_dir: Path = Path("config")):
        self.base_dir = base_dir
        self.current = self._detect_environment()
    
    def _detect_environment(self) -> Environment:
        """Detect current environment from various sources."""
        # 1. Check ENVIRONMENT variable
        env_var = os.getenv("ENVIRONMENT", "").lower()
        if env_var in [e.value for e in Environment]:
            return Environment(env_var)
        
        # 2. Check for environment-specific files
        if Path(".env.production").exists():
            return Environment.PRODUCTION
        elif Path(".env.staging").exists():
            return Environment.STAGING
        
        # 3. Default to development
        return Environment.DEVELOPMENT
    
    def get_config_path(self) -> Path:
        """Get configuration file path for current environment."""
        return self.base_dir / f"{self.current.value}.yaml"
    
    def get_env_file(self) -> Path:
        """Get .env file for current environment."""
        env_file = Path(f".env.{self.current.value}")
        if env_file.exists():
            return env_file
        return Path(".env")
    
    def is_production(self) -> bool:
        """Check if running in production."""
        return self.current == Environment.PRODUCTION
    
    def requires_https(self) -> bool:
        """Check if HTTPS is required."""
        return self.current in [Environment.STAGING, Environment.PRODUCTION]

# Environment-specific settings
ENVIRONMENT_DEFAULTS = {
    Environment.DEVELOPMENT: {
        "debug": True,
        "log_level": "DEBUG",
        "cache_ttl": 300,
        "rate_limit_enabled": False,
    },
    Environment.STAGING: {
        "debug": False,
        "log_level": "INFO",
        "cache_ttl": 900,
        "rate_limit_enabled": True,
    },
    Environment.PRODUCTION: {
        "debug": False,
        "log_level": "WARNING",
        "cache_ttl": 1800,
        "rate_limit_enabled": True,
    },
    Environment.TEST: {
        "debug": True,
        "log_level": "DEBUG",
        "cache_ttl": 0,
        "rate_limit_enabled": False,
    }
}
```

### Configuration Factory

```python
# places_mcp/config/factory.py
from typing import Type, TypeVar, Optional
from pathlib import Path

T = TypeVar("T", bound=BaseSettings)

class ConfigFactory:
    """Factory for creating environment-specific configurations."""
    
    @staticmethod
    def create(
        settings_class: Type[T],
        environment: Optional[str] = None,
        config_dir: Optional[Path] = None
    ) -> T:
        """Create settings instance for specific environment."""
        # Determine environment
        env_config = EnvironmentConfig(config_dir or Path("config"))
        if environment:
            env_config.current = Environment(environment)
        
        # Load environment variables
        env_manager = EnvironmentManager(env_config.get_env_file())
        env_manager.load()
        
        # Load YAML configuration
        config_loader = ConfigurationLoader(
            config_dir or Path("config"),
            env_config.current.value
        )
        yaml_config = config_loader.load()
        
        # Apply environment defaults
        defaults = ENVIRONMENT_DEFAULTS.get(env_config.current, {})
        
        # Merge all configurations
        merged_config = merge_configs(defaults, yaml_config)
        
        # Create settings instance
        return settings_class(**merged_config)

# Usage
def get_settings() -> Settings:
    """Get application settings."""
    return ConfigFactory.create(Settings)
```

## Configuration Testing

### Test Utilities

```python
# tests/config/test_settings.py
import pytest
from pathlib import Path
import tempfile
import os
from typing import Dict, Any

from places_mcp.config import Settings, ConfigFactory, EnvironmentManager

class ConfigTestCase:
    """Base class for configuration tests."""
    
    @pytest.fixture
    def temp_env_file(self) -> Path:
        """Create temporary .env file."""
        with tempfile.NamedTemporaryFile(
            mode='w',
            suffix='.env',
            delete=False
        ) as f:
            f.write("GOOGLE_API_KEY=AIzaTestKey123456789\n")
            f.write("REDIS_URL=redis://localhost:6379\n")
            f.write("LOG_LEVEL=DEBUG\n")
            return Path(f.name)
    
    @pytest.fixture
    def temp_config_dir(self) -> Path:
        """Create temporary config directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = Path(tmpdir) / "config"
            config_dir.mkdir()
            
            # Create base config
            base_config = config_dir / "base.yaml"
            base_config.write_text("""
server:
  port: 8000
cache:
  ttl: 1800
""")
            
            # Create env configs
            env_dir = config_dir / "environments"
            env_dir.mkdir()
            
            dev_config = env_dir / "development.yaml"
            dev_config.write_text("""
cache:
  ttl: 300
logging:
  level: DEBUG
""")
            
            yield config_dir
    
    @pytest.fixture
    def mock_env_vars(self) -> Dict[str, str]:
        """Mock environment variables."""
        original = os.environ.copy()
        
        os.environ.update({
            "GOOGLE_API_KEY": "AIzaTestKey123456789",
            "ENVIRONMENT": "test",
            "PORT": "9000",
        })
        
        yield os.environ
        
        # Restore original
        os.environ.clear()
        os.environ.update(original)

class TestSettings(ConfigTestCase):
    """Test settings validation and loading."""
    
    def test_load_from_env_file(self, temp_env_file):
        """Test loading settings from .env file."""
        env_manager = EnvironmentManager(temp_env_file)
        env_manager.load()
        
        settings = Settings()
        assert settings.google_api_key.get_secret_value().startswith("AIza")
        assert settings.log_level == "DEBUG"
    
    def test_validation_errors(self):
        """Test validation errors for invalid settings."""
        with pytest.raises(ValueError, match="API key"):
            Settings(google_api_key="invalid_key")
        
        with pytest.raises(ValueError, match="port"):
            Settings(
                google_api_key="AIzaValidKey123",
                port=70000
            )
    
    def test_environment_override(self, mock_env_vars):
        """Test environment variables override file values."""
        settings = Settings()
        assert settings.port == 9000  # From env var, not default
    
    def test_secret_masking(self):
        """Test secret values are masked in logs."""
        settings = Settings(google_api_key="AIzaTestKey123456789")
        
        # String representation should be masked
        assert "AIzaTest" not in str(settings.google_api_key)
        assert "***" in str(settings.google_api_key)
        
        # But actual value is accessible
        assert settings.google_api_key.get_secret_value() == "AIzaTestKey123456789"

class TestConfigLoader(ConfigTestCase):
    """Test YAML configuration loading."""
    
    def test_env_tag_substitution(self, temp_config_dir, mock_env_vars):
        """Test !env tag substitution in YAML."""
        yaml_file = temp_config_dir / "test.yaml"
        yaml_file.write_text("""
api:
  key: !env GOOGLE_API_KEY
  port: !env "PORT:8000"
  missing: !env "MISSING_VAR:default_value"
""")
        
        config = load_yaml_config(yaml_file)
        assert config["api"]["key"] == "AIzaTestKey123456789"
        assert config["api"]["port"] == "9000"
        assert config["api"]["missing"] == "default_value"
    
    def test_config_merging(self, temp_config_dir):
        """Test configuration merging."""
        loader = ConfigurationLoader(temp_config_dir, "development")
        config = loader.load()
        
        # Base value
        assert config["server"]["port"] == 8000
        
        # Overridden value
        assert config["cache"]["ttl"] == 300
        
        # New value from dev config
        assert config["logging"]["level"] == "DEBUG"

class TestEnvironmentDetection(ConfigTestCase):
    """Test environment detection and management."""
    
    def test_environment_detection(self, mock_env_vars):
        """Test automatic environment detection."""
        env_config = EnvironmentConfig()
        assert env_config.current == Environment.TEST
    
    def test_environment_specific_defaults(self):
        """Test environment-specific default values."""
        # Development
        dev_settings = ConfigFactory.create(
            Settings,
            environment="development"
        )
        assert dev_settings.environment == "development"
        
        # Production
        prod_settings = ConfigFactory.create(
            Settings,
            environment="production"
        )
        assert prod_settings.environment == "production"
        assert prod_settings.is_production
```

### Integration Tests

```python
# tests/config/test_integration.py
import pytest
import asyncio
from unittest.mock import Mock, patch

from places_mcp.config import Settings, SecretRotationManager

class TestConfigIntegration:
    """Integration tests for configuration system."""
    
    @pytest.mark.asyncio
    async def test_secret_rotation(self):
        """Test automatic secret rotation."""
        # Mock secret provider
        provider = Mock()
        provider.get_secret.return_value = "old_secret"
        provider.rotate_secret.return_value = "new_secret"
        
        # Create rotation manager with short interval
        manager = SecretRotationManager(
            provider,
            rotation_interval=timedelta(seconds=1)
        )
        
        # Start rotation
        await manager.start_rotation("test_key")
        
        # Wait for rotation
        await asyncio.sleep(2)
        
        # Verify rotation was called
        provider.rotate_secret.assert_called_with("test_key")
    
    def test_full_configuration_load(self, temp_config_dir, temp_env_file):
        """Test complete configuration loading process."""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "development",
            "GOOGLE_API_KEY": "AIzaTestKey123"
        }):
            settings = ConfigFactory.create(
                Settings,
                config_dir=temp_config_dir
            )
            
            assert settings.environment == "development"
            assert settings.cache.ttl == 300  # From dev config
            assert settings.google_api_key.get_secret_value() == "AIzaTestKey123"
```

## Best Practices Summary

1. **Always validate configuration at startup**
   - Use Pydantic's validation features
   - Fail fast on invalid configuration
   - Provide clear error messages

2. **Never log sensitive values**
   - Use SecretStr for all secrets
   - Implement proper masking for logs
   - Audit configuration access

3. **Support multiple configuration sources**
   - Environment variables (highest priority)
   - Configuration files
   - Default values (lowest priority)

4. **Make configuration testable**
   - Provide test utilities
   - Mock environment variables
   - Test validation logic

5. **Document all configuration options**
   - Include descriptions in Pydantic models
   - Provide example configurations
   - Document environment-specific behavior

6. **Implement proper secret management**
   - Use dedicated secret stores in production
   - Rotate secrets regularly
   - Never commit secrets to version control

7. **Use type-safe configuration**
   - Leverage Pydantic's type system
   - Avoid string-based configuration
   - Validate complex structures

8. **Plan for configuration changes**
   - Version configuration schemas
   - Provide migration paths
   - Maintain backwards compatibility