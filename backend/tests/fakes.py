"""Mod motorlarını gerçek soket olmadan sürmek için asgari taklitler.

Motorlar yalnızca `room.broadcast`, `room.players` ve `player.send` kullanıyor;
gerçek WebSocket kurmadan davranışı sınamak için bu kadarı yeterli.
"""

import json


class FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_text(self, raw: str) -> None:
        self.sent.append(json.loads(raw))

    def events(self) -> list[str]:
        """Yalnizca `event` alani tasiyan mesajlarin adlari."""
        return [m.get("event") for m in self.sent if m.get("event")]

    def errors(self) -> list[str]:
        return [m.get("code") for m in self.sent if m.get("type") == "error"]


class FakePlayer:
    def __init__(self, slot: int, name: str = "") -> None:
        self.slot = slot
        self.name = name or f"oyuncu{slot}"
        self.score = 0
        self.connected = True
        self.socket = FakeSocket()

    async def send(self, message: dict) -> None:
        await self.socket.send_text(json.dumps(message))

    def public(self) -> dict:
        return {"slot": self.slot, "name": self.name, "score": self.score}


class FakeRoom:
    def __init__(self, settings: dict | None = None, players: int = 2) -> None:
        self.code = "TEST"
        self.settings: dict = settings or {}
        self.players = [FakePlayer(slot) for slot in range(players)]

    def opponent_of(self, player):
        return next((p for p in self.players if p.slot != player.slot), None)

    async def broadcast(self, message: dict) -> None:
        for player in self.players:
            await player.send(message)
