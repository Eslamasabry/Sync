from fastapi import APIRouter

from sync_backend.api.routes.health import router as health_router


def build_api_router() -> APIRouter:
    router = APIRouter()
    router.include_router(health_router, tags=["health"])
    return router
