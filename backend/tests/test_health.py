from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from sync_backend.api.realtime import broker
from sync_backend.api.routes import health as health_routes
from sync_backend.config import get_settings
from sync_backend.db import reset_db_caches
from sync_backend.main import create_app


def test_health_endpoint(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["probe"] == "liveness"
    assert payload["checked_at"].endswith("Z")


def test_ready_endpoint_reports_ready(client: TestClient) -> None:
    response = client.get("/v1/ready")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ready"
    assert payload["probe"] == "readiness"
    assert payload["checked_at"].endswith("Z")
    assert payload["checks"]["database"]["status"] == "ok"
    assert payload["checks"]["database"]["critical"] is True
    assert isinstance(payload["checks"]["database"]["latency_ms"], float)
    assert payload["checks"]["redis"]["status"] == "skipped"
    assert payload["checks"]["redis"]["reason"] == "skipped_in_test_environment"
    assert payload["checks"]["object_store"]["status"] == "ok"
    assert payload["summary"] == {
        "ready_checks": 2,
        "skipped_checks": 1,
        "failed_checks": 0,
    }


def test_ready_endpoint_reports_degraded_dependency(
    client: TestClient,
    monkeypatch: MonkeyPatch,
) -> None:
    def fail_database() -> bool:
        raise RuntimeError("database unavailable")

    monkeypatch.setattr(health_routes, "_database_ready", fail_database)

    response = client.get("/v1/ready")

    assert response.status_code == 503
    payload = response.json()
    assert payload["status"] == "degraded"
    assert payload["checks"]["database"]["status"] == "error"
    assert payload["checks"]["database"]["critical"] is True
    assert payload["checks"]["database"]["error_type"] == "RuntimeError"
    assert payload["checks"]["database"]["detail"] == "database unavailable"
    assert isinstance(payload["checks"]["database"]["latency_ms"], float)
    assert payload["summary"] == {
        "ready_checks": 1,
        "skipped_checks": 1,
        "failed_checks": 1,
    }


def test_ready_endpoint_skips_redis_in_inline_execution_mode(
    monkeypatch: MonkeyPatch,
    tmp_path,
) -> None:
    database_path = tmp_path / "inline-ready.db"
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("JOB_EXECUTION_MODE", "inline")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()

    with TestClient(create_app()) as client:
        response = client.get("/v1/ready")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ready"
    assert payload["checks"]["redis"]["status"] == "skipped"
    assert payload["checks"]["redis"]["reason"] == "skipped_in_inline_execution_mode"
