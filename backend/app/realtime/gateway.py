"""WebSocket uç noktası (protokol v2)."""

import asyncio
import json
import logging

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.core.config import settings
from app.realtime.hub import ModeMismatch, RoomFull, RoomNotFound, hub
from app.realtime.protocol import ClientMessage, ErrorCode, ServerMessage, error

logger = logging.getLogger(__name__)
router = APIRouter()

# Bağlantı kapatma kodları
CLOSE_ROOM_FULL = 4001
CLOSE_ROOM_NOT_FOUND = 4004
CLOSE_MODE_MISMATCH = 4005
CLOSE_IDLE = 4008


@router.websocket("/ws/v2/{code}")
async def websocket_v2(
    websocket: WebSocket,
    code: str,
    name: str = Query(default=""),
    mode: str = Query(default=""),
    token: str = Query(default=""),
) -> None:
    await websocket.accept()

    try:
        room, player, resumed = await hub.join(
            code, websocket, name, mode or None, token or None
        )
    except RoomFull:
        await websocket.send_text(json.dumps(
            error(ErrorCode.ROOM_FULL, "Bu odada zaten iki oyuncu var.")))
        await websocket.close(code=CLOSE_ROOM_FULL)
        return
    except RoomNotFound:
        await websocket.send_text(json.dumps(
            error(ErrorCode.ROOM_NOT_FOUND, "Oda bulunamadı.")))
        await websocket.close(code=CLOSE_ROOM_NOT_FOUND)
        return
    except ModeMismatch as exc:
        await websocket.send_text(json.dumps(
            error(ErrorCode.MODE_MISMATCH, f"Bu oda '{exc.expected}' modunda oynanıyor.")))
        await websocket.close(code=CLOSE_MODE_MISMATCH)
        return

    logger.info(
        "Oda %s: %s (slot %s) %s",
        code, player.name, player.slot, "geri döndü" if resumed else "katıldı",
    )

    await player.send({
        "type": ServerMessage.JOINED,
        "you": player.public(),
        "room": room.snapshot(),
        # İstemci bunu saklar ve kopma sonrası `?token=` ile geri döner.
        "token": player.token,
        "resumed": resumed,
    })
    await room.send_room_state()

    # Ayrıldı bildirimi yalnızca oyuncu gerçekten çıktığında gider; kopmalarda
    # yer tolerans süresi boyunca korunur.
    left_for_good = False

    try:
        if resumed:
            # Geri dönen oyuncuya güncel oyun durumu yeniden yollanır, yoksa
            # boş bir ekranla kalıyordu.
            await room.broadcast({
                "type": ServerMessage.EVENT,
                "event": "opponent_reconnected",
                "slot": player.slot,
                "name": player.name,
            })
            if room.engine:
                await room.engine.resend_state(player)
        elif room.is_full and room.engine is None:
            engine = hub.build_engine(room)
            await engine.start()

        left_for_good = await _message_loop(room, player)

    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("Oda %s WebSocket döngüsünde hata", code)
    finally:
        if left_for_good:
            await hub.leave(room, player)
            await room.broadcast({
                "type": ServerMessage.OPPONENT_LEFT,
                "slot": player.slot,
                "name": player.name,
            })
            await room.send_room_state()
            logger.info("Oda %s: %s ayrıldı", code, player.name)
        else:
            # Beklenmedik kopma: yer korunur, rakibe "bekleniyor" denir.
            await hub.mark_disconnected(room, player)
            await room.broadcast({
                "type": ServerMessage.EVENT,
                "event": "opponent_disconnected",
                "slot": player.slot,
                "name": player.name,
                "grace_seconds": settings.RECONNECT_GRACE_SECONDS,
            })
            await room.send_room_state()
            logger.info("Oda %s: %s bağlantısı koptu, bekleniyor", code, player.name)


async def _message_loop(room, player) -> bool:
    """Döngü biter; oyuncunun bilerek çıkıp çıkmadığını döndürür.

    Boşta kalma zaman aşımı bilerek çıkış SAYILMAZ: mobil şebekede bağlantı
    kopunca TCP çoğu zaman kapanmadan asılı kalır ve akış tam bu yoldan
    düşer. Bunu "ayrıldı" saymak, kısa bir kopmada oyuncunun yerini anında
    kaybetmesine yol açıyordu.
    """
    while True:
        try:
            raw = await asyncio.wait_for(
                player.socket.receive_text(),
                timeout=settings.WS_IDLE_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            # İstemci uzun süredir sessiz: soketi kapat ama yerini koru.
            try:
                await player.socket.close(code=CLOSE_IDLE)
            except Exception:
                pass
            return False

        try:
            message = json.loads(raw)
            if not isinstance(message, dict):
                raise ValueError
        except (json.JSONDecodeError, ValueError):
            await player.send(error(ErrorCode.INVALID_MESSAGE, "Geçersiz mesaj biçimi."))
            continue

        message_type = message.get("type")

        if message_type == ClientMessage.PING:
            await player.send({"type": ServerMessage.PONG})

        elif message_type == ClientMessage.LEAVE:
            return True

        elif message_type == ClientMessage.RELAY:
            if room.engine:
                await room.engine.handle_relay(player, message.get("data", {}))

        elif message_type == ClientMessage.ACTION:
            if room.engine:
                await room.engine.handle_action(player, message)
            else:
                await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Oyun henüz başlamadı."))

        elif message_type == ClientMessage.REMATCH:
            await _handle_rematch(room, player)

        elif message_type == ClientMessage.READY:
            await room.send_room_state()

        else:
            await player.send(error(ErrorCode.INVALID_MESSAGE, f"Bilinmeyen tip: {message_type}"))


async def _handle_rematch(room, player) -> None:
    """İki oyuncu da rövanş isterse motor sıfırdan kurulur."""
    room.settings.setdefault("_rematch_votes", set())
    votes: set = room.settings["_rematch_votes"]
    votes.add(player.slot)

    await room.broadcast({
        "type": ServerMessage.EVENT,
        "event": "rematch_vote",
        "slot": player.slot,
        "votes": sorted(votes),
    })

    if len(votes) < 2:
        return

    votes.clear()
    if room.engine:
        await room.engine.stop()
    for participant in room.players:
        participant.score = 0

    engine = hub.build_engine(room)
    await engine.start()
