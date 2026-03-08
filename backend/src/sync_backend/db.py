from functools import lru_cache

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from sync_backend.config import get_settings
from sync_backend.models import Base


def _engine_kwargs(database_url: str) -> dict[str, object]:
    kwargs: dict[str, object] = {"future": True, "pool_pre_ping": True}
    if database_url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
    return kwargs


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    settings = get_settings()
    return create_engine(settings.database_url, **_engine_kwargs(settings.database_url))


@lru_cache(maxsize=1)
def get_session_factory() -> sessionmaker[Session]:
    return sessionmaker(
        bind=get_engine(),
        autoflush=False,
        autocommit=False,
        expire_on_commit=False,
    )


def init_db() -> None:
    Base.metadata.create_all(bind=get_engine())


def reset_db_caches() -> None:
    get_session_factory.cache_clear()
    get_engine.cache_clear()
