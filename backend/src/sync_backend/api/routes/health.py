from typing import Annotated

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse
from redis import Redis
from redis.exceptions import RedisError
from sqlalchemy import text

from sync_backend.api.dependencies import get_app_settings
from sync_backend.config import Settings
from sync_backend.db import get_engine
from sync_backend.storage import get_object_store

router = APIRouter()


@router.get("/health")
def health(settings: Annotated[Settings, Depends(get_app_settings)]) -> dict[str, str]:
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.app_env,
    }


def _database_ready() -> bool:
    with get_engine().connect() as connection:
        connection.execute(text("SELECT 1"))
    return True


def _redis_ready(settings: Settings) -> bool:
    if settings.app_env == "test":
        return True

    client = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        return bool(client.ping())
    finally:
        client.close()


def _object_store_ready() -> bool:
    get_object_store().ensure_ready()
    return True


@router.get("/ready")
def readiness(
    settings: Annotated[Settings, Depends(get_app_settings)],
) -> JSONResponse:
    checks: dict[str, dict[str, str]] = {}
    overall_ready = True

    for name, check in (
        ("database", _database_ready),
        ("redis", lambda: _redis_ready(settings)),
        ("object_store", _object_store_ready),
    ):
        try:
            check()
            checks[name] = {"status": "ok"}
        except (RedisError, OSError, RuntimeError, ValueError) as exc:
            overall_ready = False
            checks[name] = {"status": "error", "detail": str(exc)}
        except Exception as exc:  # pragma: no cover
            overall_ready = False
            checks[name] = {"status": "error", "detail": str(exc)}

    payload = {
        "status": "ready" if overall_ready else "degraded",
        "service": settings.app_name,
        "environment": settings.app_env,
        "checks": checks,
    }
    return JSONResponse(
        status_code=status.HTTP_200_OK
        if overall_ready
        else status.HTTP_503_SERVICE_UNAVAILABLE,
        content=payload,
    )
