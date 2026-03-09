from pytest import MonkeyPatch

from sync_backend.config import get_settings


def test_settings_read_environment(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("LOG_LEVEL", "debug")
    monkeypatch.setenv("JOB_EXECUTION_MODE", "inline")
    monkeypatch.setenv("API_AUTH_TOKEN", "secret-token")

    settings = get_settings()

    assert settings.app_env == "test"
    assert settings.log_level == "debug"
    assert settings.use_inline_job_execution is True
    assert settings.auth_enabled is True
