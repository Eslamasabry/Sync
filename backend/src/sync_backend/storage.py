from __future__ import annotations

import json
from pathlib import Path
from typing import Any, cast

from sync_backend.config import get_settings


class FileObjectStore:
    def __init__(self, base_path: Path) -> None:
        self.base_path = base_path

    def ensure_ready(self) -> None:
        self.base_path.mkdir(parents=True, exist_ok=True)

    def write_bytes(self, relative_path: str, payload: bytes) -> tuple[str, int]:
        target_path = self.base_path / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_bytes(payload)
        return relative_path, len(payload)

    def write_json(self, relative_path: str, payload: dict[str, Any]) -> tuple[str, int]:
        encoded = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        return self.write_bytes(relative_path, encoded)

    def read_json(self, relative_path: str) -> dict[str, Any]:
        target_path = self.base_path / relative_path
        return cast(dict[str, Any], json.loads(target_path.read_text(encoding="utf-8")))

    def absolute_path(self, relative_path: str) -> Path:
        return self.base_path / relative_path


def get_object_store() -> FileObjectStore:
    settings = get_settings()
    return FileObjectStore(Path(settings.alignment_workdir) / "object_store")
