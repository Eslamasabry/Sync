from __future__ import annotations

import contextlib
import json
import tempfile
from collections.abc import Iterator
from pathlib import Path
from typing import Any, Protocol, cast

from sync_backend.config import get_settings


class ObjectStore(Protocol):
    def ensure_ready(self) -> None: ...

    def exists(self, relative_path: str) -> bool: ...

    def write_bytes(self, relative_path: str, payload: bytes) -> tuple[str, int]: ...

    def write_json(self, relative_path: str, payload: dict[str, Any]) -> tuple[str, int]: ...

    def read_bytes(self, relative_path: str) -> bytes: ...

    def read_json(self, relative_path: str) -> dict[str, Any]: ...

    def iter_bytes(
        self,
        relative_path: str,
        *,
        start: int | None = None,
        end: int | None = None,
        chunk_size: int = 64 * 1024,
    ) -> Iterator[bytes]: ...

    def materialize_file(self, relative_path: str) -> contextlib.AbstractContextManager[Path]: ...


class FileObjectStore:
    def __init__(self, base_path: Path) -> None:
        self.base_path = base_path

    def ensure_ready(self) -> None:
        self.base_path.mkdir(parents=True, exist_ok=True)

    def exists(self, relative_path: str) -> bool:
        return (self.base_path / relative_path).exists()

    def write_bytes(self, relative_path: str, payload: bytes) -> tuple[str, int]:
        target_path = self.base_path / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_bytes(payload)
        return relative_path, len(payload)

    def write_json(self, relative_path: str, payload: dict[str, Any]) -> tuple[str, int]:
        encoded = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        return self.write_bytes(relative_path, encoded)

    def read_bytes(self, relative_path: str) -> bytes:
        target_path = self.base_path / relative_path
        return target_path.read_bytes()

    def read_json(self, relative_path: str) -> dict[str, Any]:
        return cast(dict[str, Any], json.loads(self.read_bytes(relative_path)))

    def iter_bytes(
        self,
        relative_path: str,
        *,
        start: int | None = None,
        end: int | None = None,
        chunk_size: int = 64 * 1024,
    ) -> Iterator[bytes]:
        target_path = self.base_path / relative_path
        with target_path.open("rb") as source_file:
            if start is not None:
                source_file.seek(start)

            remaining = None if end is None else max(0, end - (start or 0) + 1)
            while True:
                if remaining == 0:
                    break
                read_size = chunk_size if remaining is None else min(chunk_size, remaining)
                chunk = source_file.read(read_size)
                if not chunk:
                    break
                if remaining is not None:
                    remaining -= len(chunk)
                yield chunk

    @contextlib.contextmanager
    def materialize_file(self, relative_path: str) -> Iterator[Path]:
        yield self.base_path / relative_path


class S3ObjectStore:
    def __init__(
        self,
        *,
        bucket: str,
        endpoint_url: str | None,
        access_key_id: str,
        secret_access_key: str,
        client: Any | None = None,
    ) -> None:
        self.bucket = bucket
        self.endpoint_url = endpoint_url
        self.access_key_id = access_key_id
        self.secret_access_key = secret_access_key
        self._client = client

    @property
    def client(self) -> Any:
        if self._client is None:
            try:
                import boto3  # type: ignore[import-untyped]
            except ImportError as exc:  # pragma: no cover - exercised in runtime only
                raise RuntimeError(
                    "boto3 is required for OBJECT_STORE_MODE=s3"
                ) from exc
            self._client = boto3.client(
                "s3",
                endpoint_url=self.endpoint_url,
                aws_access_key_id=self.access_key_id,
                aws_secret_access_key=self.secret_access_key,
            )
        return self._client

    def ensure_ready(self) -> None:
        try:
            self.client.head_bucket(Bucket=self.bucket)
        except Exception:
            self.client.create_bucket(Bucket=self.bucket)

    @staticmethod
    def _is_missing_error(exc: Exception) -> bool:
        response = getattr(exc, "response", None)
        error = response.get("Error", {}) if isinstance(response, dict) else {}
        code = str(error.get("Code", "")).lower()
        if isinstance(response, dict):
            status = str(response.get("ResponseMetadata", {}).get("HTTPStatusCode", ""))
        else:
            status = ""
        return code in {"nosuchkey", "404", "notfound"} or status == "404"

    def write_bytes(self, relative_path: str, payload: bytes) -> tuple[str, int]:
        self.client.put_object(Bucket=self.bucket, Key=relative_path, Body=payload)
        return relative_path, len(payload)

    def exists(self, relative_path: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=relative_path)
            return True
        except Exception as exc:
            if self._is_missing_error(exc):
                return False
            raise

    def write_json(self, relative_path: str, payload: dict[str, Any]) -> tuple[str, int]:
        encoded = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        return self.write_bytes(relative_path, encoded)

    def read_bytes(self, relative_path: str) -> bytes:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=relative_path)
        except Exception as exc:
            if self._is_missing_error(exc):
                raise FileNotFoundError(relative_path) from exc
            raise
        return cast(bytes, response["Body"].read())

    def read_json(self, relative_path: str) -> dict[str, Any]:
        return cast(dict[str, Any], json.loads(self.read_bytes(relative_path)))

    def iter_bytes(
        self,
        relative_path: str,
        *,
        start: int | None = None,
        end: int | None = None,
        chunk_size: int = 64 * 1024,
    ) -> Iterator[bytes]:
        kwargs: dict[str, Any] = {"Bucket": self.bucket, "Key": relative_path}
        if start is not None or end is not None:
            range_start = 0 if start is None else start
            range_end = "" if end is None else str(end)
            kwargs["Range"] = f"bytes={range_start}-{range_end}"

        try:
            response = self.client.get_object(**kwargs)
        except Exception as exc:
            if self._is_missing_error(exc):
                raise FileNotFoundError(relative_path) from exc
            raise
        body = response["Body"]
        try:
            yield from body.iter_chunks(chunk_size=chunk_size)
        finally:
            body.close()

    @contextlib.contextmanager
    def materialize_file(self, relative_path: str) -> Iterator[Path]:
        payload = self.read_bytes(relative_path)
        suffix = Path(relative_path).suffix
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as handle:
            handle.write(payload)
            temp_path = Path(handle.name)
        try:
            yield temp_path
        finally:
            temp_path.unlink(missing_ok=True)


def get_object_store() -> ObjectStore:
    settings = get_settings()
    if settings.object_store_mode == "filesystem":
        return FileObjectStore(Path(settings.alignment_workdir) / "object_store")
    if settings.object_store_mode == "s3":
        return S3ObjectStore(
            bucket=settings.s3_bucket,
            endpoint_url=settings.s3_endpoint_url,
            access_key_id=settings.s3_access_key_id,
            secret_access_key=settings.s3_secret_access_key,
        )
    raise ValueError(f"Unsupported OBJECT_STORE_MODE: {settings.object_store_mode}")
