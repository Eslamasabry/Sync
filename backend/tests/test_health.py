from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from sync_backend.api.routes import health as health_routes


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
