"""Hızlı eşleşme kuyruğu.

Oyuna girmenin tek yolu oda kodu paylaşmaktı: canın çektiğinde açıp
oynayamıyordun, arkadaşının da aynı anda müsait olması gerekiyordu. Bu,
kaç kişinin oynadığının üstünde sert bir tavan.

Kuyruk moda göre ayrı tutulur; aynı modu bekleyen iki oyuncu eşleşir ve
onlar için sıradan bir oda açılır. Oda kodu yine üretilir, yani eşleşen
oyuncular isterlerse kodu paylaşıp rövanş yapabilirler.

Bekleyenler WebSocket üzerinden tutulur: bağlantı kopunca kuyruktan
kendiliğinden düşerler, hayalet eşleşme olmaz.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field

from app.realtime.protocol import GameMode

logger = logging.getLogger(__name__)

# Bu süre boyunca eşleşemeyen oyuncuya haber verilir; sessizce beklemek
# uygulamanın donduğu izlenimi veriyor.
WAIT_HINT_SECONDS = 20

# Kuyrukta bu kadar bekleyen düşürülür; istemci isterse yeniden girer.
MAX_WAIT_SECONDS = 180


@dataclass
class Waiting:
    """Kuyrukta bekleyen bir oyuncu."""
    socket: object
    name: str
    mode: str
    joined_at: float = field(default_factory=time.time)
    # Eşleşme gerçekleşince oda kodu buraya yazılır ve bekleyen uyandırılır.
    matched_code: str | None = None
    event: asyncio.Event = field(default_factory=asyncio.Event)


class Matchmaker:
    def __init__(self) -> None:
        self._queues: dict[str, list[Waiting]] = {}
        self._lock = asyncio.Lock()

    async def enqueue(self, socket: object, name: str, mode: str) -> Waiting:
        """Oyuncuyu kuyruğa alır; rakip hazırsa hemen eşleştirir."""
        entry = Waiting(socket=socket, name=name, mode=mode)
        async with self._lock:
            queue = self._queues.setdefault(mode, [])
            # Kuyruktaki ilk canlı oyuncuyla eşleş.
            while queue:
                other = queue.pop(0)
                if other.matched_code is not None:
                    continue
                return await self._pair(other, entry)
            queue.append(entry)
        return entry

    async def _pair(self, first: Waiting, second: Waiting) -> Waiting:
        """İki bekleyen için oda açar ve ikisini de uyandırır."""
        # Döngüsel içe aktarmayı önlemek için burada alınır.
        from app.realtime.hub import hub

        settings_for_mode = _default_settings(second.mode)
        room = await hub.reserve(second.mode, settings_for_mode)

        for waiting in (first, second):
            waiting.matched_code = room.code
            waiting.event.set()

        logger.info("Hizli eslesme: %s modunda oda %s", second.mode, room.code)
        return second

    async def cancel(self, entry: Waiting) -> None:
        """Bekleyeni kuyruktan çıkarır (bağlantı koptu ya da vazgeçti)."""
        async with self._lock:
            queue = self._queues.get(entry.mode)
            if queue and entry in queue:
                queue.remove(entry)

    async def waiting_count(self, mode: str | None = None) -> dict[str, int]:
        async with self._lock:
            if mode:
                return {mode: len(self._queues.get(mode, []))}
            return {key: len(value) for key, value in self._queues.items() if value}

    async def sweep(self) -> int:
        """Çok uzun bekleyenleri düşürür."""
        dropped = 0
        now = time.time()
        async with self._lock:
            for mode, queue in self._queues.items():
                stale = [w for w in queue if now - w.joined_at > MAX_WAIT_SECONDS]
                for waiting in stale:
                    queue.remove(waiting)
                    waiting.event.set()   # eşleşmeden uyandır
                    dropped += 1
        return dropped


def _default_settings(mode: str) -> dict:
    """Hızlı eşleşmede kurucu ayar seçmediği için makul varsayılanlar.

    Kısa maçlar tercih edilir: yabancıyla oynarken uzun seri terk edilme
    ihtimalini artırıyor.
    """
    from app.core.config import settings

    if mode == GameMode.TIKI_TAKA_TOE:
        return {"league_id": "RANDOM", "round_count": 1}
    if mode == GameMode.PLAYER_GUESS:
        return {"round_count": 3}
    return {
        "clock_seconds": settings.CLOCK_SECONDS,
        "penalty": settings.WRONG_ANSWER_PENALTY,
    }


matchmaker = Matchmaker()
