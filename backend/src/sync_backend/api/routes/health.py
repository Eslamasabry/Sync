from typing import Annotated

from fastapi import APIRouter, Depends

from sync_backend.api.dependencies import get_app_settings
from sync_backend.config import Settings

router = APIRouter()


@router.get("/health")
def health(settings: Annotated[Settings, Depends(get_app_settings)]) -> dict[str, str]:
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.app_env,
    }
