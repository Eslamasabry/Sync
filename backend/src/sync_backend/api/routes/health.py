from collections.abc import Callable
from datetime import UTC, datetime
from time import perf_counter
from typing import Annotated, Any

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


def _utc_now_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


@router.get("/health")
def health(settings: Annotated[Settings, Depends(get_app_settings)]) -> dict[str, str]:
    return {
        "status": "ok",
        "probe": "liveness",
        "service": settings.app_name,
        "environment": settings.app_env,
        "checked_at": _utc_now_iso(),
    }


def _database_ready() -> bool:
    with get_engine().connect() as connection:
        connection.execute(text("SELECT 1"))
    return True


def _redis_ready(settings: Settings) -> bool:
    client = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        return bool(client.ping())
    finally:
        client.close()


def _object_store_ready() -> bool:
    get_object_store().ensure_ready()
    return True


def _run_readiness_check(
    name: str,
    check: Callable[[], Any],
    *,
    critical: bool,
) -> tuple[str, dict[str, Any]]:
    started = perf_counter()
    try:
        result = check()
        latency_ms = round((perf_counter() - started) * 1000, 3)
        payload = result if isinstance(result, dict) else {"status": "ok"}

        payload.setdefault("status", "ok")
        payload["critical"] = critical
        payload["latency_ms"] = latency_ms
        return name, payload
    except (RedisError, OSError, RuntimeError, ValueError) as exc:
        latency_ms = round((perf_counter() - started) * 1000, 3)
        return name, {
            "status": "error",
            "critical": critical,
            "latency_ms": latency_ms,
            "error_type": type(exc).__name__,
            "detail": str(exc),
        }
    except Exception as exc:  # pragma: no cover
        latency_ms = round((perf_counter() - started) * 1000, 3)
        return name, {
            "status": "error",
            "critical": critical,
            "latency_ms": latency_ms,
            "error_type": type(exc).__name__,
            "detail": str(exc),
        }


@router.get("/ready")
def readiness(
    settings: Annotated[Settings, Depends(get_app_settings)],
) -> JSONResponse:
    checks: dict[str, dict[str, Any]] = {}

    def redis_check() -> dict[str, str]:
        if settings.app_env == "test":
            return {
                "status": "skipped",
                "reason": "skipped_in_test_environment",
            }
        if settings.use_inline_job_execution:
            return {
                "status": "skipped",
                "reason": "skipped_in_inline_execution_mode",
            }
        _redis_ready(settings)
        return {"status": "ok"}

    for name, check in (
        ("database", _database_ready),
        ("redis", redis_check),
        ("object_store", _object_store_ready),
    ):
        check_name, result = _run_readiness_check(name, check, critical=True)
        checks[check_name] = result

    overall_ready = not any(
        check["status"] == "error" and check["critical"] for check in checks.values()
    )
    summary = {
        "ready_checks": sum(check["status"] == "ok" for check in checks.values()),
        "skipped_checks": sum(
            check["status"] == "skipped" for check in checks.values()
        ),
        "failed_checks": sum(check["status"] == "error" for check in checks.values()),
    }

    payload = {
        "status": "ready" if overall_ready else "degraded",
        "probe": "readiness",
        "service": settings.app_name,
        "environment": settings.app_env,
        "checked_at": _utc_now_iso(),
        "summary": summary,
        "checks": checks,
    }
    return JSONResponse(
        status_code=status.HTTP_200_OK
        if overall_ready
        else status.HTTP_503_SERVICE_UNAVAILABLE,
        content=payload,
    )
