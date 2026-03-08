from __future__ import annotations

import asyncio
from collections import defaultdict
from datetime import UTC, datetime
from uuid import UUID

from fastapi import WebSocket

from sync_backend.api.schemas import EventEnvelope


class ProjectEventBroker:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()

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

    async def broadcast(
        self,
        *,
        project_id: str,
        event_type: str,
        job_id: str | None,
        payload: dict[str, object],
    ) -> None:
        envelope = EventEnvelope(
            type=event_type,
            project_id=UUID(project_id),
            job_id=UUID(job_id) if job_id else None,
            timestamp=datetime.now(UTC),
            payload=payload,
        )
        stale_connections: list[WebSocket] = []
        async with self._lock:
            listeners = list(self._connections.get(project_id, set()))

        for websocket in listeners:
            try:
                await websocket.send_json(envelope.model_dump(mode="json"))
            except RuntimeError:
                stale_connections.append(websocket)

        for websocket in stale_connections:
            await self.disconnect(project_id, websocket)

    def reset(self) -> None:
        self._connections.clear()


broker = ProjectEventBroker()
