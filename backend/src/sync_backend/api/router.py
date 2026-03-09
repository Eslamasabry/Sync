from fastapi import APIRouter, Depends

from sync_backend.api.dependencies import require_api_auth
from sync_backend.api.routes.health import router as health_router
from sync_backend.api.routes.projects import router as projects_router
from sync_backend.api.routes.ws import router as ws_router


def build_api_router() -> APIRouter:
    router = APIRouter()
    router.include_router(health_router, tags=["health"])
    router.include_router(projects_router, dependencies=[Depends(require_api_auth)])
    router.include_router(ws_router)
    return router
