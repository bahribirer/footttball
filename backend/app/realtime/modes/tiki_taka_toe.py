"""Tiki Taka Toe — klasik 3x3 tahta.

Bu modda oyun mantığı istemcide kalır (mevcut uygulama davranışı korunmuştur);
sunucu tahtayı üretir, rolleri dağıtır ve mesajları rakibe aktarır.
"""

import asyncio
import logging

from app.realtime.modes.base import BaseMode
from app.realtime.protocol import GameMode, ServerMessage
from app.services import grid_service

logger = logging.getLogger(__name__)


class TikiTakaToeMode(BaseMode):
    mode_id = GameMode.TIKI_TAKA_TOE

    def __init__(self, room) -> None:
        super().__init__(room)
        self.league_id: str = room.settings.get("league_id") or "RANDOM"
        self.round_count: int = int(room.settings.get("round_count") or 1)
        self.nations: list[str] = []
        self.clubs: list[str] = []
        self.current_round: int | None = None

    async def start(self) -> None:
        await self._load_grid()
        await self.room.broadcast({
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": self.state(),
        })

    async def _load_grid(self) -> None:
        """Tahta üretimi bloklayıcı SQL içerdiğinden ayrı thread'de çalışır."""
        try:
            self.nations, self.clubs = await asyncio.to_thread(
                grid_service.build_grid, self.league_id
            )
        except ValueError:
            logger.warning("Tahta üretilemedi (%s), RANDOM'a düşülüyor", self.league_id)
            self.nations, self.clubs = await asyncio.to_thread(
                grid_service.build_grid, "RANDOM"
            )

    async def handle_relay(self, player, data: dict) -> None:
        """Hamleyi her iki oyuncuya da iletir.

        Bu modda tahta durumu istemcide tutulur ve hamleyi işleyen kod
        (`makeMove`) sıra değişimini de yapar. Mesaj yalnızca rakibe
        gönderilirse oynayan taraf kendi hamlesini göremez ve sıra
        devretmediği için oyun kilitlenir. Eski protokolde de yayın
        gönderen dahil herkese gidiyordu.
        """
        await self.room.broadcast({
            "type": ServerMessage.RELAY,
            "from": player.slot,
            "data": data,
        })

    async def handle_action(self, player, payload: dict) -> None:
        action = payload.get("action")
        if action == "next_round":
            # İki istemci de aynı tur için istek gönderebilir; tahta yalnızca
            # bir kez üretilir, ikinci istek aynı veriyi geri yayınlar.
            requested_round = payload.get("round")
            async with self.room.lock:
                if requested_round != self.current_round:
                    self.current_round = requested_round
                    await self._load_grid()

            await self.room.broadcast({
                "type": ServerMessage.EVENT,
                "event": "next_round",
                "round": requested_round,
                "nations": self.nations,
                "clubs": self.clubs,
            })
        elif action == "rematch_data":
            await self._load_grid()
            await self.room.broadcast({
                "type": ServerMessage.EVENT,
                "event": "rematch_data",
                "nations": self.nations,
                "clubs": self.clubs,
            })

    def state(self) -> dict:
        return {
            "league_id": self.league_id,
            "round_count": self.round_count,
            "nations": self.nations,
            "clubs": self.clubs,
            "players": [player.public() for player in self.room.players],
        }
