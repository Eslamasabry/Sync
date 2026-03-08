from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from sync_backend.api.routes import health as health_routes


def test_health_endpoint(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_ready_endpoint_reports_ready(client: TestClient) -> None:
    response = client.get("/v1/ready")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ready"
    assert payload["checks"]["database"]["status"] == "ok"
    assert payload["checks"]["redis"]["status"] == "ok"
    assert payload["checks"]["object_store"]["status"] == "ok"


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
