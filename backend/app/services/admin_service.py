"""Yönetim paneli için sunucu içi görünüm ve duyurular.

Panel tarayıcıda çalışan tek bir HTML; buradaki fonksiyonlar onun
sorduğu soruları cevaplar: hangi odalar açık, kim bağlı, kuyrukta kim
var, kaç maç oynandı. Ayrıca oyunculara duyuru gönderir.

Duyuru iki yoldan ulaşır:
  * anlık: odadaki ve kuyruktaki soketlere `admin_notice` olayı
  * pano: `GET /api/v1/notice` — menüdeki (sokete bağlı olmayan) oyuncular
    açılışta okur; süresi dolana kadar görünür
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from app.core.config import settings
from app.realtime.hub import hub
from app.realtime.matchmaking import matchmaker
from app.services import score_service

logger = logging.getLogger(__name__)

STARTED_AT = time.time()


@dataclass
class Notice:
    title: str
    message: str
    created_at: float
    expires_at: float
    id: int

    def public(self) -> dict:
        return {"id": self.id, "title": self.title, "message": self.message,
                "expires_at": self.expires_at}


@dataclass
class _Board:
    current: Notice | None = None
    counter: int = 0
    # Panelde son gönderilenler görünsün.
    history: list[dict] = field(default_factory=list)


_board = _Board()


def enabled() -> bool:
    return bool(settings.ADMIN_TOKEN)


def check_token(token: str | None) -> bool:
    return enabled() and token is not None and token == settings.ADMIN_TOKEN


def current_notice() -> dict | None:
    n = _board.current
    if n is None or n.expires_at <= time.time():
        return None
    return n.public()


def rooms_view() -> list[dict]:
    out = []
    now = time.time()
    for room in hub.all_rooms():
        engine = room.engine
        state = {}
        if engine is not None:
            try:
                st = engine.state()
                state = {k: st.get(k) for k in ("phase", "round", "total_rounds", "current_turn")
                         if k in st}
                state["finished"] = bool(getattr(engine, "finished", False))
            except Exception:  # noqa: BLE001
                state = {"error": "state okunamadı"}
        out.append({
            "code": room.code,
            "mode": str(room.mode),
            "created_at": room.created_at,
            "age_seconds": int(now - room.created_at),
            "settings": {k: v for k, v in room.settings.items() if not str(k).startswith("_")},
            "players": [
                {**p.public(), "player_id": p.player_id,
                 "disconnected_at": p.disconnected_at}
                for p in room.players
            ],
            "has_bot": room.has_bot,
            "engine": state if engine is not None else None,
            "empty": room.is_empty,
        })
    out.sort(key=lambda r: r["created_at"], reverse=True)
    return out


async def overview() -> dict:
    rooms = rooms_view()
    online = sum(1 for r in rooms for p in r["players"] if p["connected"] and not p["is_bot"])
    queue = await matchmaker.waiting_count()
    return {
        "server": {
            "environment": settings.ENVIRONMENT,
            "release": settings.RELEASE,
            "uptime_seconds": int(time.time() - STARTED_AT),
            "multi_process": hub.multi_process,
        },
        "counts": {
            "rooms": len(rooms),
            "rooms_playing": sum(1 for r in rooms if r["engine"] and not r["engine"].get("finished")),
            "rooms_with_bot": sum(1 for r in rooms if r["has_bot"]),
            "players_online": online,
            "queue": queue,
            "queue_total": sum(queue.values()),
        },
        "scores": score_service.admin_stats(),
        "notice": current_notice(),
        "notice_history": _board.history[-10:][::-1],
    }


async def notify(title: str, message: str, target: str = "all", ttl_seconds: int = 3600) -> dict:
    """Duyuru: odalara anlık, panoya süreli.

    `target` "all" ya da bir oda kodu. Oda hedefliyse pano güncellenmez.
    """
    payload = {"type": "event", "event": "admin_notice",
               "title": title, "message": message}
    delivered = 0
    if target == "all":
        for room in hub.all_rooms():
            for p in room.players:
                if not p.is_bot and await p.send(payload):
                    delivered += 1
        delivered += await matchmaker.broadcast(payload)
        _board.counter += 1
        _board.current = Notice(title=title, message=message, created_at=time.time(),
                                expires_at=time.time() + max(60, ttl_seconds), id=_board.counter)
    else:
        room = hub.get(target)
        if room is None:
            raise KeyError(target)
        for p in room.players:
            if not p.is_bot and await p.send(payload):
                delivered += 1
    _board.history.append({"at": time.time(), "title": title, "message": message,
                           "target": target, "delivered": delivered})
    logger.info("Duyuru (%s): %s — %d alıcı", target, title, delivered)
    return {"delivered": delivered, "notice": current_notice()}


def clear_notice() -> None:
    _board.current = None


async def close_room(code: str, reason: str = "Oda yönetici tarafından kapatıldı.") -> bool:
    room = hub.get(code)
    if room is None:
        return False
    await room.broadcast({"type": "event", "event": "admin_notice",
                          "title": "Oda kapatıldı", "message": reason})
    if room.engine is not None:
        try:
            await room.engine.stop()
        except Exception:  # noqa: BLE001
            logger.exception("Oda %s motoru durdurulamadı", code)
    for p in list(room.players):
        try:
            await p.socket.close(code=4010)
        except Exception:  # noqa: BLE001
            pass
    await hub.drop_room(code)
    return True
