from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from sync_backend.api.dependencies import websocket_require_api_auth
from sync_backend.api.realtime import broker

router = APIRouter(tags=["ws"])


@router.websocket("/ws/projects/{project_id}")
async def project_events(project_id: str, websocket: WebSocket) -> None:
    if not await websocket_require_api_auth(websocket):
        return
    await broker.connect(project_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await broker.disconnect(project_id, websocket)
