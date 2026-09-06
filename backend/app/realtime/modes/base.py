"""Oyun modlarının ortak arayüzü."""

import asyncio
import logging
from typing import TYPE_CHECKING

from app.realtime.protocol import ServerMessage

if TYPE_CHECKING:
    from app.realtime.room import Player, Room

logger = logging.getLogger(__name__)


class BaseMode:
    """Bir oyun modunun sunucu tarafı yaşam döngüsü.

    Alt sınıflar `start`, `handle_action` ve `state` metodlarını uygular.
    Zamanlayıcı gereken modlar `_run_loop` içinde kendi döngülerini kurar.
    """

    mode_id: str = "base"

    def __init__(self, room: "Room") -> None:
        self.room = room
        self.finished = False
        self._task: asyncio.Task | None = None

    # --- yaşam döngüsü ---------------------------------------------------

    async def start(self) -> None:
        """İki oyuncu da bağlandığında çağrılır."""
        raise NotImplementedError

    async def handle_action(self, player: "Player", payload: dict) -> None:
        """İstemciden gelen oyun hamlesi."""

    async def handle_relay(self, player: "Player", data: dict) -> None:
        """Oyun mantığı istemcide olan modlarda ham mesaj aktarımı."""
        opponent = self.room.opponent_of(player)
        if opponent:
            await opponent.send({
                "type": ServerMessage.RELAY,
                "from": player.slot,
                "data": data,
            })

    async def on_player_left(self, player: "Player") -> None:
        await self.stop()

    async def stop(self) -> None:
        self.finished = True
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        self._task = None

    # --- yardımcılar -----------------------------------------------------

    def state(self) -> dict:
        return {}

    def spawn(self, coro) -> None:
        """Mod döngüsünü arka planda başlatır; hatalar yutulmaz, loglanır."""
        self._task = asyncio.create_task(self._guard(coro))

    async def _guard(self, coro) -> None:
        try:
            await coro
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Oda %s modunda beklenmeyen hata", self.room.code)
            await self.room.broadcast({
                "type": ServerMessage.ERROR,
                "code": "internal_error",
                "message": "Oyun beklenmedik bir hatayla durdu.",
            })

    async def resend_state(self, player: "Player") -> None:
        """Yeniden bağlanan oyuncuya oyunun güncel durumunu yollar.

        `start` yükünü kaçırdığı için tahta/kategori gibi bilgileri yalnızca
        böyle geri alabilir.
        """
        await player.send({
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": self.state(),
            "resumed": True,
        })

    async def push_state(self, event: str | None = None, **extra) -> None:
        message = {"type": ServerMessage.STATE, "payload": self.state()}
        if event:
            message["event"] = event
        message.update(extra)
        await self.room.broadcast(message)

    async def emit(self, event: str, **payload) -> None:
        await self.room.broadcast({
            "type": ServerMessage.EVENT,
            "event": event,
            **payload,
        })

    async def finish(self, winner_slot: int | None, reason: str) -> None:
        self.finished = True
        await self.room.broadcast({
            "type": ServerMessage.OVER,
            "winner": winner_slot,
            "reason": reason,
            "scores": {p.slot: p.score for p in self.room.players},
            "players": [p.public() for p in self.room.players],
        })
