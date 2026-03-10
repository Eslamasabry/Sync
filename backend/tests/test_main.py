from fastapi.testclient import TestClient
from pytest import MonkeyPatch

from sync_backend.config import get_settings
from sync_backend.main import create_app


def test_cors_middleware_allows_local_web_origin_in_development(
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.delenv("CORS_ALLOW_ORIGINS", raising=False)
    monkeypatch.delenv("CORS_ALLOW_ORIGIN_REGEX", raising=False)
    monkeypatch.setenv("APP_ENV", "development")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.options(
            "/v1/health",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"


def test_cors_middleware_disabled_by_default_in_production(
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.delenv("CORS_ALLOW_ORIGINS", raising=False)
    monkeypatch.delenv("CORS_ALLOW_ORIGIN_REGEX", raising=False)
    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.options(
            "/v1/health",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            },
        )

    assert response.status_code == 405
    assert "access-control-allow-origin" not in response.headers


def test_cors_middleware_allows_configured_origin(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,https://sync.example")
    monkeypatch.setenv("CORS_ALLOW_CREDENTIALS", "true")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.options(
            "/v1/projects",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Authorization,Content-Type",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert response.headers["access-control-allow-credentials"] == "true"
    assert "POST" in response.headers["access-control-allow-methods"]


def test_trusted_hosts_reject_unconfigured_host(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("TRUSTED_HOSTS", "localhost,127.0.0.1,sync.example")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.get(
            "/v1/health",
            headers={"host": "malicious.example"},
        )

    assert response.status_code == 400


def test_cors_origin_regex_allows_matching_origin(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ALLOW_ORIGIN_REGEX", r"https://.*\.sync\.example")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.options(
            "/v1/projects",
            headers={
                "Origin": "https://preview.sync.example",
                "Access-Control-Request-Method": "POST",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://preview.sync.example"


def test_trusted_hosts_reject_unknown_host(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("TRUSTED_HOSTS", "sync.example,localhost")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.get(
            "/v1/health",
            headers={"host": "evil.example"},
        )

    assert response.status_code == 400


def test_gzip_enabled_by_default(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("GZIP_MINIMUM_SIZE", "1")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        response = client.get(
            "/v1/health",
            headers={"Accept-Encoding": "gzip"},
        )

    assert response.status_code == 200
    assert response.headers["content-encoding"] == "gzip"


def test_project_routes_require_bearer_auth_when_configured(
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setenv("API_AUTH_TOKEN", "secret-token")
    get_settings.cache_clear()

    with TestClient(create_app()) as client:
        health_response = client.get("/v1/health")
        unauthorized_response = client.post(
            "/v1/projects",
            json={"title": "Protected Project"},
        )
        wrong_token_response = client.post(
            "/v1/projects",
            headers={"Authorization": "Bearer wrong-token"},
            json={"title": "Protected Project"},
        )
        authorized_response = client.post(
            "/v1/projects",
            headers={"Authorization": "Bearer secret-token"},
            json={"title": "Protected Project"},
        )

    assert health_response.status_code == 200
    assert unauthorized_response.status_code == 401
    assert unauthorized_response.headers["www-authenticate"] == "Bearer"
    assert unauthorized_response.json()["error"]["code"] == "auth_invalid"
    assert wrong_token_response.status_code == 401
    assert authorized_response.status_code == 201
