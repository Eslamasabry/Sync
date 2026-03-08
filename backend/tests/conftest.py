from collections.abc import Generator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from sync_backend.api.realtime import broker
from sync_backend.config import get_settings
from sync_backend.db import reset_db_caches
from sync_backend.main import create_app


@pytest.fixture(autouse=True)
def clear_settings_cache(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    database_path = tmp_path / "test.db"
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    with TestClient(create_app()) as test_client:
        yield test_client
