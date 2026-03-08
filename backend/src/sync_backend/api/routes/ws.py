from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from sync_backend.api.realtime import broker

router = APIRouter(tags=["ws"])


@router.websocket("/ws/projects/{project_id}")
async def project_events(project_id: str, websocket: WebSocket) -> None:
    await broker.connect(project_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await broker.disconnect(project_id, websocket)
