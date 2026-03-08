from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI

from sync_backend.api.router import build_api_router
from sync_backend.config import get_settings
from sync_backend.logging import configure_logging


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    configure_logging(settings.log_level)
    structlog.get_logger(__name__).info(
        "app.startup",
        environment=settings.app_env,
        debug=settings.debug,
    )
    yield
    structlog.get_logger(__name__).info("app.shutdown")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
    )
    app.include_router(build_api_router(), prefix=settings.api_v1_prefix)
    return app


app = create_app()
