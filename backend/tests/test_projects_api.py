import math
import struct
import wave
import zipfile
from io import BytesIO

from fastapi.testclient import TestClient

from sync_backend.alignment.audio import AudioPreprocessor
from sync_backend.alignment.transcription import StaticTranscriber
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.config import get_settings
from sync_backend.db import get_session_factory
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


def test_project_asset_job_flow(client: TestClient) -> None:
    project_response = client.post(
        "/v1/projects",
        json={"title": "Moby-Dick", "language": "en"},
    )
    assert project_response.status_code == 201
    project_id = project_response.json()["project_id"]

    epub_response = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "moby-dick.epub",
            "content_type": "application/epub+zip",
        },
    )
    assert epub_response.status_code == 201
    epub_asset_id = epub_response.json()["asset_id"]

    audio_response = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "audio",
            "filename": "moby-dick.mp3",
            "content_type": "audio/mpeg",
        },
    )
    assert audio_response.status_code == 201
    audio_asset_id = audio_response.json()["asset_id"]

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


def test_transcription_pipeline_generates_transcript_artifact(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Audio Project", "language": "en"},
    ).json()["project_id"]

    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]

    audio_upload = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={
            "file": (
                "narration.wav",
                make_test_wav_bytes(),
                "audio/wav",
            )
        },
    )
    assert audio_upload.status_code == 201
    audio_asset_id = audio_upload.json()["asset_id"]

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


def test_job_events_stream_over_websocket(client: TestClient) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Realtime Project"},
    ).json()["project_id"]
    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]
    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "audio",
            "filename": "book.mp3",
            "content_type": "audio/mpeg",
        },
    ).json()["asset_id"]

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
