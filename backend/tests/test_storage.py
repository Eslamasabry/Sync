from collections.abc import Iterator
from pathlib import Path

from sync_backend.storage import FileObjectStore, S3ObjectStore


class _FakeStreamingBody:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload
        self.closed = False

    def read(self) -> bytes:
        return self.payload

    def iter_chunks(self, *, chunk_size: int) -> Iterator[bytes]:
        for index in range(0, len(self.payload), chunk_size):
            yield self.payload[index:index + chunk_size]

    def close(self) -> None:
        self.closed = True


class _FakeS3Client:
    def __init__(self) -> None:
        self.buckets: set[str] = set()
        self.objects: dict[tuple[str, str], bytes] = {}

    def head_bucket(self, **kwargs: str) -> None:
        bucket = kwargs["Bucket"]
        if bucket not in self.buckets:
            raise RuntimeError("missing bucket")

    def create_bucket(self, **kwargs: str) -> None:
        self.buckets.add(kwargs["Bucket"])

    def put_object(self, **kwargs: object) -> None:
        bucket = kwargs["Bucket"]
        key = kwargs["Key"]
        body = kwargs["Body"]
        assert isinstance(bucket, str)
        assert isinstance(key, str)
        assert isinstance(body, bytes)
        self.buckets.add(bucket)
        self.objects[(bucket, key)] = body

    def get_object(self, **kwargs: str) -> dict[str, _FakeStreamingBody]:
        bucket = kwargs["Bucket"]
        key = kwargs["Key"]
        return {"Body": _FakeStreamingBody(self.objects[(bucket, key)])}


def test_file_object_store_round_trips_bytes_json_and_materialized_file(
    tmp_path: Path,
) -> None:
    store = FileObjectStore(tmp_path / "object_store")
    store.ensure_ready()

    storage_path, size_bytes = store.write_bytes("projects/demo/audio.bin", b"abcdef")
    json_path, json_size = store.write_json("projects/demo/meta.json", {"book_id": "demo"})

    assert size_bytes == 6
    assert json_size > 0
    assert store.read_bytes(storage_path) == b"abcdef"
    assert store.read_json(json_path) == {"book_id": "demo"}
    assert list(store.iter_bytes(storage_path, chunk_size=2)) == [b"ab", b"cd", b"ef"]

    with store.materialize_file(storage_path) as path:
        assert path.exists()
        assert path.read_bytes() == b"abcdef"


def test_s3_object_store_round_trips_bytes_json_chunks_and_materialized_file() -> None:
    fake_client = _FakeS3Client()
    store = S3ObjectStore(
        bucket="sync-dev",
        endpoint_url="http://localhost:9000",
        access_key_id="minioadmin",
        secret_access_key="minioadmin",
        client=fake_client,
    )

    store.ensure_ready()
    storage_path, size_bytes = store.write_bytes("projects/demo/audio.bin", b"abcdef")
    json_path, _ = store.write_json("projects/demo/meta.json", {"book_id": "demo"})

    assert "sync-dev" in fake_client.buckets
    assert size_bytes == 6
    assert store.read_bytes(storage_path) == b"abcdef"
    assert store.read_json(json_path) == {"book_id": "demo"}
    assert list(store.iter_bytes(storage_path, chunk_size=4)) == [b"abcd", b"ef"]

    materialized_path: Path | None = None
    with store.materialize_file(storage_path) as path:
        materialized_path = path
        assert path.exists()
        assert path.read_bytes() == b"abcdef"

    assert materialized_path is not None
    assert not materialized_path.exists()
