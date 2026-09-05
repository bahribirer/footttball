"""Oda ve oyuncu durum modelleri."""

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field

from fastapi import WebSocket

from app.realtime.protocol import GameMode, ServerMessage

logger = logging.getLogger(__name__)


@dataclass
class Player:
    socket: WebSocket
    name: str
    slot: int                       # 0 = kurucu (X), 1 = katılan (O)
    connected: bool = True
    score: int = 0

    @property
    def symbol(self) -> str:
        return "X" if self.slot == 0 else "O"

    def public(self) -> dict:
        return {
            "slot": self.slot,
            "name": self.name,
            "symbol": self.symbol,
            "score": self.score,
            "connected": self.connected,
        }

    async def send(self, message: dict) -> bool:
        """Mesajı gönderir. Bağlantı kopmuşsa sessizce False döner."""
        if not self.connected:
            return False
        try:
            await self.socket.send_text(json.dumps(message, ensure_ascii=False))
            return True
        except Exception:
            # Kopan bağlantıya yazmak yayını durdurmamalı.
            self.connected = False
            return False


@dataclass
class Room:
    code: str
    mode: GameMode
    settings: dict = field(default_factory=dict)
    players: list[Player] = field(default_factory=list)
    engine: object | None = None            # modes.base.BaseMode
    created_at: float = field(default_factory=time.time)
    emptied_at: float | None = None
    # Odaya hiç bağlanan olmadıysa kurucu hâlâ ayar ekranındadır; bu odalar
    # oyun bitip boşalanlardan daha uzun süre yaşatılır.
    had_players: bool = False
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def is_empty(self) -> bool:
        return not any(player.connected for player in self.players)

    def player_by_slot(self, slot: int) -> Player | None:
        return next((p for p in self.players if p.slot == slot), None)

    def opponent_of(self, player: Player) -> Player | None:
        return next((p for p in self.players if p.slot != player.slot), None)

    def next_free_slot(self) -> int:
        used = {player.slot for player in self.players}
        return 0 if 0 not in used else 1

    async def broadcast(self, message: dict, exclude: Player | None = None) -> None:
        for player in list(self.players):
            if player is exclude:
                continue
            await player.send(message)

    async def send_room_state(self) -> None:
        await self.broadcast({
            "type": ServerMessage.ROOM,
            "code": self.code,
            "mode": self.mode,
            "players": [player.public() for player in self.players],
            "ready": self.is_full,
        })

    def snapshot(self) -> dict:
        return {
            "code": self.code,
            "mode": self.mode,
            "settings": self.settings,
            "players": [player.public() for player in self.players],
        }
