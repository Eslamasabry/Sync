import pytest
from fastapi.testclient import TestClient

from sync_backend.config import get_settings
from sync_backend.main import create_app


@pytest.fixture(autouse=True)
def clear_settings_cache() -> None:
    get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app())
