from __future__ import annotations

import asyncio
import contextlib
import json
from collections import defaultdict
from datetime import UTC, datetime
from uuid import UUID

from fastapi import WebSocket
from redis import Redis
from redis import asyncio as redis_async
from redis.exceptions import RedisError

from sync_backend.api.schemas import EventEnvelope
from sync_backend.config import get_settings

CHANNEL_PREFIX = "sync:projects:"


def _channel_name(project_id: str) -> str:
    return f"{CHANNEL_PREFIX}{project_id}"


def _build_envelope(
    *,
    project_id: str,
    event_type: str,
    job_id: str | None,
    payload: dict[str, object],
) -> EventEnvelope:
    return EventEnvelope(
        type=event_type,
        project_id=UUID(project_id),
        job_id=UUID(job_id) if job_id else None,
        timestamp=datetime.now(UTC),
        payload=payload,
    )


def publish_project_event_sync(
    *,
    project_id: str,
    event_type: str,
    job_id: str | None,
    payload: dict[str, object],
) -> None:
    settings = get_settings()
    if settings.app_env == "test":
        return

    envelope = _build_envelope(
        project_id=project_id,
        event_type=event_type,
        job_id=job_id,
        payload=payload,
    )
    try:
        client = Redis.from_url(settings.redis_url, decode_responses=True)
        client.publish(_channel_name(project_id), envelope.model_dump_json())
        client.close()
    except RedisError:
        return


class ProjectEventBroker:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()
        self._listener_task: asyncio.Task[None] | None = None
        self._redis_client: redis_async.Redis | None = None

    async def connect(self, project_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._connections[project_id].add(websocket)

    async def disconnect(self, project_id: str, websocket: WebSocket) -> None:
        async with self._lock:
            listeners = self._connections.get(project_id)
            if listeners is None:
                return
            listeners.discard(websocket)
            if not listeners:
                self._connections.pop(project_id, None)

    async def start(self) -> None:
        settings = get_settings()
        if settings.app_env == "test" or self._listener_task is not None:
            return

        self._redis_client = redis_async.Redis.from_url(
            settings.redis_url,
            decode_responses=True,
        )
        self._listener_task = asyncio.create_task(self._listen_for_events())

    async def stop(self) -> None:
        if self._listener_task is not None:
            self._listener_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._listener_task
            self._listener_task = None

        if self._redis_client is not None:
            await self._redis_client.aclose()
            self._redis_client = None

    async def broadcast(
        self,
        *,
        project_id: str,
        event_type: str,
        job_id: str | None,
        payload: dict[str, object],
    ) -> None:
        envelope = _build_envelope(
            project_id=project_id,
            event_type=event_type,
            job_id=job_id,
            payload=payload,
        )
        if self._listener_task is None or self._redis_client is None:
            await self._broadcast_envelope(envelope)
            return

        try:
            await self._redis_client.publish(
                _channel_name(project_id),
                envelope.model_dump_json(),
            )
        except RedisError:
            await self._broadcast_envelope(envelope)

    async def _broadcast_envelope(self, envelope: EventEnvelope) -> None:
        stale_connections: list[WebSocket] = []
        project_id = str(envelope.project_id)
        async with self._lock:
            listeners = list(self._connections.get(project_id, set()))

        for websocket in listeners:
            try:
                await websocket.send_json(envelope.model_dump(mode="json"))
            except RuntimeError:
                stale_connections.append(websocket)

        for websocket in stale_connections:
            await self.disconnect(project_id, websocket)

    async def _listen_for_events(self) -> None:
        assert self._redis_client is not None
        pubsub = self._redis_client.pubsub()
        await pubsub.psubscribe(f"{CHANNEL_PREFIX}*")
        try:
            while True:
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True,
                    timeout=1.0,
                )
                if message is None:
                    await asyncio.sleep(0.05)
                    continue

                data = message.get("data")
                if not isinstance(data, str):
                    continue
                envelope = EventEnvelope.model_validate(json.loads(data))
                await self._broadcast_envelope(envelope)
        finally:
            with contextlib.suppress(RedisError):
                await pubsub.punsubscribe(f"{CHANNEL_PREFIX}*")
                await pubsub.aclose()

    def reset(self) -> None:
        self._connections.clear()


broker = ProjectEventBroker()
