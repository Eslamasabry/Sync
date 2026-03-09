import secrets
from collections.abc import Generator
from typing import Annotated

from fastapi import Depends, Header, WebSocket
from sqlalchemy.orm import Session

from sync_backend.api.errors import ApiError
from sync_backend.config import Settings, get_settings
from sync_backend.db import get_session_factory


def get_app_settings() -> Settings:
    return get_settings()


def get_db_session() -> Generator[Session, None, None]:
    session = get_session_factory()()
    try:
        yield session
    finally:
        session.close()


def _extract_bearer_token(value: str | None) -> str | None:
    if value is None:
        return None
    scheme, _, token = value.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    return token.strip()


def _is_valid_api_token(candidate: str | None, settings: Settings) -> bool:
    if not settings.auth_enabled:
        return True
    if candidate is None:
        return False
    return secrets.compare_digest(candidate, settings.api_auth_token)


def require_api_auth(
    settings: Annotated[Settings, Depends(get_app_settings)],
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    if not settings.auth_enabled:
        return

    if not _is_valid_api_token(_extract_bearer_token(authorization), settings):
        raise ApiError(
            code="auth_invalid",
            message="A valid bearer token is required for this resource",
            status_code=401,
            details={"auth_enabled": True},
            headers={"WWW-Authenticate": "Bearer"},
        )


async def websocket_require_api_auth(websocket: WebSocket) -> bool:
    settings = get_settings()
    if not settings.auth_enabled:
        return True

    candidate = _extract_bearer_token(websocket.headers.get("authorization"))
    if candidate is None:
        candidate = websocket.query_params.get("access_token")

    if _is_valid_api_token(candidate, settings):
        return True

    await websocket.close(code=4401, reason="Unauthorized")
    return False
