from celery import Celery

from sync_backend.config import get_settings


def create_celery_app() -> Celery:
    settings = get_settings()

    celery_app = Celery("sync_backend")
    celery_app.conf.update(
        broker_url=settings.redis_url,
        result_backend=settings.redis_url,
        task_serializer="json",
        accept_content=["json"],
        result_serializer="json",
        timezone="UTC",
        enable_utc=True,
    )
    return celery_app


celery_app = create_celery_app()
