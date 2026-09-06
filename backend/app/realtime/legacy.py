"""Eski WebSocket protokolü (v1) — mağazadaki eski uygulama sürümleri için.

Davranış aynı bırakıldı (düz metin "X"/"O"/"ready" + JSON aktarımı) ancak
şu hatalar giderildi:

  * Kilitlenme: kurucu kurulum mesajını göndermeden ikinci oyuncu bağlanırsa
    her iki taraf da `receive_text()` üzerinde sonsuza kadar bekliyordu; artık
    rol bağlantı sırasına göre veriliyor ve ikinci oyuncu kurulumu bekliyor.
  * Sızıntı: yalnızca `WebSocketDisconnect` yakalandığından başka bir hatada
    oda sözlükte kalıyor, `check_room` "dolu" cevabı vermeye devam ediyordu.
    Temizlik artık `finally` içinde.
  * Yayın: kopmuş bir bağlantı yayını yarıda kesebiliyordu; ölü bağlantılar
    ayıklanıyor.
"""

import asyncio
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_PLAYERS = 2
SETUP_TIMEOUT_SECONDS = 60

active_connections: dict[str, list[WebSocket]] = {}
room_messages: dict[str, str] = {}
_setup_ready: dict[str, asyncio.Event] = {}


def _room_status(room_id: str) -> dict:
    sockets = active_connections.get(room_id)
    if not sockets:
        return {"room_exists": False, "is_joinable": False}
    return {"room_exists": True, "is_joinable": len(sockets) < MAX_PLAYERS}


async def _broadcast(room_id: str, message: str) -> None:
    dead: list[WebSocket] = []
    for connection in list(active_connections.get(room_id, [])):
        try:
            await connection.send_text(message)
        except Exception:
            dead.append(connection)

    for connection in dead:
        sockets = active_connections.get(room_id)
        if sockets and connection in sockets:
            sockets.remove(connection)


def _cleanup(room_id: str, websocket: WebSocket) -> None:
    sockets = active_connections.get(room_id)
    if not sockets:
        return
    if websocket in sockets:
        sockets.remove(websocket)
    if not sockets:
        active_connections.pop(room_id, None)
        room_messages.pop(room_id, None)
        _setup_ready.pop(room_id, None)


@router.get("/check_room/{room_id}")
async def check_room(room_id: str) -> dict:
    """Eski istemcilerin kullandığı oda kontrolü.

    Yeni protokolde açılmış odalar da görünür olsun diye önce yeni kayıt
    defterine bakılır.
    """
    from app.realtime.hub import hub

    status = hub.room_status(room_id)
    if status["room_exists"]:
        return {"room_exists": True, "is_joinable": status["is_joinable"]}
    return _room_status(room_id)


@router.websocket("/ws/{room_id}")
async def websocket_endpoint(websocket: WebSocket, room_id: str) -> None:
    await websocket.accept()

    sockets = active_connections.setdefault(room_id, [])
    if len(sockets) >= MAX_PLAYERS:
        await websocket.close(code=1003)
        return

    sockets.append(websocket)
    is_host = len(sockets) == 1
    ready_event = _setup_ready.setdefault(room_id, asyncio.Event())

    logger.info("v1 oda %s: oyuncu katıldı (%s)", room_id, "host" if is_host else "guest")

    try:
        if is_host:
            setup = await asyncio.wait_for(
                websocket.receive_text(), timeout=SETUP_TIMEOUT_SECONDS
            )
            room_messages[room_id] = setup
            ready_event.set()
            await _broadcast(room_id, setup)
            await websocket.send_text("X")
        else:
            # Kurucu kurulumu göndermemişse bekle — eski sürümdeki kilitlenme buradaydı.
            if not ready_event.is_set():
                await asyncio.wait_for(ready_event.wait(), timeout=SETUP_TIMEOUT_SECONDS)
            await websocket.send_text(room_messages[room_id])
            await websocket.send_text("O")
            await _broadcast(room_id, "ready")

        while True:
            data = await websocket.receive_text()
            await _broadcast(room_id, data)

    except asyncio.TimeoutError:
        logger.warning("v1 oda %s: kurulum zaman aşımı", room_id)
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("v1 oda %s: beklenmeyen hata", room_id)
    finally:
        _cleanup(room_id, websocket)
        await _broadcast(room_id, f"A player has left the room {room_id}.")
