"""Oda durumunun paylaşılan deposu.

Oda durumu süreç belleğinde duruyordu. İki sonucu vardı: her yeniden
başlatma oynanan maçları öldürüyor ve ikinci bir backend süreci açılamıyordu
(iki oyuncu farklı sürece düşerse birbirlerini göremezler).

Burada iki uygulama var:

  * `MemoryStore` — tek süreç. Varsayılan; Redis kurulu olmayan geliştirme
    ortamı ve tek kutuluk üretim için yeterli. Kalıcılığı diske yazılan
    anlık görüntü sağlar (persistence.py).
  * `RedisStore` — çok süreç. Oda durumu Redis'te tutulur, süreçler arası
    mesajlar pub/sub ile taşınır. `REDIS_URL` verilince devreye girer.

Motor (oyun döngüsü) her zaman TEK bir süreçte koşar: odayı ilk kuran
süreç sahibidir. Başka bir sürece bağlanan oyuncunun hamlesi pub/sub ile
sahibe iletilir, sahibin yayınları da aynı yoldan geri döner. Böylece tur
zamanlayıcıları çoğalmaz.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import uuid
from typing import Any, Awaitable, Callable, Protocol

logger = logging.getLogger(__name__)

# Bu sürecin kimliği; odanın sahibini belirlemek için kullanılır.
NODE_ID = os.getenv("NODE_ID") or uuid.uuid4().hex[:12]

# Redis anahtar önekleri.
ROOM_KEY = "ttt:room:{code}"
ROOM_CHANNEL = "ttt:room:{code}:msg"
QUEUE_KEY = "ttt:queue:{mode}"

# Oda kaydı bu süre boyunca yaşar; her yazımda tazelenir. Süreç çökerse
# ölü odalar kendiliğinden düşer.
ROOM_TTL_SECONDS = 3600


class RoomStore(Protocol):
    """Oda durumunu paylaşan depo."""

    multi_process: bool

    async def start(self) -> None: ...
    async def stop(self) -> None: ...
    async def save_room(self, code: str, data: dict) -> None: ...
    async def load_room(self, code: str) -> dict | None: ...
    async def delete_room(self, code: str) -> None: ...
    async def publish(self, code: str, message: dict) -> None: ...
    async def subscribe(self, code: str, handler: Callable[[dict], Awaitable[None]]) -> None: ...
    async def unsubscribe(self, code: str) -> None: ...


class MemoryStore:
    """Tek süreçli çalışma. Yayınlar doğrudan yerel aboneye gider."""

    multi_process = False

    def __init__(self) -> None:
        self._rooms: dict[str, dict] = {}
        self._handlers: dict[str, Callable[[dict], Awaitable[None]]] = {}

    async def start(self) -> None:
        return None

    async def stop(self) -> None:
        return None

    async def save_room(self, code: str, data: dict) -> None:
        self._rooms[code] = data

    async def load_room(self, code: str) -> dict | None:
        return self._rooms.get(code)

    async def delete_room(self, code: str) -> None:
        self._rooms.pop(code, None)
        self._handlers.pop(code, None)

    async def publish(self, code: str, message: dict) -> None:
        # Tek süreçte pub/sub'a gerek yok; mesajlar zaten yerel.
        handler = self._handlers.get(code)
        if handler is not None:
            await handler(message)

    async def subscribe(self, code: str, handler: Callable[[dict], Awaitable[None]]) -> None:
        self._handlers[code] = handler

    async def unsubscribe(self, code: str) -> None:
        self._handlers.pop(code, None)


class RedisStore:
    """Çok süreçli çalışma. Durum Redis'te, mesajlar pub/sub ile."""

    multi_process = True

    def __init__(self, url: str) -> None:
        self._url = url
        self._redis: Any = None
        self._pubsub: Any = None
        self._handlers: dict[str, Callable[[dict], Awaitable[None]]] = {}
        self._reader: asyncio.Task | None = None

    async def start(self) -> None:
        import redis.asyncio as aioredis

        self._redis = aioredis.from_url(self._url, decode_responses=True)
        await self._redis.ping()
        self._pubsub = self._redis.pubsub(ignore_subscribe_messages=True)
        self._reader = asyncio.create_task(self._read_loop())
        logger.info("Redis deposu acik (node=%s)", NODE_ID)

    async def stop(self) -> None:
        if self._reader is not None:
            self._reader.cancel()
            try:
                await self._reader
            except asyncio.CancelledError:
                pass
            self._reader = None
        if self._pubsub is not None:
            await self._pubsub.close()
            self._pubsub = None
        if self._redis is not None:
            await self._redis.aclose()
            self._redis = None

    async def _read_loop(self) -> None:
        """Pub/sub kanalından gelen mesajları yerel işleyicilere dağıtır."""
        assert self._pubsub is not None
        while True:
            try:
                raw = await self._pubsub.get_message(timeout=1.0)
                if raw is None:
                    continue
                channel = raw.get("channel", "")
                code = channel.split(":")[2] if channel.count(":") >= 2 else ""
                handler = self._handlers.get(code)
                if handler is None:
                    continue
                payload = json.loads(raw["data"])
                # Kendi yayınımızı geri işlemeyiz; yerel soketlere zaten
                # doğrudan yazıldı.
                if payload.get("_node") == NODE_ID:
                    continue
                await handler(payload)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Redis pub/sub okuma hatasi")
                await asyncio.sleep(1)

    async def save_room(self, code: str, data: dict) -> None:
        await self._redis.set(
            ROOM_KEY.format(code=code),
            json.dumps(data, ensure_ascii=False),
            ex=ROOM_TTL_SECONDS,
        )

    async def load_room(self, code: str) -> dict | None:
        raw = await self._redis.get(ROOM_KEY.format(code=code))
        return json.loads(raw) if raw else None

    async def delete_room(self, code: str) -> None:
        await self._redis.delete(ROOM_KEY.format(code=code))

    async def publish(self, code: str, message: dict) -> None:
        message = {**message, "_node": NODE_ID}
        await self._redis.publish(
            ROOM_CHANNEL.format(code=code), json.dumps(message, ensure_ascii=False)
        )

    async def subscribe(self, code: str, handler: Callable[[dict], Awaitable[None]]) -> None:
        self._handlers[code] = handler
        await self._pubsub.subscribe(ROOM_CHANNEL.format(code=code))

    async def unsubscribe(self, code: str) -> None:
        self._handlers.pop(code, None)
        if self._pubsub is not None:
            try:
                await self._pubsub.unsubscribe(ROOM_CHANNEL.format(code=code))
            except Exception:
                logger.debug("Kanal aboneligi kapatilamadi: %s", code)


def build_store() -> RoomStore:
    """`REDIS_URL` varsa Redis, yoksa bellek deposu.

    Redis kütüphanesi yoksa ya da bağlantı kurulamıyorsa belleğe düşülür:
    tek kutuluk kurulumda Redis'in gelmemesi oyunu durdurmamalı.
    """
    url = os.getenv("REDIS_URL", "").strip()
    if not url:
        return MemoryStore()
    try:
        import redis.asyncio  # noqa: F401
    except ImportError:
        logger.warning("REDIS_URL verildi ama redis paketi kurulu degil; bellege dusuldu")
        return MemoryStore()
    return RedisStore(url)
