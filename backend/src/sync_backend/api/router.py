from fastapi import APIRouter

from sync_backend.api.routes.health import router as health_router
from sync_backend.api.routes.projects import router as projects_router
from sync_backend.api.routes.ws import router as ws_router


def build_api_router() -> APIRouter:
    router = APIRouter()
    router.include_router(health_router, tags=["health"])
    router.include_router(projects_router)
    router.include_router(ws_router)
    return router
