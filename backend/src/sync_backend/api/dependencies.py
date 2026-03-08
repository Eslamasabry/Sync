from collections.abc import Generator

from sqlalchemy.orm import Session

from sync_backend.config import Settings, get_settings
from sync_backend.db import get_session_factory


def get_app_settings() -> Settings:
    return get_settings()


def get_db_session() -> Generator[Session, None, None]:
    session = get_session_factory()()
    try:
        yield session
    finally:
        session.close()
