import math
import struct
import wave
import zipfile
from io import BytesIO
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pytest import MonkeyPatch
from sqlalchemy.exc import IntegrityError
from starlette.websockets import WebSocketDisconnect

from sync_backend.alignment.audio import AudioPreprocessor, PreparedAudioSegment
from sync_backend.alignment.matching_pipeline import build_match_artifact
from sync_backend.alignment.pipeline import run_alignment_job
from sync_backend.alignment.sync_export import build_sync_artifact
from sync_backend.alignment.transcription import StaticTranscriber, TranscriptWord
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.api.realtime import broker
from sync_backend.config import get_settings
from sync_backend.db import get_session_factory, reset_db_caches
from sync_backend.main import create_app
from sync_backend.models import AlignmentJob, Asset, TranscriptArtifact
from sync_backend.services import cancel_job, create_alignment_job
from sync_backend.storage import get_object_store


def make_test_epub_bytes() -> bytes:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr(
            "META-INF/container.xml",
            """<?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>""",
        )
        archive.writestr(
            "OEBPS/content.opf",
            """<?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="bookid">bookid</dc:identifier>
                <dc:title>Test Book</dc:title>
                <dc:language>en</dc:language>
              </metadata>
              <manifest>
                <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chapter1"/>
              </spine>
            </package>""",
        )
        archive.writestr(
            "OEBPS/chapter1.xhtml",
            """<?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Chapter 1</title></head>
              <body>
                <h1>Loomings</h1>
                <p>Call me Ishmael.</p>
                <p>Some years ago never mind how long precisely.</p>
              </body>
            </html>""",
        )
    return buffer.getvalue()


def make_test_wav_bytes(duration_seconds: float = 1.2, sample_rate: int = 16_000) -> bytes:
    frame_count = int(duration_seconds * sample_rate)
    buffer = BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        for frame_index in range(frame_count):
            sample = int(12000 * math.sin((2 * math.pi * 440 * frame_index) / sample_rate))
            wav_file.writeframes(struct.pack("<h", sample))
    return buffer.getvalue()


def upload_test_epub_asset(
    client: TestClient,
    *,
    project_id: str,
    filename: str = "book.epub",
) -> str:
    response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": (filename, make_test_epub_bytes(), "application/epub+zip")},
    )
    assert response.status_code == 201
    payload = response.json()
    return str(payload["asset_id"])


def upload_test_audio_asset(
    client: TestClient,
    *,
    project_id: str,
    filename: str = "audio.wav",
    duration_seconds: float = 1.2,
) -> str:
    response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": (filename, make_test_wav_bytes(duration_seconds), "audio/wav")},
    )
    assert response.status_code == 201
    payload = response.json()
    return str(payload["asset_id"])


def test_project_asset_job_flow(client: TestClient) -> None:
    project_response = client.post(
        "/v1/projects",
        json={"title": "Moby-Dick", "language": "en"},
    )
    assert project_response.status_code == 201
    project_id = project_response.json()["project_id"]

    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="moby-dick.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="moby-dick.wav",
    )

    job_response = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    )
    assert job_response.status_code == 201
    job_id = job_response.json()["job_id"]

    project_detail_response = client.get(f"/v1/projects/{project_id}")
    assert project_detail_response.status_code == 200
    project_detail = project_detail_response.json()
    assert len(project_detail["assets"]) == 2
    assert project_detail["latest_job"]["job_id"] == job_id

    job_detail_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
    assert job_detail_response.status_code == 200
    assert job_detail_response.json()["status"] == "queued"
    assert job_detail_response.json()["attempt_number"] == 1
    assert job_detail_response.json()["retry_of_job_id"] is None


def test_list_projects_returns_latest_first_with_job_summary(client: TestClient) -> None:
    first_project_id = client.post(
        "/v1/projects",
        json={"title": "First Project", "language": "en"},
    ).json()["project_id"]
    second_project_id = client.post(
        "/v1/projects",
        json={"title": "Second Project", "language": "fr"},
    ).json()["project_id"]

    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=second_project_id,
        filename="second.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=second_project_id,
        filename="second.wav",
    )
    client.post(
        f"/v1/projects/{second_project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    )

    response = client.get("/v1/projects")

    assert response.status_code == 200
    payload = response.json()
    assert [project["project_id"] for project in payload["projects"]] == [
        second_project_id,
        first_project_id,
    ]
    assert payload["projects"][0]["title"] == "Second Project"
    assert payload["projects"][0]["audio_asset_count"] == 1
    assert payload["projects"][0]["asset_count"] == 2
    assert payload["projects"][0]["latest_job"]["status"] == "queued"
    assert payload["projects"][1]["latest_job"] is None


def test_project_job_history_is_empty_for_new_project(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Empty History Project", "language": "en"},
    ).json()["project_id"]

    response = client.get(f"/v1/projects/{project_id}/jobs")

    assert response.status_code == 200
    payload = response.json()
    assert payload["project_id"] == project_id
    assert payload["jobs"] == []


def test_project_title_must_include_visible_characters(client: TestClient) -> None:
    response = client.post(
        "/v1/projects",
        json={"title": "   ", "language": "en"},
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "project_title_invalid"


def test_request_validation_errors_use_api_error_envelope(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Validation Project", "language": "en"},
    ).json()["project_id"]

    response = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={"job_type": "alignment", "book_asset_id": str(uuid4()), "audio_asset_ids": []},
    )

    assert response.status_code == 422
    payload = response.json()
    assert payload["error"]["code"] == "request_validation_failed"
    assert payload["error"]["message"] == "The request payload is invalid"
    assert payload["error"]["details"]["errors"][0]["location"] == [
        "body",
        "audio_asset_ids",
    ]


def test_project_job_history_returns_reverse_chronological_jobs(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "History Project", "language": "en"},
    ).json()["project_id"]

    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="history.epub",
    )

    first_audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="history-1.wav",
    )
    second_audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="history-2.wav",
    )

    first_job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [first_audio_asset_id],
        },
    ).json()["job_id"]
    second_job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [second_audio_asset_id],
        },
    ).json()["job_id"]

    response = client.get(f"/v1/projects/{project_id}/jobs")

    assert response.status_code == 200
    payload = response.json()
    assert payload["project_id"] == project_id
    assert [job["job_id"] for job in payload["jobs"]] == [second_job_id, first_job_id]
    assert payload["jobs"][0]["status"] == "queued"
    assert payload["jobs"][0]["progress"] == {"stage": "queued", "percent": 0}
    assert payload["jobs"][0]["request_fingerprint"]
    assert payload["jobs"][0]["attempt_number"] == 1
    assert payload["jobs"][0]["retry_of_job_id"] is None


def test_epub_upload_generates_reader_model(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Upload Project", "language": "en"},
    ).json()["project_id"]

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={
            "file": (
                "book.epub",
                make_test_epub_bytes(),
                "application/epub+zip",
            )
        },
    )

    assert upload_response.status_code == 201
    asset_id = upload_response.json()["asset_id"]

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assets = project_response.json()["assets"]
    assert assets[0]["asset_id"] == asset_id
    assert assets[0]["status"] == "uploaded"
    assert assets[0]["size_bytes"] is not None

    reader_model_response = client.get(f"/v1/projects/{project_id}/reader-model")
    assert reader_model_response.status_code == 200
    reader_model = reader_model_response.json()["model"]
    assert reader_model["title"] == "Test Book"
    assert reader_model["sections"][0]["title"] == "Loomings"
    first_token = reader_model["sections"][0]["paragraphs"][0]["tokens"][0]
    assert first_token["text"] == "Call"
    assert first_token["normalized"] == "call"


def test_invalid_epub_upload_returns_typed_error_and_marks_asset_invalid(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Broken Upload", "language": "en"},
    ).json()["project_id"]

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={
            "file": (
                "broken.epub",
                b"not-a-real-epub",
                "application/epub+zip",
            )
        },
    )

    assert upload_response.status_code == 422
    assert upload_response.json()["error"]["code"] == "epub_processing_failed"

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assets = project_response.json()["assets"]
    assert len(assets) == 1
    assert assets[0]["status"] == "invalid"


def test_uploaded_asset_content_can_be_downloaded(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Asset Download Project", "language": "en"},
    ).json()["project_id"]

    payload = make_test_wav_bytes(duration_seconds=0.25)
    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={
            "file": (
                "clip.wav",
                payload,
                "audio/wav",
            )
        },
    )
    assert upload_response.status_code == 201
    asset_id = upload_response.json()["asset_id"]

    content_response = client.get(f"/v1/projects/{project_id}/assets/{asset_id}/content")
    assert content_response.status_code == 200
    assert content_response.headers["content-type"] == "audio/wav"
    assert content_response.headers["accept-ranges"] == "bytes"
    assert int(content_response.headers["content-length"]) == len(payload)
    assert content_response.content == payload

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    asset = project_response.json()["assets"][0]
    assert asset["download_url"].endswith(
        f"/v1/projects/{project_id}/assets/{asset_id}/content"
    )
    assert asset["size_bytes"] == len(payload)
    assert asset["checksum_sha256"] is not None
    assert asset["duration_ms"] == 250


def test_uploaded_asset_sanitizes_storage_filename_without_changing_visible_name(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Unsafe Filename Project", "language": "en"},
    ).json()["project_id"]

    payload = make_test_wav_bytes(duration_seconds=0.25)
    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={
            "file": (
                "../../nested/../evil clip?.wav",
                payload,
                "audio/wav",
            )
        },
    )

    assert upload_response.status_code == 201
    asset_id = upload_response.json()["asset_id"]

    session_factory = get_session_factory()
    with session_factory() as session:
        asset = session.get(Asset, asset_id)
        assert asset is not None
        assert asset.filename == "../../nested/../evil clip?.wav"
        assert asset.storage_path is not None
        assert "/../" not in asset.storage_path
        assert "\\" not in asset.storage_path
        assert asset.storage_path.endswith("/evil clip_.wav")

    content_response = client.get(f"/v1/projects/{project_id}/assets/{asset_id}/content")
    assert content_response.status_code == 200
    assert content_response.content == payload


def test_download_urls_respect_forwarded_https_headers(monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setenv("PROXY_HEADER_TRUSTED_HOSTS", "*")
    get_settings.cache_clear()
    reset_db_caches()

    with TestClient(create_app()) as client:
        project_id = client.post(
            "/v1/projects",
            json={"title": "Proxy Header Project", "language": "en"},
            headers={
                "host": "sync.example",
                "x-forwarded-proto": "https",
                "x-forwarded-for": "203.0.113.10",
            },
        ).json()["project_id"]

        asset_id = client.post(
            f"/v1/projects/{project_id}/assets/upload",
            data={"kind": "audio"},
            files={"file": ("clip.wav", make_test_wav_bytes(duration_seconds=0.25), "audio/wav")},
            headers={
                "host": "sync.example",
                "x-forwarded-proto": "https",
                "x-forwarded-for": "203.0.113.10",
            },
        ).json()["asset_id"]

        project_response = client.get(
            f"/v1/projects/{project_id}",
            headers={
                "host": "sync.example",
                "x-forwarded-proto": "https",
                "x-forwarded-for": "203.0.113.10",
            },
        )

    assert project_response.status_code == 200
    asset = project_response.json()["assets"][0]
    assert asset["asset_id"] == asset_id
    assert asset["download_url"].startswith("https://sync.example/")


def test_uploaded_asset_supports_byte_range_requests(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Range Project", "language": "en"},
    ).json()["project_id"]

    payload = make_test_wav_bytes(duration_seconds=0.5)
    asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={
            "file": (
                "clip.wav",
                payload,
                "audio/wav",
            )
        },
    ).json()["asset_id"]

    range_response = client.get(
        f"/v1/projects/{project_id}/assets/{asset_id}/content",
        headers={"Range": "bytes=0-31"},
    )
    assert range_response.status_code == 206
    assert range_response.headers["accept-ranges"] == "bytes"
    assert range_response.headers["content-range"] == f"bytes 0-31/{len(payload)}"
    assert range_response.headers["content-length"] == "32"
    assert range_response.content == payload[:32]

    suffix_response = client.get(
        f"/v1/projects/{project_id}/assets/{asset_id}/content",
        headers={"Range": "bytes=-16"},
    )
    assert suffix_response.status_code == 206
    assert suffix_response.content == payload[-16:]


def test_uploaded_asset_rejects_invalid_byte_ranges(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Invalid Range Project", "language": "en"},
    ).json()["project_id"]

    payload = make_test_wav_bytes(duration_seconds=0.5)
    asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={
            "file": (
                "clip.wav",
                payload,
                "audio/wav",
            )
        },
    ).json()["asset_id"]

    invalid_response = client.get(
        f"/v1/projects/{project_id}/assets/{asset_id}/content",
        headers={"Range": f"bytes={len(payload)}-{len(payload) + 10}"},
    )
    assert invalid_response.status_code == 416
    assert invalid_response.json()["error"]["code"] == "asset_range_invalid"


def test_upload_rejects_empty_payload(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Empty Upload Project", "language": "en"},
    ).json()["project_id"]

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("empty.wav", b"", "audio/wav")},
    )

    assert upload_response.status_code == 400
    assert upload_response.json()["error"]["code"] == "asset_empty_upload"


def test_upload_rejects_unreadable_audio_payload(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Broken Audio Project", "language": "en"},
    ).json()["project_id"]

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("broken.mp3", b"not-real-audio", "audio/mpeg")},
    )

    assert upload_response.status_code == 422
    assert upload_response.json()["error"]["code"] == "audio_processing_failed"

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assert project_response.json()["assets"] == []


def test_upload_rejects_payload_that_exceeds_configured_size_limit(
    client: TestClient,
    monkeypatch: MonkeyPatch,
) -> None:
    monkeypatch.setenv("SYNC_UPLOAD_MAX_BYTES", "128")
    project_id = client.post(
        "/v1/projects",
        json={"title": "Limited Upload Project", "language": "en"},
    ).json()["project_id"]

    payload = make_test_wav_bytes(duration_seconds=0.25)
    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("large.wav", payload, "audio/wav")},
    )

    assert upload_response.status_code == 413
    body = upload_response.json()
    assert body["error"]["code"] == "asset_too_large"
    assert body["error"]["details"]["filename"] == "large.wav"
    assert body["error"]["details"]["max_size_bytes"] == 128

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assert project_response.json()["assets"] == []


def test_upload_rejects_filename_that_exceeds_storage_limit(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Long Filename Project", "language": "en"},
    ).json()["project_id"]

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": (f"{'a' * 256}.wav", make_test_wav_bytes(), "audio/wav")},
    )

    assert upload_response.status_code == 400
    assert upload_response.json()["error"]["code"] == "asset_filename_invalid"


def test_upload_storage_failure_returns_typed_api_error(
    client: TestClient,
    monkeypatch: MonkeyPatch,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Storage Failure Project", "language": "en"},
    ).json()["project_id"]

    def explode_store(**_: object) -> object:
        raise RuntimeError("synthetic object-store outage")

    monkeypatch.setattr(
        "sync_backend.api.routes.projects.store_uploaded_asset_from_file",
        explode_store,
    )

    upload_response = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("clip.wav", make_test_wav_bytes(duration_seconds=0.25), "audio/wav")},
    )

    assert upload_response.status_code == 503
    body = upload_response.json()
    assert body["error"]["code"] == "asset_upload_failed"
    assert body["error"]["details"]["filename"] == "clip.wav"
    assert body["error"]["details"]["error_type"] == "RuntimeError"

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assert project_response.json()["assets"] == []


def test_create_job_dispatches_inline_execution_when_configured(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "inline-dispatch.db"
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("JOB_EXECUTION_MODE", "inline")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()

    inline_calls: list[tuple[str, str]] = []

    def record_inline_dispatch(project_id: str, job_id: str) -> None:
        inline_calls.append((project_id, job_id))

    monkeypatch.setattr(
        "sync_backend.api.routes.projects.run_alignment_job_inline",
        record_inline_dispatch,
    )

    with TestClient(create_app()) as inline_client:
        project_id = inline_client.post(
            "/v1/projects",
            json={"title": "Inline Dispatch Project", "language": "en"},
        ).json()["project_id"]

        book_asset_id = upload_test_epub_asset(
            inline_client,
            project_id=project_id,
            filename="book.epub",
        )
        audio_asset_id = upload_test_audio_asset(
            inline_client,
            project_id=project_id,
            filename="book.wav",
        )

        response = inline_client.post(
            f"/v1/projects/{project_id}/jobs",
            json={
                "job_type": "alignment",
                "book_asset_id": book_asset_id,
                "audio_asset_ids": [audio_asset_id],
            },
        )

    assert response.status_code == 201
    job_id = response.json()["job_id"]
    assert inline_calls == [(project_id, job_id)]


def test_create_job_marks_job_failed_when_dispatch_fails(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "dispatch-failure.db"
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("JOB_EXECUTION_MODE", "celery")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()

    def explode_delay(project_id: str, job_id: str) -> None:
        raise RuntimeError(f"broker unavailable for {project_id}/{job_id}")

    monkeypatch.setattr(
        "sync_backend.api.routes.projects.run_alignment_job_task.delay",
        explode_delay,
    )

    with TestClient(create_app()) as dispatch_client:
        project_id = dispatch_client.post(
            "/v1/projects",
            json={"title": "Dispatch Failure Project", "language": "en"},
        ).json()["project_id"]

        book_asset_id = upload_test_epub_asset(
            dispatch_client,
            project_id=project_id,
            filename="dispatch.epub",
        )
        audio_asset_id = upload_test_audio_asset(
            dispatch_client,
            project_id=project_id,
            filename="dispatch.wav",
        )

        response = dispatch_client.post(
            f"/v1/projects/{project_id}/jobs",
            json={
                "job_type": "alignment",
                "book_asset_id": book_asset_id,
                "audio_asset_ids": [audio_asset_id],
            },
        )

        assert response.status_code == 503
        payload = response.json()
        assert payload["error"]["code"] == "job_dispatch_failed"
        assert payload["error"]["details"]["job_id"]

        job_id = payload["error"]["details"]["job_id"]
        job_response = dispatch_client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
        assert job_response.status_code == 200
        assert job_response.json()["status"] == "failed"
        assert job_response.json()["terminal_reason"] == "enqueue_failed"


def test_duplicate_job_request_reuses_existing_job_without_redispatch(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "idempotent-dispatch.db"
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("JOB_EXECUTION_MODE", "inline")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()

    inline_calls: list[tuple[str, str]] = []

    def record_inline_dispatch(project_id: str, job_id: str) -> None:
        inline_calls.append((project_id, job_id))

    monkeypatch.setattr(
        "sync_backend.api.routes.projects.run_alignment_job_inline",
        record_inline_dispatch,
    )

    with TestClient(create_app()) as inline_client:
        project_id = inline_client.post(
            "/v1/projects",
            json={"title": "Idempotent Dispatch Project", "language": "en"},
        ).json()["project_id"]

        book_asset_id = upload_test_epub_asset(
            inline_client,
            project_id=project_id,
            filename="book.epub",
        )
        audio_asset_id = upload_test_audio_asset(
            inline_client,
            project_id=project_id,
            filename="book.wav",
        )

        payload = {
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        }
        first_response = inline_client.post(f"/v1/projects/{project_id}/jobs", json=payload)
        second_response = inline_client.post(f"/v1/projects/{project_id}/jobs", json=payload)

    assert first_response.status_code == 201
    assert second_response.status_code == 201
    assert first_response.json()["reused_existing"] is False
    assert first_response.json()["attempt_number"] == 1
    assert second_response.json()["reused_existing"] is True
    assert second_response.json()["job_id"] == first_response.json()["job_id"]
    assert second_response.json()["attempt_number"] == 1
    assert len(inline_calls) == 1


def test_create_alignment_job_recovers_from_concurrent_insert_conflict(
    client: TestClient,
    monkeypatch: MonkeyPatch,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Concurrent Insert Project", "language": "en"},
    ).json()["project_id"]
    book_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="book.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="book.wav",
    )

    session = get_session_factory()()
    original_commit = session.commit
    conflict_injected = False

    def commit_with_conflict() -> None:
        nonlocal conflict_injected
        if conflict_injected:
            original_commit()
            return

        competing_session = get_session_factory()()
        try:
            create_alignment_job(
                session=competing_session,
                project_id=project_id,
                book_asset_id=book_asset_id,
                audio_asset_ids=[audio_asset_id],
            )
        finally:
            competing_session.close()

        conflict_injected = True
        raise IntegrityError("synthetic concurrent insert conflict", None, Exception("conflict"))

    monkeypatch.setattr(session, "commit", commit_with_conflict)

    try:
        result = create_alignment_job(
            session=session,
            project_id=project_id,
            book_asset_id=book_asset_id,
            audio_asset_ids=[audio_asset_id],
        )
    finally:
        session.close()

    assert result.reused_existing is True
    assert result.job.status == "queued"

    project_jobs = client.get(f"/v1/projects/{project_id}/jobs").json()["jobs"]
    assert len(project_jobs) == 1


def test_failed_job_request_creates_retry_attempt(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Retry Project", "language": "en"},
    ).json()["project_id"]
    book_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="book.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="book.wav",
    )

    payload = {
        "job_type": "alignment",
        "book_asset_id": book_asset_id,
        "audio_asset_ids": [audio_asset_id],
    }
    first_response = client.post(f"/v1/projects/{project_id}/jobs", json=payload)
    first_job_id = first_response.json()["job_id"]

    session = get_session_factory()()
    try:
        first_job = session.get(AlignmentJob, first_job_id)
        assert first_job is not None
        first_job.status = "failed"
        first_job.progress_stage = "failed"
        first_job.terminal_reason = "RuntimeError: transcription exploded"
        session.add(first_job)
        session.commit()
    finally:
        session.close()

    retry_response = client.post(f"/v1/projects/{project_id}/jobs", json=payload)
    retry_job_id = retry_response.json()["job_id"]

    assert retry_response.status_code == 201
    assert retry_response.json()["reused_existing"] is False
    assert retry_job_id != first_job_id
    assert retry_response.json()["attempt_number"] == 2
    assert retry_response.json()["retry_of_job_id"] == first_job_id

    retry_job_response = client.get(f"/v1/projects/{project_id}/jobs/{retry_job_id}")
    assert retry_job_response.status_code == 200
    assert retry_job_response.json()["attempt_number"] == 2
    assert retry_job_response.json()["retry_of_job_id"] == first_job_id

    project_response = client.get(f"/v1/projects/{project_id}")
    assert project_response.status_code == 200
    assert project_response.json()["latest_job"]["job_id"] == retry_job_id


def test_transcription_pipeline_generates_transcript_artifact(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Audio Project", "language": "en"},
    ).json()["project_id"]

    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="book.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="narration.wav",
    )

    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        artifact = transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=500,
            ),
            transcriber=StaticTranscriber("call me ishmael"),
        )
        assert artifact.segment_count >= 2
        assert artifact.word_count >= 6
    finally:
        session.close()

    transcript_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/transcript")
    assert transcript_response.status_code == 200
    payload = transcript_response.json()["payload"]
    assert payload["job_id"] == job_id
    assert len(payload["segments"]) >= 2
    assert payload["segments"][0]["words"][0]["text"] == "call"


def test_transcript_route_distinguishes_missing_job_from_missing_artifact(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Missing Transcript Job Project", "language": "en"},
    ).json()["project_id"]

    response = client.get(f"/v1/projects/{project_id}/jobs/{uuid4()}/transcript")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "job_not_found"


def test_matching_pipeline_generates_match_artifact(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Matching Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=5_000,
            ),
            transcriber=StaticTranscriber("call me ishmael some years ago"),
        )
        artifact = build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
        assert artifact.match_count >= 5
        assert artifact.gap_count == 0
    finally:
        session.close()

    match_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/matches")
    assert match_response.status_code == 200
    payload = match_response.json()["payload"]
    assert payload["match_count"] >= 5
    assert payload["gap_count"] == 0
    assert payload["matches"][0]["location"]["section_id"] == "s1"


def test_match_route_distinguishes_missing_job_from_missing_artifact(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Missing Match Job Project", "language": "en"},
    ).json()["project_id"]

    response = client.get(f"/v1/projects/{project_id}/jobs/{uuid4()}/matches")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "job_not_found"


def test_matching_pipeline_reports_gaps_for_mismatched_words(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Mismatch Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=500,
            ),
            transcriber=StaticTranscriber("mysterious sailor unknown phrase"),
        )
        artifact = build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
        assert artifact.gap_count >= 1
    finally:
        session.close()

    job_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
    assert job_response.status_code == 200
    assert job_response.json()["quality"]["mismatch_ranges"]


def test_sync_export_generates_sync_artifact(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Sync Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=5_000,
            ),
            transcriber=StaticTranscriber("call me ishmael some years ago"),
        )
        build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
        artifact = build_sync_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
        assert artifact.inline_payload is not None
        assert len(artifact.inline_payload["tokens"]) >= 5
    finally:
        session.close()

    sync_response = client.get(f"/v1/projects/{project_id}/sync")
    assert sync_response.status_code == 200
    payload = sync_response.json()["inline_payload"]
    assert payload["book_id"] == project_id
    assert payload["audio"][0]["asset_id"] == audio_asset_id
    assert payload["content_start_ms"] == payload["tokens"][0]["start_ms"]
    assert payload["content_end_ms"] == payload["tokens"][-1]["end_ms"]
    assert payload["tokens"][0]["text"] == "call"
    assert payload["gaps"] == []


def test_artifact_routes_expose_download_urls_and_content(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Artifact Download Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=5_000,
            ),
            transcriber=StaticTranscriber("call me ishmael some years ago"),
        )
        build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
        build_sync_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
    finally:
        session.close()

    reader_model_response = client.get(f"/v1/projects/{project_id}/reader-model")
    transcript_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/transcript")
    match_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/matches")
    sync_response = client.get(f"/v1/projects/{project_id}/sync")

    assert reader_model_response.status_code == 200
    assert transcript_response.status_code == 200
    assert match_response.status_code == 200
    assert sync_response.status_code == 200

    assert reader_model_response.json()["download_url"].endswith(
        f"/v1/projects/{project_id}/reader-model/content"
    )
    assert transcript_response.json()["download_url"].endswith(
        f"/v1/projects/{project_id}/jobs/{job_id}/transcript/content"
    )
    assert match_response.json()["download_url"].endswith(
        f"/v1/projects/{project_id}/jobs/{job_id}/matches/content"
    )
    assert sync_response.json()["download_url"].endswith(
        f"/v1/projects/{project_id}/sync/content"
    )

    reader_model_content = client.get(
        f"/v1/projects/{project_id}/reader-model/content"
    )
    transcript_content = client.get(
        f"/v1/projects/{project_id}/jobs/{job_id}/transcript/content"
    )
    match_content = client.get(
        f"/v1/projects/{project_id}/jobs/{job_id}/matches/content"
    )
    sync_content = client.get(
        f"/v1/projects/{project_id}/sync/content"
    )

    assert reader_model_content.status_code == 200
    assert transcript_content.status_code == 200
    assert match_content.status_code == 200
    assert sync_content.status_code == 200
    assert int(reader_model_content.headers["content-length"]) > 0
    assert int(transcript_content.headers["content-length"]) > 0
    assert int(match_content.headers["content-length"]) > 0
    assert int(sync_content.headers["content-length"]) > 0
    assert reader_model_content.headers["accept-ranges"] == "bytes"
    assert transcript_content.headers["accept-ranges"] == "bytes"
    assert match_content.headers["accept-ranges"] == "bytes"
    assert sync_content.headers["accept-ranges"] == "bytes"

    assert reader_model_content.json()["book_id"] == project_id
    assert transcript_content.json()["job_id"] == job_id
    assert match_content.json()["match_count"] >= 5
    assert sync_content.json()["book_id"] == project_id


def test_sync_route_distinguishes_missing_project_from_missing_artifact(
    client: TestClient,
) -> None:
    response = client.get(f"/v1/projects/{uuid4()}/sync")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "project_not_found"


def test_artifact_routes_return_typed_error_when_blob_is_missing(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Missing Blob Project", "language": "en"},
    ).json()["project_id"]

    upload_test_epub_asset(client, project_id=project_id, filename="book.epub")
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="narration.wav",
    )

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=500,
            ),
            transcriber=StaticTranscriber("call me ishmael"),
        )
        transcript_artifact = session.query(TranscriptArtifact).filter_by(job_id=job_id).one()
        with get_object_store().materialize_file(transcript_artifact.storage_path) as blob_path:
            blob_path.unlink()
    finally:
        session.close()

    transcript_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/transcript")
    transcript_content_response = client.get(
        f"/v1/projects/{project_id}/jobs/{job_id}/transcript/content"
    )

    assert transcript_response.status_code == 409
    assert transcript_content_response.status_code == 409
    assert transcript_response.json()["error"]["code"] == "artifact_content_missing"
    assert transcript_content_response.json()["error"]["code"] == "artifact_content_missing"


def test_alignment_pipeline_completes_job_and_offsets_multiple_audio_assets(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Multipart Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    first_audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("part1.wav", make_test_wav_bytes(duration_seconds=0.6), "audio/wav")},
    ).json()["asset_id"]
    second_audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("part2.wav", make_test_wav_bytes(duration_seconds=0.6), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [first_audio_asset_id, second_audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        run_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=400,
            ),
            transcriber=StaticTranscriber("call me ishmael some years ago"),
        )
    finally:
        session.close()

    job_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
    assert job_response.status_code == 200
    assert job_response.json()["status"] == "completed"
    assert job_response.json()["progress"]["percent"] == 100
    assert job_response.json()["terminal_reason"] is None

    sync_payload = client.get(f"/v1/projects/{project_id}/sync").json()["inline_payload"]
    assert len(sync_payload["audio"]) == 2
    assert sync_payload["audio"][0]["asset_id"] == first_audio_asset_id
    assert sync_payload["audio"][1]["asset_id"] == second_audio_asset_id
    assert sync_payload["audio"][1]["offset_ms"] >= sync_payload["audio"][0]["duration_ms"]
    assert sync_payload["tokens"][-1]["end_ms"] > sync_payload["tokens"][0]["start_ms"]


def test_job_creation_requires_epub_asset(client: TestClient) -> None:
    project_id = client.post("/v1/projects", json={"title": "Bad Project"}).json()["project_id"]
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "audio",
            "filename": "track.mp3",
            "content_type": "audio/mpeg",
        },
    ).json()["asset_id"]

    response = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": audio_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "asset_missing"


def test_job_creation_requires_uploaded_assets(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Pending Upload Project"},
    ).json()["project_id"]
    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="track.wav",
    )

    response = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "asset_not_ready"
    assert response.json()["error"]["details"]["role"] == "book"


def test_job_events_stream_over_websocket(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Realtime Project"},
    ).json()["project_id"]
    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="book.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="book.wav",
    )

    with client.websocket_connect(f"/v1/ws/projects/{project_id}") as websocket:
        create_response = client.post(
            f"/v1/projects/{project_id}/jobs",
            json={
                "job_type": "alignment",
                "book_asset_id": epub_asset_id,
                "audio_asset_ids": [audio_asset_id],
            },
        )
        job_id = create_response.json()["job_id"]
        queued_event = websocket.receive_json()
        assert queued_event["type"] == "job.queued"
        assert queued_event["job_id"] == job_id

        cancel_response = client.post(f"/v1/projects/{project_id}/jobs/{job_id}/cancel")
        assert cancel_response.status_code == 200
        cancelled_event = websocket.receive_json()
        assert cancelled_event["type"] == "job.cancelled"
        assert cancelled_event["job_id"] == job_id


def test_project_websocket_requires_auth_when_configured(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    database_path = tmp_path / "ws-auth.db"
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("API_AUTH_TOKEN", "secret-token")
    monkeypatch.setenv("DATABASE_URL", f"sqlite+pysqlite:///{database_path}")
    monkeypatch.setenv("ALIGNMENT_WORKDIR", str(tmp_path / "artifacts"))
    get_settings.cache_clear()
    reset_db_caches()
    broker.reset()

    with TestClient(create_app()) as auth_client:
        project_id = auth_client.post(
            "/v1/projects",
            headers={"Authorization": "Bearer secret-token"},
            json={"title": "Realtime Auth Project"},
        ).json()["project_id"]
        epub_asset_id = auth_client.post(
            f"/v1/projects/{project_id}/assets/upload",
            headers={"Authorization": "Bearer secret-token"},
            data={"kind": "epub"},
            files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
        ).json()["asset_id"]
        audio_asset_id = auth_client.post(
            f"/v1/projects/{project_id}/assets/upload",
            headers={"Authorization": "Bearer secret-token"},
            data={"kind": "audio"},
            files={"file": ("book.wav", make_test_wav_bytes(), "audio/wav")},
        ).json()["asset_id"]

        with pytest.raises(WebSocketDisconnect), auth_client.websocket_connect(
            f"/v1/ws/projects/{project_id}"
        ):
            pass

        with auth_client.websocket_connect(
            f"/v1/ws/projects/{project_id}?access_token=secret-token"
        ) as websocket:
            create_response = auth_client.post(
                f"/v1/projects/{project_id}/jobs",
                headers={"Authorization": "Bearer secret-token"},
                json={
                    "job_type": "alignment",
                    "book_asset_id": epub_asset_id,
                    "audio_asset_ids": [audio_asset_id],
                },
            )
            job_id = create_response.json()["job_id"]
            queued_event = websocket.receive_json()
            assert queued_event["type"] == "job.queued"
            assert queued_event["job_id"] == job_id


def test_cancel_job_is_idempotent_for_already_cancelled_job(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Cancel Idempotency Project"},
    ).json()["project_id"]
    epub_asset_id = upload_test_epub_asset(
        client,
        project_id=project_id,
        filename="book.epub",
    )
    audio_asset_id = upload_test_audio_asset(
        client,
        project_id=project_id,
        filename="book.wav",
    )

    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    first_cancel_response = client.post(f"/v1/projects/{project_id}/jobs/{job_id}/cancel")
    second_cancel_response = client.post(f"/v1/projects/{project_id}/jobs/{job_id}/cancel")

    assert first_cancel_response.status_code == 200
    assert second_cancel_response.status_code == 200
    assert second_cancel_response.json()["status"] == "cancelled"


def test_cancelled_job_does_not_finish_pipeline_or_emit_artifacts(client: TestClient) -> None:
    class CancellingTranscriber:
        def __init__(self, *, project_id: str, job_id: str) -> None:
            self.project_id = project_id
            self.job_id = job_id
            self._cancelled = False

        def set_preferred_language(self, language: str | None) -> None:
            return

        def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]:
            if not self._cancelled:
                session = get_session_factory()()
                try:
                    cancel_job(
                        session=session,
                        project_id=self.project_id,
                        job_id=self.job_id,
                    )
                finally:
                    session.close()
                self._cancelled = True
            return [
                TranscriptWord(
                    text="call",
                    start_ms=0,
                    end_ms=min(100, segment.duration_ms),
                    confidence=0.9,
                )
            ]

    project_id = client.post(
        "/v1/projects",
        json={"title": "Cancellation Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        run_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=400,
            ),
            transcriber=CancellingTranscriber(project_id=project_id, job_id=job_id),
        )
    finally:
        session.close()

    job_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
    assert job_response.status_code == 200
    assert job_response.json()["status"] == "cancelled"
    assert job_response.json()["terminal_reason"] == "cancelled_by_request"

    transcript_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/transcript")
    match_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/matches")
    sync_response = client.get(f"/v1/projects/{project_id}/sync")

    assert transcript_response.status_code == 404
    assert match_response.status_code == 404
    assert sync_response.status_code == 404


def test_failed_alignment_job_persists_terminal_reason(client: TestClient) -> None:
    class FailingTranscriber:
        def set_preferred_language(self, language: str | None) -> None:
            return

        def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]:
            raise RuntimeError("synthetic transcription failure")

    project_id = client.post(
        "/v1/projects",
        json={"title": "Failure Reason Project", "language": "en"},
    ).json()["project_id"]

    client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "epub"},
        files={"file": ("book.epub", make_test_epub_bytes(), "application/epub+zip")},
    )
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("narration.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    project_detail = client.get(f"/v1/projects/{project_id}").json()
    book_asset_id = next(
        asset["asset_id"] for asset in project_detail["assets"] if asset["kind"] == "epub"
    )
    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": book_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        try:
            run_alignment_job(
                session=session,
                project_id=project_id,
                job_id=job_id,
                object_store=get_object_store(),
                preprocessor=AudioPreprocessor(
                    object_store=get_object_store(),
                    ffmpeg_bin=settings.ffmpeg_bin,
                    ffprobe_bin=settings.ffprobe_bin,
                    chunk_duration_ms=400,
                ),
                transcriber=FailingTranscriber(),
            )
        except RuntimeError as exc:
            assert str(exc) == "synthetic transcription failure"
    finally:
        session.close()

    job_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}")
    assert job_response.status_code == 200
    assert job_response.json()["status"] == "failed"
    assert job_response.json()["terminal_reason"] == "RuntimeError: synthetic transcription failure"
