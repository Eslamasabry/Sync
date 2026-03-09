from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Sync Backend"
    app_env: str = Field(default="development", alias="APP_ENV")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    debug: bool = Field(default=False, alias="DEBUG")
    enable_gzip: bool = Field(default=True, alias="ENABLE_GZIP")
    gzip_minimum_size: int = Field(default=500, alias="GZIP_MINIMUM_SIZE")
    api_v1_prefix: str = "/v1"
    health_path: str = "/health"

    database_url: str = Field(
        default="postgresql+psycopg://sync:sync@localhost:5432/sync",
        alias="DATABASE_URL",
    )
    redis_url: str = Field(default="redis://localhost:6379/0", alias="REDIS_URL")
    job_execution_mode: str = Field(default="celery", alias="JOB_EXECUTION_MODE")
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
    cors_allow_origins: str = Field(default="", alias="CORS_ALLOW_ORIGINS")
    cors_allow_origin_regex: str = Field(default="", alias="CORS_ALLOW_ORIGIN_REGEX")
    cors_allow_methods: str = Field(
        default="GET,POST,PUT,PATCH,DELETE,OPTIONS",
        alias="CORS_ALLOW_METHODS",
    )
    cors_allow_headers: str = Field(
        default="Authorization,Content-Type,Accept,Origin",
        alias="CORS_ALLOW_HEADERS",
    )
    cors_allow_credentials: bool = Field(default=False, alias="CORS_ALLOW_CREDENTIALS")
    trusted_hosts: str = Field(default="", alias="TRUSTED_HOSTS")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
        populate_by_name=True,
    )

    @property
    def cors_origins(self) -> list[str]:
        return _parse_csv_env(self.cors_allow_origins)

    @property
    def cors_methods(self) -> list[str]:
        values = _parse_csv_env(self.cors_allow_methods)
        return values or ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    @property
    def cors_headers(self) -> list[str]:
        values = _parse_csv_env(self.cors_allow_headers)
        return values or ["Authorization", "Content-Type", "Accept", "Origin"]

    @property
    def cors_origin_regex(self) -> str | None:
        value = self.cors_allow_origin_regex.strip()
        return value or None

    @property
    def trusted_host_values(self) -> list[str]:
        return _parse_csv_env(self.trusted_hosts)

    @property
    def use_inline_job_execution(self) -> bool:
        return self.job_execution_mode.strip().lower() == "inline"


def _parse_csv_env(raw_value: str) -> list[str]:
    return [value.strip() for value in raw_value.split(",") if value.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
