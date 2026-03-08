from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Sync Backend"
    app_env: str = Field(default="development", alias="APP_ENV")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    debug: bool = Field(default=False, alias="DEBUG")
    api_v1_prefix: str = "/v1"
    health_path: str = "/health"

    database_url: str = Field(
        default="postgresql+psycopg://sync:sync@localhost:5432/sync",
        alias="DATABASE_URL",
    )
    redis_url: str = Field(default="redis://localhost:6379/0", alias="REDIS_URL")
    s3_endpoint_url: str = Field(default="http://localhost:9000", alias="S3_ENDPOINT_URL")
    s3_access_key_id: str = Field(default="minioadmin", alias="S3_ACCESS_KEY_ID")
    s3_secret_access_key: str = Field(default="minioadmin", alias="S3_SECRET_ACCESS_KEY")
    s3_bucket: str = Field(default="sync-dev", alias="S3_BUCKET")
    alignment_workdir: str = Field(default="./artifacts", alias="ALIGNMENT_WORKDIR")
    object_store_mode: str = Field(default="filesystem", alias="OBJECT_STORE_MODE")
    ffmpeg_bin: str = Field(default="ffmpeg", alias="FFMPEG_BIN")
    ffprobe_bin: str = Field(default="ffprobe", alias="FFPROBE_BIN")
    audio_chunk_duration_ms: int = Field(default=300_000, alias="AUDIO_CHUNK_DURATION_MS")
    transcriber_provider: str = Field(default="whisperx", alias="TRANSCRIBER_PROVIDER")
    whisper_model_name: str = Field(default="base", alias="WHISPER_MODEL_NAME")
    mock_transcript_text: str = Field(default="call me ishmael", alias="MOCK_TRANSCRIPT_TEXT")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
        populate_by_name=True,
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
