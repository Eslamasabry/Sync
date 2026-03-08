from sync_backend.config import get_settings


def test_settings_read_environment(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("LOG_LEVEL", "debug")

    settings = get_settings()

    assert settings.app_env == "test"
    assert settings.log_level == "debug"
