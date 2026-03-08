from fastapi.testclient import TestClient


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
