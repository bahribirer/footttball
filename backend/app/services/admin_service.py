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

import dataclasses
import hashlib
import hmac
import logging
import time
from dataclasses import dataclass, field

from app.core.config import settings
from app.realtime.hub import hub
from app.realtime.matchmaking import matchmaker
from app.services import lives_service, score_service

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
    return bool(settings.ADMIN_PASSWORD)


def check_token(token: str | None) -> bool:
    """Ham parola (betikler için) ya da oturum belirteci."""
    if not enabled() or not token:
        return False
    if hmac.compare_digest(token, settings.ADMIN_PASSWORD):
        return True
    return verify_session(token) is not None


def login(username: str, password: str) -> str | None:
    """Kullanıcı adı + parola doğruysa süreli oturum belirteci döner."""
    if not enabled():
        return None
    ok_user = hmac.compare_digest(username.strip().casefold(), settings.ADMIN_USER.casefold())
    ok_pass = hmac.compare_digest(password, settings.ADMIN_PASSWORD)
    if not (ok_user and ok_pass):
        return None
    exp = int(time.time()) + settings.ADMIN_SESSION_HOURS * 3600
    body = f"{settings.ADMIN_USER}:{exp}"
    sig = hmac.new(settings.ADMIN_PASSWORD.encode(), body.encode(), hashlib.sha256).hexdigest()
    return f"{body}:{sig}"


def verify_session(token: str) -> str | None:
    """Belirteç geçerliyse kullanıcı adı, değilse None."""
    try:
        user, exp, sig = token.rsplit(":", 2)
        if int(exp) < time.time():
            return None
        expect = hmac.new(settings.ADMIN_PASSWORD.encode(), f"{user}:{exp}".encode(), hashlib.sha256).hexdigest()
        return user if hmac.compare_digest(sig, expect) else None
    except (ValueError, AttributeError):
        return None


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


def system_info() -> dict:
    """Sistem sayfası: veri katmanları, önbellek, ayarlar."""
    import os
    from app.db.database import fetch_one
    from app.services import mode_service

    def _count(sql: str) -> int | None:
        try:
            return int(fetch_one(sql)["n"])
        except Exception:  # noqa: BLE001
            return None

    logo_dir = settings.LOGO_DIR
    try:
        logos = len([f for f in os.listdir(logo_dir) if f.endswith((".png", ".jpg", ".gif"))])
    except OSError:
        logos = 0
    db_size = os.path.getsize(settings.DB_PATH) if os.path.exists(settings.DB_PATH) else 0
    scores_path = score_service.db_path()
    scores_size = os.path.getsize(scores_path) if os.path.exists(scores_path) else 0
    return {
        "environment": settings.ENVIRONMENT,
        "release": settings.RELEASE,
        "uptime_seconds": int(time.time() - STARTED_AT),
        "multi_process": hub.multi_process,
        "modes": [dataclasses.asdict(m) for m in mode_service.catalog()],
        "data": {
            "players": _count("SELECT COUNT(*) AS n FROM players"),
            "club_history": _count("SELECT COUNT(*) AS n FROM club_history"),
            "club_history_players": _count("SELECT COUNT(DISTINCT name_normalized) AS n FROM club_history"),
            "player_photos": _count("SELECT COUNT(*) AS n FROM player_photos WHERE image_url IS NOT NULL"),
            "name_tokens": _count("SELECT COUNT(*) AS n FROM name_tokens"),
            "logos_cached": logos,
            "db_bytes": db_size,
            "scores_db_bytes": scores_size,
        },
        "lives": {"max": lives_service.MAX_LIVES, "window_seconds": lives_service.WINDOW_SECONDS},
    }


def players_page(q: str = "", page: int = 1, size: int = 50) -> dict:
    """Oyuncu listesi: arama, sayfalama, puan, can durumu."""
    q = (q or "").strip()
    offset = max(0, page - 1) * size
    where, params = "", []
    if q:
        where = "WHERE m.name_key LIKE ? OR m.player_id LIKE ?"
        params = [f"%{score_service.name_key(q)}%", f"{q}%"]
    with score_service.connection() as con:
        total = con.execute(f"SELECT COUNT(*) AS n FROM players_meta m {where}", params).fetchone()["n"]
        rows = con.execute(
            f"""SELECT m.player_id, m.name, m.name_key, m.created_at, m.updated_at,
                       COALESCE((SELECT SUM(points) FROM score_events e WHERE e.player_id = m.player_id), 0) AS points,
                       (SELECT COUNT(*) FROM score_events e WHERE e.player_id = m.player_id
                          AND e.kind IN ('win','draw','loss')) AS matches,
                       (SELECT COUNT(*) FROM score_events e WHERE e.player_id = m.player_id AND e.kind = 'win') AS wins
                FROM players_meta m {where}
                ORDER BY m.updated_at DESC LIMIT ? OFFSET ?""",
            (*params, size, offset)).fetchall()
    items = []
    for r in rows:
        d = dict(r)
        d["lives"] = lives_service.status(r["player_id"])
        items.append(d)
    return {"items": items, "total": int(total), "page": page, "size": size}


def player_detail(player_id: str) -> dict | None:
    with score_service.connection() as con:
        meta = con.execute("SELECT * FROM players_meta WHERE player_id = ?", (player_id,)).fetchone()
        if not meta:
            return None
        events = [dict(r) for r in con.execute(
            """SELECT mode, kind, points, vs_bot, ref, created_at FROM score_events
               WHERE player_id = ? ORDER BY id DESC LIMIT 100""", (player_id,))]
        same_name = [dict(r) for r in con.execute(
            "SELECT player_id, name, updated_at FROM players_meta WHERE name_key = ? AND player_id <> ?",
            (meta["name_key"], player_id))]
    online = None
    for room in hub.all_rooms():
        for p in room.players:
            if p.player_id == player_id:
                online = {"room": room.code, "mode": str(room.mode), "connected": p.connected}
    return {
        "player": dict(meta),
        "summary": score_service.summary(player_id),
        "lives": lives_service.status(player_id),
        "events": events,
        "same_name_devices": same_name,
        "online": online,
    }
