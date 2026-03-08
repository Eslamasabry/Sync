from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI

from sync_backend.api.errors import ApiError, api_error_handler
from sync_backend.api.realtime import broker
from sync_backend.api.router import build_api_router
from sync_backend.config import get_settings
from sync_backend.db import init_db
from sync_backend.logging import configure_logging
from sync_backend.storage import get_object_store


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    configure_logging(settings.log_level)
    init_db()
    get_object_store().ensure_ready()
    await broker.start()
    structlog.get_logger(__name__).info(
        "app.startup",
        environment=settings.app_env,
        debug=settings.debug,
    )
    yield
    await broker.stop()
    structlog.get_logger(__name__).info("app.shutdown")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
    )
    app.add_exception_handler(ApiError, api_error_handler)
    app.include_router(build_api_router(), prefix=settings.api_v1_prefix)
    return app


app = create_app()
