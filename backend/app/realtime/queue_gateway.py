"""Hızlı eşleşme WebSocket'i.

    ws://.../ws/queue?name=Bahri&mode=last_letter

Bağlantı açık kaldığı sürece oyuncu kuyruktadır. Eşleşme olunca oda kodu
gönderilir ve bağlantı kapanır; istemci sıradan oda akışına geçer.
Bağlantı koparsa oyuncu kuyruktan kendiliğinden düşer — hayalet eşleşme
olmaz.
"""

import asyncio
import json
import logging

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.realtime.matchmaking import WAIT_HINT_SECONDS, matchmaker
from app.realtime.protocol import ErrorCode, GameMode, ServerMessage, error
from app.services import mode_service

logger = logging.getLogger(__name__)

router = APIRouter()

CLOSE_MODE_UNKNOWN = 4005
CLOSE_TIMEOUT = 4009


@router.websocket("/ws/queue")
async def queue_socket(
    websocket: WebSocket,
    name: str = Query(default=""),
    mode: str = Query(default=""),
) -> None:
    await websocket.accept()

    try:
        resolved = GameMode(mode)
    except ValueError:
        await websocket.send_text(json.dumps(
            error(ErrorCode.MODE_UNKNOWN, "Bu modu tanımıyorum, uygulamayı güncelle.")))
        await websocket.close(code=CLOSE_MODE_UNKNOWN)
        return

    if not mode_service.is_enabled(resolved.value):
        await websocket.send_text(json.dumps(
            error(ErrorCode.MODE_DISABLED, "Bu mod şu an kapalı.")))
        await websocket.close(code=CLOSE_MODE_UNKNOWN)
        return

    entry = await matchmaker.enqueue(websocket, name, resolved.value)

    await websocket.send_text(json.dumps({
        "type": ServerMessage.EVENT,
        "event": "queued",
        "mode": resolved.value,
    }))

    # İki iş paralel: eşleşmeyi beklemek ve bağlantının kopmasını fark etmek.
    waiter = asyncio.create_task(entry.event.wait())
    watcher = asyncio.create_task(_watch_disconnect(websocket))
    hint_sent = False

    try:
        while True:
            done, _ = await asyncio.wait(
                {waiter, watcher},
                timeout=WAIT_HINT_SECONDS,
                return_when=asyncio.FIRST_COMPLETED,
            )

            if watcher in done:
                return  # istemci kapattı

            if waiter in done:
                if entry.matched_code:
                    await websocket.send_text(json.dumps({
                        "type": ServerMessage.EVENT,
                        "event": "matched",
                        "code": entry.matched_code,
                        "mode": resolved.value,
                    }))
                else:
                    # Süre doldu, eşleşme olmadı.
                    await websocket.send_text(json.dumps({
                        "type": ServerMessage.EVENT,
                        "event": "queue_timeout",
                    }))
                    await websocket.close(code=CLOSE_TIMEOUT)
                return

            if not hint_sent:
                # Sessiz bekleme uygulamanın donduğu izlenimi veriyor.
                hint_sent = True
                counts = await matchmaker.waiting_count(resolved.value)
                await websocket.send_text(json.dumps({
                    "type": ServerMessage.EVENT,
                    "event": "still_waiting",
                    "waiting": counts.get(resolved.value, 0),
                }))
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("Kuyruk soketi hatasi")
    finally:
        for task in (waiter, watcher):
            if not task.done():
                task.cancel()
        await matchmaker.cancel(entry)
        try:
            await websocket.close()
        except Exception:
            pass


async def _watch_disconnect(websocket: WebSocket) -> None:
    """İstemciden mesaj beklemek kopmayı fark etmenin en güvenilir yolu."""
    try:
        while True:
            await websocket.receive_text()
    except Exception:
        return
